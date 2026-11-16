## A terminal UI library on termbox2: an Elm loop over a view tree, with key, mouse, paste, resize and tick
## messages. `Raw` is the terminal by hand: cells, present and waiting for events.
##
## ```ruby
## import TUI from "pkg/tui/tui"
##
## enum Msg
##   Key(TUI.Event)
## end
##
## def update(count: Int, msg: Msg) -> TUI.Step[Int, Msg]
##   case msg
##     Msg.Key(TUI.Event.Char("q", _)) -> TUI.Step(model: count, cmds: [TUI.Cmd.Quit])
##     Msg.Key(_) -> TUI.Step(model: count + 1)
##   end
## end
##
## def view(count: Int) -> TUI.Node = TUI.text("#{count} keys, q quits")
##
## def subscriptions(_count: Int) -> List[TUI.Sub[Msg]] = [TUI.Sub.Events(->(event) { Msg.Key(event) })]
##
## def main() -> Void
##   case TUI.run(TUI.App(model: 0, update: &update, view: &view, subscriptions: &subscriptions))
##     ok(count) -> puts("#{count} keys")
##     error(e) -> IO.warn(e.message)
##   end
## end
## ```

import Bd from "src/backend"
import Ev from "src/event"
import Fk from "src/fake"
import Gr from "src/grid"
import Pg from "src/program"
import St from "src/style"
import Tb from "src/termbox"
import View from "src/view"
import Wg from "src/widgets"

export Pg.run
export Pg.App
export Pg.Step
export Pg.Cmd
export Pg.Sub
export Bd.Backend
export Bd.Modes
export Bd.Cursor
export Ev.Event
export Ev.Key
export Ev.Mouse
export Ev.Mods
export Ev.InputMode
export St.Color
export St.Attr
export St.Style
export St.merge
export St.OutputMode
export View.Node
export View.Border
export View.Frame
export View.text
export View.row
export View.col
export View.box
export View.spacer
export View.Cell
export View.layout
export View.wrap
export View.Span
export View.line
export View.span
export View.list
export View.list_first
export Wg.table

## A fake terminal for the tests of a program: run it with `Raw.program(Testing.backend(fake), app)`, send it events,
## and read back what the program drew.
module Testing
  type Fake = Fk.Fake

  ## A call of the program on the fake terminal.
  type Call = Fk.Call

  ## A fake terminal of `width` by `height`; send events on its `events`, and close them to end the terminal.
  def fake(width: Int, height: Int) -> Fake = Fk.new(width, height)

  def backend(fake: Fake) -> Bd.Backend = Fk.backend(fake)

  ## The calls made since the last time, in order, after waiting up to `wait_ms` for one when none waits. `screen`,
  ## `wait_for`, `cursor` and `style_at` read them too.
  def calls(fake: Fake, wait_ms: Int = 0) -> List[Call] = Fk.calls(fake, wait_ms)

  ## The text of each row after `calls`, from the last clear; a wide character's covered cell adds nothing.
  def rows(fake: Fake, calls: List[Call]) -> List[String] = Fk.rows(fake, calls)

  ## The terminal takes a new size and sends its `Resize` event.
  def resize(fake: Fake, width: Int, height: Int) -> Result[Void] = Fk.resize(fake, width, height)

  ## The text of each row the terminal shows now (it reads the new calls, as `calls` does).
  def screen(fake: Fake) -> List[String] = Fk.screen(fake)

  ## Waits up to `wait_ms` for the terminal to show rows that `done` takes, and gives them; an error with the rows it
  ## shows when the time runs out.
  def wait_for(fake: Fake, done: Fn[List[String], Bool], wait_ms: Int = 5000) -> Result[List[String]]
    Fk.wait_for(fake, done, wait_ms)
  end

  ## The style of the cell at column x, row y the terminal shows now; none outside the screen.
  def style_at(fake: Fake, x: Int, y: Int) -> Optional[St.Style] = Fk.style_at(fake, x, y)

  ## Where the cursor shows now; none when it is hidden.
  def cursor(fake: Fake) -> Optional[Bd.Cursor] = Fk.cursor(fake)
end

## The terminal by hand, for what `run` does not cover: open it, draw cells, show them, wait for events.
module Raw
  ## The open terminal.
  type Screen = Tb.Screen

  ## A screen as a value, as `render` gives it.
  type Grid = Gr.Grid

  ## What one cell of a `Grid` shows.
  type Glyph = Gr.Glyph

  ## Opens the terminal (full screen, raw input, no cursor), gives it to the block and closes it when the block ends,
  ## whatever it returns. Gives the block's result, an error when the terminal cannot be opened, or
  ## `error("task crashed: ...")` when the block stops with a runtime error.
  def open[T](body: Fn[Screen, Result[T]]) -> Result[T] = Tb.open(body)

  ## The open screen as a backend of `program`.
  def backend(screen: Screen) -> Bd.Backend = Tb.backend(screen)

  ## Runs `app` on a backend (an open screen, or a fake one), as `run` does, and gives the terminal back the modes it
  ## had before.
  def program[M, Msg](backend: Bd.Backend, app: Pg.App[M, Msg]) -> Result[M] = Pg.program(backend, app)

  ## The width of the terminal in columns. It changes after a `Resize` event, once the screen is cleared or shown.
  def width(screen: Screen) -> Int = Tb.width(screen)

  ## The height of the terminal in rows.
  def height(screen: Screen) -> Int = Tb.height(screen)

  ## Fills the back buffer with spaces of the style.
  def clear(screen: Screen, style: St.Style = St.Style()) -> Result[Void] = Tb.clear(screen, style)

  ## Sets the cell at column x, row y (from 0) to one character.
  def set_cell(screen: Screen, x: Int, y: Int, char: String, style: St.Style = St.Style()) -> Result[Void]
    Tb.set_cell(screen, x, y, char, style)
  end

  ## Writes text from column x, row y; what goes past the right edge is cut. Gives the width of the text.
  def write(screen: Screen, x: Int, y: Int, text: String, style: St.Style = St.Style()) -> Result[Int]
    Tb.write(screen, x, y, text, style)
  end

  ## Shows the back buffer on the terminal: nothing drawn appears before this.
  def present(screen: Screen) -> Result[Void] = Tb.present(screen)

  ## Draws `node` over the whole screen and shows it, writing only the cells that differ from `last`, and gives what
  ## the screen shows now.
  def render(screen: Screen, node: View.Node, last: Optional[Grid] = none) -> Result[Grid]
    Tb.render(screen, node, last)
  end

  ## The cells to write to turn `old` into `new`.
  def diff(old: Grid, new: Grid) -> List[View.Cell] = Gr.diff(old, new)

  ## Shows the cursor at column x, row y.
  def set_cursor(screen: Screen, x: Int, y: Int) -> Result[Void] = Tb.set_cursor(screen, x, y)

  ## Hides the cursor.
  def hide_cursor(screen: Screen) -> Result[Void] = Tb.hide_cursor(screen)

  ## Waits for the next event; other tasks run (and may draw) meanwhile.
  def poll_event(screen: Screen) -> Result[Ev.Event] = Tb.poll_event(screen)

  ## Waits up to timeout_ms milliseconds for an event: `none` when none came.
  def peek_event(screen: Screen, timeout_ms: Int) -> Result[Optional[Ev.Event]] = Tb.peek_event(screen, timeout_ms)

  ## Sets how Escape is read, and whether mouse events come.
  def set_input_mode(screen: Screen, mode: Ev.InputMode, mouse: Bool = false) -> Result[Void]
    Tb.set_input_mode(screen, mode, mouse: mouse)
  end

  ## Sets how colors are sent.
  def set_output_mode(screen: Screen, mode: St.OutputMode) -> Result[Void] = Tb.set_output_mode(screen, mode)
end
