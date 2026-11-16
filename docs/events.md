# Events

`TUI.poll_event(screen)` waits for the next `Event`; `TUI.peek_event(screen, timeout_ms)` gives `none` when none
comes in time. [`TUI.program`](elm-loop.md) waits with `poll_event`.

- `Key(Key, Mods)`: a key that is not a character.
- `Char(String, Mods)`: a typed character, a space too.
- `Mouse(Mouse, x, y, Mods)`: a mouse button or the wheel at cell `x`, `y` (from 0).
- `Resize(width, height)`: the new size of the terminal.
- `Paste(text)`: pasted text, whole.

```ruby
import TUI from "pkg/tui/tui"

def describe(event: TUI.Event) -> String
  case event
    TUI.Event.Key(TUI.Key.Ctrl("c"), _) -> "ctrl-c"
    TUI.Event.Key(key, _) -> "key #{key}"
    TUI.Event.Char(char, mods) -> "char #{char}, alt #{mods.alt}"
    TUI.Event.Mouse(button, x, y, _) -> "mouse #{button} at #{x},#{y}"
    TUI.Event.Resize(width, height) -> "size #{width}x#{height}"
    TUI.Event.Paste(text) -> "paste of #{text.length} characters"
  end
end
```

## Keys

`Key` is `Up`, `Down`, `Left`, `Right`, `Enter`, `Escape`, `Tab`, `BackTab`, `Backspace`, `Insert`, `Delete`,
`Home`, `End`, `PageUp`, `PageDown`, `F(n)` (1 to 12), `Ctrl("c")` (lowercase for a letter) or `Other(code)`.
`Mods` has `alt`, `ctrl`, `shift` and `motion` (a mouse move with a button down).

A lone Escape byte is read as `Key.Escape` (`InputMode.Esc`, the default) or as Alt with the next key
(`InputMode.Alt`): `TUI.set_input_mode(screen, TUI.InputMode.Alt)`.

## Mouse

Mouse events come only after `TUI.set_input_mode(screen, mode, true)`. `Mouse` is `Left`, `Right`, `Middle`,
`Release`, `WheelUp` or `WheelDown`. A report whose cell is outside the screen gives the nearest cell inside it.

## Paste

The screen turns on bracketed paste when it opens and off when it closes, so a paste comes as one `Paste` with `\n`
line ends, and the keys in it never come as `Key` or `Char` events.

- A paste keeps its first 1 MiB and drops the rest, up to its end mark.
- A paste with no end mark ends after 2 s with nothing more to read; what follows comes as keys.
- A lone end mark is dropped.

A program that writes its own end mark inside a paste can still inject keys. So a `Paste` must never confirm
anything, and a confirmation should not rest on keys alone.

## Resize

`Resize(width, height)` comes when the terminal changes size; `TUI.width(screen)` and `TUI.height(screen)` give the
new size after it. `TUI.program` renders the view again after every event, a resize too.
