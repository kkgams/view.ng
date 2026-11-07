# Node Graph View

Canvas-based node graph editor for [GAMS](https://github.com/kkgams/gams), distributed as `view.ng.zip`.

| View ID | Source → deployment path | Purpose | Screenshot | License / original work |
| --- | --- | --- | --- | --- |
| `view-ng` | `src/views/view-ng.js` → `views/view-ng.js` | Edit, load/save and execute node graphs | Not available | [Apache-2.0](LICENSE), [NOTICE](NOTICE); [kkgams](https://github.com/kkgams) |

Register `view-ng` using an explicitly tagged archive URL with `#views/view-ng.js`. Retain LICENSE and NOTICE when installing. Existing releases retain their original asset names.

Requires a compatible GAMS Host, `plugin.fs`, `plugin.lua`, the popup/toast/tooltip UI Services, `view.files` and `view.ng-node`. Host `/core`, `/util`, `/widgets` libraries and styling are supplied separately, not bundled.

The local Project opens an empty graph without presets. Graph editing and saving use the configured file chooser. Pipeline execution also requires your Project's `ng/compile-graph.lua` and referenced Lua/code assets; this repository does not supply them.

## Development

Requires Make, Node.js 24+, Python 3 (stdlib), Git, curl, tar, unzip, zip and shasum. No package installation or compilation is needed. Local `gams.json` uses canonical View source and pinned released dependencies, without sibling checkouts.

| Command | Purpose |
| --- | --- |
| `make open` | Check source and open local `gams.json` in the released Host; download only if absent (macOS Apple Silicon) |
| `make tools/gams.app` | Download the Host and accompanying notices without launching it |
| `make test` | Check JavaScript syntax and local Project View entry paths; no graph runtime tests |
| `make package` | Build incremental `build.nosync/view.ng.zip` and `SHA256SUMS` |
| `make serve-docs` | Preview the pinned wiki; `DOCS_PORT` defaults to 8080 |
| `make docs` | Build the wiki into `build.nosync/site/` |
| `make validate-docs` | Validate wiki content |
| `make clean` | Remove `build.nosync/`, `tools/gams.app`, `tools/gams-release-notices` and downloaded `gams_modules/`; refuse tracked targets or directory symlinks |

First launch needs network access. Existing Host downloads are not updated implicitly; macOS security checks remain intact. Build output, temporary downloads and pinned justgook/wiki v1.4.0 stay under ignored `build.nosync/`. Static checks do not establish graph execution, native Host integration or theme rendering.
