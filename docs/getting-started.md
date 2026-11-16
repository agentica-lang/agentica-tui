# Getting started

## Install

agentica-tui needs Agentica 0.31.0 or later on Linux x86_64 (glibc 2.33 or later). There is no release tag yet, so
add the package at a commit of `main` (the whole commit id):

```sh
agentica add tui https://github.com/agentica-lang/agentica-tui --ref COMMIT
```

That writes the line of `agentica.toml` and the entry of `agentica.lock`, and puts the package in `deps/`. No C
compiler is needed: the package ships its library ([Native library](native.md)).

## A first program

`TUI.open` opens the terminal, gives the block a `Screen`, and restores the terminal when the block ends, whatever
it returns.

```ruby
import TUI from "pkg/tui/tui"

def hello(screen: TUI.Screen) -> Result[Void]
  try TUI.render(screen, TUI.text("hello, press a key", TUI.Style(fg: TUI.Color.Green)))
  _ = try TUI.poll_event(screen)
  ok()
end

def main() -> Void
  case TUI.open(&hello)
    ok(_) -> puts("bye")
    error(e) -> IO.warn(e.message)
  end
end
```

A runtime error in the block comes back as `error("task crashed: ...")` after the terminal is restored, and
`System.exit` in the block still restores it.

## Run it

```sh
agentica hello.agc
```

The program needs a real terminal: `TUI.open` fails when there is none. From a clone of this repository, the
examples run the same way:

```sh
agentica examples/view.agc   # a counter in a box; + and - count, q quits
agentica examples/box.agc    # a box that moves with the arrow keys or a click; q quits
```

Next: the [view tree](view-tree.md) and the [Elm loop](elm-loop.md).
