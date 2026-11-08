# Node Graph View

Canvas-based node graph editor for [GAMS](https://github.com/kkgams/gams), distributed as `view.ng.zip`.

| Item | Source → deployment path | Purpose | License |
| --- | --- | --- | --- |
| `view-ng` | `src/views/view-ng.js` + helpers/compiler → `views/view-ng.js` | Edit, save and execute Lua graph documents | [Apache-2.0](LICENSE), [NOTICE](NOTICE) |
| `view-ng-node` | `src/views/view-ng-node.js` → `views/view-ng-node.js` | Internal node editor popup | Apache-2.0 |
| Lua node presets | `presets/` → `presets/` | Importable node functions | Apache-2.0 |

Register both Views from the same explicitly tagged archive. Project configuration owns the preset menu definitions; local `gams.json` supplies the node names and ports. Make assembles the graph compiler and document helpers into the graph View module because the Host loads Project Views through blob URLs. Keep LICENSE and NOTICE. Host `/core`, `/util`, `/widgets` and styling remain separately supplied dependencies.

## Lua documents

Save graphs as `.ng.lua`. Each document defines `main(context)` and `ng_graph_json()`, and returns its module exports for `import`. The original editor graph is embedded as JSON; generated execution code is replaced on every save. An unfinished graph remains saveable: its `main()` raises the compilation diagnostic while its metadata remains readable. Legacy JSON documents and inline node scripts are not supported.

Node code modules return a function:

```lua
return function(inputs, outputs, context)
    outputs[1] = inputs[1]
end
```

Dependencies resolve relative to the importing Lua file, including nested imports. Node implementations and linked Group documents are imported on execution, so their changes are picked up on the next run without regenerating the parent. Inline Groups remain part of the parent. The saved module contains its execution-plan builder, which expands current Group metadata at execution rather than persisting a flattened Group snapshot. Imports are cached within one Lua invocation, not across runs. A changed Group interface can invalidate its parent and raises an error.

The editor displays Project-relative paths; saved documents store paths relative to their own file. Save As preserves dependency destinations. Run saves edited linked Group documents before executing the current root snapshot. Unchanged Groups are not rewritten; conflicting external edits block a save instead of being overwritten. Reload to display external Group changes. External code, Group documents and other required assets must remain available; a graph file is not an asset bundle.

`main()` runs without editor progress reporting. The editor supplies `{pluginId=..., runId=...}` as its optional context; reporting includes node locations. Execution outside the editor still requires a compatible Lua runtime and any APIs used by node code. Opening a Lua document evaluates its top-level code to call `ng_graph_json()`; only open trusted files.

## Development

Use `nix develop` for the pinned tools. Requires Make, Node.js 24+, Lua 5.4+, Python 3, Git, curl, tar, unzip, zip and shasum. The local Project uses the assembled graph View and canonical node editor source and pinned released UI dependencies, without requiring sibling checkouts or package installation.

The local Project pins `plugin.lua` v0.3.0 for the named-entry/arguments/import API; the Host installs the published component on launch. No manual component installation or sibling build is required. Other dependencies: `plugin.fs`, the popup/toast/tooltip UI Services, `view.files`, and `view.code`.

| Command | Purpose |
| --- | --- |
| `make open` | Build the View without tests and launch local `gams.json`; install pinned dependencies and download the Host only if absent (macOS Apple Silicon) |
| `make tools/gams.app` | Download the released Host with its notices, without launching it |
| `make test` / `make tests` | JavaScript syntax, document path/serialization tests, native Lua graph tests and local View entry checks |
| `make package` | Incremental `build.nosync/view.ng.zip` and `SHA256SUMS` |
| `make serve-docs` | Preview pinned wiki; independent `DOCS_PORT` defaults to 8080 |
| `make docs` / `make validate-docs` | Build / validate documentation |
| `make clean` | Remove recreatable `build.nosync/`, downloaded Host/notices and `gams_modules/`; refuse tracked targets or directory symlinks |

Existing downloads are not updated implicitly. Static checks do not establish native Host integration or theme rendering. Existing release assets and tags are unchanged.
