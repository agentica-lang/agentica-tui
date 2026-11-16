## The program tests/test_pty.py drives for `TUI.Raw.program`: the app turns the mouse on, q quits it, and the
## screen after it must have the mouse off again. Then it writes "back" and waits for q.

import TUI from "../../tui"

enum Msg
  Key(TUI.Event)
end

def main() -> Void
  case TUI.Raw.open(&both)
    ok(_) -> puts("bye")
    error(e) -> IO.warn(e.message)
  end
end

def both(screen: TUI.Raw.Screen) -> Result[Void]
  app = TUI.App(model: nil, update: &update, view: &view, subscriptions: &subscriptions, mouse: true)
  _ = try TUI.Raw.program(screen, app)
  _ = try TUI.Raw.render(screen, TUI.text("back"))
  _ = try TUI.Raw.poll_event(screen)
  ok()
end

def update(model: Nil, _msg: Msg) -> TUI.Step[Nil, Msg] = TUI.Step(model: model, cmds: [TUI.Cmd.Quit])

def view(_model: Nil) -> TUI.Node = TUI.text("app")

def subscriptions(_model: Nil) -> List[TUI.Sub[Msg]] = [TUI.Sub.Events(->(event) { Msg.Key(event) })]
