import Ev from "../src/event"
import In from "../src/input"

PLAIN = Ev.Mods()
CTRL = Ev.Mods(ctrl: true)
ALT = Ev.Mods(alt: true)

# `^` stands for the Escape byte.
def bytes_of(text: String) -> Bytes = text.replace("^", String.from_code(27)).bytes

def events_of(text: String) -> List[Ev.Event] = In.feed(In.Parser(), bytes_of(text), Ev.InputMode.Esc).events

# What a read made and what the parser still holds, for each read of `reads` in turn.
def after_reads(reads: List[String], mode: Ev.InputMode) -> In.Fed
  start = In.Fed(parser: In.Parser(), events: [])
  reads.reduce(start) do |fed, text|
    next_fed = In.feed(fed.parser, bytes_of(text), mode)
    In.Fed(parser: next_fed.parser, events: fed.events + next_fed.events)
  end
end

def key(key: Ev.Key, mods: Ev.Mods = PLAIN) -> Ev.Event = Ev.Event.Key(key, mods)

def char(text: String, mods: Ev.Mods = PLAIN) -> Ev.Event = Ev.Event.Char(text, mods)

def main() -> Void
  Test.run([
    Test.test("characters, control keys and the keys of an escape sequence") do
      try Test.eq(events_of("a ñ"), [char("a"), char(" "), char("ñ")])
      try Test.eq(events_of("\r\t"), [key(Ev.Key.Enter), key(Ev.Key.Tab)])
      try Test.eq(events_of(String.from_code(127)), [key(Ev.Key.Backspace)])
      try Test.eq(events_of(String.from_code(3)), [key(Ev.Key.Ctrl("c"), CTRL)])
      try Test.eq(events_of(String.from_code(0)), [key(Ev.Key.Ctrl("@"), CTRL)])
      try Test.eq(events_of("^[A^OB^[C^OD"), [key(Ev.Key.Up), key(Ev.Key.Down), key(Ev.Key.Right), key(Ev.Key.Left)])
      try Test.eq(
        events_of("^[H^OF^[3~^[5~^[Z"),
        [key(Ev.Key.Home), key(Ev.Key.End), key(Ev.Key.Delete), key(Ev.Key.PageUp), key(Ev.Key.BackTab)],
      )

      try Test.eq(
        events_of("^OP^OS^[15~^[24~"),
        [key(Ev.Key.F(1)), key(Ev.Key.F(4)), key(Ev.Key.F(5)), key(Ev.Key.F(12))],
      )

      try Test.eq(events_of("^[1;5D"), [key(Ev.Key.Left, CTRL)])
      try Test.eq(events_of("^[1;3A"), [key(Ev.Key.Up, ALT)])
      Test.eq(events_of("^[1;2P"), [key(Ev.Key.F(1), Ev.Mods(shift: true))])
    end,
    Test.test("Escape with a key read together is Alt and that key") do
      try Test.eq(
        events_of("^b^\r^" + String.from_code(127)),
        [char("b", ALT), key(Ev.Key.Enter, ALT), key(Ev.Key.Backspace, ALT)],
      )

      # Escape and Escape, a control key and a letter of an escape sequence stay what they are.
      try Test.eq(events_of("^^\t"), [key(Ev.Key.Escape), key(Ev.Key.Escape), key(Ev.Key.Tab)])
      Test.eq(events_of("^[x"), [key(Ev.Key.Escape), char("["), char("x")])
    end,
    Test.test("a sequence cut between two reads is one event") do
      try Test.eq(after_reads(["^[1;", "5D"], Ev.InputMode.Esc).events, [key(Ev.Key.Left, CTRL)])
      try Test.eq(after_reads(["^", "[A"], Ev.InputMode.Esc).events, [key(Ev.Key.Up)])
      bytes = "ñ".bytes
      fed = In.feed(In.Parser(), bytes.take(1), Ev.InputMode.Esc)
      try Test.eq(fed.events, [])
      Test.eq(In.feed(fed.parser, bytes.drop(1), Ev.InputMode.Esc).events, [char("ñ")])
    end,
    Test.test("a lone Escape waits, then is the key; in mode Alt it waits for the key") do
      fed = In.feed(In.Parser(), bytes_of("^"), Ev.InputMode.Esc)
      try Test.eq(fed.events, [])
      try Test.eq(In.wait_ms(fed.parser, Ev.InputMode.Esc), some(In.SEQUENCE_MS))
      try Test.eq(In.flush(fed.parser, Ev.InputMode.Esc).events, [key(Ev.Key.Escape)])
      try Test.eq(In.wait_ms(In.Parser(), Ev.InputMode.Esc), none)
      try Test.eq(In.wait_ms(fed.parser, Ev.InputMode.Alt), none)
      alt = after_reads(["^", "\t^b"], Ev.InputMode.Alt)
      Test.eq(alt.events, [key(Ev.Key.Tab, ALT), char("b", ALT)])
    end,
    Test.test("mouse reports: buttons, release, wheel, motion and modifiers") do
      try Test.eq(events_of("^[<0;5;3M"), [Ev.Event.Mouse(Ev.Mouse.Left, 4, 2, PLAIN)])
      try Test.eq(events_of("^[<2;1;1M"), [Ev.Event.Mouse(Ev.Mouse.Right, 0, 0, PLAIN)])
      try Test.eq(events_of("^[<0;6;4m"), [Ev.Event.Mouse(Ev.Mouse.Release, 5, 3, PLAIN)])
      try Test.eq(
        events_of("^[<64;10;10M^[<65;1;1M"),
        [Ev.Event.Mouse(Ev.Mouse.WheelUp, 9, 9, PLAIN), Ev.Event.Mouse(Ev.Mouse.WheelDown, 0, 0, PLAIN)],
      )

      try Test.eq(events_of("^[<32;2;2M"), [Ev.Event.Mouse(Ev.Mouse.Left, 1, 1, Ev.Mods(motion: true))])
      Test.eq(events_of("^[<20;2;2M"), [Ev.Event.Mouse(Ev.Mouse.Left, 1, 1, Ev.Mods(ctrl: true, shift: true))])
    end,
    Test.test("a report that is not whole is dropped and the input after it is kept") do
      try Test.eq(events_of("^[<0;-5;3Ma"), [char("a")])
      try Test.eq(events_of("^[<0;0;3Ma"), [char("a")])
      try Test.eq(events_of("^[<66;1;1Ma"), [char("a")])
      try Test.eq(events_of("^[?1;2cb"), [char("b")])
      try Test.eq(events_of("^[" + List.repeat("1;", 20).join("") + "a"), [])
      Test.eq(events_of("^[200;5Xz^[<0;1;1M"), [char("z"), Ev.Event.Mouse(Ev.Mouse.Left, 0, 0, PLAIN)])
    end,
    Test.test("a code with no name is Key.Other; a bad byte is U+FFFD") do
      try Test.eq(events_of("^[99~"), [key(Ev.Key.Other(99))])
      bad = Bytes.from_list([0xff, 0xc3, 0x61, 0xed, 0xa0, 0x80]).unwrap!
      Test.eq(In.feed(In.Parser(), bad, Ev.InputMode.Esc).events, [char("�"), char("�"), char("a"), char("�")])
    end,
    Test.test("a paste is one event: its keys never arrive, its line ends are \\n") do
      text = "hi \nthere" + String.from_code(27) + "[A"
      try Test.eq(events_of("^[200~hi \r\nthere^[A^[201~x"), [Ev.Event.Paste(text), char("x")])
      try Test.eq(events_of("^[201~a"), [char("a")])
      Test.eq(events_of("^[200~ñ^[201~"), [Ev.Event.Paste("ñ")])
    end,
    Test.test("a paste cut anywhere, even inside its marks, is one event") do
      fed = after_reads(["^[20", "0~ab^", "[2", "01", "~c"], Ev.InputMode.Esc)
      try Test.eq(fed.events, [Ev.Event.Paste("ab"), char("c")])
      other = after_reads(["^[200~a^", "[x^[201~"], Ev.InputMode.Esc)
      Test.eq(other.events, [Ev.Event.Paste("a" + String.from_code(27) + "[x")])
    end,
    Test.test("a paste keeps its first MiB and a quiet one ends by flush") do
      big = In.feed(In.Parser(), bytes_of("^[200~"), Ev.InputMode.Esc)
      chunk = List.repeat("x", 1024).join("").bytes
      fed = (0...1100).reduce(big) do |state, _| In.feed(state.parser, chunk, Ev.InputMode.Esc) end
      try Test.eq(In.wait_ms(fed.parser, Ev.InputMode.Esc), some(In.PASTE_IDLE_MS))
      done = In.feed(fed.parser, bytes_of("^[201~"), Ev.InputMode.Esc)
      try Test.eq(done.events.size, 1)
      try Test.eq(done.events.map { |event| paste_length(event) }, [In.MAX_PASTE])
      quiet = after_reads(["^[200~abc"], Ev.InputMode.Esc)
      Test.eq(In.flush(quiet.parser, Ev.InputMode.Esc).events, [Ev.Event.Paste("abc")])
    end,
  ])
end

def paste_length(event: Ev.Event) -> Int
  case event
    Ev.Event.Paste(text) -> text.length
    _ -> -1
  end
end
