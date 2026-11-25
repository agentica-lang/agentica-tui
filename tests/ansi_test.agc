import Ansi from "../src/ansi"
import Bd from "../src/backend"
import Gr from "../src/grid"
import St from "../src/style"
import View from "../src/view"

WIDTH = 8
HEIGHT = 3
PLAIN = St.Style()

# The Escape bytes show as `^`.
def shown(bytes: String) -> String = bytes.replace(Ansi.ESC, "^")

def screen(cells: List[View.Cell]) -> Gr.Grid = Gr.apply(Gr.blank(WIDTH, HEIGHT), cells)

def cell(x: Int, y: Int, char: String, style: St.Style = PLAIN) -> View.Cell
  View.Cell(x: x, y: y, char: char, style: style)
end

def drawn(old: Gr.Grid, new: Gr.Grid, output: St.OutputMode = St.OutputMode.Normal) -> String
  shown(Ansi.update(some(old), new, output))
end

def main() -> Void
  Test.run([
    Test.test("only the cells that changed are sent, each run after one cursor move") do
      old = screen([cell(0, 0, "a"), cell(1, 0, "b")])
      new = screen([cell(0, 0, "a"), cell(1, 0, "c"), cell(2, 0, "d"), cell(5, 2, "e")])
      try Test.eq(drawn(old, old), "")
      Test.eq(drawn(old, new), "^[1;2H^[0mcd^[3;6He")
    end,
    Test.test("the first screen clears the terminal and sends what is not blank") do
      new = screen([cell(1, 1, "x", St.Style(fg: St.Color.Red, bold: true))])
      try Test.eq(shown(Ansi.update(none, new, St.OutputMode.Normal)), "^[0m^[H^[2J^[2;2H^[0;1;31mx^[0m")
      other = Gr.blank(WIDTH + 1, HEIGHT)
      Test.eq(shown(Ansi.update(some(other), new, St.OutputMode.Normal)), "^[0m^[H^[2J^[2;2H^[0;1;31mx^[0m")
    end,
    Test.test("a style change sends all of the style, and the end resets it") do
      old = Gr.blank(WIDTH, HEIGHT)
      new = screen([
        cell(0, 0, "a", St.Style(fg: St.Color.Green, bg: St.Color.Blue, underline: true, italic: true)),
        cell(1, 0, "b", St.Style(fg: St.Color.Green, attrs: [St.Attr.Strikeout, St.Attr.Overline])),
      ])

      Test.eq(drawn(old, new), "^[1;1H^[0;3;4;32;44ma^[0;9;53;32mb^[0m")
    end,
    Test.test("a color the output mode cannot show is the terminal's own") do
      style = St.Style(fg: St.Color.Index(196), bg: St.Color.Rgb(1, 2, 3))
      new = screen([cell(0, 0, "a", style)])
      blank = Gr.blank(WIDTH, HEIGHT)
      try Test.eq(drawn(blank, new, St.OutputMode.Normal), "^[1;1H^[0ma^[0m")
      try Test.eq(drawn(blank, new, St.OutputMode.Colors256), "^[1;1H^[0;38;5;196ma^[0m")
      try Test.eq(drawn(blank, new, St.OutputMode.Truecolor), "^[1;1H^[0;38;5;196;48;2;1;2;3ma^[0m")
      bright = screen([cell(0, 0, "b", St.Style(fg: St.Color.Red, bg: St.Color.Cyan, attrs: [St.Attr.Bright]))])
      Test.eq(drawn(blank, bright), "^[1;1H^[0;91;106mb^[0m")
    end,
    Test.test("a wide character moves the cursor two columns, and its covered cell sends nothing") do
      old = screen([cell(0, 0, "a"), cell(1, 0, "b")])
      new = screen([cell(0, 0, "中"), cell(2, 0, "z")])
      Test.eq(drawn(old, new), "^[1;1H^[0m中z")
    end,
    Test.test("a control character shows as U+FFFD, and a color out of range is an error") do
      try Test.eq(drawn(Gr.blank(WIDTH, HEIGHT), screen([cell(0, 0, Ansi.ESC)])), "^[1;1H^[0m�")
      try Test.eq(Ansi.check(St.Style(fg: St.Color.Index(255), bg: St.Color.Rgb(0, 0, 255))), ok())
      try Test.eq(Ansi.check(St.Style(fg: St.Color.Index(256))).ok?, false)
      Test.eq(Ansi.check(St.Style(bg: St.Color.Rgb(0, -1, 0))).ok?, false)
    end,
    Test.test("the cursor is placed on every draw and hidden once") do
      at = some(Bd.Cursor(x: 4, y: 2))
      try Test.eq(shown(Ansi.place(none, at)), "^[3;5H^[?25h")
      try Test.eq(shown(Ansi.place(at, at)), "^[3;5H")
      try Test.eq(shown(Ansi.place(at, none)), "^[?25l")
      try Test.eq(Ansi.place(none, none), "")
      try Test.eq(shown(Ansi.mouse(true)), "^[?1000h^[?1002h^[?1006h")
      Test.eq(shown(Ansi.mouse(false)), "^[?1006l^[?1002l^[?1000l")
    end,
  ])
end
