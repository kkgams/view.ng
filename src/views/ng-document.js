// File documents use module-relative paths; the editor uses Project-relative paths.
function assertDocument(condition, message) {
    if (!condition) throw new Error(message)
}

export function projectPath(path) {
    assertDocument(typeof path === "string" && path.length > 0, "Graph path is required")
    assertDocument(!path.startsWith("/") && !/^[A-Za-z]:/.test(path) && !path.includes("\\") && !path.includes("\0"), `Invalid Project path: ${path}`)
    const parts = []
    for (const part of path.split("/")) {
        if (!part || part === ".") continue
        if (part === "..") {
            assertDocument(parts.length > 0, `Path escapes the Project: ${path}`)
            parts.pop()
        } else parts.push(part)
    }
    assertDocument(parts.length > 0, `Path must identify a file: ${path}`)
    return parts.join("/")
}

export function resolveModulePath(documentPath, dependency) {
    assertDocument(typeof dependency === "string" && dependency.length > 0 && !dependency.startsWith("/") && !/^[A-Za-z]:/.test(dependency), "Import must be a relative file path")
    const directory = projectPath(documentPath).split("/").slice(0, -1)
    return projectPath([...directory, dependency].join("/"))
}

export function relativeModulePath(documentPath, dependency) {
    const from = projectPath(documentPath).split("/").slice(0, -1)
    const to = projectPath(dependency).split("/")
    while (from.length && to.length && from[0] === to[0]) { from.shift(); to.shift() }
    return [...from.map(() => ".."), ...to].join("/")
}

export function mapDocumentPaths(document, documentPath, toRelative) {
    const result = structuredClone(document)
    const nodes = Array.isArray(result) ? result : result.nodes
    assertDocument(Array.isArray(nodes), "Graph document must contain a node array")
    const convert = toRelative ? relativeModulePath : resolveModulePath
    const visit = (level) => {
        for (const node of level) {
            if (node.kind === 2 && node.codePath) node.codePath = convert(documentPath, node.codePath)
            if (node.kind === 3 && node.storage?.mode === "linked") node.storage.path = convert(documentPath, node.storage.path)
            else if (Array.isArray(node.childGraph)) visit(node.childGraph)
        }
    }
    visit(nodes)
    return result
}

export function luaStringLiteral(value) {
    return '"' + [...new TextEncoder().encode(String(value))].map((byte) => `\\${String(byte).padStart(3, "0")}`).join("") + '"'
}

export function unfinishedGraphSource(document, diagnostic) {
    return `-- Generated node graph; edit through view-ng.\nfunction ng_graph_json()\n  return ${luaStringLiteral(JSON.stringify(document))}\nend\nfunction main()\n  error(${luaStringLiteral(diagnostic)})\nend\nfunction ng_graph_import(path) return import(path) end\nreturn { main = main, ng_graph_json = ng_graph_json, ng_graph_import = ng_graph_import }\n`
}
