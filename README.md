# view.ng

Initial prerelease extraction of the GAMS `view` Project Unit from
`views/view-ng.js`. Source behavior is intentionally unchanged.
## Install mapping

Prospective local candidate: `view.ng-0.2.1.zip` and `SHA256SUMS` for
`v0.2.1` (prepared, not yet published). After tag-triggered publication,
download and verify the checksum. Unpack into a separate staging
folder: copy its deployment files to the same Project-relative paths, and keep its
LICENSE, NOTICE, README.md and unit.json under `notices/project-units/view.ng/`.
Do not unpack metadata over the Project's own README or license. The entry is
`views/view-ng.js` (the archive strips `src/`). Configure that path in Project Config.
The example's checksum-pinned installer performs these steps for all Units.
Install dependencies listed below separately; they are not bundled.
The Host source contract targeted is 2.0.3; package-level GUI validation is a release
gate, not a claim about every future Host. See `PUBLISHING.md` for release gates.

## Current prerelease Host contract

This Unit runs inside the GAMS Host. Absolute JavaScript imports under `/core`,
`/util`, and `/widgets` are Host-owned package-library APIs and are deliberately not
vendored here. In particular, `/core/runtime.js` supplies plugin calls. There is no
arbitrary shared SDK repository. The Host must also provide the browser DOM/custom
elements environment and base/theme semantic CSS contract expected by the source.

Repository dependencies in this extraction set:
- `plugin.fs`
- `plugin.lua`
- `ui-service.popup`
- `ui-service.toast`
- `ui-service.tooltip`
- `view.files`
- `view.ng-node`

These are repository names only. Deployed JavaScript filenames and Project Config ids
remain unchanged. The list records actual static configuration/call boundaries; it
does not claim that every interaction has a standalone dynamic integration test.

## Verify

Requires Node.js 24 and Python 3 (stdlib only).

```sh
npm test
```

Verification scans Unit-owned `src/` assets plus its test script/package/workflow
metadata, checks each JavaScript file in that boundary with `node --check`, rejects
unresolved or escaping local imports/assets, permits only the documented Host
absolute import roots, and resolves non-data CSS `url(...)` assets. Git internals,
dependency installs, and build outputs are outside the scan boundary.

## Release status

GAMS-authored code is Apache-2.0. `package.json` remains private: distribution is a
GitHub Release ZIP, never npm or OCI. A pushed matching version tag authorizes publication; source/evidence and artifact
checks remain required, with no digest approval variables or required source branch. Identified third-party terms are
retained in NOTICE, including 98.css MIT terms for the theme. See `LICENSING.md`
and `PUBLISHING.md`.

## Local Project and documentation

Requires Node.js 24+, Python 3, Make, curl, tar and unzip. On macOS Apple Silicon:

```sh
make open            # check source and open this repository's gams.json
make serve-docs      # http://localhost:8080; DOCS_PORT overrides
make validate-docs
make docs            # portable documentation under build/site/
```

`make open` downloads the released Host into ignored `tools/gams.app` when absent,
retains its notices in `tools/gams-release-notices/`, and explicitly sets
`GAMS_APP_CWD`. It never updates an existing app implicitly or bypasses Gatekeeper.
The Project uses local canonical View source; no sibling checkout is needed.
First startup installs pinned released dependencies into ignored `gams_modules/`
and requires network access. Source-only Views need no compilation; `make build`
checks JavaScript syntax and local Project entry paths before launch.

Documentation uses pinned justgook/wiki v1.4.0, with downloaded engine and output
under ignored `build/`. `build-docs` remains an alias. Every push to `release`
publishes via `make docs`, independently of version tags; select GitHub Actions
as the repository's Pages source. A pushed matching version tag authorizes the Unit release from any branch.

The local Project opens an empty graph with no preset files. Graph editing and
saving use the configured file chooser. Pipeline execution additionally needs your
Project’s `ng/compile-graph.lua` and any referenced Lua/code assets; they are not
provided by this View repository.
