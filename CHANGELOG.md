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
- termbox2 v2.5.0, vendored, built into `libtermbox2`; the package ships it prebuilt for Linux x86_64 (glibc 2.33 or
  later), so `agentica add` and `agentica install` work with no C compiler. sha256 `32b1321834545539e9e1ef0fa073b8670a92061a172e1f594bd9399940999661`; CI checks it is byte
  for byte a fresh build on ubuntu-22.04.

### Changed

- **Breaking:** needs Agentica 0.31.0 (was 0.20.0); an error of `TUI.open` and the other functions is an `Error`
  record, so `error(e)` reads its text as `e.message`.
