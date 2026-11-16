# Elm loop

`TUI.program(screen, model, update, view)` runs a loop:

1. it renders `view(model)`;
2. it waits for an [event](events.md);
3. it calls `update(model, event)`, which gives `Step.Continue(next)` or `Step.Quit`.

On `Step.Quit` it gives the last model. The model can be any type.

```ruby
import TUI from "pkg/tui/tui"

struct Todo
  items: List[String]
  draft: String
end

def update(todo: Todo, event: TUI.Event) -> TUI.Step[Todo]
  case event
    TUI.Event.Key(TUI.Key.Escape, _) -> TUI.Step.Quit
    TUI.Event.Key(TUI.Key.Enter, _) -> TUI.Step.Continue(Todo(items: todo.items.push(todo.draft), draft: ""))
    TUI.Event.Char(char, _) -> TUI.Step.Continue(todo.with(draft: todo.draft + char))
    _ -> TUI.Step.Continue(todo)
  end
end

def view(todo: Todo) -> TUI.Node
  lines = todo.items.map { |item| TUI.text("- #{item}") }
  TUI.col(lines + [TUI.spacer(), TUI.text("> #{todo.draft}", TUI.Style(bold: true))])
end

def main() -> Void
  case TUI.open(->(screen) { TUI.program(screen, Todo(items: [], draft: ""), &update, &view) })
    ok(todo) -> puts("#{todo.items.size} items")
    error(e) -> IO.warn(e.message)
  end
end
```

`update` and `view` are plain functions, so a test can call them with no terminal ([Tests](tests.md)).
`examples/view.agc` is a counter written this way.

## Limits

The loop wakes only on an event: it has no tick or timeout yet. For a clock or a timer, write the loop by hand with
`peek_event(screen, timeout_ms)` and `render` ([Low level](low-level.md)).
