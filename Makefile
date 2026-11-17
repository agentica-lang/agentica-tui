AGENTICA ?= agentica
CC ?= cc
PYTHON ?= python3
DART_SASS ?= $(HOME)/.local/opt/dart-sass
CFLAGS ?= -O2

# termbox2's own flags (its Makefile), position-independent for a shared library.
TB_CFLAGS = -std=c99 -Wall -Wextra -Wno-unused-result -fPIC -pthread -D_XOPEN_SOURCE -D_DEFAULT_SOURCE
LIB_FLAGS = -shared -Wl,-soname,libtermbox2.so
# The committed library, built by the `native` job of CI on ubuntu-22.04 (glibc 2.35), which agentica.toml names.
LIB = native/linux/libtermbox2.so
# Where native-verify builds the library to compare it with LIB.
FRESH ?= tmp/fresh/libtermbox2.so

SOURCES = tui.agc src/*.agc examples/*.agc tests/*.agc tests/fixtures/*.agc

.PHONY: native native-verify verify-vendor check test unit pty site site-serve site-sass

# Rebuilds the library in place (a local build may need a newer glibc than the committed one).
native:
	$(CC) $(TB_CFLAGS) $(CFLAGS) $(LIB_FLAGS) native/tui.c -o $(LIB)

# Builds the library into FRESH and compares it with the committed one, byte for byte: on ubuntu-22.04 they match.
native-verify:
	mkdir -p $(dir $(FRESH))
	$(CC) $(TB_CFLAGS) $(CFLAGS) $(LIB_FLAGS) native/tui.c -o $(FRESH)
	cmp -s $(FRESH) $(LIB) || { \
	  sha256sum $(FRESH) $(LIB) >&2; \
	  echo "$(LIB) is not this build of native/: commit the native artifact of CI (ubuntu-22.04)" >&2; \
	  exit 1; }

# termbox2.h is the release file, unchanged: its sha256 is in native/termbox2/VERSION.
verify-vendor:
	cd native/termbox2 && sed -n 's/^sha256 //p' VERSION | sha256sum -c -

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
