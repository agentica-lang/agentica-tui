# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-11-25

### Added

- `Cmd.Suspend(work)` gives the terminal back while `work` runs another program on it (an editor) and takes it again
  with the same modes; `TUI.Raw.suspend` and `resume` do it by hand, and `TUI.Testing` keeps `Suspended` and
  `Resumed` calls.
- In both input modes, Escape and a printable ASCII character (other than `[` and `O`, which start escape
  sequences) or Backspace read together are that key with Alt (Alt+B, Alt+Backspace), as Escape and Enter already
  were; Escape alone stays a key.
- A terminal key keeps its Ctrl (Ctrl+Left is `Key(Left, Mods(ctrl: true))`).
- Combining marks and zero-width joiners are drawn on the cell before them in `text` and `line` (variation selectors
  are left out), and `TUI.Raw.set_cell` takes a character with its zero-width ones.
- `TUI.line(spans)`, one line of styled `TUI.span`s that never wraps; `TUI.list(items, selected)`, a list that marks
  its selected item and scrolls to it in the room its siblings leave (`TUI.list_first` maps a row to its item);
  `TUI.table(cells)`, the aligned lines of a table. A `case` over `Node` needs the variants `Line` and `List`.
- `TUI.Raw.program` puts the screen's input and output modes back when it ends.
- Alt+Enter is `Key.Enter` with `alt` in both input modes (was Escape, then Enter in `InputMode.Esc`).
- `TUI.App` has `cursor`, where the terminal cursor shows for a model (`TUI.Cursor`).
- `TUI.Testing`: `resize`, `screen`, `wait_for`, `style_at` and `cursor` read and change the fake terminal, `rows`
  shows a wide character once, and a full call buffer is an error that says how to read it.
- `TUI.render` takes the last `Grid` it gave and writes only the changed cells; `TUI.program` uses it, so a
  frame no longer clears the screen. `TUI.diff` compares two grids.
- `TUI.run(app)` opens the terminal and runs the Elm loop; ticks (`Sub.Tick`) and commands in tasks (`Cmd.Run`).
- `TUI.open`, a block form that opens the terminal and always restores it; a crash in the block comes back as an
  error.
- Drawing: `clear`, `set_cell`, `write`, `present`, `width`, `height`, `set_cursor` and `hide_cursor`, with `Style`,
  `Color` and `Attr`.
- Events: `poll_event` and `peek_event(timeout_ms)` give `Event.Key`, `Char`, `Mouse` or `Resize`; other tasks run,
  and may draw, while they wait; closing the screen ends a wait with an error.
- A key the library does not name (`CSI n ~`) is `Event.Key(Key.Other(n), mods)`; an unknown sequence is dropped.
- `Style` has the fields `bold`, `dim`, `italic`, `underline` and `reverse` (`attrs` still works), and
  `TUI.merge(base, over)` puts one style on top of another.
- A view tree: `TUI.Node`, built with `TUI.text`, `row`, `col`, `box` and `spacer`, drawn by
  `TUI.render(screen, node)`, measured in terminal columns, wrapped and clipped to the screen; `TUI.layout` gives its
  cells without a terminal.
- `TUI.program(screen, app)`, the Elm loop on an open screen: a `TUI.App` of `model`, `update`, `view` and
  `subscriptions`; `update` gives a `Step` of the next model and its commands.
- An SGR (1006) mouse report keeps the input after it (a key, another report, a paste): the library reads these
  reports strictly, and drops an unknown CSI sequence with parameters instead of reading it as a click; Alt+[ and a
  letter stay Escape (or Alt) and the characters.
- The README is short; the guide is the docs site, https://www.agentica-lang.com/agentica-tui/, one topic per page,
  with screenshots of the examples.
- Bracketed paste: the screen turns it on and off, and a paste is one `Event.Paste(text)`, so its keys never come
  as key events. A `case` over `Event` needs the new variant (or `_`).
- `set_input_mode` (Escape or Alt, mouse on or off) and `set_output_mode` (`Normal`, `Colors256`, `Truecolor`).

### Changed

- The package runs on macOS as well as Linux: CI runs the unit tests and the pseudo-terminal tests on Linux x86_64,
  macOS arm64 and macOS x86_64, and checks the code and runs the unit tests on Windows x86_64 (the terminal is not
  tested there).
- **Breaking:** the package is written in Agentica alone, on `Terminal` (raw mode, size, resize signal) and VT
  sequences: termbox2, `native/` and the prebuilt `libtermbox2.so` are gone, so there is no C code to build or
  trust. What changes for a program:
  - The terminal is standard input and output, which must both be terminals (it was `/dev/tty`); `open` is an error
    otherwise.
  - A call on a closed screen is `error("tui: the screen is closed")` (it stopped the task with
    `RUNTIME-NATIVE-CLOSED`).
  - `System.exit` inside `open` gives back the terminal's mode, but no longer leaves the alternate screen.
  - The process keeps its `LC_CTYPE`: the library no longer measures characters with the C library.
  - Mouse reports are SGR (1006) only; the older urxvt (1015) and X10 forms are not read.
  - A lone Escape waits 50 ms for the rest of a sequence before it is the key.
  - A mouse report has the `shift`, `alt` and `ctrl` of its button code in `mods`.
  - The named colors show in every output mode, `Index` in `Colors256` and `Truecolor`, `Rgb` in `Truecolor` (in
    `Colors256` as the nearest color of the palette); a color the mode cannot show is the terminal's own.
  - `suspend` and the close ask the terminal for its status (`ESC [ 5 n`) so that no read of standard input is left
    pending (a cancelled read still races for the next bytes: agentica-lang/agentica#2013). A terminal that does not
    answer delays them by half a second, and an answer later than that reaches the next program that reads the
    terminal (a shell may show `^[[0n`).
  - A cell with a wide character, or with marks on it, is followed by an absolute cursor move.
  - The close restores the terminal even when a task cancelled while it drew took the screen's lock with it; do not
    cancel a task that waits for an event or draws.
- The package needs Agentica 0.39.0, where `Term` is a reserved type name; the fake terminal of `TUI.Testing` keeps
  its state in `TermState`.
- **Breaking:** `TUI.Backend` has `suspend` and `resume`, which a backend built by hand gives; a `case` over `Cmd`
  needs `Suspend`.
- **Breaking:** in `InputMode.Esc`, `Char` and `Key` events can carry `alt: true`, and a terminal key can carry
  `ctrl: true`: a `case` that reads a letter as typed text checks `mods.alt`. Escape and a key in one read are Alt and
  that key.
- **Breaking:** `TUI.Raw.program` takes a `TUI.Backend` (`TUI.Raw.backend(screen)` for an open screen) instead of
  the screen; the program loop reaches the terminal only through that record, so `TUI.Testing.fake` runs a program in
  a test with scripted events and the calls it made.
- In a `col`, the lists fill the free lines first and the spacers share what they leave (was an even share).
- **Breaking:** the terminal by hand moves to `TUI.Raw`: `open`, `width`, `height`, `clear`, `set_cell`, `write`,
  `present`, `render`, `diff`, `program`, `set_cursor`, `hide_cursor`, `poll_event`, `peek_event`,
  `set_input_mode`, `set_output_mode`, `Screen`, `Grid` and `Glyph` (was `TUI.open` and so on); `TUI.run` is the
  main way.
- `TUI.App` has `input`, `mouse` and `output` for the terminal modes, which `TUI.run` sets.
- The messages that come after a `Cmd.Quit` in one batch no longer reach `update`.
- **Breaking:** `TUI.render` gives `Result[Grid]` (was `Result[Void]`).
- **Breaking:** `TUI.program` takes a `TUI.App`; `update` gets your messages and gives `TUI.Step(model:, cmds:)`,
  and `Cmd.Quit` ends the loop (was `Step.Continue` and `Step.Quit`).
- Layout and grids are about twice as fast on a 200x60 screen.
- **Breaking:** needs Agentica 0.32.0 (was 0.20.0); an error of `TUI.open` and the other functions is an `Error`
  record, so `error(e)` reads its text as `e.message`.

### Fixed

- `TUI.Raw.present` (and so `render` and `program`) goes on with a write the terminal cut short, from where it
  stopped, and after an interrupt; nothing is sent twice.
- `TUI.run` and `TUI.Raw.program` put the input mode back when setting the output mode fails.
