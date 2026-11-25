---
title: agentica-tui
description: A terminal UI package for Agentica. A typed view tree, an Elm-like loop, and key, mouse, paste and resize events, in Agentica alone.
---

agentica-tui is a terminal UI library for [Agentica](https://www.agentica-lang.com/agentica/): build a view tree, draw it full screen, and read key, mouse, paste and resize events. It is written in Agentica alone, on the `Terminal` builtin: no native code.

It needs Agentica 0.39.0 or later, on Linux for now (macOS and Windows are checked in a later change), and a terminal that takes VT sequences. There is no release tag yet: add the package at a commit of `main` (the whole commit id).

```sh
agentica add tui https://github.com/agentica-lang/agentica-tui --ref COMMIT
```

A counter: `+` and `-` change it, `q` quits.

```agentica
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

In a terminal of 40 by 7 cells, after a few keys:

![The counter: a box with a line border around the text count: 6](images/counter.png)

- [Getting started](getting-started.md): install, a first program, run it.
- [View tree](view-tree.md): `text`, `row`, `col`, `box`, `spacer`, `line`, `list`, `table`, layout and widths.
- [Elm loop](elm-loop.md): `TUI.run`, `App`, `Step`, commands and subscriptions.
- [Events](events.md): keys, mouse, paste and resize.
- [Styles](styles.md): colors, attributes and `merge`.
- [Low level](low-level.md): `TUI.Raw`, cells, `present`, waiting for events, tasks.
- [Tests](tests.md): the test suites and how to test a view.
- The source and the changelog are [on GitHub](https://github.com/agentica-lang/agentica-tui).

agentica-tui is under the Apache License 2.0.
