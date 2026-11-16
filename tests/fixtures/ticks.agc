## The program tests/test_pty.py drives for ticks under steady input: a tick every 50 ms, and each key counted. q
## quits and prints both counts.

import TUI from "../../tui"

struct Model
  ticks: Int = 0
  keys: Int = 0
end

enum Msg
  Tick
  Key(TUI.Event)
end

def main() -> Void
  app = TUI.App(model: Model(), update: &update, view: &view, subscriptions: &subscriptions)
  case TUI.run(app)
    ok(model) -> puts("ticks #{model.ticks} keys #{model.keys}")
    error(e) -> IO.warn(e.message)
  end
end

def update(model: Model, msg: Msg) -> TUI.Step[Model, Msg]
  case msg
    Msg.Tick -> TUI.Step(model: model.with(ticks: model.ticks + 1))
    Msg.Key(TUI.Event.Char("q", _)) -> TUI.Step(model: model, cmds: [TUI.Cmd.Quit])
    Msg.Key(_) -> TUI.Step(model: model.with(keys: model.keys + 1))
  end
end

def view(model: Model) -> TUI.Node = TUI.text("ticks #{model.ticks} keys #{model.keys}")

def subscriptions(_model: Model) -> List[TUI.Sub[Msg]]
  [TUI.Sub.Events(->(event) { Msg.Key(event) }), TUI.Sub.Tick(50, Msg.Tick)]
end
