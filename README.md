# agentica-tui

A terminal UI library for [Agentica](https://github.com/agentica-lang/agentica): a full-screen grid of cells with colors
and attributes, and key, mouse and resize events. It is [termbox2](https://github.com/termbox/termbox2) (v2.5.0,
vendored in `native/termbox2/`) called through the Agentica FFI, with a small C file (`native/tui.c`) built into the
same shared library.

## Get started

Needs Agentica 0.31.0 or later on Linux x86_64 (glibc 2.33 or later): the package ships
`native/linux/libtermbox2.so`, built by CI on ubuntu-22.04 from `native/`. There is no release tag yet: add it to
a project at a commit of `main` (the whole commit id):

```sh
agentica add tui https://github.com/agentica-lang/agentica-tui --ref COMMIT
```

To check the library: `sha256sum native/linux/libtermbox2.so` gives `32b1321834545539e9e1ef0fa073b8670a92061a172e1f594bd9399940999661` at this version, and the `native` job of
CI fails unless the committed file is byte for byte a fresh build of `native/` on ubuntu-22.04 (`make
native-verify`).

From a clone:

```sh
agentica examples/box.agc   # a box that moves with the arrow keys; q quits
```

`make native` rebuilds the library with your C compiler (it may then need your newer glibc; do not commit it: CI
builds the committed one, see `make native-verify`).

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
    error(e) -> IO.warn(e.message)
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
  tasks run while they wait, and may draw: every termbox2 call is under one lock. A close (the end of the block)
  ends a wait with an error within 50 ms.
- `set_input_mode(screen, mode, mouse)` with `InputMode.Esc` or `InputMode.Alt`; `set_output_mode(screen, mode)` with
  `OutputMode.Normal`, `Colors256` or `Truecolor`.
- `set_cursor(screen, x, y)`, `hide_cursor(screen)`.
- A call with a screen after it is closed stops the task with `RUNTIME-NATIVE-CLOSED`.
- `Event`: `Key(Key, Mods)`, `Char(String, Mods)`, `Mouse(Mouse, x, y, Mods)`, `Resize(width, height)`.
- `Key`: `Up`, `Down`, `Left`, `Right`, `Enter`, `Escape`, `Tab`, `BackTab`, `Backspace`, `Insert`, `Delete`, `Home`,
  `End`, `PageUp`, `PageDown`, `F(n)`, `Ctrl("c")`, `Other(code)`.
- `Style(fg:, bg:, bold:, dim:, italic:, underline:, reverse:, attrs:)`, every field optional, with `Color`
  (`Default`, the eight named colors for mode `Normal`, `Index(n)` for `Colors256`, `Rgb(r, g, b)` for `Truecolor`);
  `attrs` takes the other attributes of `Attr` (`Blink`, `Bright`, `Strikeout`, `DoubleUnderline`, `Overline`,
  `Invisible`, and the five above). `merge(base, over)` puts `over` on top: its colors that are not `Default`, and
  the attributes of both.

## View tree

Instead of placing text by hand, build a tree of `Node` values and draw it with `TUI.render(screen, node)`, which
clears the screen, draws the tree over all of it and presents it:

```ruby
def view(count: Int) -> TUI.Node
  title = TUI.Node.Text("Counter", TUI.Style(bold: true))
  value = TUI.Node.Text("count: #{count}", TUI.Style(fg: TUI.Color.Green))
  box = TUI.Node.Box(TUI.Node.Col([title, value]), 1, true, TUI.Style(fg: TUI.Color.Cyan))
  TUI.Node.Col([box, TUI.Node.Spacer, TUI.Node.Row([TUI.Node.Spacer, TUI.Node.Text("q quits", TUI.Style())])])
end
```

- `Text(text, style)`: the lines of `text` (`\n`), wrapped at spaces to the width it gets; a longer word is cut.
- `Row(children)`: side by side; each child takes the width it needs of what is left, and the height of the row.
- `Col(children)`: one under another; each child takes the whole width and the height it needs.
- `Box(child, padding, border, style)`: `padding` cells around the child and a line border when `border` is true,
  filled with `style`; the styles inside are drawn on it (`merge`).
- `Spacer`: an equal share of the room the other children of a `Row` or `Col` leave.

Widths are terminal columns (glibc's `wcwidth`, `src/width_table.agc`, made by `scripts/width_table.py`), so wide
characters take two. Nothing is drawn outside the screen. `TUI.layout(node, width, height)` gives the cells without
a terminal, for tests, and `TUI.wrap(text, width)` the wrapped lines.

`TUI.program(screen, model, update, view)` is an Elm-like loop: it renders `view(model)`, waits for an event, and
takes the model that `update(model, event)` gives, until `update` gives `none`; it gives the last model.
`examples/view.agc` is a counter written that way.

## Tests

```sh
make test AGENTICA=/path/to/agentica
```

`make check` checks every `.agc` file, `make unit` runs the unit tests of the pure helpers (`tests/*_test.agc`), and
`make pty` runs `tests/test_pty.py`: Python (standard library only) starts the programs of `tests/fixtures/` and the
example under a new pseudo-terminal, sends keys, a mouse click and a resize, and checks the screen, the colors and
the cursor, a draw while another task waits, a second `open`, and that the terminal modes and the locale come
back.

## Limits

- One terminal per process (termbox2 keeps global state): a second `open` while one is open is an error.
- While the screen is open the process has a UTF-8 `LC_CTYPE` (termbox2 needs it to measure characters); `open`
  puts the old one back at the close.
- Linux x86_64 only for now (no arm64, macOS or Windows library yet).
- `poll_event` and `peek_event` wait on the VM's compute pool, in calls of at most 50 ms.
- A close that lands between a wait's check that the screen is open and its next 50 ms call stops the waiting task
  with `RUNTIME-NATIVE-CLOSED` instead of the error (a narrow race).
- Not bound yet: grapheme clusters (`tb_set_cell_ex`), `tb_printf`, output modes 216 and grayscale.

## License

Apache License 2.0. See [LICENSE](LICENSE). termbox2 is MIT, see [native/termbox2/LICENSE](native/termbox2/LICENSE).
