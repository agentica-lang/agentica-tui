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

def update(count: Int, event: TUI.Event) -> TUI.Step[Int]
  case event
    TUI.Event.Char("q", _) -> TUI.Step.Quit
    TUI.Event.Char("+", _) -> TUI.Step.Continue(count + 1)
    TUI.Event.Char("-", _) -> TUI.Step.Continue(count - 1)
    _ -> TUI.Step.Continue(count)
  end
end

def view(count: Int) -> TUI.Node = TUI.box(TUI.text("count: #{count}"), padding: 1, border: TUI.Border.Line)

def main() -> Void
  case TUI.open(->(screen) { TUI.program(screen, 0, &update, &view) })
    ok(count) -> puts("count: #{count}")
    error(e) -> IO.warn(e.message)
  end
end
```

## Docs

- [Getting started](docs/getting-started.md): install, a first program, run it.
- [View tree](docs/view-tree.md): `text`, `row`, `col`, `box`, `spacer`, layout and widths.
- [Elm loop](docs/elm-loop.md): `TUI.program`, `Step`, `update` and `view`.
- [Events](docs/events.md): keys, mouse, paste and resize.
- [Styles](docs/styles.md): colors, attributes and `merge`.
- [Low level](docs/low-level.md): cells, `present`, waiting for events, tasks.
- [Native library](docs/native.md): termbox2, the `.so` and how CI builds it.
- [Tests](docs/tests.md): the test suites and how to test a view.

## License

Apache License 2.0. See [LICENSE](LICENSE). termbox2 is MIT, see [native/termbox2/LICENSE](native/termbox2/LICENSE).
