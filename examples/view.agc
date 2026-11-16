## A view tree drawn with `TUI.render`: a counter in a box. + and - change it, q quits.
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
  count = 0
  while true
    try TUI.render(screen, view(count))
    case try TUI.poll_event(screen)
      TUI.Event.Char("q", _) -> break
      TUI.Event.Char("+", _) -> count = count + 1
      TUI.Event.Char("-", _) -> count = count - 1
      _ -> nil
    end
  end

  ok()
end

def view(count: Int) -> TUI.Node
  title = TUI.Node.Text("Counter", TUI.Style(bold: true))
  value = TUI.Node.Text("count: #{count}", TUI.Style(fg: TUI.Color.Green))
  box = TUI.Node.Box(TUI.Node.Col([title, value]), 1, true, TUI.Style(fg: TUI.Color.Cyan))
  help = TUI.Node.Row([TUI.Node.Spacer, TUI.Node.Text("+ and - count, q quits", TUI.Style(dim: true))])
  TUI.Node.Col([box, TUI.Node.Spacer, help])
end
