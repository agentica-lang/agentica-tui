# agentica-tui

A terminal UI package for Agentica, in Agentica alone: the `Terminal` builtin and VT sequences.

## Map

```text
tui.agc                the public API: re-exports src/; `module Raw` wraps src/terminal.agc, `module Testing`
                       src/fake.agc
src/backend.agc        Backend, what the loop needs of a terminal (a record of functions), Modes, render
src/terminal.agc       the terminal: `Screen` (a value behind one lock), open and close, the cell buffers, the
                       reader of standard input, the resize task, suspend and resume, event waits, the backend
src/input.agc          bytes to events: keys, CSI and SS3 sequences, SGR mouse, paste, split reads (pure)
src/ansi.agc           the bytes for the terminal: the diff of two grids, colors, modes (pure)
src/fake.agc           a backend with no terminal for tests: scripted events, the calls kept in order
src/event.agc          Event, Key, Mouse, Mods, InputMode (pure)
src/style.agc          Color, Attr, Style, OutputMode (pure)
src/view.agc           the view tree and its layout into cells (pure)
src/grid.agc           Grid, a screen as a value, and diff (pure)
src/widgets.agc        table, the lines of a table built from the tree (pure)
src/program.agc        the Elm loop: App, Step, Cmd, Sub, run and program
examples/              the demos (box.agc, view.agc)
site/                  the docs site (Hugo): content/ has the user guide, one topic per page, assets/images/ the
                       screenshots; the look comes from themes/docs-theme (a submodule); `make site` builds it
tests/*_test.agc       unit tests of the pure helpers; program_test runs the loop on the fake backend
tests/test_pty.py      end-to-end tests under a pseudo-terminal; drives tests/fixtures/*.agc and the demo
```

## Commands

- Binary: the release pinned in `.github/workflows/ci.yml` (`AGENTICA_VERSION`, with its sha256). Keep a local copy
  under `.tools/` (gitignored), never `/tmp`.
- `make test AGENTICA=...`: `check`, `unit` (`agentica test tests`), `pty` (`python3 -m unittest`).
- CI (`ci.yml`): `make test` on Linux x86_64, macOS arm64 and macOS x86_64; on Windows x86_64 `agentica check` of every
  file and the unit tests (no pty). Claim a system as supported only where CI runs the terminal tests on it.

## Rules

- Search with `rg`.
- On a hot path (layout, grids), add to a list with `push` or pass it down: `xs + ys` copies both lists when `ys`
  has more than 32 items.
- Load the `agentica-programming` and `agentica-code-guidelines` skills of the Agentica repository before writing
  `.agc` code. Lines are at most 119 characters; `agentica fmt --check` passes.
- The package API is `tui.agc`: it re-exports the Elm loop, the view tree, events and styles, and its `Raw` block
  wraps the terminal by hand (`Screen`, open, draw, events). Input parsing and the bytes of the screen stay pure
  (`input.agc`, `ansi.agc`) so the unit tests run without a terminal.
- The terminal is standard input and output; the only things taken from the system are `Terminal.raw`,
  `Terminal.size`, `Terminal.tty?` and `System.Signal.Winch`. No `extern`, no native code.
- Every change of the `Screen` goes through the lock of `src/terminal.agc` (`locked`, `drawing`), and a wait never
  holds it while it sleeps. A function given to them never stops with a runtime error: the screen would stay taken.
- A stop of the reader (suspend, close) asks the terminal for its status and waits for the answer, so that no read of
  standard input is left pending for another program to lose a key to.
- Tests are hermetic: no real terminal, Python standard library only. Behavior visible on the screen is a pty test;
  edge cases of pure helpers are unit tests.
- Every user-visible change adds a line under `## [Unreleased]` of `CHANGELOG.md`.
- A line that is only `end` is followed by an empty line, except before another `end`, `else`, `elsif`, a closing `)`
  or `]`, or the end of the file (`[style] blank_line_after_end`).
