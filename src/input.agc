## Input events from the bytes a terminal sends: characters, control keys, escape sequences (CSI and SS3 keys, SGR
## mouse reports) and bracketed paste. Pure: `feed` takes the bytes of one read and gives the events they make and the
## state for the next read, so a sequence cut between two reads is still one event.

import Ev from "event"

## The most bytes a paste keeps; the rest is read and dropped up to its end mark.
MAX_PASTE = 1_048_576

## How long a paste with no end mark waits for more bytes before it ends.
PASTE_IDLE_MS = 2000

## How long a lone Escape, or an Escape and `[` or `O`, waits for its next byte before it is the key.
SEQUENCE_MS = 50

## How long a longer unfinished sequence waits for its next byte before it is dropped.
PARTIAL_MS = 1000

## What `feed` keeps between two reads: the bytes of an unfinished sequence, or the paste being read.
struct Parser
  rest: Bytes = "".bytes
  paste: Optional[Paste] = none
end

## The events a read made, and the parser for the next one.
struct Fed
  parser: Parser
  events: List[Ev.Event]
end

## A bracketed paste being read: the text kept so far (its first MAX_PASTE bytes), and the start of an end mark that
## the last read cut.
struct Paste
  pieces: List[Bytes] = []
  size: Int = 0
  tail: Bytes = "".bytes
end

## The events of `chunk`, the bytes read after those `parser` kept.
def feed(parser: Parser, chunk: Bytes, mode: Ev.InputMode) -> Fed
  case parser.paste
    some(paste) -> pasting(paste, chunk, mode, [])
    none -> scan(parser.rest + chunk, mode, false, [])
  end
end

## The events of what `parser` still waits for, read as it is: the wait for more bytes ended.
def flush(parser: Parser, mode: Ev.InputMode) -> Fed
  case parser.paste
    some(paste) ->
      kept = paste.with(pieces: paste.pieces.push(paste.tail), size: paste.size + paste.tail.length)
      Fed(parser: Parser(), events: [paste_event(kept)])
    none -> scan(parser.rest, mode, true, [])
  end
end

## How many milliseconds `feed` should wait for the next byte before `flush`; none when it holds nothing to resolve
## (or, in mode `Alt`, a lone Escape, which waits for the key that follows).
def wait_ms(parser: Parser, mode: Ev.InputMode) -> Optional[Int]
  return some(PASTE_IDLE_MS) if parser.paste.some?
  return none if parser.rest.empty?
  return none if mode == Ev.InputMode.Alt and parser.rest.length == 1 and parser.rest[0] == ESC
  return some(SEQUENCE_MS) if parser.rest.length <= 2

  some(PARTIAL_MS)
end

private

ESC = 0x1b
DEL = 0x7f
BACKSPACE = 0x08
TAB = 0x09
ENTER = 0x0d
SPACE = 0x20
LBRACKET = "[".code
UPPER_O = "O".code
LESS_THAN = "<".code
SEMICOLON = ";".code
ZERO = "0".code
DIGITS = ZERO.."9".code
# A CSI sequence longer than this with no final byte is dropped.
CSI_MAX = 32
MAX_DIGITS = 6
REPLACEMENT = 0xfffd
END_MARK = Bytes.from_list([ESC, LBRACKET, 0x32, 0x30, 0x31, 0x7e]).unwrap!
MARK_LENGTH = 6
# Caret notation: control code c is Ctrl and the character c + 64 (1 is Ctrl-A).
CARET_OFFSET = 0x40
CSI_KEYS = {
  "A": Ev.Key.Up,
  "B": Ev.Key.Down,
  "C": Ev.Key.Right,
  "D": Ev.Key.Left,
  "H": Ev.Key.Home,
  "F": Ev.Key.End,
  "P": Ev.Key.F(1),
  "Q": Ev.Key.F(2),
  "R": Ev.Key.F(3),
  "S": Ev.Key.F(4),
  "Z": Ev.Key.BackTab,
}
SS3_KEYS = {
  "A": Ev.Key.Up,
  "B": Ev.Key.Down,
  "C": Ev.Key.Right,
  "D": Ev.Key.Left,
  "H": Ev.Key.Home,
  "F": Ev.Key.End,
  "P": Ev.Key.F(1),
  "Q": Ev.Key.F(2),
  "R": Ev.Key.F(3),
  "S": Ev.Key.F(4),
}
TILDE_KEYS = {
  1: Ev.Key.Home,
  2: Ev.Key.Insert,
  3: Ev.Key.Delete,
  4: Ev.Key.End,
  5: Ev.Key.PageUp,
  6: Ev.Key.PageDown,
  7: Ev.Key.Home,
  8: Ev.Key.End,
  11: Ev.Key.F(1),
  12: Ev.Key.F(2),
  13: Ev.Key.F(3),
  14: Ev.Key.F(4),
  15: Ev.Key.F(5),
  17: Ev.Key.F(6),
  18: Ev.Key.F(7),
  19: Ev.Key.F(8),
  20: Ev.Key.F(9),
  21: Ev.Key.F(10),
  23: Ev.Key.F(11),
  24: Ev.Key.F(12),
}
PASTE_START = 200
PASTE_END = 201
BUTTONS = [Ev.Mouse.Left, Ev.Mouse.Middle, Ev.Mouse.Right, Ev.Mouse.Release]
# The bits of the button code of a mouse report.
BUTTON_BITS = 3
SHIFT_BIT = 4
ALT_BIT = 8
CTRL_BIT = 16
MOTION_BIT = 32
WHEEL_BIT = 64

enum Taken
  Got(Ev.Event, Int)
  Skip(Int)
  PasteStart(Int)
  More
end

enum CsiEnd
  Whole(Int)
  Cut(Int)
  Open
end

# The events of `data` from the start; what is left (an unfinished sequence) goes into the parser, unless `final`
# says no more bytes come.
def scan(data: Bytes, mode: Ev.InputMode, final: Bool, events: List[Ev.Event]) -> Fed
  at = 0
  out = events
  while at < data.length
    step = take(data, at, mode, final)
    case step
      Taken.Got(event, used) ->
        out = out.push(event)
        at = at + used
      Taken.Skip(used) -> at = at + used
      Taken.PasteStart(used) -> return pasting(Paste(), data.drop(at + used), mode, out)
      Taken.More -> break
    end
  end

  Fed(parser: Parser(rest: data.drop(at)), events: out)
end

def take(data: Bytes, at: Int, mode: Ev.InputMode, final: Bool) -> Taken
  byte = data[at]
  if byte == ESC
    return escape(data, at, mode, final)
  elsif byte < SPACE or byte == DEL
    return Taken.Got(control(byte), 1)
  elsif byte < 0x80
    return Taken.Got(Ev.Event.Char(String.from_code(byte), Ev.Mods()), 1)
  end

  utf8(data, at, final)
end

def control(byte: Int) -> Ev.Event
  if byte == TAB
    return Ev.Event.Key(Ev.Key.Tab, Ev.Mods())
  elsif byte == ENTER
    return Ev.Event.Key(Ev.Key.Enter, Ev.Mods())
  elsif byte == DEL or byte == BACKSPACE
    return Ev.Event.Key(Ev.Key.Backspace, Ev.Mods())
  end

  Ev.Event.Key(Ev.Key.Ctrl(String.from_code(byte + CARET_OFFSET).downcase), Ev.Mods(ctrl: true))
end

def escape_key() -> Ev.Event = Ev.Event.Key(Ev.Key.Escape, Ev.Mods())

# An Escape that starts nothing known is the key, and what follows is read afresh: Escape then `[` then `x` for
# `ESC [ x`.
def escape(data: Bytes, at: Int, mode: Ev.InputMode, final: Bool) -> Taken
  if at + 1 >= data.length
    return Taken.Got(escape_key(), 1) if final

    return Taken.More
  end

  next_byte = data[at + 1]
  if next_byte == LBRACKET
    return csi(data, at, final)
  elsif next_byte == UPPER_O
    return ss3(data, at, final)
  elsif not alt_target?(next_byte, mode)
    return Taken.Got(escape_key(), 1)
  end

  inner = take(data, at + 1, mode, final)
  case inner
    Taken.Got(event, used) -> Taken.Got(with_alt(event), used + 1)
    Taken.Skip(used) -> Taken.Skip(used + 1)
    Taken.PasteStart(_), Taken.More -> inner
  end
end

# Escape and a key arrive together when Alt is held: Enter, Backspace and printable ASCII in mode `Esc`, any key in
# mode `Alt`. `[` and `O` start escape sequences.
def alt_target?(byte: Int, mode: Ev.InputMode) -> Bool
  return false if byte == ESC or byte == LBRACKET or byte == UPPER_O

  case mode
    Ev.InputMode.Alt -> true
    Ev.InputMode.Esc -> byte == ENTER or byte == DEL or byte == BACKSPACE or (byte >= SPACE and byte < DEL)
  end
end

def with_alt(event: Ev.Event) -> Ev.Event
  case event
    Ev.Event.Key(key, mods) -> Ev.Event.Key(key, mods.with(alt: true))
    Ev.Event.Char(char, mods) -> Ev.Event.Char(char, mods.with(alt: true))
    _ -> event
  end
end

# `ESC O` and a letter; with digits between (`ESC O 5 P`, Ctrl+F1) the last number is the xterm modifier. A sequence
# with parameters that names no key is dropped whole.
def ss3(data: Bytes, at: Int, final: Bool) -> Taken
  stop = at + 2
  while stop < data.length and (DIGITS.include?(data[stop]) or data[stop] == SEMICOLON)
    stop = stop + 1
  end

  if stop >= data.length
    return Taken.Got(escape_key(), 1) if final and stop == at + 2
    return Taken.Skip(data.length - at) if final

    return Taken.More
  end

  used = stop - at + 1
  key = SS3_KEYS.get(String.from_code(data[stop]))
  return Taken.Got(escape_key(), 1) if stop == at + 2 and key.none?

  params = fields(data, at + 2, stop)
  return Taken.Skip(used) if key.none? or params.none?

  numbers = params.unwrap!
  Taken.Got(Ev.Event.Key(key.unwrap!, mods_of(numbers, numbers.size - 1)), used)
end

def csi(data: Bytes, at: Int, final: Bool) -> Taken
  case csi_end(data, at)
    CsiEnd.Whole(last) -> sequence(data, at, last)
    CsiEnd.Cut(index) -> Taken.Skip(index - at)
    CsiEnd.Open ->
      left = data.length - at
      return Taken.More if not final and left < CSI_MAX
      return Taken.Got(escape_key(), 1) if left == 2

      Taken.Skip(left)
  end
end

# Where the CSI sequence at `at` ends: its final byte, the byte that has no place in a CSI and cuts it, or more bytes
# may come.
def csi_end(data: Bytes, at: Int) -> CsiEnd
  i = at + 2
  while i < data.length
    byte = data[i]
    if byte >= 0x40 and byte <= 0x7e
      return CsiEnd.Whole(i)
    elsif byte < SPACE or byte > 0x3f
      return CsiEnd.Cut(i)
    end

    i = i + 1
  end

  CsiEnd.Open
end

# The event of the whole CSI sequence from `at` to its final byte at `last`.
def sequence(data: Bytes, at: Int, last: Int) -> Taken
  used = last - at + 1
  letter = String.from_code(data[last])
  return mouse(data, at, last, letter) if data[at + 2] == LESS_THAN

  numbers = fields(data, at + 2, last)
  return Taken.Skip(used) if numbers.none?

  params = numbers.unwrap!
  return tilde(params, used) if letter == "~"

  case CSI_KEYS.get(letter)
    some(key) -> Taken.Got(Ev.Event.Key(key, mods_of(params, 1)), used)
    none ->
      # `ESC [` and a letter with nothing between is Escape, `[` and the letter.
      return Taken.Got(escape_key(), 1) if last == at + 2

      Taken.Skip(used)
  end
end

def tilde(params: List[Int], used: Int) -> Taken
  return Taken.Skip(used) if params.empty?

  code = params[0]
  if code == PASTE_START
    return Taken.PasteStart(used)
  elsif code == PASTE_END
    return Taken.Skip(used)
  end

  key = TILDE_KEYS.get(code).unwrap_or(Ev.Key.Other(code))
  Taken.Got(Ev.Event.Key(key, mods_of(params, 1)), used)
end

# A mouse report `ESC [ < button ; x ; y M` (or `m` for a release), strictly; anything else is dropped. The cell is
# from 0.
def mouse(data: Bytes, at: Int, last: Int, letter: String) -> Taken
  used = last - at + 1
  numbers = fields(data, at + 3, last)
  return Taken.Skip(used) if numbers.none? or (letter != "M" and letter != "m")

  report = numbers.unwrap!
  return Taken.Skip(used) if report.size != 3 or report[1] < 1 or report[2] < 1

  code = report[0]
  mods = Ev.Mods(
    shift: bit?(code, SHIFT_BIT),
    alt: bit?(code, ALT_BIT),
    ctrl: bit?(code, CTRL_BIT),
    motion: bit?(code, MOTION_BIT),
  )

  button = code.bit_and(BUTTON_BITS)
  if letter == "m"
    return Taken.Got(Ev.Event.Mouse(Ev.Mouse.Release, report[1] - 1, report[2] - 1, mods), used)
  elsif bit?(code, WHEEL_BIT)
    # A sideways wheel (buttons 2 and 3) is dropped.
    return Taken.Skip(used) if button > 1

    wheel = Ev.Mouse.WheelUp
    if button == 1
      wheel = Ev.Mouse.WheelDown
    end

    return Taken.Got(Ev.Event.Mouse(wheel, report[1] - 1, report[2] - 1, mods), used)
  end

  Taken.Got(Ev.Event.Mouse(BUTTONS[button], report[1] - 1, report[2] - 1, mods), used)
end

# The numbers between `from` and `to` (not included) separated by `;`, an empty one being 0; none when anything else
# is there.
def fields(data: Bytes, from: Int, to: Int) -> Optional[List[Int]]
  return some([]) if from >= to

  out: List[Int] = []
  value = 0
  digits = 0
  for i in from...to
    byte = data[i]
    if byte == SEMICOLON
      out = out.push(value)
      value = 0
      digits = 0
    elsif DIGITS.include?(byte) and digits < MAX_DIGITS
      value = value * 10 + byte - ZERO
      digits = digits + 1
    else
      return none
    end
  end

  some(out.push(value))
end

# The modifiers of the xterm parameter at `index`: 1 plus the bits shift (1), alt (2), ctrl (4) and meta (8).
def mods_of(params: List[Int], index: Int) -> Ev.Mods
  return Ev.Mods() if index < 0 or params.size <= index or params[index] < 1

  bits = params[index] - 1
  Ev.Mods(shift: bit?(bits, 1), alt: bit?(bits, 2) or bit?(bits, 8), ctrl: bit?(bits, 4))
end

def bit?(bits: Int, flag: Int) -> Bool = bits.bit_and(flag) != 0

# A character of UTF-8 at `at`: a bad or overlong byte sequence, a surrogate or a code point past U+10FFFF is U+FFFD.
def utf8(data: Bytes, at: Int, final: Bool) -> Taken
  lead = data[at]
  length = utf8_length(lead)
  bad = Taken.Got(Ev.Event.Char(String.from_code(REPLACEMENT), Ev.Mods()), 1)
  return bad if length == 0

  left = data.length - at
  # A byte that cannot continue the character ends it there: only the lead is U+FFFD, and the byte is read afresh.
  for i in 1...[left, length].min.unwrap!
    return bad if data[at + i].bit_and(0xc0) != 0x80
  end

  if left < length
    return Taken.Got(Ev.Event.Char(String.from_code(REPLACEMENT), Ev.Mods()), left) if final

    return Taken.More
  end

  code = lead.bit_and(0xff.shift_right(length + 1))
  for i in 1...length
    byte = data[at + i]
    return bad if byte.bit_and(0xc0) != 0x80

    code = code.shift_left(6).bit_or(byte.bit_and(0x3f))
  end

  Taken.Got(Ev.Event.Char(scalar(code, length), Ev.Mods()), length)
end

def utf8_length(lead: Int) -> Int
  if lead >= 0xc2 and lead <= 0xdf
    return 2
  elsif lead >= 0xe0 and lead <= 0xef
    return 3
  elsif lead >= 0xf0 and lead <= 0xf4
    return 4
  end

  0
end

# The shortest code point of each length: a smaller one is an overlong form.
def scalar(code: Int, length: Int) -> String
  least = [0, 0, 0x80, 0x800, 0x10000][length]
  surrogate = code >= 0xd800 and code <= 0xdfff
  return String.from_code(REPLACEMENT) if code < least or surrogate or code > 0x10ffff

  String.from_code(code)
end

# The bytes after a paste start mark, up to the end mark. The text keeps its first MAX_PASTE bytes. Only the places of
# the Escape bytes are looked at (found in a latin-1 text of the bytes, one character each, which the VM splits at
# once), so the text itself costs no step per byte.
def pasting(paste: Paste, chunk: Bytes, mode: Ev.InputMode, events: List[Ev.Event]) -> Fed
  data = paste.tail + chunk
  kept = paste.with(tail: "".bytes)
  # Every byte is a latin-1 character, so the decode cannot fail.
  parts = data.decode("latin-1").unwrap!.split(String.from_code(ESC))
  at = 0
  for part in parts.take(parts.size - 1)
    at = at + part.length
    left = data.length - at
    if left >= MARK_LENGTH
      if data.slice(at, MARK_LENGTH) == END_MARK
        done = keep(kept, data.take(at))
        return scan(data.drop(at + MARK_LENGTH), mode, false, events.push(paste_event(done)))
      end
    elsif data.drop(at) == END_MARK.take(left)
      # The end mark may go on in the next read.
      held = keep(kept, data.take(at))
      return Fed(parser: Parser(paste: some(held.with(tail: data.drop(at)))), events: events)
    end

    at = at + 1
  end

  Fed(parser: Parser(paste: some(keep(kept, data))), events: events)
end

def keep(paste: Paste, piece: Bytes) -> Paste
  room = MAX_PASTE - paste.size
  return paste if room <= 0 or piece.empty?

  taken = piece.take(room)
  paste.with(pieces: paste.pieces.push(taken), size: paste.size + taken.length)
end

def paste_event(paste: Paste) -> Ev.Event
  text = Bytes.concat(paste.pieces).scrub()
  Ev.Event.Paste(text.replace("\r\n", "\n").replace("\r", "\n"))
end
