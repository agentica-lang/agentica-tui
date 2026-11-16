import Gr from "../src/grid"
import St from "../src/style"
import View from "../src/view"
import Wg from "../src/widgets"

def main() -> Void
  Test.run([
    Test.test("a list shows the rows around the selected item and marks it") do
      items = (0...10).map { |i| View.text("item #{i}") }
      try Test.eq(lines(Wg.list(items, 0, 3), 7, 3), ["item 0 ", "item 1 ", "item 2 "])
      try Test.eq(lines(Wg.list(items, 5, 3), 7, 3), ["item 4 ", "item 5 ", "item 6 "])
      try Test.eq(lines(Wg.list(items, 9, 3), 7, 3), ["item 7 ", "item 8 ", "item 9 "])
      grid = Gr.of(Wg.list(items, 5, 3), 7, 3)
      try Test.assert(grid.rows[1].all? { |g| g.style == St.Style(reverse: true) }, "the selected line is reversed")
      Test.eq(grid.rows[0][0].style, St.Style())
    end,
    Test.test("a short list shows every item, and a focus style can be given") do
      items = [View.text("a"), View.text("b")]
      try Test.eq(lines(Wg.list(items, 1, 5), 2, 3), ["a ", "b ", "  "])
      grid = Gr.of(Wg.list(items, 1, 5, focus: some(St.Style(bold: true))), 2, 3)
      Test.eq(grid.rows[1][0].style, St.Style(bold: true))
    end,
    Test.test("a table aligns its columns to the widest cell, or to the widths given, and cuts longer text") do
      cells = [["name", "size"], ["a.txt", "12"], ["中文", "3"]]
      try Test.eq(lines(View.col(Wg.table(cells)), 10, 3), ["name  size", "a.txt 12  ", "中文  3   "])
      Test.eq(lines(View.col(Wg.table(cells, widths: [3, 2])), 6, 3), ["nam si", "a.t 12", "中  3 "])
    end,
    Test.test("table lines go in a list to select a row") do
      rows = Wg.table([["a", "1"], ["bb", "2"]])
      Test.eq(Gr.of(Wg.list(rows, 1, 2), 4, 2).rows[1][3].style, St.Style(reverse: true))
    end,
  ])
end

def lines(node: View.Node, width: Int, height: Int) -> List[String]
  Gr.of(node, width, height).rows.map { |row| row.map { |g| g.char }.join("") }
end
