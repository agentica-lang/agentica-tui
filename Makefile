AGENTICA ?= agentica
CC ?= cc
PYTHON ?= python3
CFLAGS ?= -O2

# termbox2's own flags (its Makefile), position-independent for a shared library.
TB_CFLAGS = -std=c99 -Wall -Wextra -Wno-unused-result -fPIC -pthread -D_XOPEN_SOURCE -D_DEFAULT_SOURCE
LIB_FLAGS = -shared -Wl,-soname,libtermbox2.so
# The committed library, built by the `native` job of CI on ubuntu-22.04 (glibc 2.35), which agentica.toml names.
LIB = native/linux/libtermbox2.so
# Where native-verify builds the library to compare it with LIB.
FRESH ?= tmp/fresh/libtermbox2.so

SOURCES = tui.agc src/*.agc examples/*.agc tests/*.agc tests/fixtures/*.agc

.PHONY: native native-verify verify-vendor check test unit pty

# Rebuilds the library in place (a local build may need a newer glibc than the committed one).
native:
	$(CC) $(TB_CFLAGS) $(CFLAGS) $(LIB_FLAGS) native/tui.c -o $(LIB)

# Builds the library into FRESH and compares it with the committed one, byte for byte: on ubuntu-22.04 they match.
native-verify:
	mkdir -p $(dir $(FRESH))
	$(CC) $(TB_CFLAGS) $(CFLAGS) $(LIB_FLAGS) native/tui.c -o $(FRESH)
	cmp $(FRESH) $(LIB) || { echo "$(LIB) is not the build of native/: commit the native artifact of CI" >&2; exit 1; }

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
