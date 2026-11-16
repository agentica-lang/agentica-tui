## A view tree in the loop of `TUI.run`: a counter in a box. + and - change it, q quits.
##
## Run it from the repository after `make native`: `agentica examples/view.agc`.

import TUI from "../tui"

enum Msg
  Key(TUI.Event)
end

def main() -> Void
  app = TUI.App(model: 0, update: &update, view: &view, subscriptions: &subscriptions)
  case TUI.run(app)
    ok(_) -> puts("bye")
    error(e) -> IO.warn(e.message)
  end
end

def update(count: Int, msg: Msg) -> TUI.Step[Int, Msg]
  case msg
    Msg.Key(TUI.Event.Char("q", _)) -> TUI.Step(model: count, cmds: [TUI.Cmd.Quit])
    Msg.Key(TUI.Event.Char("+", _)) -> TUI.Step(model: count + 1)
    Msg.Key(TUI.Event.Char("-", _)) -> TUI.Step(model: count - 1)
    Msg.Key(_) -> TUI.Step(model: count)
  end
end

def view(count: Int) -> TUI.Node
  title = TUI.text("Counter", style: TUI.Style(bold: true))
  value = TUI.text("count: #{count}", style: TUI.Style(fg: TUI.Color.Green))
  box = TUI.box(TUI.col([title, value]), padding: 1, border: TUI.Border.Line, style: TUI.Style(fg: TUI.Color.Cyan))
  help = TUI.row([TUI.spacer(), TUI.text("+ and - count, q quits", style: TUI.Style(dim: true))])
  TUI.col([box, TUI.spacer(), help])
end

def subscriptions(_count: Int) -> List[TUI.Sub[Msg]] = [TUI.Sub.Events(->(event) { Msg.Key(event) })]
