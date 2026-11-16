# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `TUI.render` takes the last `Grid` it gave and writes only the changed cells; `TUI.program` uses it, so a
  frame no longer clears the screen. `TUI.diff` compares two grids.
- `TUI.run(app)` opens the terminal and runs the Elm loop; ticks (`Sub.Tick`) and commands in tasks (`Cmd.Run`).
- `TUI.open`, a block form that opens the terminal and always restores it; a crash in the block comes back as an
  error.
- Drawing: `clear`, `set_cell`, `write`, `present`, `width`, `height`, `set_cursor` and `hide_cursor`, with `Style`,
  `Color` and `Attr`.
- Events: `poll_event` and `peek_event(timeout_ms)` give `Event.Key`, `Char`, `Mouse` or `Resize`; other tasks run,
  and may draw, while they wait; closing the screen ends a wait with an error.
- A mouse event with a key the library does not name is `Event.Key(Key.Other(code), mods)`; an unknown event kind
  is skipped.
- `Style` has the fields `bold`, `dim`, `italic`, `underline` and `reverse` (`attrs` still works), and
  `TUI.merge(base, over)` puts one style on top of another.
- A view tree: `TUI.Node`, built with `TUI.text`, `row`, `col`, `box` and `spacer`, drawn by
  `TUI.render(screen, node)`, measured in terminal columns, wrapped and clipped to the screen; `TUI.layout` gives its
  cells without a terminal.
- `TUI.program(screen, app)`, the Elm loop on an open screen: a `TUI.App` of `model`, `update`, `view` and
  `subscriptions`; `update` gives a `Step` of the next model and its commands.
- An SGR (1006) or urxvt (1015) mouse report keeps the input after it (a key, another report, a paste): the library
  reads these reports itself, strictly, and drops an unknown CSI sequence with parameters instead of reading it as
  a click; Alt+[ and a letter stay Escape (or Alt) and the characters.
- The README is short; the guide is in `docs/`, one topic per page.
- Bracketed paste: the screen turns it on and off, and a paste is one `Event.Paste(text)`, so its keys never come
  as key events. A `case` over `Event` needs the new variant (or `_`).
- `set_input_mode` (Escape or Alt, mouse on or off) and `set_output_mode` (`Normal`, `Colors256`, `Truecolor`).
- termbox2 v2.5.0, vendored, built into `libtermbox2`; the package ships it prebuilt for Linux x86_64 (glibc 2.33 or
  later), so `agentica add` and `agentica install` work with no C compiler. sha256 `45123ec3703f195630f4b54a8ef8f9cd97b99c6f3ebd2e05c1be060330189bab`; CI checks it is byte
  for byte a fresh build on ubuntu-22.04.

### Changed

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
- **Breaking:** needs Agentica 0.31.0 (was 0.20.0); an error of `TUI.open` and the other functions is an `Error`
  record, so `error(e)` reads its text as `e.message`.
