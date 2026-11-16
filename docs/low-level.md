# Low level

Under the [view tree](view-tree.md) is a grid of cells with a back buffer. Every function that can fail gives a
`Result`.

- `open(body)`: opens the terminal (full screen, raw input, no cursor), gives the block a `Screen`, and closes it
  when the block ends.
- `width(screen)`, `height(screen)`: the size in cells.
- `clear(screen, style)`: fills the back buffer with spaces in `style`.
- `set_cell(screen, x, y, char, style)`: one character at column `x`, line `y` (from 0).
- `write(screen, x, y, text, style)`: text from `x`, `y`; what passes the right edge is cut. Gives the width of
  the text.
- `present(screen)`: shows the back buffer; nothing drawn appears before it.
- `set_cursor(screen, x, y)`, `hide_cursor(screen)`.
- `poll_event(screen)`, `peek_event(screen, timeout_ms)`: see [Events](events.md).
- `set_input_mode(screen, mode, mouse)`, `set_output_mode(screen, mode)`.

`style` may be left out. A loop with a tick, which [`TUI.program`](elm-loop.md) does not have:

```ruby
import TUI from "pkg/tui/tui"

def clock(screen: TUI.Screen) -> Result[Void]
  while true
    try TUI.clear(screen)
    _ = try TUI.write(screen, 0, 0, "#{Time.now_ms() / 1000} s, q quits")
    try TUI.present(screen)
    case try TUI.peek_event(screen, 1000)
      some(TUI.Event.Char("q", _)) -> break
      _ -> nil
    end
  end

  ok()
end

def main() -> Void
  case TUI.open(&clock)
    ok(_) -> puts("bye")
    error(e) -> IO.warn(e.message)
  end
end
```

## Tasks and locks

`poll_event` and `peek_event` wait in calls of at most 50 ms. Other tasks run while they wait, and may draw: every
termbox2 call holds one lock. Closing the screen (the end of the `open` block) ends a wait with an error.

A call with a screen after it is closed stops the task with `RUNTIME-NATIVE-CLOSED`. A close that lands between a
wait's check that the screen is open and its next 50 ms call does the same, instead of giving the error.

## Limits

- One terminal per process: termbox2 keeps global state, so a second `open` while one is open is an error.
- While the screen is open the process has a UTF-8 `LC_CTYPE` (termbox2 needs it to measure characters); the close
  puts the old one back.
- Not bound: grapheme clusters (`tb_set_cell_ex`), `tb_printf`, output modes 216 and grayscale.
