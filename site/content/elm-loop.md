---
title: Elm loop
weight: 3
description: "TUI.run and the Elm loop: App, Step, the commands Run and Quit, and the subscriptions Tick and Events."
---

`TUI.run(app)` opens the terminal, runs a `TUI.App` and restores the terminal:

- `model`: the first model, any type;
- `update(model, msg)`: gives a `TUI.Step` with the next model and the commands to run;
- `view(model)`: the [view tree](view-tree.md) of a model;
- `subscriptions(model)`: what the loop listens to while the model is this one;
- `cmds`: the commands to run at the start (none when left out);
- `cursor`: `some(->(model) { ... })` gives where the terminal cursor shows, a `TUI.Cursor(x:, y:)`, or none to hide it; left out, the cursor stays hidden;
- `input`, `mouse`, `output`: how Escape is read (`InputMode.Esc` when left out), whether mouse events come (`false`) and how colors are sent (`OutputMode.Normal`); see [Events](events.md) and [Styles](styles.md).

The messages are your own type, often an enum. The loop takes every message that is waiting, gives each to `update`, then draws `view(model)` once, writing only the cells that changed. It gives the last model when a command is `Cmd.Quit`; the messages after it never reach `update`, and a key typed after it may be lost. A runtime error in `update`, `view` or `subscriptions` ends the loop with that error, given once the terminal is restored. `TUI.Raw.program(TUI.Raw.backend(screen), app)` is the same loop on a screen that is already open.

## Commands

- `Cmd.Run(work)`: calls `work` in a task of its own; the message it returns goes to `update`. A runtime error in `work` ends the loop with that error.
- `Cmd.Suspend(work)`: gives the terminal back as it was before the loop, calls `work`, which may run a program on the terminal (an editor through `Process.spawn_group`), then takes the terminal again with the same modes and draws the whole screen. The message of `work` goes to `update`, after a `Resize` event when the size changed meanwhile. The loop waits for `work`: no key or tick comes meanwhile, and keys typed then go to the other program. A runtime error in `work` ends the loop with that error, once the terminal is taken again. The terminal modes the other program leaves are not kept. The other program gets no resize signal while it runs, and Ctrl+Z does not stop it. A program started with `Process.spawn_group` runs in a session of its own, so a Ctrl+C typed while it reads a line stops your program, not it (an editor in raw mode reads Ctrl+C as a key); `System.subscribe([System.Signal.Int])` at the start of `work` keeps it, until `work` returns.
- `Cmd.Quit`: ends the loop.

## Subscriptions

- `Sub.Events(message)`: each [event](events.md) (keys, mouse, paste, resize) as `message(event)`.
- `Sub.Tick(ms, msg)`: `msg` every `ms` milliseconds (10 or more; less counts as 10). The period starts when the subscription first appears, and stops when `subscriptions` no longer gives it. A tick that falls due while messages come goes with them.

```agentica
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
  case TUI.run(app)
    ok(todo) -> puts("#{todo.items.size} items")
    error(e) -> IO.warn(e.message)
  end
end
```

A clock adds `Sub.Tick(1000, Msg.Second)` to its subscriptions, and a slow call (a file, a request) is a `Cmd.Run(-> { Msg.Loaded(load()) })`, so the screen keeps answering keys while it runs.

`update`, `view` and `subscriptions` are plain functions, so a test can call them with no terminal ([Tests](tests.md)). `examples/view.agc` is a counter written this way.
