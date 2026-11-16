## A view tree in the loop of `TUI.program`: a counter in a box. + and - change it, q quits.
##
## Run it from the repository after `make native`: `agentica examples/view.agc`.

import TUI from "../tui"

def main() -> Void
  case TUI.open(&run)
    ok(_) -> puts("bye")
    error(e) -> IO.warn(e.message)
  end
end

def run(screen: TUI.Screen) -> Result[Void]
  _ = try TUI.program(screen, 0, &update, &view)
  ok()
end

def update(count: Int, event: TUI.Event) -> TUI.Step[Int]
  case event
    TUI.Event.Char("q", _) -> TUI.Step.Quit
    TUI.Event.Char("+", _) -> TUI.Step.Continue(count + 1)
    TUI.Event.Char("-", _) -> TUI.Step.Continue(count - 1)
    _ -> TUI.Step.Continue(count)
  end
end

def view(count: Int) -> TUI.Node
  title = TUI.text("Counter", TUI.Style(bold: true))
  value = TUI.text("count: #{count}", TUI.Style(fg: TUI.Color.Green))
  box = TUI.box(TUI.col([title, value]), padding: 1, border: TUI.Border.Line, style: TUI.Style(fg: TUI.Color.Cyan))
  help = TUI.row([TUI.spacer(), TUI.text("+ and - count, q quits", TUI.Style(dim: true))])
  TUI.col([box, TUI.spacer(), help])
end
