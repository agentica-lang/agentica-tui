import St from "../src/style"
import View from "../src/view"
import Width from "../src/width"

def main() -> Void
  Test.run([
    Test.test("text wraps at spaces, cuts a long word, and counts wide characters as two columns") do
      try Test.eq(View.wrap("the quick brown fox", 9), ["the quick", "brown fox"])
      try Test.eq(View.wrap("abcdefghij", 4), ["abcd", "efgh", "ij"])
      try Test.eq(View.wrap("中文字", 5), ["中文", "字"])
      Test.eq(View.wrap("a\n\nb", 3), ["a", "", "b"])
    end,
    Test.test("a spacer takes the room a row or a column leaves") do
      row = View.row([View.text("a"), View.spacer(), View.text("b")])
      col = View.col([View.text("top"), View.spacer(), View.text("end")])
      try Test.eq(grid(View.layout(row, 5, 1), 5, 1), ["a   b"])
      Test.eq(grid(View.layout(col, 3, 4), 3, 4), ["top", "   ", "   ", "end"])
    end,
    Test.test("a box draws its border and padding around its child, across the width of a column") do
      box = View.box(View.text("hi"), padding: 1, border: View.Border.Line)
      Test.eq(
        grid(View.layout(View.col([box]), 8, 6), 8, 6),
        ["┌──────┐", "│      │", "│ hi   │", "│      │", "└──────┘", "        "],
      )
    end,
    Test.test("the styles inside a box are drawn on the style of the box") do
      inner = View.text("x", St.Style(fg: St.Color.Red))
      cells = View.layout(View.box(inner, style: St.Style(bg: St.Color.Blue, bold: true)), 1, 1)
      Test.eq(cells.last.style, St.Style(fg: St.Color.Red, bg: St.Color.Blue, bold: true))
    end,
    Test.test("nothing is drawn outside the screen") do
      tree = View.col([
        View.box(View.text("hello world, a long line"), padding: 2, border: View.Border.Line),
        View.row([View.text("中文中文"), View.text("more")]),
        View.box(View.text("negative"), padding: -3),
      ])

      cells = View.layout(tree, 3, 2)
      try Test.eq(cells.select { |c| c.x < 0 or c.y < 0 or c.x + width(c.char) > 3 or c.y >= 2 }, [])
      try Test.eq(grid(View.layout(View.text("hello world"), 3, 1), 3, 1), ["hel"])
      Test.eq(grid(View.layout(View.text("a中b"), 2, 2), 2, 2), ["a ", "中"])
    end,
    Test.test("a negative padding counts as none") do
      row = View.row([View.box(View.text("ab"), padding: -1), View.text("c")])
      cells = View.layout(row, 4, 1)
      try Test.eq(cells.select { |c| c.x < 0 or c.y != 0 }, [])
      Test.eq(grid(cells, 4, 1), ["abc "])
    end,
    Test.test("deep nesting is laid out once per level") do
      deep = (0...20).to_a.reduce(View.text("deep")) do |child, i| nest(child, i) end
      Test.eq(grid(View.layout(deep, 6, 1), 6, 1), ["deep  "])
    end,
  ])
end

def width(char: String) -> Int = Width.char(char)

# A row with a spacer around `child` on even levels, a column on odd ones.
def nest(child: View.Node, level: Int) -> View.Node
  return View.row([child, View.spacer()]) if level % 2 == 0

  View.col([child])
end

# The lines a terminal shows for `cells`; a wide character covers the column after it.
def grid(cells: List[View.Cell], w: Int, h: Int) -> List[String]
  rows = (0...h).map { |_y| (0...w).map { |_x| " " } }
  for cell in cells
    row = rows[cell.y]
    row = row.take(cell.x) + [cell.char] + row.drop(cell.x + width(cell.char))
    rows = rows.take(cell.y) + [row] + rows.drop(cell.y + 1)
  end

  rows.map { |row| row.join("") }
end
