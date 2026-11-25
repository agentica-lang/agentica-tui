# agentica-tui

A terminal UI library for [Agentica](https://github.com/agentica-lang/agentica): build a view tree, draw it full
screen, and read key, mouse, paste and resize events. It is written in Agentica alone, on the `Terminal` builtin: no
native code, no C compiler.

## Install

Needs Agentica 0.39.0 or later and a terminal that takes VT sequences (xterm and its relatives, and the terminals
of Linux, macOS and Windows 10 or later). Standard input and output must be a terminal. There is no release tag yet:
pin a commit of `main` in `agentica.toml`:

```toml
[dependencies]
tui = { git = "https://github.com/agentica-lang/agentica-tui", ref = "COMMIT" }
```

## Example

A counter: `+` and `-` change it, `q` quits.

```ruby
import TUI from "pkg/tui/tui"

enum Msg
  Key(TUI.Event)
end

def update(count: Int, msg: Msg) -> TUI.Step[Int, Msg]
  case msg
    Msg.Key(TUI.Event.Char("q", _)) -> TUI.Step(model: count, cmds: [TUI.Cmd.Quit])
    Msg.Key(TUI.Event.Char("+", _)) -> TUI.Step(model: count + 1)
    Msg.Key(TUI.Event.Char("-", _)) -> TUI.Step(model: count - 1)
    Msg.Key(_) -> TUI.Step(model: count)
  end
end

def view(count: Int) -> TUI.Node = TUI.box(TUI.text("count: #{count}"), padding: 1, border: TUI.Border.Line)

def subscriptions(_count: Int) -> List[TUI.Sub[Msg]] = [TUI.Sub.Events(->(event) { Msg.Key(event) })]

def main() -> Void
  app = TUI.App(model: 0, update: &update, view: &view, subscriptions: &subscriptions)
  case TUI.run(app)
    ok(count) -> puts("count: #{count}")
    error(e) -> IO.warn(e.message)
  end
end
```

## Docs

The docs are at https://www.agentica-lang.com/agentica-tui/:

- [Getting started](https://www.agentica-lang.com/agentica-tui/getting-started/): install, a first program, run it.
- [View tree](https://www.agentica-lang.com/agentica-tui/view-tree/): `text`, `row`, `col`, `box`, `spacer`, `line`,
  `list`, `table`, layout and widths.
- [Elm loop](https://www.agentica-lang.com/agentica-tui/elm-loop/): `TUI.run`, `App`, `Step`, commands and
  subscriptions.
- [Events](https://www.agentica-lang.com/agentica-tui/events/): keys, mouse, paste and resize.
- [Styles](https://www.agentica-lang.com/agentica-tui/styles/): colors, attributes and `merge`.
- [Low level](https://www.agentica-lang.com/agentica-tui/low-level/): `TUI.Raw`, cells, `present`, waiting for events,
  tasks.
- [Tests](https://www.agentica-lang.com/agentica-tui/tests/): the test suites and how to test a view.

## License

Apache License 2.0. See [LICENSE](LICENSE).
