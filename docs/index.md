---
title: Node Graph View
status: reference
---

# Node Graph View

Canvas-based node graph editor for [GAMS](https://github.com/kkgams/gams), distributed as `view.ng.zip`.

| View ID | Source → deployment path | Purpose | Screenshot |
| --- | --- | --- | --- |
| `view-ng` | `src/views/view-ng.js` → `views/view-ng.js` | Edit, load/save and execute node graphs | Not available |

Register `view-ng` using an explicitly tagged archive URL with `#views/view-ng.js`. Existing releases retain their original asset names.

Requires a compatible GAMS Host, `plugin.fs`, `plugin.lua`, the popup/toast/tooltip UI Services, `view.files` and `view.ng-node`. Host `/core`, `/util`, `/widgets` libraries and styling are supplied separately.

The local Project opens an empty graph without presets. Graph editing and saving use the configured file chooser. Pipeline execution additionally requires your Project's `ng/compile-graph.lua` and referenced Lua/code assets; they are not supplied here.

## Development

Requires Make, Node.js 24+, Python 3 (stdlib), Git, curl, tar, unzip, zip and shasum. Local `gams.json` uses canonical View source and pinned released dependencies without sibling checkouts or package installation.

| Command | Purpose |
| --- | --- |
| `make open` | Check source and open local `gams.json` in the released Host; download only if absent (macOS Apple Silicon) |
| `make tools/gams.app` | Download the Host and accompanying notices |
| `make test` | Check JavaScript syntax and local Project View entry paths; no graph runtime tests |
| `make package` | Build incremental `build.nosync/view.ng.zip` and `SHA256SUMS` |
| `make serve-docs` | Preview the pinned wiki; `DOCS_PORT` defaults to 8080 |
| `make docs` | Build the wiki into `build.nosync/site/` |
| `make validate-docs` | Validate wiki content |
| `make clean` | Remove `build.nosync/`, `tools/gams.app`, `tools/gams-release-notices` and downloaded `gams_modules/`; refuse tracked targets or directory symlinks |

First launch needs network access. Existing Host downloads are not updated implicitly. The pinned justgook/wiki v1.4.0 engine, temporary downloads and output stay under ignored `build.nosync/`. Static checks do not establish graph execution, native Host integration or theme rendering.
