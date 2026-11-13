## Input events: keys, characters, mouse and resize, decoded from the fields of a termbox2 `struct tb_event`.

## The fields of a termbox2 `struct tb_event`, as numbers.
struct Raw
  kind: Int
  mod: Int
  key: Int
  ch: Int
  width: Int = 0
  height: Int = 0
  x: Int = 0
  y: Int = 0
end

## The modifier keys held with a key or a mouse event. `motion` is a mouse move with a button down.
struct Mods
  alt: Bool = false
  ctrl: Bool = false
  shift: Bool = false
  motion: Bool = false
end

## A key that is not a character.
enum Key
  Up
  Down
  Left
  Right
  Enter
  Escape
  Tab
  BackTab
  Backspace
  Insert
  Delete
  Home
  End
  PageUp
  PageDown
  ## A function key, 1 to 12.
  F(Int)
  ## Ctrl and a character in caret notation, lowercase for a letter: `Ctrl("c")`, `Ctrl("@")`.
  Ctrl(String)
  ## A termbox2 key code this library does not name.
  Other(Int)
end

## A mouse button, or the wheel.
enum Mouse
  Left
  Right
  Middle
  Release
  WheelUp
  WheelDown
end

## An input event.
enum Event
  Key(Key, Mods)
  ## A typed character (a space too), with the modifiers.
  Char(String, Mods)
  ## A mouse button at the cell x, y (columns and rows from 0).
  Mouse(Mouse, Int, Int, Mods)
  ## The new width and height of the terminal.
  Resize(Int, Int)
end

## How a lone Escape byte is read: as `Key.Escape` (`Esc`, the default) or as Alt held with the next key (`Alt`).
enum InputMode
  Esc
  Alt
end

## The event of the fields termbox2 gave, or `none` for an event kind termbox2 does not make. A mouse event with a
## key this library does not name is `Key(Key.Other(code), mods)`.
def decode(raw: Raw) -> Optional[Event]
  if raw.kind == KIND_KEY
    return some(key_event(raw))
  elsif raw.kind == KIND_RESIZE
    return some(Event.Resize(raw.width, raw.height))
  elsif raw.kind == KIND_MOUSE
    return some(mouse_event(raw))
  end

  none
end

## The termbox2 value of an input mode, with mouse events or not.
def input_mode_value(mode: InputMode, mouse: Bool) -> Int
  case mode
    InputMode.Esc -> INPUT_ESC.bit_or(mouse_flag(mouse))
    InputMode.Alt -> INPUT_ALT.bit_or(mouse_flag(mouse))
  end
end

## The modifiers of the bits of `tb_event.mod`.
def mods(bits: Int) -> Mods
  Mods(
    alt: bit?(bits, MOD_ALT),
    ctrl: bit?(bits, MOD_CTRL),
    shift: bit?(bits, MOD_SHIFT),
    motion: bit?(bits, MOD_MOTION),
  )
end

## The key of a termbox2 key code.
def key(code: Int) -> Key = NAMED_CONTROLS.get(code).unwrap_or(other_key(code))

private

# termbox2.h `TB_EVENT_*`.
KIND_KEY = 1
KIND_RESIZE = 2
KIND_MOUSE = 3
# termbox2.h `TB_MOD_*`, bits of `tb_event.mod`.
MOD_ALT = 1
MOD_CTRL = 2
MOD_SHIFT = 4
MOD_MOTION = 8
# termbox2.h `TB_INPUT_*`, bits of tb_set_input_mode.
INPUT_ESC = 1
INPUT_ALT = 2
INPUT_MOUSE = 4
# The ASCII control keys of `tb_event.key` that have a name of their own (0x7f is the Backspace of most terminals).
NAMED_CONTROLS = {0x08: Key.Backspace, 0x09: Key.Tab, 0x0d: Key.Enter, 0x1b: Key.Escape, 0x7f: Key.Backspace}
LAST_CONTROL = 0x1f
# Caret notation: control code c is Ctrl and the character c + 64 (1 is Ctrl-A).
CARET_OFFSET = 0x40
# termbox2 decodes UTF-8 without checking it: a code point that is no Unicode scalar becomes U+FFFD.
REPLACEMENT = 0xfffd
SURROGATES = 0xd800..0xdfff
MAX_CODE_POINT = 0x10ffff
# The terminal keys are counted down from 0xffff (termbox2.h `tb_key_i`), F1 first.
KEY_TOP = 0xffff
FUNCTION_KEYS = 12
TERMINAL_KEYS = [
  Key.Insert,
  Key.Delete,
  Key.Home,
  Key.End,
  Key.PageUp,
  Key.PageDown,
  Key.Up,
  Key.Down,
  Key.Left,
  Key.Right,
  Key.BackTab,
]
MOUSE_BUTTONS = [Mouse.Left, Mouse.Right, Mouse.Middle, Mouse.Release, Mouse.WheelUp, Mouse.WheelDown]

def key_event(raw: Raw) -> Event
  return Event.Char(char(raw.ch), mods(raw.mod)) if raw.ch != 0

  found = key(raw.key)
  held = mods(raw.mod)
  # termbox2 marks every ASCII control byte with Ctrl; only Ctrl(...) keys are typed with it.
  case found
    Key.Ctrl(_) -> Event.Key(found, held)
    _ -> Event.Key(found, held.with(ctrl: false))
  end
end

def char(code: Int) -> String
  return String.from_code(REPLACEMENT) if SURROGATES.include?(code) or code > MAX_CODE_POINT

  String.from_code(code)
end

def other_key(code: Int) -> Key
  return Key.Ctrl(String.from_code(code + CARET_OFFSET).downcase) if code >= 0 and code <= LAST_CONTROL

  index = KEY_TOP - code
  return Key.F(index + 1) if index >= 0 and index < FUNCTION_KEYS

  terminal = index - FUNCTION_KEYS
  return TERMINAL_KEYS[terminal] if terminal >= 0 and terminal < TERMINAL_KEYS.size

  Key.Other(code)
end

def mouse_event(raw: Raw) -> Event
  index = KEY_TOP - raw.key - FUNCTION_KEYS - TERMINAL_KEYS.size
  return Event.Mouse(MOUSE_BUTTONS[index], raw.x, raw.y, mods(raw.mod)) if index >= 0 and index < MOUSE_BUTTONS.size

  Event.Key(Key.Other(raw.key), mods(raw.mod))
end

def mouse_flag(mouse: Bool) -> Int
  return INPUT_MOUSE if mouse

  0
end

def bit?(bits: Int, flag: Int) -> Bool = bits.bit_and(flag) != 0
