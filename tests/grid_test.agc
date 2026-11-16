import Gr from "../src/grid"
import St from "../src/style"
import View from "../src/view"

WIDTH = 12
HEIGHT = 5

def main() -> Void
  Test.run([
    Test.test("writing the diff on the old screen gives the new screen, as a full redraw does") do
      grids = frames().map { |node| Gr.of(node, WIDTH, HEIGHT) }
      pairs = (0...grids.size).flat_map { |i| (0...grids.size).map { |j| [i, j] } }
      wrong = pairs.select { |p| Gr.apply(grids[p[0]], Gr.diff(grids[p[0]], grids[p[1]])) != grids[p[1]] }
      Test.eq(wrong, [])
    end,
    Test.test("only the cells that change are written") do
      old = Gr.of(counter(9), WIDTH, HEIGHT)
      new = Gr.of(counter(10), WIDTH, HEIGHT)
      try Test.eq(Gr.diff(old, old), [])
      Test.eq(Gr.diff(old, new).map { |cell| "#{cell.x},#{cell.y} #{cell.char}" }, ["3,1 1", "4,1 0"])
    end,
    Test.test("another size writes every cell") do
      old = Gr.of(counter(1), WIDTH, HEIGHT)
      Test.eq(Gr.diff(old, Gr.of(counter(1), 4, 2)).size, 8)
    end,
    Test.test("a narrow character over a wide one leaves a space where the wide one ended") do
      old = Gr.of(text("中b"), 4, 1)
      new = Gr.of(text("ab"), 4, 1)
      try Test.eq(chars(old), ["中", "", "b", " "])
      try Test.eq(chars(new), ["a", "b", " ", " "])
      try Test.eq(Gr.apply(old, Gr.diff(old, new)), new)
      Test.eq(chars(Gr.apply(old, [View.Cell(x: 0, y: 0, char: "a", style: St.Style())])), ["a", " ", "b", " "])
    end,
    Test.test("a covered cell is written with its wide character") do
      old = Gr.of(text("ab"), 4, 1)
      new = Gr.of(text("中"), 4, 1)
      Test.eq(Gr.diff(old, new).map { |cell| "#{cell.x} #{cell.char}" }, ["0 中", "1 "])
    end,
  ])
end

def text(s: String) -> View.Node = View.text(s)

def chars(grid: Gr.Grid) -> List[String] = grid.rows.flat_map { |line| line.map { |g| g.char } }

def counter(count: Int) -> View.Node = View.box(View.text("n #{count}"), border: View.Border.Line)

def frames() -> List[View.Node]
  [
    View.text(""),
    counter(9),
    counter(10),
    View.col([View.text("中文 wide", St.Style(bold: true)), View.spacer(), View.text("end")]),
    View.row([View.text("a"), View.spacer(), View.text("中")]),
    View.box(View.text("styled", St.Style(fg: St.Color.Red)), padding: 1, style: St.Style(bg: St.Color.Blue)),
    View.text("a long line that wraps over the whole screen and past its end, cut at the bottom"),
  ]
end
