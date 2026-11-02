# agentica-tui

A terminal UI library for [Agentica](https://github.com/agentica-lang/agentica): a full-screen grid of cells with colors
and attributes, and key, mouse and resize events. It is [termbox2](https://github.com/termbox/termbox2) (v2.5.0,
vendored in `native/termbox2/`) called through the Agentica FFI, with a small C file (`native/tui.c`) built into the
same shared library.

## Get started

Needs Agentica 0.20.0 or later, a C compiler and `make` (Linux; macOS should work but is not tested yet).

```sh
make native                 # builds native/linux/libtermbox2.so (native/macos/libtermbox2.dylib on macOS)
agentica examples/box.agc   # a box that moves with the arrow keys; q quits
```

## Example

```ruby
import TUI from "pkg/tui/tui"

def draw(screen: TUI.Screen) -> Result[Void]
  try TUI.write(screen, 0, 0, "hello, press a key", TUI.Style(fg: TUI.Color.Green))
  try TUI.present(screen)
  _ = try TUI.poll_event(screen)
  return ok()
end

def main() -> Void
  case TUI.open(&draw)
    ok(_) -> puts("bye")
    error(message) -> IO.warn(message)
  end
end
```

`TUI.open` restores the terminal when the block ends, whatever it returns. A runtime error in the block comes back as
`error("task crashed: ...")` after the terminal is restored, and `System.exit` in the block still restores it (the
screen is a native resource that the end of the run closes).

## API

All in `tui.agc` (`import TUI from "pkg/tui/tui"`). Every function that can fail returns a `Result`.

- `open(body)`: opens the terminal (full screen, raw input, no cursor) and gives the block a `Screen`.
- `width(screen)`, `height(screen)`: the size in cells.
- `clear(screen, style)`, `set_cell(screen, x, y, char, style)`, `write(screen, x, y, text, style)` (gives the width
  of the text; what passes the right edge is cut): draw into a back buffer. `style` may be left out.
- `present(screen)`: shows the back buffer.
- `poll_event(screen)`: waits for an `Event`; `peek_event(screen, timeout_ms)` gives `none` after the timeout. Other
  tasks run while they wait.
- `set_input_mode(screen, mode, mouse)` with `InputMode.Esc` or `InputMode.Alt`; `set_output_mode(screen, mode)` with
  `OutputMode.Normal`, `Colors256` or `Truecolor`.
- `set_cursor(screen, x, y)`, `hide_cursor(screen)`.
- `Event`: `Key(Key, Mods)`, `Char(String, Mods)`, `Mouse(Mouse, x, y, Mods)`, `Resize(width, height)`.
- `Key`: `Up`, `Down`, `Left`, `Right`, `Enter`, `Escape`, `Tab`, `BackTab`, `Backspace`, `Insert`, `Delete`, `Home`,
  `End`, `PageUp`, `PageDown`, `F(n)`, `Ctrl("c")`, `Other(code)`.
- `Style(fg:, bg:, attrs:)` with `Color` (`Default`, the eight named colors for mode `Normal`, `Index(n)` for
  `Colors256`, `Rgb(r, g, b)` for `Truecolor`) and `Attr` (`Bold`, `Underline`, `Reverse`, `Italic`, `Blink`, `Dim`,
  `Bright`, `Strikeout`, `DoubleUnderline`, `Overline`, `Invisible`).

## Tests

```sh
make test AGENTICA=/path/to/agentica
```

`make check` checks every `.agc` file, `make unit` runs the unit tests of the pure helpers (`tests/*_test.agc`), and
`make pty` runs `tests/test_pty.py`: Python (standard library only) starts the programs of `tests/fixtures/` and the
example under a new pseudo-terminal, sends keys, a mouse click and a resize, and checks the screen and that the
terminal modes come back.

## Limits

- Not installable from another project yet: `agentica install` would bring the package without the built library,
  and building it inside `deps/` changes the package hash. A release will publish prebuilt libraries for the
  `[native.termbox2]` entries of `agentica.toml`.
- One terminal per process, used from one task at a time (termbox2 keeps global state).
- Linux is tested; the macOS build (a universal `.dylib`) is not tested yet; no Windows.
- `poll_event` and `peek_event` run on the VM's compute pool: a call that waits holds one of its threads.
- Not bound yet: grapheme clusters (`tb_set_cell_ex`), `tb_printf`, output modes 216 and grayscale.

## License

Apache License 2.0. See [LICENSE](LICENSE). termbox2 is MIT, see [native/termbox2/LICENSE](native/termbox2/LICENSE).
