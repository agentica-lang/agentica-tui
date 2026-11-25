---
title: Low level
weight: 6
description: "TUI.Raw, the terminal by hand: cells, present, waiting for events, render, tasks and limits."
---

`TUI.Raw` is the terminal by hand, for what [`TUI.run`](elm-loop.md) does not cover. Under the [view tree](view-tree.md) is a grid of cells with a back buffer. Every function that can fail gives a `Result`.

- `open(body)`: opens the terminal (full screen, raw input, no cursor), gives the block a `Screen`, and closes it when the block ends.
- `width(screen)`, `height(screen)`: the size in cells.
- `clear(screen, style)`: fills the back buffer with spaces in `style`.
- `set_cell(screen, x, y, char, style)`: one character at column `x`, line `y` (from 0), with the zero-width ones that go on it (combining marks, joiners), at most 32 in all.
- `write(screen, x, y, text, style)`: text from `x`, `y`; what passes the right edge is cut. Gives the width of the text.
- `present(screen)`: shows the back buffer; nothing drawn appears before it.
- `set_cursor(screen, x, y)`, `hide_cursor(screen)`.
- `poll_event(screen)`, `peek_event(screen, timeout_ms)`: see [Events](events.md).
- `set_input_mode(screen, mode, mouse)`, `set_output_mode(screen, mode)`.
- `suspend(screen)`, `resume(screen)`: give the terminal back to another program (main screen, its own modes) and take it again with the modes it had; draw the whole screen after `resume`. Calling either twice changes nothing.
- `render(screen, node, last)`, `diff(old, new)`, `Grid`: see [View tree](view-tree.md).
- `program(backend(screen), app)`: the loop of `TUI.run` on a screen already open; it sets the modes of the app and puts the screen's own modes back when it ends. `backend(screen)` is the screen as a `TUI.Backend`, the record of functions the loop reaches the terminal through.

`style` may be left out. A loop written by hand with a one-second wait (in [`TUI.run`](elm-loop.md) it is a `Sub.Tick`):

```agentica
import TUI from "pkg/tui/tui"

def clock(screen: TUI.Raw.Screen) -> Result[Void]
  while true
    try TUI.Raw.clear(screen)
    _ = try TUI.Raw.write(screen, 0, 0, "#{Time.now_ms() / 1000} s, q quits")
    try TUI.Raw.present(screen)
    case try TUI.Raw.peek_event(screen, 1000)
      some(TUI.Event.Char("q", _)) -> break
      _ -> nil
    end
  end

  ok()
end

def main() -> Void
  case TUI.Raw.open(&clock)
    ok(_) -> puts("bye")
    error(e) -> IO.warn(e.message)
  end
end
```

`examples/box.agc` is a longer loop by hand: a box that moves with the arrow keys or a click, under a line with the size and the last event.

![examples/box.agc: a status line with the size of the terminal and the last key, and a cyan box](images/box.png)

## Tasks and locks

The screen is one value behind a lock: any task may draw while another waits for an event. `poll_event` and `peek_event` wait on the input without holding it. Closing the screen (the end of the `open` block) ends a wait with an error.

A call with a screen after it is closed gives `error("tui: the screen is closed")`, and one while it is suspended `error("tui: the terminal is suspended")`.

## Limits

- One terminal per process: a second `open` while one is open is an error.
- The terminal is standard input and output, and both must be terminals (`Terminal.tty?`): `open` is an error otherwise.
- The VM gives back the terminal's mode when the program ends, `System.exit` in the `open` block too, but nothing runs then to leave the alternate screen: return from the block to close the screen.
- `suspend` and the close ask the terminal for its status (`ESC [ 5 n`) so that the read of standard input that waits ends and takes none of the keys that follow. A terminal that does not answer delays them by half a second.
- Mouse reports are the SGR form (1006); a terminal that only knows the older forms sends none.
