import { runtime, unwrap } from "/core/runtime.js"
import {
    NG_FOR_EACH_INPUT_OUTPUTS,
    NG_FOR_EACH_SHARED_INPUT_OUTPUT,
    NG_ITERATION_CONTROL_INPUTS,
    NG_NODE_KINDS,
    cloneNgGraph,
    cloneNgGraphFragment,
    cloneNgNodesWithNewIds,
    createNgNodeGraph,
    findNgGroupPath,
    flattenNgGraphWithLocations,
    nextNgNodeId,
    normalizeNgGroupPath,
    parseNgGroupGraphDocument,
    serializeNgGroupGraphDocument,
    ngInputPortId,
    ngOutputPortId,
    serializeNgNodeGraph,
    syncNgForEachBoundary,
    syncNgGroupBoundary,
    visibleNgExecutionNodeId,
} from "/util/ng-node-graph.js"
import { normalizeNgPresetDraft, ngPresetKind } from "/util/ng-node-preset.js"
import { NodeGraphRenderer } from "/util/node-graph-renderer.js"
import { ViewCanvasBase } from "/util/view-canvas-base.js"
import "/widgets/breadcrumbs.js"

const CLIPBOARD_FORMAT = "gams.view-ng.nodes"
const HISTORY_LIMIT = 100

function assert(condition, message) {
    if (!condition) throw new Error(message)
}

function okResult() {
    return { ok: true }
}

function luaStringLiteral(value) {
    return JSON.stringify(String(value))
}

function canvasBackgroundColor(value) {
    assert(Array.isArray(value) && value.length === 4, "view-ng background must contain four numbers")
    value.forEach((channel, index) => assert(typeof channel === "number" && Number.isFinite(channel), `view-ng background[${index}] must be finite`))
    return `rgba(${Math.round(value[0] * 255)}, ${Math.round(value[1] * 255)}, ${Math.round(value[2] * 255)}, ${value[3]})`
}

export class ViewNg extends ViewCanvasBase {
    static get observedAttributes() {
        return ["graph-name", "data-source"]
    }

    constructor() {
        super()
        this.renderer = null
        this.rootGraph = []
        this.linkedGraphs = new Map()
        this.activeGroupPath = []
        this.graphModel = createNgNodeGraph([])
        this.graph = this.graphModel.graph
        this.graphName = String(this.getAttribute("graph-name") || "default").trim() || "default"
        this.graphPath = String(this.getAttribute("data-source") || "").trim()
        this._suppressDataSourceReload = false
        this.nodePresetConfig = null
        this.currentRunId = ""
        this.currentExecutionLocations = new Map()
        this.selectedNodeIds = new Set()
        this.selectedNodeId = null
        this.selectedEdgeId = null
        this.hoveredNodeId = null
        this.hoveredPort = null
        this.connectionDrag = null
        this.draggedNodeId = null
        this.dragStartPoint = null
        this.dragNodeStarts = null
        this.dragBeforeSnapshot = null
        this.selectionDrag = null
        this.selectionBase = null
        this.lastPointerWorld = null
        this.panDrag = null
        this.undoStack = []
        this.redoStack = []
        this.clipboardGraph = null
        this.handleElement = null
        this.backendElement = null
        this.statusElement = null
        this._ready = false
        this._hasLoadedInitialSource = false
        this._connecting = false
        this._onContextMenu = this._onContextMenu.bind(this)
        this._onCopy = this._onCopy.bind(this)
        this._onPaste = this._onPaste.bind(this)
    }

    connectedCallback() {
        this._connecting = true
        if (!this._ready) {
            this._ready = true
            assert(this.viewConfig && typeof this.viewConfig === "object", "view-ng viewConfig is required")
            assert(this.viewConfig.config && typeof this.viewConfig.config === "object", "view-ng viewConfig.config is required")
            const config = this.viewConfig.config
            assert(config.layout && typeof config.layout === "object", "view-ng config.layout is required")
            for (const key of ["gridOriginX", "gridOriginY", "gridStepX", "gridStepY"])
                assert(Number.isFinite(config.layout[key]), `view-ng config.layout.${key} must be finite`)
            this.renderer = new NodeGraphRenderer(config.renderer)
            this.innerHTML = `
      <canvas data-element="canvas"></canvas>
      <footer>
        <output data-element="handle">nodes: 0</output>
        <output data-element="backend" class="success">state: frontend</output>
        <output data-element="status" class="info">rendering frontend node graph state</output>
      </footer>
    `
            this.handleElement = this.querySelector('[data-element="handle"]')
            this.backendElement = this.querySelector('[data-element="backend"]')
            this.statusElement = this.querySelector('[data-element="status"]')
            assert(this.handleElement instanceof HTMLOutputElement, "view-ng missing handle output")
            assert(this.backendElement instanceof HTMLOutputElement, "view-ng missing backend output")
            assert(this.statusElement instanceof HTMLOutputElement, "view-ng missing status output")
        }
        super.connectedCallback()
        this._connecting = false
        this.canvas.style.backgroundColor = canvasBackgroundColor(this.viewConfig.config.background)
        this.canvas.addEventListener("contextmenu", this._onContextMenu)
        this.addEventListener("copy", this._onCopy)
        this.addEventListener("paste", this._onPaste)
        this.setData(this.graph, { autoFit: !this._hasLoadedInitialSource })
        this.syncControls()
        if (!this.nodePresetConfig) void this._loadNodePresetConfig()
        if (this._hasLoadedInitialSource) return
        this._hasLoadedInitialSource = true
        const path = String(this.getAttribute("data-source") || "").trim()
        if (path) void this.loadGraphFS(path)
        else this._setStatus(`ready for graph '${this.graphName}'`, "info")
    }

    disconnectedCallback() {
        if (this.canvas instanceof HTMLCanvasElement) this.canvas.removeEventListener("contextmenu", this._onContextMenu)
        this.removeEventListener("copy", this._onCopy)
        this.removeEventListener("paste", this._onPaste)
        void runtime.call("ui.tooltip.closeAll")
        super.disconnectedCallback()
    }

    createViewPluginMethods() {
        return {
            nodeStart: (input) => this._handleRunProgress("nodeStart", input),
            nodeDone: (input) => this._handleRunProgress("nodeDone", input),
            nodeError: (input) => this._handleRunProgress("nodeError", input),
            goalStart: (input) => this._handleRunProgress("goalStart", input),
            goalDone: (input) => this._handleRunProgress("goalDone", input),
            tool_1: async () => { await this.run(); return okResult() },
            tool_2: async () => { await this.showAddNodePopup(); return okResult() },
            tool_3: async () => { await this.edit(); return okResult() },
            tool_4: async () => { await this.deleteSelected(); return okResult() },
        }
    }

    attributeChangedCallback(name, oldValue, newValue) {
        if (oldValue === newValue) return
        if (name === "graph-name") {
            this.graphName = String(newValue || "default").trim() || "default"
            if (this._ready) {
                this.syncBreadcrumbs()
                this._setStatus(`graph name set to '${this.graphName}'`, "info")
            }
            return
        }
        if (name === "data-source") {
            this.graphPath = String(newValue || "").trim()
            if (this._ready && this.isConnected && !this._connecting && !this._suppressDataSourceReload && this.graphPath) void this.loadGraphFS(this.graphPath)
        }
    }

    async _loadNodePresetConfig() {
        this.nodePresetConfig = await runtime.call("ui.views.config", "view-ng-node")
    }

    breadcrumbItems() {
        const items = [{ id: "root", label: this.graphName, icon: "schema" }]
        let level = this.rootGraph
        this.activeGroupPath.forEach((groupId, index) => {
            const group = level.find((node) => node.id === groupId)
            assert(group && (group.kind === NG_NODE_KINDS.GROUP || group.kind === NG_NODE_KINDS.FOR_EACH), `view-ng missing breadcrumb child-graph owner ${groupId}`)
            const fallback = group.kind === NG_NODE_KINDS.FOR_EACH ? "for each" : "group"
            items.push({ id: `group:${index}`, label: group.name || `${fallback} #${group.id}`, icon: group.kind === NG_NODE_KINDS.FOR_EACH ? "repeat" : "account_tree" })
            level = this.groupChildGraph(group)
        })
        return items
    }

    syncBreadcrumbs() {
        const breadcrumbs = this.queryHeaderControl('[data-element="breadcrumbs"]')
        if (!breadcrumbs) return
        assert(breadcrumbs.localName === "widget-breadcrumbs", "view-ng breadcrumbs must be a widget-breadcrumbs element")
        breadcrumbs.items = this.breadcrumbItems()
    }

    navigateToBreadcrumb(id) {
        if (id === "root") this.navigateToGroupPath([])
        else {
            assert(/^group:\d+$/.test(id), `view-ng breadcrumb has invalid Group path id ${id}`)
            const index = Number(id.slice("group:".length))
            assert(index >= 0 && index < this.activeGroupPath.length, `view-ng breadcrumb references inactive Group path ${id}`)
            this.navigateToGroupPath(this.activeGroupPath.slice(0, index + 1))
        }
    }

    createHeaderControlsElement() {
        const controls = document.createElement("div")
        controls.innerHTML = `
      <widget-breadcrumbs data-element="breadcrumbs"></widget-breadcrumbs>
      <div role="buttongroup" data-element="file-actions">
        <button type="button" data-action="new" aria-label="New graph" title="New graph"><i aria-hidden="true">docs</i></button>
        <button type="button" data-action="open" aria-label="Open graph" title="Open graph"><i aria-hidden="true">folder_open</i></button>
        <button type="button" data-action="save" class="accent" aria-label="Save graph" title="Save graph"><i aria-hidden="true">save</i></button>
        <button type="button" data-action="save-as" aria-label="Save graph as" title="Save graph as"><i aria-hidden="true">save_as</i></button>
        <button type="button" data-action="reload" aria-label="Reload graph" title="Reload graph"><i aria-hidden="true">refresh</i></button>
      </div>
      <div role="buttongroup" data-element="tool-actions">
        <button type="button" data-action="run" class="success" aria-label="Run" title="Run"><i aria-hidden="true">play_arrow</i></button>
        <button type="button" data-action="add" aria-label="Add node" title="Add node"><i aria-hidden="true">add</i></button>
        <button type="button" data-action="edit" aria-label="Edit" title="Edit"><i aria-hidden="true">edit</i></button>
        <button type="button" data-action="delete" class="danger" aria-label="Delete selected" title="Delete selected"><i aria-hidden="true">delete</i></button>
        <button type="button" data-action="import-group" aria-label="Import linked Group" title="Import linked Group"><i aria-hidden="true">link</i></button>
        <button type="button" data-action="export-group" aria-label="Export Group" title="Export selected inline Group"><i aria-hidden="true">upload</i></button>
        <button type="button" data-action="make-inline" aria-label="Make inline" title="Make selected linked Group inline"><i aria-hidden="true">link_off</i></button>
      </div>
      <div role="buttongroup" data-element="edit-actions">
        <button type="button" data-action="undo" aria-label="Undo" title="Undo"><i aria-hidden="true">undo</i></button>
        <button type="button" data-action="redo" aria-label="Redo" title="Redo"><i aria-hidden="true">redo</i></button>
        <button type="button" data-action="copy" aria-label="Copy selected" title="Copy selected"><i aria-hidden="true">content_copy</i></button>
        <button type="button" data-action="paste" aria-label="Paste" title="Paste"><i aria-hidden="true">content_paste</i></button>
      </div>
      <div role="buttongroup" data-element="view-actions">
        <button type="button" data-action="zoom-in" aria-label="Zoom in" title="Zoom in"><i aria-hidden="true">zoom_in</i></button>
        <button type="button" data-action="zoom-fit" aria-label="Fit graph" title="Fit graph"><i aria-hidden="true">fit_screen</i></button>
        <button type="button" data-action="zoom-out" aria-label="Zoom out" title="Zoom out"><i aria-hidden="true">zoom_out</i></button>
        <button type="button" data-action="auto-arrange" aria-label="Auto arrange" title="Auto arrange"><i aria-hidden="true">account_tree</i></button>
      </div>
    `
        const breadcrumbs = controls.querySelector('[data-element="breadcrumbs"]')
        assert(breadcrumbs instanceof HTMLElement && breadcrumbs.localName === "widget-breadcrumbs", "view-ng missing breadcrumbs control")
        breadcrumbs.items = this.breadcrumbItems()
        breadcrumbs.addEventListener("navigate", (event) => this.navigateToBreadcrumb(event.detail.id))

        const actions = {
            new: () => this.new(), open: () => this.open(), save: () => this.save(), saveAs: () => this.saveAs(), reload: () => this.reload(),
            run: () => this.run(), add: () => this.add(), edit: () => this.edit(), delete: () => this.deleteSelected(),
            importGroup: () => this.importLinkedGroup(), exportGroup: () => this.exportSelectedGroup(), makeInline: () => this.makeSelectedGroupInline(),
            undo: () => this.undo(), redo: () => this.redo(), copy: () => this.copy(), paste: () => this.paste(),
            zoomIn: () => this.zoomIn(), zoomFit: () => this.zoomFit(), zoomOut: () => this.zoomOut(), autoArrange: () => this.autoArrangeNodes(),
        }
        for (const [name, handler] of Object.entries(actions)) {
            const action = name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)
            const button = controls.querySelector(`[data-action="${action}"]`)
            assert(button instanceof HTMLButtonElement, `view-ng missing ${action} control`)
            button.addEventListener("click", () => void handler())
        }
        return controls
    }

    _setOutputTone(element, tone = null) {
        assert(element instanceof HTMLOutputElement, "view-ng output is required")
        element.classList.remove("accent", "success", "warning", "danger", "info")
        if (tone) element.classList.add(tone)
    }

    _setStatus(text, tone = null) {
        assert(this.statusElement instanceof HTMLOutputElement, "view-ng status output is required")
        this.statusElement.textContent = text
        this._setOutputTone(this.statusElement, tone)
    }

    syncControls() {
        const hasNodeSelection = this.selectedNodeIds.size > 0
        const editButton = this.queryHeaderControl('[data-action="edit"]')
        if (editButton instanceof HTMLButtonElement) editButton.disabled = !hasNodeSelection && this.activeGroupPath.length === 0
        const copyButton = this.queryHeaderControl('[data-action="copy"]')
        if (copyButton instanceof HTMLButtonElement) copyButton.disabled = !hasNodeSelection
        const deleteButton = this.queryHeaderControl('[data-action="delete"]')
        if (deleteButton instanceof HTMLButtonElement) deleteButton.disabled = !hasNodeSelection && this.selectedEdgeId === null
        const selectedGroup = this.selectedGroup()
        const exportButton = this.queryHeaderControl('[data-action="export-group"]')
        if (exportButton instanceof HTMLButtonElement) exportButton.disabled = !selectedGroup || this.groupStorageMode(selectedGroup) !== "inline"
        const inlineButton = this.queryHeaderControl('[data-action="make-inline"]')
        if (inlineButton instanceof HTMLButtonElement) inlineButton.disabled = !selectedGroup || this.groupStorageMode(selectedGroup) !== "linked"
        const undo = this.queryHeaderControl('[data-action="undo"]')
        const redo = this.queryHeaderControl('[data-action="redo"]')
        if (undo instanceof HTMLButtonElement) undo.disabled = this.undoStack.length === 0
        if (redo instanceof HTMLButtonElement) redo.disabled = this.redoStack.length === 0
    }

    setNodeSelection(ids, activeId = null) {
        this.selectedNodeIds = new Set(ids)
        this.selectedNodeId = activeId === null ? (this.selectedNodeIds.size ? [...this.selectedNodeIds].at(-1) : null) : activeId
        this.selectedEdgeId = null
        this.syncControls()
    }

    calculateContentBounds(graph) {
        assert(graph === this.graph, "view-ng data must reference its graph")
        return this.renderer.contentBounds(graph.nodes)
    }

    drawContent(ctx, graph) {
        if (!graph) return
        this.renderer.draw(ctx, graph, {
            selectedNodeIds: this.selectedNodeIds,
            selectedEdgeId: this.selectedEdgeId,
            hoveredNodeId: this.hoveredNodeId,
            hoveredPort: this.hoveredPort,
            requiredNodeIds: new Set(),
        })
        if (this.connectionDrag) {
            const hit = this.renderer.hitPort(graph.nodes, this.connectionDrag.current)
            const endpoint = hit ? { nodeId: hit.node.id, portId: hit.port.id } : null
            const valid = Boolean(endpoint && this._canFinishConnection(endpoint).ok)
            const start = this.connectionDrag.fixedDirection === "output" ? this.connectionDrag.fixedPoint : this.connectionDrag.current
            const end = this.connectionDrag.fixedDirection === "output" ? this.connectionDrag.current : this.connectionDrag.fixedPoint
            this.renderer.drawConnectionPreview(ctx, start, end, valid)
        }
        if (this.selectionDrag) this.renderer.drawSelectionRect(ctx, this.selectionRect())
    }

    selectionRect() {
        assert(this.selectionDrag, "view-ng selection drag is required")
        const { start, current } = this.selectionDrag
        return { x: Math.min(start.x, current.x), y: Math.min(start.y, current.y), width: Math.abs(current.x - start.x), height: Math.abs(current.y - start.y) }
    }

    linkedResolver() {
        return (path) => {
            const normalized = normalizeNgGroupPath(path)
            assert(this.linkedGraphs.has(normalized), `view-ng linked Group document is not loaded: ${normalized}`)
            return this.linkedGraphs.get(normalized)
        }
    }

    groupStorageMode(group) {
        return group.storage?.mode || "inline"
    }

    groupChildGraph(group) {
        if (group.kind === NG_NODE_KINDS.FOR_EACH) return group.childGraph
        assert(group.kind === NG_NODE_KINDS.GROUP, `view-ng node ${group.id} must own a child graph`)
        return this.groupStorageMode(group) === "inline" ? group.childGraph : this.linkedResolver()(group.storage.path)
    }

    selectedGroup() {
        if (this.selectedNodeIds.size !== 1) return null
        const id = this.selectedNodeId ?? [...this.selectedNodeIds][0]
        const node = this.graph?.nodes.find((candidate) => candidate.id === id)?.ng
        return node?.kind === NG_NODE_KINDS.GROUP ? node : null
    }

    activeLocation() {
        let level = this.rootGraph
        let documentPath = null
        for (const groupId of this.activeGroupPath) {
            const group = level.find((node) => node.id === groupId)
            assert(group && (group.kind === NG_NODE_KINDS.GROUP || group.kind === NG_NODE_KINDS.FOR_EACH), `view-ng missing child-graph owner ${groupId}`)
            if (group.kind === NG_NODE_KINDS.GROUP && this.groupStorageMode(group) === "linked") documentPath = group.storage.path
            level = this.groupChildGraph(group)
        }
        return { graph: level, documentPath }
    }

    activeGraph() {
        return serializeNgNodeGraph(this.graphModel)
    }

    syncAllGroupBoundaries() {
        const seenDocuments = new Set()
        const syncLevel = (level, documentKey) => {
            if (seenDocuments.has(documentKey)) return
            seenDocuments.add(documentKey)
            for (const group of level.filter((node) => node.kind === NG_NODE_KINDS.GROUP || node.kind === NG_NODE_KINDS.FOR_EACH)) {
                const child = this.groupChildGraph(group)
                if (group.kind === NG_NODE_KINDS.FOR_EACH || this.groupStorageMode(group) === "inline") syncLevel(child, `${documentKey}/inline:${group.id}`)
                else syncLevel(child, `linked:${group.storage.path}`)
                if (group.kind === NG_NODE_KINDS.FOR_EACH) syncNgForEachBoundary(group, level)
                else syncNgGroupBoundary(group, level, { resolveLinked: this.linkedResolver() })
            }
        }
        syncLevel(this.rootGraph, "root")
        for (const [path, graph] of this.linkedGraphs) syncLevel(graph, `linked:${path}`)
    }

    syncActiveGraph() {
        const active = this.activeGraph()
        if (this.activeGroupPath.length === 0) this.rootGraph = active
        else {
            const parentPath = this.activeGroupPath.slice(0, -1)
            const parent = findNgGroupPath(this.rootGraph, parentPath, { resolveLinked: this.linkedResolver() }).graph
            const groupId = this.activeGroupPath.at(-1)
            const group = parent.find((node) => node.id === groupId)
            assert(group && (group.kind === NG_NODE_KINDS.GROUP || group.kind === NG_NODE_KINDS.FOR_EACH), `view-ng missing active child-graph owner ${groupId}`)
            if (group.kind === NG_NODE_KINDS.FOR_EACH || this.groupStorageMode(group) === "inline") group.childGraph = active
            else this.linkedGraphs.set(group.storage.path, active)
        }
        this.syncAllGroupBoundaries()
    }

    getGraph() {
        this.syncActiveGraph()
        return cloneNgGraph(this.rootGraph, { resolveLinked: this.linkedResolver() })
    }

    loadActiveGraph({ autoFit = true } = {}) {
        const active = findNgGroupPath(this.rootGraph, this.activeGroupPath, { resolveLinked: this.linkedResolver() }).graph
        this.graphModel = createNgNodeGraph(active)
        this.graph = this.graphModel.graph
        this.setNodeSelection([])
        this.hoveredNodeId = null
        this.hoveredPort = null
        this.connectionDrag = null
        this.setData(this.graph, { autoFit })
        if (this.handleElement instanceof HTMLOutputElement) this.handleElement.textContent = `nodes: ${this.graph.nodes.length}`
        this.syncBreadcrumbs()
        this.syncControls()
    }

    replaceActiveGraph(rawGraph, { autoFit = false } = {}) {
        if (this.activeGroupPath.length === 0) this.rootGraph = cloneNgGraph(rawGraph)
        else {
            const parent = findNgGroupPath(this.rootGraph, this.activeGroupPath.slice(0, -1), { resolveLinked: this.linkedResolver() }).graph
            const group = parent.find((node) => node.id === this.activeGroupPath.at(-1))
            assert(group && (group.kind === NG_NODE_KINDS.GROUP || group.kind === NG_NODE_KINDS.FOR_EACH), `view-ng missing active child-graph owner ${this.activeGroupPath.at(-1)}`)
            const ownerKind = group.kind
            const insideForEach = this.isInsideForEach()
            if (group.kind === NG_NODE_KINDS.FOR_EACH || this.groupStorageMode(group) === "inline") group.childGraph = cloneNgGraphFragment(rawGraph, { ownerKind, insideForEach })
            else this.linkedGraphs.set(group.storage.path, cloneNgGraphFragment(rawGraph, { ownerKind, insideForEach }))
            this.syncAllGroupBoundaries()
        }
        this.loadActiveGraph({ autoFit })
    }

    loadGraph(rawGraph, { resetHistory = true, autoFit = true } = {}) {
        this.rootGraph = cloneNgGraph(rawGraph, { resolveLinked: this.linkedResolver() })
        this.activeGroupPath = []
        this.loadActiveGraph({ autoFit })
        if (resetHistory) { this.undoStack = []; this.redoStack = [] }
    }

    navigateToGroupPath(path) {
        this.syncActiveGraph()
        findNgGroupPath(this.rootGraph, path, { resolveLinked: this.linkedResolver() })
        this.activeGroupPath = [...path]
        this.loadActiveGraph()
        const owner = this.activeGroupPath.length ? this.activeGroupNode() : null
        const ownerLabel = owner?.kind === NG_NODE_KINDS.FOR_EACH ? "For Each" : "Group"
        this._setStatus(owner ? `editing ${ownerLabel} '${this.breadcrumbItems().at(-1).label}'` : `editing graph '${this.graphName}'`, "info")
    }

    captureSnapshot() {
        return {
            graph: this.getGraph(),
            linkedGraphs: [...this.linkedGraphs].map(([path, graph]) => [path, cloneNgGraphFragment(graph)]),
            activeGroupPath: [...this.activeGroupPath],
            selectedNodeIds: [...this.selectedNodeIds],
            selectedNodeId: this.selectedNodeId,
            selectedEdgeId: this.selectedEdgeId,
        }
    }

    restoreSnapshot(snapshot) {
        this.linkedGraphs = new Map(snapshot.linkedGraphs.map(([path, graph]) => [path, cloneNgGraphFragment(graph)]))
        this.rootGraph = cloneNgGraph(snapshot.graph, { resolveLinked: this.linkedResolver() })
        this.syncAllGroupBoundaries()
        this.activeGroupPath = [...snapshot.activeGroupPath]
        this.loadActiveGraph({ autoFit: false })
        const ids = new Set(this.graph.nodes.map((node) => node.id))
        this.selectedNodeIds = new Set(snapshot.selectedNodeIds.filter((id) => ids.has(id)))
        this.selectedNodeId = ids.has(snapshot.selectedNodeId) ? snapshot.selectedNodeId : null
        this.selectedEdgeId = this.graph.edges.some((edge) => edge.id === snapshot.selectedEdgeId) ? snapshot.selectedEdgeId : null
        this.syncControls()
        this.draw()
    }

    recordEdit(label, before) {
        const after = this.captureSnapshot()
        if (JSON.stringify(before) === JSON.stringify(after)) return false
        this.undoStack.push({ label, before, after })
        if (this.undoStack.length > HISTORY_LIMIT) this.undoStack.shift()
        this.redoStack = []
        this.syncControls()
        return true
    }

    undo() {
        const entry = this.undoStack.pop()
        if (!entry) return false
        this.redoStack.push(entry)
        this.restoreSnapshot(entry.before)
        this._setStatus(`undid ${entry.label}`, "info")
        return true
    }

    redo() {
        const entry = this.redoStack.pop()
        if (!entry) return false
        this.undoStack.push(entry)
        this.restoreSnapshot(entry.after)
        this._setStatus(`redid ${entry.label}`, "info")
        return true
    }

    _nodeFromDraft(nodeId, draft, existing = null) {
        const kind = Number(draft.kind || existing?.kind || NG_NODE_KINDS.CODE)
        const name = String(draft.name || "").trim()
        const defaultForEachChild = [{
            id: 1, kind: NG_NODE_KINDS.FOR_EACH_INPUT, x: 0, y: 0, name: "items", inputs: [],
            outputs: NG_FOR_EACH_INPUT_OUTPUTS.map((port) => ({ ...port, value: null })),
        }]
        const freshChildGraph = (childGraph) => cloneNgNodesWithNewIds(childGraph, Number(nodeId) + 1).nodes
        const forEachChild = kind === NG_NODE_KINDS.FOR_EACH
            ? structuredClone(existing?.childGraph || freshChildGraph(Array.isArray(draft.childGraph) && draft.childGraph.length ? draft.childGraph : defaultForEachChild))
            : null
        const draftInputs = kind === NG_NODE_KINDS.GRAPH_OUTPUT
            ? [{ inputId: 1, name }]
            : kind === NG_NODE_KINDS.ITERATION_CONTROL
              ? NG_ITERATION_CONTROL_INPUTS.map((port) => ({ inputId: port.id, name: port.name }))
              : [NG_NODE_KINDS.GRAPH_INPUT, NG_NODE_KINDS.FOR_EACH_INPUT, NG_NODE_KINDS.FOR_EACH_SHARED_INPUT, NG_NODE_KINDS.GROUP, NG_NODE_KINDS.FOR_EACH].includes(kind)
                ? [] : (Array.isArray(draft.inputs) ? draft.inputs : [])
        const draftOutputs = kind === NG_NODE_KINDS.GRAPH_INPUT
            ? [{ outputId: 1, name, value: null }]
            : kind === NG_NODE_KINDS.FOR_EACH_INPUT
              ? NG_FOR_EACH_INPUT_OUTPUTS.map((port) => ({ outputId: port.id, name: port.name, value: null }))
              : kind === NG_NODE_KINDS.FOR_EACH_SHARED_INPUT
                ? [{ outputId: NG_FOR_EACH_SHARED_INPUT_OUTPUT.id, name: NG_FOR_EACH_SHARED_INPUT_OUTPUT.name, value: null }]
                : kind === NG_NODE_KINDS.FOR_EACH_GET_VAR
                  ? draftInputs.map((input, index) => ({ outputId: Number(input.inputId || input.id || index + 1), name: String(input.name || "").trim(), value: null }))
                  : [NG_NODE_KINDS.GRAPH_OUTPUT, NG_NODE_KINDS.FOR_EACH_SET_VAR, NG_NODE_KINDS.ITERATION_CONTROL, NG_NODE_KINDS.GROUP, NG_NODE_KINDS.FOR_EACH].includes(kind)
                    ? [] : (Array.isArray(draft.outputs) ? draft.outputs : [])
        const result = {
            id: Number(nodeId), kind, x: Number(existing?.x ?? 0), y: Number(existing?.y ?? 0), name,
            ...(kind === NG_NODE_KINDS.CODE ? { codePath: String(draft.codePath || "").trim() } : {}),
            inputs: draftInputs.map((port, index) => {
                const id = Number(port.inputId || port.id || index + 1)
                const prior = existing?.inputs?.find((input) => input.id === id)
                return { id, name: String(port.name || "").trim(), srcNodeId: Number(prior?.srcNodeId || 0), srcOutputId: Number(prior?.srcOutputId || 0) }
            }),
            outputs: draftOutputs.map((port, index) => {
                const id = Number(port.outputId || port.id || index + 1)
                const prior = existing?.outputs?.find((output) => output.id === id)
                return { id, name: kind === NG_NODE_KINDS.VALUE ? "" : String(port.name || prior?.name || "").trim(), value: port.value === null ? null : String(port.value ?? prior?.value ?? "") || null }
            }),
            ...(kind === NG_NODE_KINDS.GROUP ? (() => {
                const storage = structuredClone(draft.storage || existing?.storage || { mode: "inline" })
                return {
                    storage,
                    ...(storage.mode === "inline" ? { childGraph: structuredClone(existing?.childGraph || freshChildGraph(draft.childGraph || [])) } : {}),
                }
            })() : {}),
            ...(kind === NG_NODE_KINDS.FOR_EACH ? { childGraph: forEachChild } : {}),
        }
        if (kind === NG_NODE_KINDS.FOR_EACH) syncNgForEachBoundary(result)
        return result
    }

    nextNodeId() {
        const { graph, documentPath } = this.activeLocation()
        const authoritative = documentPath ? this.linkedResolver()(documentPath) : this.rootGraph
        return nextNgNodeId(authoritative)
    }

    async showAddNodePopup() {
        const payload = unwrap(await runtime.call("ui.popup.open", {
            title: "Add node",
            size: "medium",
            tag: "view-ng-node",
            props: {
                mode: "create",
                allowGraphBoundaryNodes: this.activeGroupPath.length > 0,
                childGraphOwnerKind: this.activeGroupPath.length ? this.activeGroupNode().kind : 0,
                insideForEach: this.isInsideForEach(),
            },
        }))
        if (!payload || payload.cancelled) return false
        const node = await this.createNodeFromDraftAt(payload.draft || {}, this.viewportCenterWorld(), { centerNode: true })
        if (!node) return false
        this._setStatus(`added node #${node.id}`, "success")
        return true
    }

    async add() { return this.showAddNodePopup() }

    async edit() {
        if (this.selectedNodeIds.size === 0 && this.activeGroupPath.length > 0) return this.showRenameActiveGroupPopup()
        return this.showEditNodePopup()
    }

    activeGroupNode() {
        assert(this.activeGroupPath.length > 0, "view-ng must be inside a child-graph node")
        const parent = findNgGroupPath(this.rootGraph, this.activeGroupPath.slice(0, -1), { resolveLinked: this.linkedResolver() }).graph
        const groupId = this.activeGroupPath.at(-1)
        const group = parent.find((node) => node.id === groupId)
        assert(group && (group.kind === NG_NODE_KINDS.GROUP || group.kind === NG_NODE_KINDS.FOR_EACH), `view-ng missing active child-graph owner ${groupId}`)
        return group
    }

    isInsideForEach() {
        if (!this.activeGroupPath.length) return false
        return findNgGroupPath(this.rootGraph, this.activeGroupPath, { resolveLinked: this.linkedResolver() }).owners.some((owner) => owner.kind === NG_NODE_KINDS.FOR_EACH)
    }

    async showRenameActiveGroupPopup() {
        this.syncActiveGraph()
        const group = this.activeGroupNode()
        const label = group.kind === NG_NODE_KINDS.FOR_EACH ? "For Each" : "Group"
        const payload = unwrap(await runtime.call("ui.popup.open", {
            title: `Rename ${label} #${group.id}`,
            size: "medium",
            tag: "view-ng-node",
            props: { mode: "edit", nodeId: group.id, kind: group.kind, nodeName: group.name },
        }))
        if (!payload || payload.cancelled) return false
        assert(payload.draft && typeof payload.draft === "object", `view-ng ${label} rename requires a draft`)
        assert(typeof payload.draft.name === "string", `view-ng ${label} rename requires a name`)
        const before = this.captureSnapshot()
        group.name = payload.draft.name.trim()
        this.syncBreadcrumbs()
        this.recordEdit(`rename ${label}`, before)
        this.draw()
        this._setStatus(`renamed ${label} #${group.id} to '${group.name}'`, "success")
        return true
    }

    async showEditNodePopup() {
        if (this.selectedNodeIds.size !== 1) { this._setStatus("select exactly one node to edit", "warning"); return false }
        const nodeId = this.selectedNodeId ?? [...this.selectedNodeIds][0]
        const raw = this.activeGraph()
        const node = raw.find((candidate) => candidate.id === nodeId)
        assert(node, `view-ng missing selected node ${nodeId}`)
        if (node.kind === NG_NODE_KINDS.GROUP || node.kind === NG_NODE_KINDS.FOR_EACH) {
            this.navigateToGroupPath([...this.activeGroupPath, node.id])
            return true
        }
        const payload = unwrap(await runtime.call("ui.popup.open", {
            title: `Edit node #${nodeId}`, size: "medium", tag: "view-ng-node", props: {
                mode: "edit", nodeId, kind: node.kind, nodeName: node.name, inputCount: node.inputs.length, outputCount: node.outputs.length,
                allowGraphBoundaryNodes: [NG_NODE_KINDS.GRAPH_INPUT, NG_NODE_KINDS.GRAPH_OUTPUT, NG_NODE_KINDS.FOR_EACH_INPUT, NG_NODE_KINDS.FOR_EACH_SHARED_INPUT, NG_NODE_KINDS.FOR_EACH_GET_VAR, NG_NODE_KINDS.FOR_EACH_SET_VAR, NG_NODE_KINDS.ITERATION_CONTROL].includes(node.kind),
                childGraphOwnerKind: this.activeGroupPath.length ? this.activeGroupNode().kind : 0,
                insideForEach: this.isInsideForEach(),
                ...(node.kind === NG_NODE_KINDS.CODE ? { codePath: node.codePath, code: "" } : {}),
                valueText: node.kind === NG_NODE_KINDS.VALUE ? node.outputs[0]?.value || "" : "",
                inputLabels: node.inputs.map((input, index) => input.name || `input ${index + 1}`),
                outputLabels: node.outputs.map((output, index) => node.kind === NG_NODE_KINDS.VALUE ? output.value : output.name || `output ${index + 1}`),
            },
        }))
        if (!payload || payload.cancelled) return false
        const before = this.captureSnapshot()
        const next = this._nodeFromDraft(nodeId, payload.draft || {}, node)
        const index = raw.findIndex((candidate) => candidate.id === nodeId)
        raw[index] = next
        this.replaceActiveGraph(raw, { autoFit: false })
        this.setNodeSelection([nodeId], nodeId)
        this.recordEdit("edit node", before)
        this.draw()
        this._setStatus(`updated node #${nodeId}`, "success")
        return true
    }

    async deleteSelected() {
        if (!this.selectedNodeIds.size && this.selectedEdgeId === null) return false
        if (this.selectedNodeIds.size && this.activeGroupPath.length && this.activeGroupNode().kind === NG_NODE_KINDS.FOR_EACH) {
            const raw = this.activeGraph()
            const remainingInputs = raw.filter((node) => node.kind === NG_NODE_KINDS.FOR_EACH_INPUT && !this.selectedNodeIds.has(node.id))
            if (remainingInputs.length === 0) {
                this._setStatus("For Each requires at least one For Each Input", "warning")
                return false
            }
        }
        const before = this.captureSnapshot()
        if (this.selectedEdgeId !== null) {
            this.graphModel.removeEdge(this.selectedEdgeId)
            this.selectedEdgeId = null
            this.recordEdit("disconnect nodes", before)
            this.draw()
            this._setStatus("deleted connection", "success")
            return true
        }
        const result = this.graphModel.removeNodes(this.selectedNodeIds)
        this.setNodeSelection([])
        this.contentBounds = this.calculateContentBounds(this.graph)
        this.recordEdit("delete nodes", before)
        this.draw()
        this.handleElement.textContent = `nodes: ${this.graph.nodes.length}`
        this._setStatus(`deleted ${result.removedNodeIds.length} selected node${result.removedNodeIds.length === 1 ? "" : "s"}`, "success")
        return true
    }

    clearSelection() {
        if (this.selectedNodeIds.size === 0 && this.selectedEdgeId === null && this.activeGroupPath.length > 0) {
            this.navigateToGroupPath(this.activeGroupPath.slice(0, -1))
            return true
        }
        this.setNodeSelection([])
        this.draw()
        return true
    }

    viewportCenterWorld() {
        const rect = this.canvas.getBoundingClientRect()
        return this.getWorldPoint(rect.left + rect.width / 2, rect.top + rect.height / 2)
    }

    _nodePresetEntries() {
        const presets = this.config?.presets || this.config?.nodePresets || this.viewConfig?.nodePresets || this.nodePresetConfig?.presets || []
        return presets.map((entry) => {
            const name = String(entry?.name || "").trim()
            if (!name) return null
            const kind = ngPresetKind(entry.kind, NG_NODE_KINDS.CODE)
            const ownerKind = this.activeGroupPath.length ? this.activeGroupNode().kind : 0
            if (kind === NG_NODE_KINDS.GRAPH_INPUT && ownerKind !== NG_NODE_KINDS.GROUP) return null
            if (kind === NG_NODE_KINDS.GRAPH_OUTPUT && ![NG_NODE_KINDS.GROUP, NG_NODE_KINDS.FOR_EACH].includes(ownerKind)) return null
            if ([NG_NODE_KINDS.FOR_EACH_INPUT, NG_NODE_KINDS.FOR_EACH_SHARED_INPUT, NG_NODE_KINDS.FOR_EACH_GET_VAR, NG_NODE_KINDS.FOR_EACH_SET_VAR, NG_NODE_KINDS.ITERATION_CONTROL].includes(kind) && ownerKind !== NG_NODE_KINDS.FOR_EACH) return null
            if (kind === NG_NODE_KINDS.GOAL && this.isInsideForEach()) return null
            const group = String(entry.group || "Presets").trim() || "Presets"
            return { name, kind, group, data: { ...entry, name, kind, group } }
        }).filter(Boolean)
    }

    _buildNodeContextMenuItems() {
        const ownerKind = this.activeGroupPath.length ? this.activeGroupNode().kind : 0
        const base = [
            { label: "value", kind: NG_NODE_KINDS.VALUE, outputs: [{ value: "" }] },
            { label: "code", kind: NG_NODE_KINDS.CODE },
            ...(!this.isInsideForEach() ? [{ label: "goal", kind: NG_NODE_KINDS.GOAL }] : []),
            { label: "group", kind: NG_NODE_KINDS.GROUP },
            { label: "for each", kind: NG_NODE_KINDS.FOR_EACH },
            ...(ownerKind === NG_NODE_KINDS.GROUP ? [{ label: "input", kind: NG_NODE_KINDS.GRAPH_INPUT, name: "input" }] : []),
            ...([NG_NODE_KINDS.GROUP, NG_NODE_KINDS.FOR_EACH].includes(ownerKind) ? [{ label: "output", kind: NG_NODE_KINDS.GRAPH_OUTPUT, name: "output" }] : []),
            ...(ownerKind === NG_NODE_KINDS.FOR_EACH ? [
                { label: "input", kind: NG_NODE_KINDS.FOR_EACH_INPUT, name: "items" },
                { label: "shared input", kind: NG_NODE_KINDS.FOR_EACH_SHARED_INPUT, name: "value" },
                { label: "get var", kind: NG_NODE_KINDS.FOR_EACH_GET_VAR, name: "GetVar" },
                { label: "set var", kind: NG_NODE_KINDS.FOR_EACH_SET_VAR, name: "SetVar" },
                { label: "iteration control", kind: NG_NODE_KINDS.ITERATION_CONTROL, name: "Iteration Control" },
            ] : []),
        ]
        const groups = new Map()
        for (const entry of this._nodePresetEntries()) {
            if (!groups.has(entry.group)) groups.set(entry.group, [])
            groups.get(entry.group).push(entry)
        }
        return [{ label: "Base", items: base.map((entry) => ({ label: entry.label, keywords: [entry.label], value: { draft: normalizeNgPresetDraft(entry) } })) },
            ...[...groups.entries()].map(([group, entries]) => ({ label: group, items: entries.map((entry) => ({ label: entry.name, keywords: [entry.name, group], value: { draft: normalizeNgPresetDraft(entry.data, entry.kind) } })) }))]
    }

    async createNodeFromDraftAt(draft, worldPoint, { centerNode = false } = {}) {
        const before = this.captureSnapshot()
        const raw = this.activeGraph()
        const node = this._nodeFromDraft(this.nextNodeId(), draft, { x: Math.round(worldPoint.x), y: Math.round(worldPoint.y) })
        if (node.kind === NG_NODE_KINDS.ITERATION_CONTROL && raw.some((candidate) => candidate.kind === NG_NODE_KINDS.ITERATION_CONTROL)) {
            this._setStatus("For Each allows only one Iteration Control", "warning")
            return false
        }
        const previousLinkedGraphs = this.linkedGraphs
        try {
            if (node.kind === NG_NODE_KINDS.GROUP && this.groupStorageMode(node) === "linked") {
                const path = normalizeNgGroupPath(node.storage.path)
                const hydrated = new Map(previousLinkedGraphs)
                await this.loadLinkedGraphFS(path, [], hydrated)
                this.linkedGraphs = hydrated
                this.assertLinkAllowedInActiveDocument(path)
                syncNgGroupBoundary(node, raw, { resolveLinked: this.linkedResolver() })
            }
            raw.push(node)
            this.replaceActiveGraph(raw, { autoFit: false })
            if (centerNode) {
                const projected = this.graphModel.node(node.id)
                const size = this.renderer.nodeSize(projected)
                projected.x = Math.round(worldPoint.x - size.width / 2)
                projected.y = Math.round(worldPoint.y - size.height / 2)
            }
            this.setNodeSelection([node.id], node.id)
            this.recordEdit("add node", before)
            this.contentBounds = this.calculateContentBounds(this.graph)
            this.draw()
            if (!centerNode) this._setStatus(`added ${node.name || "node"} #${node.id}`, "success")
            return node
        } catch (error) {
            this.linkedGraphs = previousLinkedGraphs
            this.restoreSnapshot(before)
            throw error
        }
    }

    clipboardPayload() {
        if (!this.selectedNodeIds.size) return null
        const selected = new Set(this.selectedNodeIds)
        const nodes = this.activeGraph().filter((node) => selected.has(node.id)).map((node) => ({ ...node, inputs: node.inputs.map((input) => selected.has(input.srcNodeId) ? input : { ...input, srcNodeId: 0, srcOutputId: 0 }) }))
        return { format: CLIPBOARD_FORMAT, version: 1, nodes }
    }

    parseClipboardPayload(text) {
        const payload = JSON.parse(String(text))
        if (payload?.format === CLIPBOARD_FORMAT && payload.version === 1) return cloneNgGraphFragment(payload.nodes)
        if (Array.isArray(payload)) return cloneNgGraphFragment(payload)
        throw new Error("view-ng clipboard does not contain graph nodes")
    }

    async copy() {
        return this.copySelectedNodesToClipboard()
    }

    async copySelectedNodesToClipboard(clipboardData = null) {
        const payload = this.clipboardPayload()
        if (!payload) return false
        this.clipboardGraph = payload
        const text = JSON.stringify(payload, null, 2)
        if (clipboardData) clipboardData.setData("text/plain", text)
        else {
            assert(navigator.clipboard, "view-ng copy requires navigator.clipboard")
            await navigator.clipboard.writeText(text)
        }
        this._setStatus(`copied ${payload.nodes.length} node${payload.nodes.length === 1 ? "" : "s"}`, "success")
        return true
    }

    async paste() {
        return this.pasteNodesFromClipboard()
    }

    async pasteNodesFromClipboard(text = null, anchor = null) {
        if (text === null && !this.clipboardGraph) assert(navigator.clipboard, "view-ng paste requires navigator.clipboard")
        const source = text === null
            ? this.clipboardGraph ? JSON.stringify(this.clipboardGraph) : await navigator.clipboard.readText()
            : String(text)
        return this.pasteNodes(source, anchor || this.lastPointerWorld || this.viewportCenterWorld())
    }

    async pasteNodes(text, anchor) {
        const source = this.parseClipboardPayload(text)
        if (!source.length) return false
        const ownerKind = this.activeGroupPath.length ? this.activeGroupNode().kind : 0
        const invalidBoundary = source.some((node) =>
            (node.kind === NG_NODE_KINDS.GRAPH_INPUT && ownerKind !== NG_NODE_KINDS.GROUP) ||
            (node.kind === NG_NODE_KINDS.GRAPH_OUTPUT && ![NG_NODE_KINDS.GROUP, NG_NODE_KINDS.FOR_EACH].includes(ownerKind)) ||
            ([NG_NODE_KINDS.FOR_EACH_INPUT, NG_NODE_KINDS.FOR_EACH_SHARED_INPUT, NG_NODE_KINDS.FOR_EACH_GET_VAR, NG_NODE_KINDS.FOR_EACH_SET_VAR, NG_NODE_KINDS.ITERATION_CONTROL].includes(node.kind) && ownerKind !== NG_NODE_KINDS.FOR_EACH))
        if (invalidBoundary) {
            this._setStatus("boundary nodes can only be pasted into their matching child graph", "warning")
            return false
        }
        const raw = this.activeGraph()
        const pastedControlCount = source.filter((node) => node.kind === NG_NODE_KINDS.ITERATION_CONTROL).length
        const existingControlCount = raw.filter((node) => node.kind === NG_NODE_KINDS.ITERATION_CONTROL).length
        if (ownerKind === NG_NODE_KINDS.FOR_EACH && pastedControlCount + existingControlCount > 1) {
            this._setStatus("For Each allows only one Iteration Control", "warning")
            return false
        }
        const before = this.captureSnapshot()
        const previousLinkedGraphs = this.linkedGraphs
        try {
            const linkedPaths = this.linkedPathsInGraph(source)
            const hydrated = new Map(previousLinkedGraphs)
            for (const path of linkedPaths) await this.loadLinkedGraphFS(path, [], hydrated)
            this.linkedGraphs = hydrated
            for (const path of linkedPaths) this.assertLinkAllowedInActiveDocument(path)

            const minX = Math.min(...source.map((node) => node.x))
            const minY = Math.min(...source.map((node) => node.y))
            const remapped = cloneNgNodesWithNewIds(source, this.nextNodeId()).nodes
            const pasted = remapped.map((node) => ({ ...node, x: Math.round(node.x + anchor.x - minX), y: Math.round(node.y + anchor.y - minY) }))
            raw.push(...pasted)
            this.replaceActiveGraph(raw, { autoFit: false })
            this.setNodeSelection(pasted.map((node) => node.id), pasted.at(-1).id)
            this.recordEdit("paste nodes", before)
            this.draw()
            this._setStatus(`pasted ${pasted.length} node${pasted.length === 1 ? "" : "s"}`, "success")
            return true
        } catch (error) {
            this.linkedGraphs = previousLinkedGraphs
            this.restoreSnapshot(before)
            throw error
        }
    }

    _onCopy(event) {
        const payload = this.clipboardPayload()
        if (!payload) return
        event.preventDefault()
        this.clipboardGraph = payload
        event.clipboardData.setData("text/plain", JSON.stringify(payload, null, 2))
    }

    _onPaste(event) {
        const text = event.clipboardData.getData("text/plain")
        if (!text) return
        event.preventDefault()
        void this.pasteNodes(text, this.lastPointerWorld || this.viewportCenterWorld())
    }

    async _onContextMenu(event) {
        const point = this.getWorldPoint(event.clientX, event.clientY)
        this.lastPointerWorld = point
        if (this.renderer.hitNode(this.graph.nodes, point) || this.renderer.hitEdge(this.graph, point, 10 / this.scale)) return
        event.preventDefault()
        this.focus()
        if (!this.nodePresetConfig) await this._loadNodePresetConfig()
        const result = unwrap(await runtime.call("ui.tooltip.contextMenu", { anchor: { kind: "point", x: event.clientX, y: event.clientY }, searchable: true, placeholder: "Search node presets…", items: this._buildNodeContextMenuItems() }), "ui.tooltip.contextMenu")
        if (result.ok) await this.createNodeFromDraftAt(result.selected.value.draft, point)
    }

    _edgeForInput(nodeId, portId) {
        return this.graph.edges.find((edge) => edge.to.nodeId === nodeId && edge.to.portId === portId) || null
    }

    beginConnection(portHit) {
        const endpoint = { nodeId: portHit.node.id, portId: portHit.port.id }
        let fixed = endpoint
        let fixedDirection = portHit.port.direction
        let originalEdge = null
        if (portHit.port.direction === "input") {
            originalEdge = this._edgeForInput(endpoint.nodeId, endpoint.portId)
            if (originalEdge) {
                fixed = originalEdge.from
                fixedDirection = "output"
            }
        }
        this.connectionDrag = { fixed, fixedDirection, fixedPoint: this.renderer.portPoint(this.graphModel.node(fixed.nodeId), fixed.portId), current: portHit.point, originalEdge, before: this.captureSnapshot() }
        this.setNodeSelection([portHit.node.id], portHit.node.id)
        return true
    }

    beginEdgeReconnect(edge, point) {
        const fromNode = this.graphModel.node(edge.from.nodeId)
        const toNode = this.graphModel.node(edge.to.nodeId)
        const fromPoint = this.renderer.portPoint(fromNode, edge.from.portId)
        const toPoint = this.renderer.portPoint(toNode, edge.to.portId)
        const moveSource = Math.hypot(point.x - fromPoint.x, point.y - fromPoint.y) <= Math.hypot(point.x - toPoint.x, point.y - toPoint.y)
        const fixed = moveSource ? edge.to : edge.from
        this.connectionDrag = {
            fixed, fixedDirection: moveSource ? "input" : "output", fixedPoint: moveSource ? toPoint : fromPoint,
            current: point, originalEdge: edge, before: this.captureSnapshot(),
        }
    }

    _connectionEndpoints(target) {
        const drag = this.connectionDrag
        assert(drag, "view-ng connection drag is required")
        return drag.fixedDirection === "output" ? { from: drag.fixed, to: target } : { from: target, to: drag.fixed }
    }

    _canFinishConnection(target) {
        const drag = this.connectionDrag
        const endpoints = this._connectionEndpoints(target)
        const targetPort = this.graphModel.port(target)
        if (targetPort.direction === drag.fixedDirection) return { ok: false, reason: "Connect opposite port directions" }
        const ignored = new Set()
        if (drag.originalEdge) ignored.add(drag.originalEdge)
        const occupiedInput = this._edgeForInput(endpoints.to.nodeId, endpoints.to.portId)
        if (occupiedInput) ignored.add(occupiedInput)
        const removed = [...ignored].map((edge) => ({ edge, index: this.graph.edges.indexOf(edge) })).filter((entry) => entry.index >= 0).sort((a, b) => b.index - a.index)
        for (const entry of removed) this.graph.edges.splice(entry.index, 1)
        try { return this.graphModel.canAddEdge(endpoints.from, endpoints.to) }
        finally {
            for (const entry of removed.sort((a, b) => a.index - b.index)) this.graph.edges.splice(entry.index, 0, entry.edge)
        }
    }

    finishConnection(point) {
        const drag = this.connectionDrag
        assert(drag, "view-ng connection drag is required")
        this.connectionDrag = null
        const hit = this.renderer.hitPort(this.graph.nodes, point)
        if (!hit) {
            if (drag.originalEdge) {
                this.graphModel.removeEdge(drag.originalEdge.id)
                this.recordEdit("disconnect nodes", drag.before)
                this._setStatus("disconnected nodes", "success")
            } else this._setStatus("connection cancelled", "info")
            this.draw()
            return
        }
        const target = { nodeId: hit.node.id, portId: hit.port.id }
        const result = (() => { this.connectionDrag = drag; try { return this._canFinishConnection(target) } finally { this.connectionDrag = null } })()
        if (!result.ok) { this._setStatus(result.reason, "warning"); this.draw(); return }
        const endpoints = (() => { this.connectionDrag = drag; try { return this._connectionEndpoints(target) } finally { this.connectionDrag = null } })()
        if (drag.originalEdge) this.graphModel.removeEdge(drag.originalEdge.id)
        const occupiedInput = this._edgeForInput(endpoints.to.nodeId, endpoints.to.portId)
        if (occupiedInput) this.graphModel.removeEdge(occupiedInput.id)
        const same = drag.originalEdge && JSON.stringify(drag.originalEdge.from) === JSON.stringify(endpoints.from) && JSON.stringify(drag.originalEdge.to) === JSON.stringify(endpoints.to)
        if (same) this.graphModel.addEdge(drag.originalEdge)
        else this.graphModel.addEdge({ id: this.graph.edges.length ? Math.max(...this.graph.edges.map((edge) => Number(edge.id))) + 1 : 1, ...endpoints, execState: "idle" })
        this.recordEdit(drag.originalEdge ? "reconnect nodes" : "connect nodes", drag.before)
        this._setStatus(`connected ${endpoints.from.nodeId}.${endpoints.from.portId} → ${endpoints.to.nodeId}.${endpoints.to.portId}`, "success")
        this.draw()
    }

    onCanvasMouseDown(event) {
        if (event.button !== 0 && event.button !== 1) return
        const point = this.getWorldPoint(event.clientX, event.clientY)
        this.lastPointerWorld = point
        if (event.button === 1 || event.ctrlKey || event.metaKey) {
            this.panDrag = { clientX: event.clientX, clientY: event.clientY, offsetX: this.offsetX, offsetY: this.offsetY }
            this.canvas.style.cursor = "grabbing"
            return
        }
        const port = this.renderer.hitPort(this.graph.nodes, point)
        if (port && this.beginConnection(port)) { this.canvas.style.cursor = "crosshair"; this.draw(); return }
        const node = this.renderer.hitNode(this.graph.nodes, point)
        if (node) {
            if (event.shiftKey) {
                const ids = new Set(this.selectedNodeIds)
                if (ids.has(node.id)) ids.delete(node.id); else ids.add(node.id)
                this.setNodeSelection(ids, ids.has(node.id) ? node.id : null)
            } else if (!this.selectedNodeIds.has(node.id)) this.setNodeSelection([node.id], node.id)
            else this.selectedNodeId = node.id
            if (!this.selectedNodeIds.size) this.setNodeSelection([node.id], node.id)
            this.dragBeforeSnapshot = this.captureSnapshot()
            this.draggedNodeId = node.id
            this.dragStartPoint = point
            this.dragNodeStarts = new Map(this.graph.nodes.filter((candidate) => this.selectedNodeIds.has(candidate.id)).map((candidate) => [candidate.id, { x: candidate.x, y: candidate.y }]))
            this.canvas.style.cursor = "grabbing"
            this.draw()
            return
        }
        const edge = this.renderer.hitEdge(this.graph, point, 10 / this.scale)
        if (edge) {
            this.selectedNodeIds.clear(); this.selectedNodeId = null; this.selectedEdgeId = edge.id
            this.beginEdgeReconnect(edge, point)
            this.syncControls(); this.canvas.style.cursor = "crosshair"; this.draw(); return
        }
        this.selectionBase = event.shiftKey ? new Set(this.selectedNodeIds) : new Set()
        if (!event.shiftKey) this.setNodeSelection([])
        this.selectionDrag = { start: point, current: point }
        this.canvas.style.cursor = "crosshair"
        this.draw()
    }

    onCanvasMouseMove(event) {
        const point = this.getWorldPoint(event.clientX, event.clientY)
        this.lastPointerWorld = point
        if (this.panDrag) {
            this.offsetX = this.panDrag.offsetX + event.clientX - this.panDrag.clientX
            this.offsetY = this.panDrag.offsetY + event.clientY - this.panDrag.clientY
            this.draw(); return
        }
        if (this.connectionDrag) {
            this.connectionDrag.current = point
            const hit = this.renderer.hitPort(this.graph.nodes, point)
            this.hoveredPort = hit ? { nodeId: hit.node.id, portId: hit.port.id } : null
            this.canvas.style.cursor = "crosshair"; this.draw(); return
        }
        if (this.draggedNodeId !== null) {
            const dx = point.x - this.dragStartPoint.x
            const dy = point.y - this.dragStartPoint.y
            for (const [id, start] of this.dragNodeStarts) { const node = this.graphModel.node(id); node.x = Math.round(start.x + dx); node.y = Math.round(start.y + dy) }
            this.contentBounds = this.calculateContentBounds(this.graph)
            this.draw(); return
        }
        if (this.selectionDrag) {
            this.selectionDrag.current = point
            const rect = this.selectionRect()
            const selected = new Set(this.selectionBase)
            for (const node of this.graph.nodes) {
                const bounds = this.renderer.nodeBounds(node)
                if (bounds.x <= rect.x + rect.width && bounds.x + bounds.width >= rect.x && bounds.y <= rect.y + rect.height && bounds.y + bounds.height >= rect.y) selected.add(node.id)
            }
            this.setNodeSelection(selected)
            this.draw(); return
        }
        const port = this.renderer.hitPort(this.graph.nodes, point)
        const node = this.renderer.hitNode(this.graph.nodes, point)
        this.hoveredPort = port ? { nodeId: port.node.id, portId: port.port.id } : null
        this.hoveredNodeId = node?.id ?? null
        this.canvas.style.cursor = port ? "crosshair" : node ? "grab" : "default"
        this.draw()
    }

    onCanvasMouseUp(event) {
        const point = this.getWorldPoint(event.clientX, event.clientY)
        if (this.panDrag) { this.panDrag = null; this.canvas.style.cursor = "default"; return }
        if (this.connectionDrag) { this.finishConnection(point); this.canvas.style.cursor = "default"; return }
        if (this.draggedNodeId !== null) {
            const before = this.dragBeforeSnapshot
            const count = this.selectedNodeIds.size
            this.draggedNodeId = null; this.dragStartPoint = null; this.dragNodeStarts = null; this.dragBeforeSnapshot = null
            if (this.recordEdit("move nodes", before)) this._setStatus(`moved ${count} node${count === 1 ? "" : "s"}`, "info")
        }
        if (this.selectionDrag) { this.selectionDrag = null; this.selectionBase = null; this.syncControls() }
        this.canvas.style.cursor = this.hoveredNodeId === null ? "default" : "grab"
        this.draw()
    }

    onCanvasMouseLeave(event) {
        if (this.connectionDrag) {
            this.connectionDrag = null
            this.hoveredPort = null
            this._setStatus("connection cancelled", "info")
            this.draw()
            return
        }
        if (this.draggedNodeId !== null) this.onCanvasMouseUp({ clientX: event.clientX, clientY: event.clientY })
        this.panDrag = null; this.selectionDrag = null; this.selectionBase = null
        this.hoveredNodeId = null; this.hoveredPort = null
        this.draw()
    }

    autoArrangeNodes() {
        if (!this.graph.nodes.length) return false
        const before = this.captureSnapshot()
        const incoming = new Map(this.graph.nodes.map((node) => [node.id, []]))
        const outgoing = new Map(this.graph.nodes.map((node) => [node.id, []]))
        for (const edge of this.graph.edges) { outgoing.get(edge.from.nodeId).push(edge.to.nodeId); incoming.get(edge.to.nodeId).push(edge.from.nodeId) }
        const indegree = new Map([...incoming].map(([id, list]) => [id, list.length]))
        const queue = this.graph.nodes.filter((node) => indegree.get(node.id) === 0).map((node) => node.id).sort((a, b) => a - b)
        const ordered = []
        while (queue.length) { const id = queue.shift(); ordered.push(id); for (const next of outgoing.get(id)) { indegree.set(next, indegree.get(next) - 1); if (indegree.get(next) === 0) queue.push(next) } }
        for (const node of this.graph.nodes) if (!ordered.includes(node.id)) ordered.push(node.id)
        const layer = new Map()
        for (const id of ordered) layer.set(id, Math.max(0, ...incoming.get(id).filter((source) => layer.has(source)).map((source) => layer.get(source) + 1)))
        const groups = new Map()
        for (const id of ordered) { const index = layer.get(id); if (!groups.has(index)) groups.set(index, []); groups.get(index).push(id) }
        const layout = this.viewConfig.config.layout
        for (const [column, ids] of groups) ids.forEach((id, row) => { const node = this.graphModel.node(id); node.x = layout.gridOriginX + column * layout.gridStepX; node.y = layout.gridOriginY + row * layout.gridStepY })
        this.contentBounds = this.calculateContentBounds(this.graph)
        this.recordEdit("auto arrange", before)
        this.fitToContent()
        this._setStatus(`auto-arranged ${this.graph.nodes.length} nodes by connections`, "success")
        return true
    }

    resetExecutionState() {
        for (const node of this.graph.nodes) node.execState = "idle"
        for (const edge of this.graph.edges) edge.execState = "idle"
        this.draw()
    }

    _handleRunProgress(method, payload) {
        if (payload.runId !== this.currentRunId) return okResult()
        const nodeId = Number(payload.nodeId || 0)
        assert(nodeId > 0, `view-ng progress ${method} missing nodeId`)
        const location = this.currentExecutionLocations.get(nodeId)
        assert(location, `view-ng progress references missing execution node ${nodeId}`)
        const visibleNodeId = visibleNgExecutionNodeId(location, this.activeGroupPath)
        const node = visibleNodeId === null ? null : this.graph.nodes.find((candidate) => candidate.id === visibleNodeId)
        if (!node) return okResult()
        const starting = method === "nodeStart" || method === "goalStart"
        const state = starting ? "running" : method === "nodeError" ? "error" : "done"
        node.execState = state
        for (const edge of this.graph.edges) {
            const connected = edge.from.nodeId === visibleNodeId || edge.to.nodeId === visibleNodeId
            if ((starting && edge.to.nodeId === visibleNodeId) || (!starting && connected)) edge.execState = state
        }
        this.draw()
        return okResult()
    }

    async run() {
        this.resetExecutionState()
        const runId = crypto.randomUUID()
        this.currentRunId = runId
        this._setStatus("compiling graph run...", "info")
        const compilerRead = unwrap(await runtime.invoke("fs/fs::read-text", "ng/compile-graph.lua"))
        const execution = flattenNgGraphWithLocations(this.getGraph(), { resolveLinked: this.linkedResolver() })
        const graph = execution.nodes
        this.currentExecutionLocations = execution.locations
        const progressSource = `local __ng_progress_plugin = ${luaStringLiteral(this.pluginId)}\nlocal __ng_progress_run_id = ${luaStringLiteral(runId)}\nfunction __ng_progress(method, nodeId, message)\n  host.call(__ng_progress_plugin .. "." .. method, { runId = __ng_progress_run_id, nodeId = nodeId, message = message })\nend`
        const compilerSource = `_G.input = ${luaStringLiteral(JSON.stringify(graph))}\n_G.ngProgressSource = ${luaStringLiteral(progressSource)}\n${compilerRead}`
        const generatedSource = unwrap(await runtime.invoke("lua/lua::run", compilerSource))
        this._setStatus("running generated graph code...", "info")
        const resultText = unwrap(await runtime.invoke("lua/lua::run", generatedSource))
        if (this.currentRunId !== runId) return false
        this._setStatus("graph run completed", "success")
        const goalResult = graph.some((node) => node.kind === NG_NODE_KINDS.GOAL) ? `: ${resultText}` : ""
        await runtime.call("ui.toast.success", { message: `Pipeline '${this.graphName}' completed${goalResult}` })
        return true
    }

    linkedPathsInGraph(graph) {
        const paths = new Set()
        const scan = (level) => {
            for (const node of level) {
                if (node.kind === NG_NODE_KINDS.FOR_EACH) scan(node.childGraph)
                else if (node.kind === NG_NODE_KINDS.GROUP) {
                    if (this.groupStorageMode(node) === "linked") paths.add(normalizeNgGroupPath(node.storage.path))
                    else scan(node.childGraph)
                }
            }
        }
        scan(graph)
        return paths
    }

    async loadLinkedGraphFS(path, ancestors = [], target = this.linkedGraphs) {
        const normalized = normalizeNgGroupPath(path)
        assert(!ancestors.includes(normalized), `view-ng linked Group cycle: ${[...ancestors, normalized].join(" -> ")}`)
        if (target.has(normalized)) return target.get(normalized)
        const document = parseNgGroupGraphDocument(unwrap(await runtime.invoke("fs/fs::read-text", normalized), normalized))
        target.set(normalized, document)
        for (const childPath of this.linkedPathsInGraph(document)) await this.loadLinkedGraphFS(childPath, [...ancestors, normalized], target)
        return document
    }

    async hydrateLinkedGraphs(rootGraph) {
        const hydrated = new Map()
        for (const path of this.linkedPathsInGraph(rootGraph)) await this.loadLinkedGraphFS(path, [], hydrated)
        this.linkedGraphs = hydrated
    }

    graphLinksTo(graph, targetPath, seen = new Set()) {
        for (const path of this.linkedPathsInGraph(graph)) {
            if (path === targetPath) return true
            if (seen.has(path)) continue
            seen.add(path)
            if (this.graphLinksTo(this.linkedResolver()(path), targetPath, seen)) return true
        }
        return false
    }

    assertLinkAllowedInActiveDocument(path, graph = this.linkedResolver()(path)) {
        const targetPath = this.activeLocation().documentPath
        if (!targetPath) return
        assert(path !== targetPath && !this.graphLinksTo(graph, targetPath), `view-ng linked Group cycle: ${targetPath} -> ${path} -> ${targetPath}`)
    }

    selectedRawGroup() {
        const selected = this.selectedGroup()
        if (!selected) return null
        const raw = this.activeGraph()
        return raw.find((node) => node.id === selected.id && node.kind === NG_NODE_KINDS.GROUP) || null
    }

    async importLinkedGroup() {
        const payload = unwrap(await runtime.call("ui.popup.open", { title: "Import Linked Group", size: "medium", tag: "view-files", props: { mode: "chooser", filter: "*.ng.json,*.json" } }))
        if (!payload || payload.cancelled) return false
        const selection = Array.isArray(payload.selection) ? payload.selection[0] : payload.selection
        const path = normalizeNgGroupPath(selection?.path || "")
        const before = this.captureSnapshot()
        const previousLinkedGraphs = this.linkedGraphs
        const importedLinkedGraphs = new Map(previousLinkedGraphs)
        await this.loadLinkedGraphFS(path, [], importedLinkedGraphs)
        this.linkedGraphs = importedLinkedGraphs
        try { this.assertLinkAllowedInActiveDocument(path) }
        catch (error) { this.linkedGraphs = previousLinkedGraphs; throw error }
        const center = this.viewportCenterWorld()
        const raw = this.activeGraph()
        const group = {
            id: this.nextNodeId(), kind: NG_NODE_KINDS.GROUP, x: Math.round(center.x), y: Math.round(center.y),
            name: path.split("/").pop().replace(/\.ng\.json$/i, "").replace(/\.json$/i, ""),
            inputs: [], outputs: [], storage: { mode: "linked", path },
        }
        syncNgGroupBoundary(group, raw, { resolveLinked: this.linkedResolver() })
        raw.push(group)
        this.replaceActiveGraph(raw, { autoFit: false })
        this.setNodeSelection([group.id], group.id)
        this.recordEdit("import linked Group", before)
        this.draw()
        this._setStatus(`imported linked Group from ${path}`, "success")
        return true
    }

    async exportSelectedGroup() {
        const group = this.selectedRawGroup()
        if (!group || this.groupStorageMode(group) !== "inline") return false
        const payload = unwrap(await runtime.call("ui.popup.open", { title: "Export Group", size: "medium", tag: "view-files", props: { mode: "saver", filter: "*.ng.json,*.json", defaultName: `${group.name || "group"}.ng.json` } }))
        if (!payload || payload.cancelled) return false
        const path = normalizeNgGroupPath(payload.path)
        if (this.graphPath) {
            const rootPath = normalizeNgGroupPath(this.graphPath)
            assert(path !== rootPath, "view-ng Group export cannot overwrite the root graph document")
            assert(!this.graphLinksTo(group.childGraph, rootPath), `view-ng Group export would link back to the root graph ${rootPath}`)
        }
        assert(!this.graphLinksTo(group.childGraph, path), `view-ng Group export would create a linked cycle through ${path}`)
        this.assertLinkAllowedInActiveDocument(path, group.childGraph)
        const document = serializeNgGroupGraphDocument(group.childGraph)
        await this.saveDocumentToPath(path, document)
        const before = this.captureSnapshot()
        this.linkedGraphs.set(path, cloneNgGraphFragment(group.childGraph))
        const raw = this.activeGraph()
        const index = raw.findIndex((node) => node.id === group.id)
        raw[index] = { ...raw[index], storage: { mode: "linked", path } }
        delete raw[index].childGraph
        this.replaceActiveGraph(raw, { autoFit: false })
        this.setNodeSelection([group.id], group.id)
        this.recordEdit("export Group", before)
        this.draw()
        this._setStatus(`exported Group to ${path}`, "success")
        await runtime.call("ui.toast.success", { message: `Exported Group to ${path}` })
        return true
    }

    makeSelectedGroupInline() {
        const group = this.selectedRawGroup()
        if (!group || this.groupStorageMode(group) !== "linked") return false
        const before = this.captureSnapshot()
        const raw = this.activeGraph()
        const index = raw.findIndex((node) => node.id === group.id)
        const remapped = cloneNgNodesWithNewIds(this.linkedResolver()(group.storage.path), this.nextNodeId())
        const next = { ...group, storage: { mode: "inline" }, childGraph: remapped.nodes }
        next.inputs = group.inputs.map((input) => ({ ...input, id: remapped.idMap.get(input.id) }))
        next.outputs = group.outputs.map((output) => ({ ...output, id: remapped.idMap.get(output.id) }))
        for (const node of raw) for (const input of node.inputs) if (input.srcNodeId === group.id && remapped.idMap.has(input.srcOutputId)) input.srcOutputId = remapped.idMap.get(input.srcOutputId)
        raw[index] = next
        this.replaceActiveGraph(raw, { autoFit: false })
        this.setNodeSelection([group.id], group.id)
        this.recordEdit("make Group inline", before)
        this.draw()
        this._setStatus(`made Group #${group.id} inline`, "success")
        return true
    }

    assertRootSavePathAvailable(path) {
        const normalized = normalizeNgGroupPath(path)
        assert(!this.linkedGraphs.has(normalized), `view-ng root graph path conflicts with linked Group document ${normalized}`)
        return normalized
    }

    async new() {
        const payload = unwrap(await runtime.call("ui.popup.open", { title: "Create Graph", size: "medium", tag: "view-files", props: { mode: "saver", filter: "*.ng.json,*.json", defaultName: "new-graph.ng.json" } }))
        if (!payload || payload.cancelled) return false
        assert(payload.path, "view-ng new graph requires selected path")
        this.assertRootSavePathAvailable(payload.path)
        await this.saveToPath(payload.path, [])
        await this.loadGraphFS(payload.path, false)
        await runtime.call("ui.toast.success", { message: `Created graph ${payload.path}` })
        return true
    }

    async open() {
        const payload = unwrap(await runtime.call("ui.popup.open", { title: "Load Graph", size: "medium", tag: "view-files", props: { mode: "chooser", filter: "*.ng.json,*.json" } }))
        if (!payload || payload.cancelled) return false
        const selection = payload.selection
        const path = Array.isArray(selection) ? selection[0]?.path : selection?.path
        assert(path, "view-ng load graph requires selected file path")
        await this.loadGraphFS(path)
        return true
    }

    async reload() {
        assert(this.graphPath.length > 0, "view-ng reload requires current graph path")
        await this.loadGraphFS(this.graphPath, false)
        await runtime.call("ui.toast.success", { message: `Reloaded graph from ${this.graphPath}` })
        return true
    }

    async save() {
        assert(this.graphPath.length > 0, "view-ng save requires current graph path")
        await this.saveLinkedGraphs()
        await this.saveToPath(this.graphPath, this.getGraph())
        this._setStatus(`saved graph to ${this.graphPath}`, "success")
        await runtime.call("ui.toast.success", { message: `Saved graph to ${this.graphPath}` })
        return true
    }

    async saveAs() {
        const payload = unwrap(await runtime.call("ui.popup.open", { title: "Save Graph As", size: "medium", tag: "view-files", props: { mode: "saver", filter: "*.ng.json,*.json", defaultName: `${this.graphName || "graph"}.ng.json` } }))
        if (!payload || payload.cancelled) return false
        assert(payload.path, "view-ng save-as requires selected path")
        this.assertRootSavePathAvailable(payload.path)
        await this.saveLinkedGraphs()
        await this.saveToPath(payload.path, this.getGraph())
        this.setGraphPath(payload.path)
        await runtime.call("ui.toast.success", { message: `Saved graph to ${payload.path}` })
        return true
    }

    async saveLinkedGraphs() {
        this.syncActiveGraph()
        const saved = new Set()
        const active = new Set()
        const savePath = async (path) => {
            if (saved.has(path)) return
            assert(!active.has(path), `view-ng linked Group cycle while saving: ${[...active, path].join(" -> ")}`)
            active.add(path)
            const graph = this.linkedResolver()(path)
            for (const childPath of this.linkedPathsInGraph(graph)) await savePath(childPath)
            await this.saveDocumentToPath(path, serializeNgGroupGraphDocument(graph))
            active.delete(path)
            saved.add(path)
        }
        for (const path of this.linkedPathsInGraph(this.rootGraph)) await savePath(path)
    }

    async saveDocumentToPath(path, document) {
        assert(typeof path === "string" && path.length > 0, "view-ng save requires path")
        unwrap(await runtime.invoke("fs/fs::write-text", path, `${JSON.stringify(document, null, 2)}\n`))
    }

    async saveToPath(path, graph) {
        await this.saveDocumentToPath(path, graph)
    }

    setGraphPath(path) {
        assert(typeof path === "string" && path.length > 0, "view-ng graph path is required")
        this.graphPath = path
        this.graphName = String(path.split("/").pop() || this.graphName).replace(/\.ng\.json$/i, "").replace(/\.json$/i, "")
        if (this.getAttribute("data-source") !== path) { this._suppressDataSourceReload = true; this.setAttribute("data-source", path); this._suppressDataSourceReload = false }
        this.syncBreadcrumbs()
    }

    async loadGraphFS(path, notify = true) {
        const graph = JSON.parse(unwrap(await runtime.invoke("fs/fs::read-text", path), path))
        const root = cloneNgGraph(graph)
        await this.hydrateLinkedGraphs(root)
        this.loadGraph(root)
        this.setGraphPath(path)
        this._setStatus(`loaded graph from ${path}`, "success")
        if (notify) await runtime.call("ui.toast.success", { message: `Loaded graph from ${path}` })
    }

    async resetGraph() {
        const before = this.captureSnapshot()
        this.linkedGraphs = new Map()
        this.loadGraph([], { resetHistory: false })
        this.recordEdit("reset graph", before)
        this._setStatus(`reset graph '${this.graphName}'`, "info")
    }

    _buildPersistedGraphDocument() {
        return this.getGraph()
    }

    refreshGraphSource() {
        this.setData(this.graph, { autoFit: false })
        this._setStatus(`rendering graph '${this.graphName}' from frontend state`, "info")
    }
}

if (!customElements.get("view-ng")) customElements.define("view-ng", ViewNg)

export { cloneNgGraph }
