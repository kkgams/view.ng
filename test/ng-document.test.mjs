import test from "node:test"
import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { mapDocumentPaths, projectPath, resolveModulePath, relativeModulePath, luaStringLiteral, unfinishedGraphSource } from "../src/views/ng-document.js"

test("nested imports resolve relative to their owning document", () => {
    assert.equal(resolveModulePath("graphs/sub/root.ng.lua", "../nodes/code.lua"), "graphs/nodes/code.lua")
    assert.equal(resolveModulePath("graphs/groups/a.ng.lua", "b.ng.lua"), "graphs/groups/b.ng.lua")
    assert.equal(relativeModulePath("graphs/sub/root.ng.lua", "nodes/code.lua"), "../../nodes/code.lua")
})

test("paths cannot escape the Project", () => {
    for (const path of ["../bad.lua", "/bad.lua", "C:/bad.lua", "a/../../bad.lua", "bad\\file", "a\0b"]) assert.throws(() => projectPath(path))
    assert.throws(() => resolveModulePath("root.ng.lua", "../bad.lua"))
    assert.throws(() => resolveModulePath("graphs/root.ng.lua", "C:/bad.lua"))
    assert.equal(projectPath("./graphs/a/../root.ng.lua"), "graphs/root.ng.lua")
})

test("document paths round trip without altering source or linked contents", () => {
    const graph = [
        { kind: 2, codePath: "nodes/code.lua" },
        { kind: 3, storage: { mode: "linked", path: "groups/shared.ng.lua" } },
        { kind: 7, childGraph: [{ kind: 2, codePath: "graphs/local.lua" }] },
    ]
    const original = structuredClone(graph)
    const relative = mapDocumentPaths(graph, "graphs/root.ng.lua", true)
    assert.equal(relative[0].codePath, "../nodes/code.lua")
    assert.equal(relative[1].storage.path, "../groups/shared.ng.lua")
    assert.equal(relative[2].childGraph[0].codePath, "local.lua")
    assert.deepEqual(mapDocumentPaths(relative, "graphs/root.ng.lua", false), graph)
    assert.deepEqual(graph, original)
    const envelope = { format: "gams.ng.group", version: 1, nodes: graph }
    assert.deepEqual(mapDocumentPaths(mapDocumentPaths(envelope, "graphs/root.ng.lua", true), "graphs/root.ng.lua", false), envelope)
})

test("Lua strings encode exact UTF-8 bytes, including control characters", () => {
    assert.equal(luaStringLiteral('"\n\0é'), '"\\034\\010\\000\\195\\169"')
    const source = unfinishedGraphSource([], 'missing "goal"')
    assert.match(source, /function ng_graph_json\(\)/)
    assert.match(source, /function main\(\)\n  error\(/)
})

test("unfinished Lua documents retain exact graph metadata and fail only on execution", () => {
    const graph = [{ kind: 2, name: "é\n\0quoted\"" }]
    const source = unfinishedGraphSource(graph, "missing goal")
    const script = `local module = assert(load(${luaStringLiteral(source)}))()\nassert(type(module.ng_graph_import) == "function")\nlocal ok, diagnostic = pcall(module.main)\nassert(not ok and diagnostic:find("missing goal", 1, true))\nio.write(module.ng_graph_json())\n`
    const result = spawnSync(process.env.LUA || "lua", ["-"], { input: script, encoding: "utf8" })
    assert.equal(result.status, 0, result.stderr || result.error?.message)
    assert.deepEqual(JSON.parse(result.stdout), graph)
})
