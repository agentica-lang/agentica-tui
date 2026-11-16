## The program tests/test_pty.py drives for `TUI.program`: it counts three ticks of 30 ms and then stops listening to
## them; r runs a command, x runs one that crashes, q quits. At the end it prints the model.

import TUI from "../../tui"

struct Model
  ticks: Int = 0
  ran: String = ""
end

enum Msg
  Tick
  Ran(String)
  Key(TUI.Event)
end

def main() -> Void
  app = TUI.App(model: Model(), update: &update, view: &view, subscriptions: &subscriptions)
  case TUI.open(->(screen) { TUI.program(screen, app) })
    ok(model) -> puts("ticks #{model.ticks}, ran #{model.ran}")
    error(e) -> fail(e.message)
  end
end

def update(model: Model, msg: Msg) -> TUI.Step[Model, Msg]
  case msg
    Msg.Tick -> TUI.Step(model: model.with(ticks: model.ticks + 1))
    Msg.Ran(text) -> TUI.Step(model: model.with(ran: text))
    Msg.Key(TUI.Event.Char("r", _)) -> TUI.Step(model: model, cmds: [TUI.Cmd.Run(-> { Msg.Ran("done") })])
    Msg.Key(TUI.Event.Char("x", _)) -> TUI.Step(model: model, cmds: [TUI.Cmd.Run(&crash)])
    Msg.Key(TUI.Event.Char("q", _)) -> TUI.Step(model: model, cmds: [TUI.Cmd.Quit])
    Msg.Key(_) -> TUI.Step(model: model)
  end
end

def view(model: Model) -> TUI.Node = TUI.col([TUI.text("ticks #{model.ticks}"), TUI.text("ran #{model.ran}")])

def subscriptions(model: Model) -> List[TUI.Sub[Msg]]
  keys = TUI.Sub.Events(->(event) { Msg.Key(event) })
  return [keys] if model.ticks >= 3

  [keys, TUI.Sub.Tick(30, Msg.Tick)]
end

def crash() -> Msg
  empty: List[Msg] = []
  # Past the end: RUNTIME-INDEX-OUT-OF-RANGE.
  empty[0]
end

def fail(message: String) -> Void
  IO.warn(message)
  System.exit(1)
end
