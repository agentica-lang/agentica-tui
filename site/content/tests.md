---
title: Tests
weight: 8
description: The test suites, and how to test a view or a program without a terminal.
---

```sh
make test AGENTICA=/path/to/agentica
```

- `make check`: `agentica check` on every `.agc` file.
- `make unit`: the unit tests (`tests/*_test.agc`): events, styles, the layout, and the program loop on a fake terminal.
- `make pty`: `tests/test_pty.py` (Python, standard library only) runs the programs of `tests/fixtures/` and the examples under a new pseudo-terminal, sends keys, mouse reports, pastes and a resize, and checks the screen and that the terminal comes back. The harness answers the status request of a stop, as a terminal does.

## Testing a view

A view needs no terminal: `TUI.layout(node, width, height)` gives its cells, and `update` is a plain function.

```agentica
import TUI from "pkg/tui/tui"

def view(count: Int) -> TUI.Node = TUI.row([TUI.text("count"), TUI.spacer(), TUI.text("#{count}")])

def test_the_count_is_on_the_right() -> Result[Void]
  cells = TUI.layout(view(7), 10, 1)
  Test.eq(cells.map { |cell| "#{cell.x}:#{cell.char}" }.last, "9:7")
end
```

## Testing a program

`TUI.Testing.fake(width, height)` is a terminal with no screen: run the program on it in a task, send it events, and read back what it shows.

```agentica
import TUI from "pkg/tui/tui"

enum Msg
  Key(TUI.Event)
end

def update(count: Int, msg: Msg) -> TUI.Step[Int, Msg]
  case msg
    Msg.Key(TUI.Event.Char("q", _)) -> TUI.Step(model: count, cmds: [TUI.Cmd.Quit])
    Msg.Key(_) -> TUI.Step(model: count + 1)
  end
end

def view(count: Int) -> TUI.Node = TUI.text("#{count} keys, q quits")

def subscriptions(_count: Int) -> List[TUI.Sub[Msg]] = [TUI.Sub.Events(->(event) { Msg.Key(event) })]

def app() -> TUI.App[Int, Msg] = TUI.App(model: 0, update: &update, view: &view, subscriptions: &subscriptions)

def test_q_quits() -> Result[Void]
  fake = TUI.Testing.fake(20, 1)
  runner = Task.spawn do TUI.Raw.program(TUI.Testing.backend(fake), app()) end
  try TUI.Testing.wait_for(fake, ->(rows: List[String]) { rows[0] == "0 keys, q quits" })
  try fake.events.send(TUI.Event.Char("q", TUI.Mods()), 1000)
  try Task.await(runner)
  Test.eq(TUI.Testing.screen(fake), ["0 keys, q quits"])
end
```

- `screen(fake)`: the text of each row now; `wait_for(fake, done, wait_ms)` waits until `done` takes the rows.
- `style_at(fake, x, y)` and `cursor(fake)`: the style of a cell and where the cursor shows (none when hidden).
- `resize(fake, width, height)`: the new size and its `Resize` event.
- `screen`, `style_at` and `cursor` show the terminal as the last present left it.
- `calls(fake, wait_ms)`: the calls since the last read, in order, and `rows(fake, calls)` the rows they draw. The fake keeps 65536 calls that nobody read; past that, a call is an error.
- A call is read once: use either the screen helpers or `calls` in a test, not both.
