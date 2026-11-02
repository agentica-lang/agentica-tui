AGENTICA ?= agentica
CC ?= cc
PYTHON ?= python3
CFLAGS ?= -O2

# termbox2's own flags (its Makefile), position-independent for a shared library.
TB_CFLAGS = -std=c99 -Wall -Wextra -Wno-unused-result -fPIC -pthread -D_XOPEN_SOURCE -D_DEFAULT_SOURCE

ifeq ($(shell uname -s),Darwin)
# A macOS library of a package is a universal binary.
LIB = native/macos/libtermbox2.dylib
LIB_FLAGS = -dynamiclib -arch arm64 -arch x86_64 -install_name @rpath/libtermbox2.dylib
else
LIB = native/linux/libtermbox2.so
LIB_FLAGS = -shared -Wl,-soname,libtermbox2.so
endif

SOURCES = tui.agc src/*.agc examples/*.agc tests/*.agc tests/fixtures/*.agc

.PHONY: native verify-vendor check test unit pty clean

native: $(LIB)

$(LIB): native/tui.c native/termbox2/termbox2.h
	mkdir -p $(dir $@)
	$(CC) $(TB_CFLAGS) $(CFLAGS) $(LIB_FLAGS) native/tui.c -o $@

# termbox2.h is the release file, unchanged: its sha256 is in native/termbox2/VERSION.
verify-vendor:
	cd native/termbox2 && sed -n 's/^sha256 //p' VERSION | sha256sum -c -

check: native
	for file in $(SOURCES); do $(AGENTICA) check $$file || exit 1; done

unit:
	$(AGENTICA) test tests

pty: native
	AGENTICA="$(AGENTICA)" $(PYTHON) -m unittest discover -s tests -p 'test_*.py' -v

test: check unit pty

clean:
	rm -rf native/linux native/macos
