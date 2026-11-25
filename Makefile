AGENTICA ?= agentica
PYTHON ?= python3
DART_SASS ?= $(HOME)/.local/opt/dart-sass

SOURCES = tui.agc src/*.agc examples/*.agc tests/*.agc tests/fixtures/*.agc

.PHONY: check test unit pty site site-serve site-sass

check:
	for file in $(SOURCES); do $(AGENTICA) check $$file || exit 1; done

unit:
	$(AGENTICA) test tests

pty:
	AGENTICA="$(AGENTICA)" $(PYTHON) -m unittest discover -s tests -p 'test_*.py' -v

test: check unit pty

site site-serve site-sass: export PATH := $(DART_SASS):$(PATH)

THEME := site/themes/docs-theme

site-sass:
	@test -e $(THEME)/hugo.toml || { echo "The site needs its theme: git submodule update --init $(THEME)" >&2; exit 1; }
	@command -v sass >/dev/null || { \
		echo "The site needs Dart Sass: put its sass on PATH or in $(DART_SASS)" \
			"(pinned version in .github/workflows/pages.yml)" >&2; \
		exit 1; \
	}

$(THEME)/highlight/node_modules: $(THEME)/highlight/package.json $(THEME)/highlight/package-lock.json
	npm ci --prefix $(THEME)/highlight --ignore-scripts --no-audit --no-fund
	touch $@

# Builds the site into site/public with the docs theme. HUGO_FLAGS="--baseURL URL" sets the address.
site: site-sass $(THEME)/highlight/node_modules
	hugo --cleanDestinationDir --source site --panicOnWarning $(HUGO_FLAGS)
	node $(THEME)/highlight/highlight.mjs site/public
	@# The layouts print the title of a home or a list page, so its content must not start with the same heading.
	@# The redirect page of an alias has no heading, so it is skipped.
	@bad=0; for f in $$(find site/public -name index.html); do \
		grep -q 'http-equiv=refresh' $$f && continue; \
		n=$$(grep -o '<h1' $$f | wc -l); \
		[ $$n -eq 1 ] || { echo "$$f has $$n h1" >&2; bad=1; }; \
	done; [ $$bad -eq 0 ]

site-serve: site-sass
	hugo server --source site
