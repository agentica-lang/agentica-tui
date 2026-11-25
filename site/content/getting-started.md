---
title: Getting started
weight: 1
description: Install the package, write a first program and run it.
---

## Install

agentica-tui needs Agentica 0.39.0 or later on Linux x86_64 (glibc 2.33 or later). There is no release tag yet, so add the package at a commit of `main` (the whole commit id):

```sh
agentica add tui https://github.com/agentica-lang/agentica-tui --ref COMMIT
```

That writes the line of `agentica.toml` and the entry of `agentica.lock`, and puts the package in `deps/`. No C compiler is needed: the package ships its library ([Native library](native.md)).

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
