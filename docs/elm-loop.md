# Elm loop

`TUI.program(screen, app)` runs a `TUI.App`:

- `model`: the first model, any type;
- `update(model, msg)`: gives a `TUI.Step` with the next model and the commands to run;
- `view(model)`: the [view tree](view-tree.md) of a model;
- `subscriptions(model)`: what the loop listens to while the model is this one;
- `cmds`: the commands to run at the start (none when left out).

The messages are your own type, often an enum. After each message the loop draws `view(model)`, writing only the
cells that changed. It gives the last model when a command is `Cmd.Quit`.

## Commands

- `Cmd.Run(work)`: calls `work` in a task of its own; the message it returns goes to `update`. A runtime error in
  `work` ends the loop with that error.
- `Cmd.Quit`: ends the loop.

## Subscriptions

- `Sub.Events(message)`: each [event](events.md) (keys, mouse, paste, resize) as `message(event)`.
- `Sub.Tick(ms, msg)`: `msg` every `ms` milliseconds. The period starts when the subscription first appears, and
  stops when `subscriptions` no longer gives it.

```ruby
import TUI from "pkg/tui/tui"

struct Todo
  items: List[String] = []
  draft: String = ""
end

enum Msg
  Key(TUI.Event)
end

def update(todo: Todo, msg: Msg) -> TUI.Step[Todo, Msg]
  case msg
    Msg.Key(TUI.Event.Key(TUI.Key.Escape, _)) -> TUI.Step(model: todo, cmds: [TUI.Cmd.Quit])
    Msg.Key(TUI.Event.Key(TUI.Key.Enter, _)) -> TUI.Step(model: added(todo))
    Msg.Key(TUI.Event.Char(char, _)) -> TUI.Step(model: todo.with(draft: todo.draft + char))
    Msg.Key(_) -> TUI.Step(model: todo)
  end
end

def added(todo: Todo) -> Todo
  return todo if todo.draft == ""

  todo.with(items: todo.items.push(todo.draft), draft: "")
end

def view(todo: Todo) -> TUI.Node
  lines = todo.items.map { |item| TUI.text("- #{item}") }
  prompt = TUI.text("> #{todo.draft}", style: TUI.Style(bold: true))
  TUI.col(lines + [TUI.spacer(), prompt])
end

def subscriptions(_todo: Todo) -> List[TUI.Sub[Msg]] = [TUI.Sub.Events(->(event) { Msg.Key(event) })]

def main() -> Void
  app = TUI.App(model: Todo(), update: &update, view: &view, subscriptions: &subscriptions)
  case TUI.open(->(screen) { TUI.program(screen, app) })
    ok(todo) -> puts("#{todo.items.size} items")
    error(e) -> IO.warn(e.message)
  end
end
```

A clock adds `Sub.Tick(1000, Msg.Second)` to its subscriptions, and a slow call (a file, a request) is a
`Cmd.Run(-> { Msg.Loaded(load()) })`, so the screen keeps answering keys while it runs.

`update`, `view` and `subscriptions` are plain functions, so a test can call them with no terminal
([Tests](tests.md)). `examples/view.agc` is a counter written this way.
