## A terminal UI library on termbox2: a full-screen grid of cells, colors, and key, mouse and resize events.
##
## ```ruby
## import TUI from "pkg/tui/tui"
##
## def draw(screen: TUI.Screen) -> Result[Void]
##   try TUI.write(screen, 0, 0, "hello, press a key", TUI.Style(fg: TUI.Color.Green))
##   try TUI.present(screen)
##   _ = try TUI.poll_event(screen)
##   return ok()
## end
##
## def main() -> Void
##   case TUI.open(&draw)
##     ok(_) -> puts("bye")
##     error(message) -> IO.warn(message)
##   end
## end
## ```

import Ev from "src/event"
import St from "src/style"
import Tb from "src/termbox"

export Tb.Screen
export Tb.open
export Tb.width
export Tb.height
export Tb.clear
export Tb.set_cell
export Tb.write
export Tb.present
export Tb.set_cursor
export Tb.hide_cursor
export Tb.poll_event
export Tb.peek_event
export Tb.set_input_mode
export Tb.set_output_mode
export Ev.Event
export Ev.Key
export Ev.Mouse
export Ev.Mods
export Ev.InputMode
export St.Color
export St.Attr
export St.Style
export St.OutputMode
