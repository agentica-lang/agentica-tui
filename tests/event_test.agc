import Ev from "../src/event"

# termbox2.h key codes: the terminal keys count down from 0xffff.
KEY_F1 = 0xffff
KEY_UP = 0xffff - 18
KEY_BACK_TAB = 0xffff - 22
KEY_MOUSE_LEFT = 0xffff - 23
KEY_WHEEL_DOWN = 0xffff - 28
MOD_CTRL = 2

def main() -> Void
  Test.run([
    Test.test("named keys") do
      try Test.eq(Ev.key(KEY_UP), Ev.Key.Up)
      try Test.eq(Ev.key(KEY_BACK_TAB), Ev.Key.BackTab)
      try Test.eq(Ev.key(KEY_F1), Ev.Key.F(1))
      try Test.eq(Ev.key(KEY_F1 - 11), Ev.Key.F(12))
      try Test.eq(Ev.key(0x0d), Ev.Key.Enter)
      try Test.eq(Ev.key(0x1b), Ev.Key.Escape)
      try Test.eq(Ev.key(0x7f), Ev.Key.Backspace)
      Test.eq(Ev.key(0x08), Ev.Key.Backspace)
    end,
    Test.test("control keys in caret notation") do
      try Test.eq(Ev.key(0x03), Ev.Key.Ctrl("c"))
      try Test.eq(Ev.key(0x00), Ev.Key.Ctrl("@"))
      Test.eq(Ev.key(0x1f), Ev.Key.Ctrl("_"))
    end,
    Test.test("a code with no name") do Test.eq(Ev.key(0xffff - 40), Ev.Key.Other(0xffff - 40)) end,
    Test.test("a character with its modifiers") do
      raw = Ev.Raw(kind: 1, mod: 1, key: 0, ch: 0xf1)
      Test.eq(Ev.decode(raw), some(Ev.Event.Char("ñ", Ev.Mods(alt: true))))
    end,
    Test.test("a code point that is no character is U+FFFD") do
      surrogate = Ev.Raw(kind: 1, mod: 0, key: 0, ch: 0xd800)
      Test.eq(Ev.decode(surrogate), some(Ev.Event.Char("�", Ev.Mods())))
    end,
    Test.test("Ctrl stays on Ctrl keys only") do
      ctrl_c = Ev.Raw(kind: 1, mod: MOD_CTRL, key: 0x03, ch: 0)
      enter = Ev.Raw(kind: 1, mod: MOD_CTRL, key: 0x0d, ch: 0)
      try Test.eq(Ev.decode(ctrl_c), some(Ev.Event.Key(Ev.Key.Ctrl("c"), Ev.Mods(ctrl: true))))
      Test.eq(Ev.decode(enter), some(Ev.Event.Key(Ev.Key.Enter, Ev.Mods())))
    end,
    Test.test("mouse and resize") do
      click = Ev.Raw(kind: 3, mod: 8, key: KEY_MOUSE_LEFT, ch: 0, x: 4, y: 2)
      wheel = Ev.Raw(kind: 3, mod: 0, key: KEY_WHEEL_DOWN, ch: 0)
      resize = Ev.Raw(kind: 2, mod: 0, key: 0, ch: 0, width: 100, height: 30)
      try Test.eq(Ev.decode(click), some(Ev.Event.Mouse(Ev.Mouse.Left, 4, 2, Ev.Mods(motion: true))))
      try Test.eq(Ev.decode(wheel), some(Ev.Event.Mouse(Ev.Mouse.WheelDown, 0, 0, Ev.Mods())))
      Test.eq(Ev.decode(resize), some(Ev.Event.Resize(100, 30)))
    end,
    Test.test("an event kind termbox2 does not make") do
      Test.eq(Ev.decode(Ev.Raw(kind: 9, mod: 0, key: 0, ch: 0)), none)
    end,
    Test.test("a mouse key with no name") do
      odd = Ev.Raw(kind: 3, mod: 0, key: KEY_UP, ch: 0)
      Test.eq(Ev.decode(odd), some(Ev.Event.Key(Ev.Key.Other(KEY_UP), Ev.Mods())))
    end,
    Test.test("modifier bits") do Test.eq(Ev.mods(15), Ev.Mods(alt: true, ctrl: true, shift: true, motion: true)) end,
    Test.test("input modes") do
      try Test.eq(Ev.input_mode_value(Ev.InputMode.Esc, false), 1)
      try Test.eq(Ev.input_mode_value(Ev.InputMode.Alt, false), 2)
      Test.eq(Ev.input_mode_value(Ev.InputMode.Esc, true), 5)
    end,
  ])
end
