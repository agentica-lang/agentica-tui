# Tests

```sh
make test AGENTICA=/path/to/agentica
```

- `make check`: `agentica check` on every `.agc` file.
- `make unit`: the unit tests (`tests/*_test.agc`): events, styles, the layout, and the program loop on a fake
  terminal.
- `make pty`: `tests/test_pty.py` (Python, standard library only) runs the programs of `tests/fixtures/` and the
  examples under a new pseudo-terminal, sends keys, mouse reports, pastes and a resize, and checks the screen and
  that the terminal comes back.

## Testing a view

A view needs no terminal: `TUI.layout(node, width, height)` gives its cells, and `update` is a plain function.

```ruby
import TUI from "pkg/tui/tui"

def view(count: Int) -> TUI.Node = TUI.row([TUI.text("count"), TUI.spacer(), TUI.text("#{count}")])

def test_the_count_is_on_the_right() -> Result[Void]
  cells = TUI.layout(view(7), 10, 1)
  Test.eq(cells.map { |cell| "#{cell.x}:#{cell.char}" }.last, "9:7")
end
```

## Testing a program

`TUI.Testing.fake(width, height)` is a terminal with no screen: run the program on it in a task, send it events, and
read back the calls the program made and the rows they draw.

```ruby
def test_q_quits() -> Result[Void]
  fake = TUI.Testing.fake(20, 1)
  runner = Task.spawn do TUI.Raw.program(TUI.Testing.backend(fake), app()) end
  try fake.events.send(TUI.Event.Char("q", TUI.Mods()), 1000)
  try Task.await(runner)
  Test.eq(TUI.Testing.rows(fake, TUI.Testing.calls(fake)), ["0 keys, q quits"])
end
```
