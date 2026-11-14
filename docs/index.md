---
title: Node Graph View
status: reference
---

# Node Graph View

Edit `.ng.lua` documents visually and execute them in GAMS. The `view.ng.zip` archive contains `view-ng`, its internal `view-ng-node` popup, with the Lua compiler embedded in the graph View module. Register both View entries from the same tagged archive and retain its other files and notices. The archive also includes importable node modules under `presets/` and their names, groups and ports in `presets.json`. Local `gams.json` references this catalog.

## Include the preset catalog

Extract `presets.json` and the complete `presets/` directory from the archive
into your Project root. Set `ui.views.view-ng-node.config.presets` in `gams.json`:

```json
{ "$ref": "presets.json#/presets" }
```

Use a Host with `$ref` and `$file` support. All 68 definitions are included.
Catalog `codePath` values use `{ "$file": "presets/…lua" }`; the Host resolves
each path relative to the catalog, locally or inside a remote ZIP. The Unit
still receives ordinary Project-relative string paths, not `$file` objects. Extraction as shown above
still works when the directory structure is preserved. An older downloaded
Host may not support this syntax; existing downloads are not updated implicitly.
Domain-specific nodes still need their corresponding plugins and Project data.
Project Save preserves unchanged references; edited preset definitions are written
into the active config without modifying `presets.json`.

## Documents and dependencies

A document defines `main(context)` and `ng_graph_json()`. The latter returns the original editor graph as JSON, preserving positions and Group hierarchy. Saving regenerates execution code; manual generated-code edits are overwritten. Unfinished graphs save normally, with `main()` raising their compilation diagnostic. Older JSON documents are not supported.

Code nodes reference Lua modules returning a function:

```lua
return function(inputs, outputs, context)
    outputs[1] = inputs[1]
end
```

Node modules and linked Group documents are imported relative to the Lua file that imports them. Nested imports retain their own file's directory. Updates are picked up on the next execution without regenerating the parent; incompatible Group port changes fail explicitly. The saved module builds its execution plan from current Group metadata on each run. Keep referenced dependencies and runtime APIs available. Other assets are read through filesystem or domain APIs, not imported as Lua modules.

The editor shows Project-relative paths and stores module-relative paths in documents. Save As preserves dependency destinations. Run saves edited linked Groups, then executes the current root graph. Unchanged linked files are not rewritten; conflicting external changes require a reload before saving. Reload also refreshes their visual representation. Inline Groups stay embedded.

Calling `main()` without context omits progress reporting. GAMS supplies `{pluginId=..., runId=...}` for editor progress. Running without the editor still requires compatible `plugin.lua` APIs and whatever services the nodes use. Opening calls the metadata function after evaluating the file's top-level code: only open trusted Lua documents.

## Local development

Make assembles the graph View from its canonical source, document helpers and compiler into `build.nosync/views/view-ng.js`; the Host loads Project Views through blob URLs, so no relative module loading is required. The local Project uses that module and canonical node editor source and pinned released UI dependencies. The Project pins published `plugin.lua` v0.3.0 for the named-entry/arguments/import API; the Host installs it on launch. No manual component installation or sibling checkout is required.

| Command | Purpose |
| --- | --- |
| `make open` | Build the View without tests and open the Project in the released Host |
| `make test` / `make tests` | Check JavaScript syntax, document paths, native Lua graph behavior and local View paths |
| `make package` | Build incremental `build.nosync/view.ng.zip` and checksums |
| `make serve-docs` | Preview docs, independent `DOCS_PORT=8080` |
| `make docs` | Build docs under `build.nosync/site/` |
| `make validate-docs` | Validate wiki content |
| `make clean` | Remove recreatable build output, downloaded Host/notices and installed `gams_modules/`; refuse tracked files and directory symlinks |

Use `nix develop` for the pinned tools. Requires Make, Node.js 24+, Lua 5.4+, Python 3, Git, curl, tar, unzip, zip and shasum. Dependencies include the compatible Host, `plugin.fs`, `plugin.lua` v0.3.0, popup/toast/tooltip UI Services, `view.files` and `view.code`. Host libraries and styling remain external. Existing downloaded Hosts are preserved, and published assets/tags remain unchanged.
