import St from "../src/style"
import View from "../src/view"

def main() -> Void
  Test.run([
    Test.test("text wraps at spaces, cuts a long word, and counts wide characters as two columns") do
      try Test.eq(View.wrap("the quick brown fox", 9), ["the quick", "brown fox"])
      try Test.eq(View.wrap("abcdefghij", 4), ["abcd", "efgh", "ij"])
      try Test.eq(View.wrap("中文字", 5), ["中文", "字"])
      Test.eq(View.wrap("a\n\nb", 3), ["a", "", "b"])
    end,
    Test.test("a spacer takes the room a row or a column leaves") do
      row = View.Node.Row([text("a"), View.Node.Spacer, text("b")])
      col = View.Node.Col([text("top"), View.Node.Spacer, text("end")])
      try Test.eq(grid(View.layout(row, 5, 1), 5, 1), ["a   b"])
      Test.eq(grid(View.layout(col, 3, 4), 3, 4), ["top", "   ", "   ", "end"])
    end,
    Test.test("a box draws its border and padding around its child, across the width of a column") do
      box = View.Node.Box(text("hi"), 1, true, St.Style())
      Test.eq(
        grid(View.layout(View.Node.Col([box]), 8, 6), 8, 6),
        ["┌──────┐", "│      │", "│ hi   │", "│      │", "└──────┘", "        "],
      )
    end,
    Test.test("the styles inside a box are drawn on the style of the box") do
      inner = View.Node.Text("x", St.Style(fg: St.Color.Red))
      cells = View.layout(View.Node.Box(inner, 0, false, St.Style(bg: St.Color.Blue, bold: true)), 1, 1)
      Test.eq(cells.last.style, St.Style(fg: St.Color.Red, bg: St.Color.Blue, bold: true))
    end,
    Test.test("nothing is drawn outside the screen") do
      tree = View.Node.Col([
        View.Node.Box(text("hello world, a long line"), 2, true, St.Style()),
        View.Node.Row([text("中文中文"), text("more")]),
      ])

      cells = View.layout(tree, 3, 2)
      try Test.eq(cells.select { |c| c.x < 0 or c.y < 0 or c.x + width(c.char) > 3 or c.y >= 2 }, [])
      try Test.eq(grid(View.layout(text("hello world"), 3, 1), 3, 1), ["hel"])
      Test.eq(grid(View.layout(text("a中b"), 2, 2), 2, 2), ["a ", "中"])
    end,
  ])
end

def text(s: String) -> View.Node = View.Node.Text(s, St.Style())

def width(char: String) -> Int
  return 2 if char.code >= 0x4e00

  1
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
