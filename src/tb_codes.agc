## The termbox2 values of the library's types: the fields of a `struct tb_event` decoded into an event, and the
## cell attributes, colors and modes encoded. The library is built with 64-bit attributes (`TB_LIB_OPTS` of
## termbox2.h): a color in the low 32 bits, the attributes above it. Pure.

import Ev from "event"
import St from "style"

## The event kind of a paste (native/tui.c `TUI_EVENT_PASTE`).
KIND_PASTE = 100

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
  ## The text of a paste.
  text: String = ""
end

## The event of the fields termbox2 gave, or `none` for an event kind termbox2 does not make. A mouse event with a
## key this library does not name is `Event.Key(Key.Other(code), mods)`.
def decode(raw: Raw) -> Optional[Ev.Event]
  if raw.kind == KIND_KEY
    return some(key_event(raw))
  elsif raw.kind == KIND_RESIZE
    return some(Ev.Event.Resize(raw.width, raw.height))
  elsif raw.kind == KIND_MOUSE
    return some(mouse_event(raw))
  elsif raw.kind == KIND_PASTE
    return some(Ev.Event.Paste(raw.text.replace("\r\n", "\n").replace("\r", "\n")))
  end

  none
end

## The termbox2 value of an input mode, with mouse events or not.
def input_mode_value(mode: Ev.InputMode, mouse: Bool) -> Int
  case mode
    Ev.InputMode.Esc -> INPUT_ESC.bit_or(mouse_flag(mouse))
    Ev.InputMode.Alt -> INPUT_ALT.bit_or(mouse_flag(mouse))
  end
end

## The modifiers of the bits of `tb_event.mod`.
def mods(bits: Int) -> Ev.Mods
  Ev.Mods(
    alt: bit?(bits, MOD_ALT),
    ctrl: bit?(bits, MOD_CTRL),
    shift: bit?(bits, MOD_SHIFT),
    motion: bit?(bits, MOD_MOTION),
  )
end

## The key of a termbox2 key code.
def key(code: Int) -> Ev.Key = NAMED_CONTROLS.get(code).unwrap_or(other_key(code))

## The termbox2 foreground value of a style: its color and its attributes.
def fg_value(style: St.Style) -> Result[Int]
  color = try color_value(style.fg)
  ok(St.attrs_of(style).reduce(color) do |bits, attr| bits.bit_or(attr_value(attr)) end)
end

## The termbox2 background value of a style: its color.
def bg_value(style: St.Style) -> Result[Int] = color_value(style.bg)

## The termbox2 color value, or an error for an index or channel out of range.
def color_value(color: St.Color) -> Result[Int]
  # The named colors are the values of output mode Normal, termbox2.h `TB_BLACK` to `TB_WHITE`.
  case color
    St.Color.Default -> ok(0)
    St.Color.Black -> ok(1)
    St.Color.Red -> ok(2)
    St.Color.Green -> ok(3)
    St.Color.Yellow -> ok(4)
    St.Color.Blue -> ok(5)
    St.Color.Magenta -> ok(6)
    St.Color.Cyan -> ok(7)
    St.Color.White -> ok(8)
    St.Color.Index(index) -> index_value(index)
    St.Color.Rgb(red, green, blue) -> rgb_value(red, green, blue)
  end
end

## The termbox2 value of an output mode (`TB_OUTPUT_*`).
def output_mode_value(mode: St.OutputMode) -> Int
  case mode
    St.OutputMode.Normal -> 1
    St.OutputMode.Colors256 -> 2
    St.OutputMode.Truecolor -> 5
  end
end

private

# Black in modes Colors256 and Truecolor, where the value 0 means the default color (`TB_HI_BLACK`).
HI_BLACK = 0x2000_0000
MAX_INDEX = 255
MAX_CHANNEL = 255
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
NAMED_CONTROLS = {
  0x08: Ev.Key.Backspace, 0x09: Ev.Key.Tab, 0x0d: Ev.Key.Enter, 0x1b: Ev.Key.Escape, 0x7f: Ev.Key.Backspace,
}
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
  Ev.Key.Insert,
  Ev.Key.Delete,
  Ev.Key.Home,
  Ev.Key.End,
  Ev.Key.PageUp,
  Ev.Key.PageDown,
  Ev.Key.Up,
  Ev.Key.Down,
  Ev.Key.Left,
  Ev.Key.Right,
  Ev.Key.BackTab,
]
MOUSE_BUTTONS = [
  Ev.Mouse.Left, Ev.Mouse.Right, Ev.Mouse.Middle, Ev.Mouse.Release, Ev.Mouse.WheelUp, Ev.Mouse.WheelDown,
]

def key_event(raw: Raw) -> Ev.Event
  return Ev.Event.Char(char(raw.ch), mods(raw.mod)) if raw.ch != 0

  found = key(raw.key)
  held = mods(raw.mod)
  # termbox2 marks every ASCII control byte with Ctrl: the ones with a name of their own (Enter, Tab...) are typed
  # without it. A terminal key (Left, Home...) keeps the Ctrl of its escape sequence.
  return Ev.Event.Key(found, held.with(ctrl: false)) if NAMED_CONTROLS.get(raw.key).some?

  Ev.Event.Key(found, held)
end

def char(code: Int) -> String
  return String.from_code(REPLACEMENT) if SURROGATES.include?(code) or code > MAX_CODE_POINT

  String.from_code(code)
end

def other_key(code: Int) -> Ev.Key
  return Ev.Key.Ctrl(String.from_code(code + CARET_OFFSET).downcase) if code >= 0 and code <= LAST_CONTROL

  index = KEY_TOP - code
  return Ev.Key.F(index + 1) if index >= 0 and index < FUNCTION_KEYS

  terminal = index - FUNCTION_KEYS
  return TERMINAL_KEYS[terminal] if terminal >= 0 and terminal < TERMINAL_KEYS.size

  Ev.Key.Other(code)
end

def mouse_event(raw: Raw) -> Ev.Event
  index = KEY_TOP - raw.key - FUNCTION_KEYS - TERMINAL_KEYS.size
  return Ev.Event.Mouse(MOUSE_BUTTONS[index], raw.x, raw.y, mods(raw.mod)) if index >= 0 and index < MOUSE_BUTTONS.size

  Ev.Event.Key(Ev.Key.Other(raw.key), mods(raw.mod))
end

def mouse_flag(mouse: Bool) -> Int
  return INPUT_MOUSE if mouse

  0
end

def bit?(bits: Int, flag: Int) -> Bool = bits.bit_and(flag) != 0

def index_value(index: Int) -> Result[Int]
  return error("tui: color index out of range 0..#{MAX_INDEX}: #{index}") if index < 0 or index > MAX_INDEX

  return ok(HI_BLACK) if index == 0

  ok(index)
end

def rgb_value(red: Int, green: Int, blue: Int) -> Result[Int]
  bad = [red, green, blue].select do |channel| channel < 0 or channel > MAX_CHANNEL end
  return error("tui: color channel out of range 0..#{MAX_CHANNEL}: #{bad[0]}") if bad.size > 0

  value = red.shift_left(16).bit_or(green.shift_left(8)).bit_or(blue)
  return ok(HI_BLACK) if value == 0

  ok(value)
end

# termbox2.h, `TB_OPT_ATTR_W == 64`.
def attr_value(attr: St.Attr) -> Int
  case attr
    St.Attr.Bold -> 0x0100_0000
    St.Attr.Underline -> 0x0200_0000
    St.Attr.Reverse -> 0x0400_0000
    St.Attr.Italic -> 0x0800_0000
    St.Attr.Blink -> 0x1000_0000
    St.Attr.Bright -> 0x4000_0000
    St.Attr.Dim -> 0x8000_0000
    St.Attr.Strikeout -> 0x1_0000_0000
    St.Attr.DoubleUnderline -> 0x2_0000_0000
    St.Attr.Overline -> 0x4_0000_0000
    St.Attr.Invisible -> 0x8_0000_0000
  end
end
