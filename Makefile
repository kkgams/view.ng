.DEFAULT_GOAL := open
.DELETE_ON_ERROR:
PRESET_FILES := $(shell find presets -type f -name '*.lua' | sort)
PRESET_DIRS := $(shell find presets -type d | sort)
ZIP_FILES := README.md LICENSE NOTICE src/views/view-ng-node.js build.nosync/views/view-ng.js $(PRESET_FILES)
export TMPDIR := $(abspath build.nosync/tmp)
export PYTHONPYCACHEPREFIX := $(abspath build.nosync/pycache)
PYTHON ?= python3
NODE ?= node
LUA ?= lua
CURL ?= curl
GAMS_RELEASE_API ?= https://api.github.com/repos/kkgams/gams/releases/latest
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)
DOCS_PORT ?= 8080
WIKI_VERSION := v1.4.0
WIKI_REPOSITORY := https://github.com/justgook/wiki
WIKI_MAKEFILE := build.nosync/wiki-$(WIKI_VERSION).mk
WIKI_ENGINE := $(abspath build.nosync/wiki-$(WIKI_VERSION))

.PHONY: open test tests docs serve-docs validate-docs package clean

build.nosync/views/view-ng.js: src/views/view-ng.js src/views/ng-document.js src/lua/compile-graph.lua scripts/bundle.py
	$(PYTHON) -B scripts/bundle.py

test: build.nosync/views/view-ng.js
	$(NODE) --input-type=module --check < build.nosync/views/view-ng.js
	@for source in src/views/*.js; do $(NODE) --input-type=module --check < "$$source" || exit; done
	LUA="$(LUA)" $(NODE) --test test/*.test.mjs
	$(LUA) test/lua/graph_test.lua
	$(LUA) test/lua/presets_test.lua $(PRESET_FILES)
	$(PYTHON) -c 'import json,pathlib; c=json.loads(pathlib.Path("gams.json").read_text()); assert all(pathlib.Path(v["url"]).is_file() for v in c["ui"]["views"].values() if not v["url"].startswith("https://"))'

tests: test

# Retain an existing app; never update it implicitly.
tools/gams.app: | build.nosync/tmp
	@test "$(UNAME_S)" = Darwin && test "$(UNAME_M)" = arm64 || \
		{ echo 'GAMS release download requires macOS Apple Silicon' >&2; exit 1; }
	@test ! -e tools/gams-release-notices || \
		{ echo 'tools/gams-release-notices already exists; move it aside before reinstalling GAMS' >&2; exit 1; }
	@mkdir -p tools
	@set -eu; stage=$$(mktemp -d "$(TMPDIR)/gams-download.XXXXXX"); \
		trap 'rm -rf "$$stage"' EXIT; \
		$(CURL) --fail --location --silent --show-error "$(GAMS_RELEASE_API)" --output "$$stage/release.json"; \
		url=$$($(PYTHON) -c 'import json, sys; release = json.load(open(sys.argv[1])); assets = [a for a in release["assets"] if a["name"].startswith("GAMS-") and a["name"].endswith("-macos-aarch64.zip")]; assert len(assets) == 1, "Expected exactly one GAMS macOS Apple Silicon ZIP asset"; print(assets[0]["browser_download_url"])' "$$stage/release.json"); \
		$(CURL) --fail --location --silent --show-error "$$url" --output "$$stage/gams.zip"; \
		unzip -q "$$stage/gams.zip" -d "$$stage/unpacked"; \
		test -f "$$stage/unpacked/GAMS.app/Contents/Info.plist"; \
		test -x "$$stage/unpacked/GAMS.app/Contents/MacOS/gams"; \
		mv "$$stage/unpacked/GAMS.app" "$$stage/GAMS.app"; \
		mv "$$stage/unpacked" tools/gams-release-notices; \
		mv "$$stage/GAMS.app" "$@"

open: build.nosync/views/view-ng.js tools/gams.app
	GAMS_APP_CWD="$(CURDIR)" GAMS_CONFIG="gams.json" ./tools/gams.app/Contents/MacOS/gams

build.nosync/tmp:
	@mkdir -p "$@"

$(WIKI_MAKEFILE): | build.nosync/tmp
	@mkdir -p "$(@D)"
	@set -eu; trap 'rm -f "$@.tmp"' EXIT; \
		$(CURL) --fail --location --retry 3 "$(WIKI_REPOSITORY)/raw/$(WIKI_VERSION)/Makefile" -o "$@.tmp"; \
		mv "$@.tmp" "$@"

docs serve-docs validate-docs: $(WIKI_MAKEFILE) | build.nosync/tmp
	$(MAKE) -f "$(WIKI_MAKEFILE)" "$(if $(filter docs,$@),build,$(patsubst %-docs,%,$@))" WIKI_REPOSITORY="$(WIKI_REPOSITORY)" WIKI_VERSION="$(WIKI_VERSION)" WIKI_ENGINE="$(WIKI_ENGINE)" WIKI_SOURCE="$(abspath docs)" WIKI_OUTPUT="$(abspath build.nosync/site)" PORT="$(DOCS_PORT)"

package: build.nosync/SHA256SUMS build.nosync/view.ng.zip

# Directory prerequisites also invalidate the archive when presets are removed.
build.nosync/view.ng.zip: $(ZIP_FILES) $(PRESET_DIRS) Makefile | build.nosync/tmp
	rm -f "$@"
	cd build.nosync && zip -q -X "view.ng.zip" views/view-ng.js
	cd src && zip -q -X "../$@" views/view-ng-node.js
	zip -q -X "$@" README.md LICENSE NOTICE $(PRESET_FILES)

build.nosync/SHA256SUMS: build.nosync/view.ng.zip
	cd build.nosync && shasum -a 256 view.ng.zip > SHA256SUMS

clean:
	$(PYTHON) -B scripts/clean.py
