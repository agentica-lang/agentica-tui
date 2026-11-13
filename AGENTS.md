# agentica-tui

A terminal UI package for Agentica: termbox2 through the FFI.

## Map

```text
tui.agc                the public API: re-exports src/
src/termbox.agc        the extern block (resource Screen) and the wrappers: open, draw, present, events, modes
src/event.agc          Event, Key, Mouse, Mods, InputMode; decodes the fields of a struct tb_event (pure)
src/style.agc          Color, Attr, Style, OutputMode; the termbox2 attribute values (pure)
native/termbox2/       termbox2.h vendored at a tag (VERSION has the tag, commit and sha256), its MIT LICENSE
native/tui.c           termbox2 plus the tui_* functions the bindings call: one lock around every termbox2 call,
                       tui_shutdown (the free function of Screen), tui_wait_event (waits of at most 50 ms)
examples/box.agc       the demo
tests/*_test.agc       unit tests of the pure helpers
tests/test_pty.py      end-to-end tests under a pseudo-terminal; drives tests/fixtures/*.agc and the demo
```

## Commands

- Binary: the release pinned in `.github/workflows/ci.yml` (`AGENTICA_VERSION`, with its sha256). Keep a local copy
  under `.tools/` (gitignored), never `/tmp`.
- `native/linux/libtermbox2.so` is committed: the `native` job of CI builds it on ubuntu-22.04 (`make
  native-verify` compares a fresh build with it, byte for byte) and uploads the build. After a change of `native/`,
  commit that artifact (`gh run download RUN -n libtermbox2-linux-x86_64`), never a local build: it may need a newer
  glibc, and update its sha256 in the README and the CHANGELOG. `make native` rebuilds it in place for local work.
  `make native-verify` fails on a machine whose gcc or glibc differs from ubuntu-22.04 (it prints both sha256): only
  the CI job is the judge.
- `make test AGENTICA=...`: `check`, `unit` (`agentica test tests`), `pty` (`python3 -m unittest`).
- `make verify-vendor`: the sha256 of `native/termbox2/termbox2.h` against its `VERSION`.

## Rules

- Search with `rg`.
- Load the `agentica-programming` and `agentica-code-guidelines` skills of the Agentica repository before writing
  `.agc` code. Lines are at most 119 characters; `agentica fmt --check` passes.
- The package API is `tui.agc`: it re-exports `Screen` and the wrappers, never a `tui_*` function. The extern block
  of `src/termbox.agc` declares the resource `Screen`, so Agentica makes the block public as a whole (its `tui_*`
  functions too) and puts it above the wrappers; everything else of that file after the wrappers is after `private`.
  Decoding and attribute values stay pure (no extern) so the unit tests run without the library.
- termbox2 is never edited: a change goes in `native/tui.c`. A new termbox2 tag updates `native/termbox2/VERSION`.
- The extern block calls only `tui_*` functions of `native/tui.c`, each taking the screen (so the VM refuses a
  call after the close and never frees the screen during one) and each holding the lock around termbox2. A wait
  never holds the lock while it sleeps.
- Tests are hermetic: no real terminal, Python standard library only. Behavior visible on the screen is a pty test;
  edge cases of pure helpers are unit tests.
- Every user-visible change adds a line under `## [Unreleased]` of `CHANGELOG.md`.
- A line that is only `end` is followed by an empty line, except before another `end`, `else`, `elsif`, a closing `)`
  or `]`, or the end of the file (`[style] blank_line_after_end`).
