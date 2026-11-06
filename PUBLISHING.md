# Owner publishing procedure

Distribution is a GitHub Release ZIP, not npm registry or OCI. Prepared version:
0.2.1 / v0.2.1. Local tagging is authorized; preparation does not push.

## Release authorization

A pushed matching version tag authorizes publication from any branch. Manual
checksum approval variables and release-branch HEAD requirements are removed.
This policy migration does not perform or authorize local commits, tags, pushes,
publication, remote configuration changes or source/legal evidence refreshes.

This is not evidence of hosted Linux CI, GUI/Host consumption, registry visibility,
immutable policy, draft-first rehearsal or anonymous public-byte verification.
Version, source closure, evidence and candidate-byte checks remain strict.
Never move or overwrite an existing tag.

## Current local validation

`npm test` passed with Node 24.19.0 and Python 3: source verification and
14 Python tests.
These are local checks, not GUI/Host integration or hosted CI results.

1. Source closure, LICENSE, NOTICE and NOTICE-EVIDENCE.json are prepared;
   the owner dropped pending human checksum/license reviews for unchanged bytes.
   Apache-2.0 is the owner's standing choice for GAMS-authored code. Identified
   98.css CSS/artwork portions retain their complete MIT terms in theme NOTICE.
   Its comparison snapshot is not a claim of the original imported version.
2. Run `npm test` with Node 24 and Python 3. Review source bytes and deployment paths.
3. Pushes to `release` build, verify and upload candidates without manual
   checksum approval variables. Changed source/evidence still fails loudly.
4. Push a matching version tag from any branch to authorize publication.
   Tag CI independently tests, checks tag/version/workflow commit identity,
   stages and checks a fresh ZIP. The publish job rechecks identity, bytes and
   generated SHA256SUMS using the automatic GitHub token. GitHub API errors fail
   closed. Only version tags create **public** releases. Never move a pushed tag.
5. GUI/Host consumption and hosted CI have not been established by local tests.
6. Any existing GitHub Release, including draft, blocks creation. No overwrite
   path. Recover with a new version rather than replacing published assets.

Local rehearsal (no approval environment variables required):

```sh
python3 scripts/release.py stage --tag v0.2.1
python3 scripts/release.py check --tag v0.2.1
```

Staging output must not already exist. ZIP contains deployment paths without
`src/`, LICENSE, NOTICE, README.md and unit.json. SHA256SUMS is a sidecar. Install
source files at their mapped Project-relative paths; retain metadata and notices
under `notices/project-units/<repository>/`, never over the Project's own files.
Install dependencies separately. The example's pinned installer automates this.
The target Host source contract is 2.0.3; package-level GUI validation is a release
gate, not an assertion that every later Host is compatible.

## Coordinated local preparation (local tags authorized)

Own version v0.2.1 is prospective, not a published download or dependency pin.
The retained, verified source Host target is 2.0.3; no 2.1.0 GUI claim is made.
SOURCE.json preserves the historical extraction snapshot and appends a separate
metadata and bounded test-fixture maintenance delta. NOTICE-EVIDENCE.json audits
the src closure and its recorded extra inputs, NOT the complete prepared tree.
Evidence, NOTICE, LICENSE and upstream terms retain their original bytes.

Release workflows now accept matching tags from any branch without manual
checksum approval variables. Fresh tag stage/check and authenticated absence
checks still precede direct public creation. There is no common publisher migration,
private-draft byte rehearsal, immutable-policy gate or stable anonymous public
byte recheck. Recorded immutable policy was disabled; no fresh remote check was
performed. These publication coverage gaps and GUI/Host consumption gates
are not local-tag blockers. Pending human hosted review is superseded by the
owner's instruction; unavailable technical coverage is not claimed as passed.
Existing releases/tags must never be overwritten.
The standalone protocol tests retain synthetic v0.1.0 fixtures. Their setup now
temporarily binds release.__file__ to the synthetic root, with unittest cleanup,
so branch() reads that fixture's package instead of this checkout's version.
Stock npm test validates the prepared checkout directly. Tag/version mismatch
and source/evidence/artifact checks remain strict. Non-release-branch matching
tags are accepted; mismatched tags and workflow commits are rejected.
