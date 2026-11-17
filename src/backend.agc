## What a program needs of a terminal, as a record of functions: its size, drawing cells and showing them, waiting
## for events, and the modes. termbox2 is one backend (`termbox.agc`); a fake one (`fake.agc`) runs a program in a
## test.

import Ev from "event"
import Gr from "grid"
import St from "style"
import View from "view"

## The modes a program runs the terminal with: how Escape is read, whether mouse events come, how colors are sent.
struct Modes
  input: Ev.InputMode = Ev.InputMode.Esc
  mouse: Bool = false
  output: St.OutputMode = St.OutputMode.Normal
end

## Where the terminal cursor shows: column x, row y.
struct Cursor
  x: Int
  y: Int
end

struct Backend
  width: Fn[Int]
  height: Fn[Int]
  ## Fills the screen with spaces of the default style.
  clear: Fn[Result[Void]]
  ## Writes cells; "" is a cell a wide character on its left covers.
  draw: Fn[List[View.Cell], Result[Void]]
  ## Shows what was drawn.
  present: Fn[Result[Void]]
  ## Waits up to so many milliseconds for an event: none when none came, an error once the terminal is gone.
  next_event: Fn[Int, Result[Optional[Ev.Event]]]
  ## Sets the modes, and gives the function that puts back the modes before.
  set_modes: Fn[Modes, Result[Fn[Result[Void]]]]
  set_cursor: Fn[Int, Int, Result[Void]]
  hide_cursor: Fn[Result[Void]]
  ## Gives the terminal back to another program, and takes it again (`TUI.Raw.suspend` and `resume`).
  suspend: Fn[Result[Void]]
  resume: Fn[Result[Void]]
end

## Draws `node` over the whole screen and shows it. Only the cells that differ from `last` (what the screen shows) are
## written; with no `last`, the screen is cleared first. With `cursor`, the cursor shows there, or is hidden when it
## holds none; with no `cursor` it stays as it was. Gives what the screen shows now, for the next call.
def render(
  backend: Backend,
  node: View.Node,
  last: Optional[Gr.Grid] = none,
  cursor: Optional[Optional[Cursor]] = none,
) -> Result[Gr.Grid]
  # The size is read after the clear: termbox2 takes a new size then.
  shown = case last
    some(grid) -> grid
    none -> try cleared(backend)
  end

  next = Gr.of(node, backend.width.call(), backend.height.call())
  try backend.draw.call(Gr.diff(shown, next))
  if cursor.some?
    try placed(backend, cursor.unwrap!)
  end

  try backend.present.call()
  ok(next)
end

private

def placed(backend: Backend, cursor: Optional[Cursor]) -> Result[Void]
  case cursor
    some(at) -> backend.set_cursor.call(at.x, at.y)
    none -> backend.hide_cursor.call()
  end
end

def cleared(backend: Backend) -> Result[Gr.Grid]
  try backend.clear.call()
  ok(Gr.blank(backend.width.call(), backend.height.call()))
end
