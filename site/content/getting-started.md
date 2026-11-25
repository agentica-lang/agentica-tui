---
title: Getting started
weight: 1
description: Install the package, write a first program and run it.
---

## Install

agentica-tui needs Agentica 0.39.0 or later, and standard input and output on a terminal that takes VT sequences. CI runs the unit tests and the pseudo-terminal tests on Linux x86_64, macOS arm64 and macOS x86_64; on Windows x86_64 it checks the code and runs the unit tests only, and the terminal is not tested there. There is no release tag yet, so add the package at a commit of `main` (the whole commit id):

```sh
agentica add tui https://github.com/agentica-lang/agentica-tui --tag 0.1.0
```

That writes the line of `agentica.toml` and the entry of `agentica.lock`, and puts the package in `deps/`. The package is Agentica alone: no C compiler is needed.

## A first program

`TUI.run(app)` opens the terminal, runs the [Elm loop](elm-loop.md) of the app and restores the terminal when it ends, whatever happens.

```agentica
import TUI from "pkg/tui/tui"

enum Msg
  Key(TUI.Event)
end

def update(model: Nil, msg: Msg) -> TUI.Step[Nil, Msg] = TUI.Step(model: model, cmds: [TUI.Cmd.Quit])

def view(_model: Nil) -> TUI.Node = TUI.text("hello, press a key", style: TUI.Style(fg: TUI.Color.Green))

def subscriptions(_model: Nil) -> List[TUI.Sub[Msg]] = [TUI.Sub.Events(->(event) { Msg.Key(event) })]

def main() -> Void
  case TUI.run(TUI.App(model: nil, update: &update, view: &view, subscriptions: &subscriptions))
    ok(_) -> puts("bye")
    error(e) -> IO.warn(e.message)
  end
end
```

A runtime error in the app comes back as `error("task crashed: ...")` after the terminal is restored, and `System.exit` still restores it.

## Run it

```sh
agentica hello.agc
```

The program needs a real terminal: `TUI.run` fails when there is none. From a clone of this repository, the examples run the same way:

```sh
agentica examples/view.agc   # a counter in a box; + and - count, q quits
agentica examples/box.agc    # by hand with TUI.Raw: a box that moves with the arrows or a click; q quits
```

Next: the [view tree](view-tree.md) and the [Elm loop](elm-loop.md).
