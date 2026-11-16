# agentica-tui

A terminal UI library for [Agentica](https://github.com/agentica-lang/agentica): build a view tree, draw it full
screen, and read key, mouse, paste and resize events. It calls [termbox2](https://github.com/termbox/termbox2) (v2.5.0,
vendored) through the Agentica FFI.

## Install

Needs Agentica 0.31.0 or later on Linux x86_64 (glibc 2.33 or later). There is no release tag yet: pin a commit of
`main` in `agentica.toml`:

```toml
[dependencies]
tui = { git = "https://github.com/agentica-lang/agentica-tui", ref = "COMMIT" }
```

The package ships `native/linux/libtermbox2.so`, built by CI; see [Native library](docs/native.md).

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

- [Getting started](docs/getting-started.md): install, a first program, run it.
- [View tree](docs/view-tree.md): `text`, `row`, `col`, `box`, `spacer`, `line`, `list`, `table`, layout and widths.
- [Elm loop](docs/elm-loop.md): `TUI.run`, `App`, `Step`, commands and subscriptions.
- [Events](docs/events.md): keys, mouse, paste and resize.
- [Styles](docs/styles.md): colors, attributes and `merge`.
- [Low level](docs/low-level.md): `TUI.Raw`, cells, `present`, waiting for events, tasks.
- [Native library](docs/native.md): termbox2, the `.so` and how CI builds it.
- [Tests](docs/tests.md): the test suites and how to test a view.
- [llms.txt](docs/llms.txt): these pages as links, for language models.

## License

Apache License 2.0. See [LICENSE](LICENSE). termbox2 is MIT, see [native/termbox2/LICENSE](native/termbox2/LICENSE).
