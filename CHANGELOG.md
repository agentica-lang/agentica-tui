# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `TUI.open`, a block form that opens the terminal and always restores it; a crash in the block comes back as an
  error.
- Drawing: `clear`, `set_cell`, `write`, `present`, `width`, `height`, `set_cursor` and `hide_cursor`, with `Style`,
  `Color` and `Attr`.
- Events: `poll_event` and `peek_event(timeout_ms)` give `Event.Key`, `Char`, `Mouse` or `Resize`; other tasks run,
  and may draw, while they wait; closing the screen ends a wait with an error.
- A mouse event with a key the library does not name is `Event.Key(Key.Other(code), mods)`; an unknown event kind
  is skipped.
- `set_input_mode` (Escape or Alt, mouse on or off) and `set_output_mode` (`Normal`, `Colors256`, `Truecolor`).
- termbox2 v2.5.0, vendored, built into `libtermbox2` by `make native`.
- Needs Agentica 0.20.0.
