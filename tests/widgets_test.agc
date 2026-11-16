import Gr from "../src/grid"
import St from "../src/style"
import View from "../src/view"
import Wg from "../src/widgets"

BOLD = St.Style(bold: true)
REVERSE = St.Style(reverse: true)

def main() -> Void
  Test.run([
    Test.test("a line keeps its spaces, never wraps, and cuts before a wide character that does not fit") do
      try Test.eq(lines(View.line([View.span("  a b c d")]), 5, 2), ["  a b", "     "])
      try Test.eq(lines(View.line([View.span("ab中")]), 3, 1), ["ab "])
      Test.eq(lines(View.line([View.span("a\nb")]), 3, 1), ["a b"])
    end,
    Test.test("each span of a line keeps its style") do
      grid = Gr.of(View.line([View.span("a", BOLD), View.span("b")]), 2, 1)
      Test.eq(grid.rows[0].map { |g| g.style }, [BOLD, St.Style()])
    end,
    Test.test("a list shows the items around the selected one in the room it gets, and marks it") do
      items = (0...10).map { |i| View.text("item #{i}") }
      try Test.eq(lines(View.list(items, 0), 7, 3), ["item 0 ", "item 1 ", "item 2 "])
      try Test.eq(lines(View.list(items, 5), 7, 3), ["item 4 ", "item 5 ", "item 6 "])
      try Test.eq(lines(View.list(items, 9), 7, 3), ["item 7 ", "item 8 ", "item 9 "])
      grid = Gr.of(View.list(items, 5), 7, 3)
      try Test.assert(grid.rows[1].all? { |g| g.style == REVERSE }, "the selected line is reversed")
      Test.eq(grid.rows[0][0].style, St.Style())
    end,
    Test.test("a list item taller than a line shows its first line, so the selected one stays in view") do
      items = [View.text("one two"), View.text("three four"), View.text("five")]
      Test.eq(lines(View.list(items, 1), 5, 2), ["one  ", "three"])
    end,
    Test.test("a short list leaves the rest empty, takes a focus style, and marks nothing out of range") do
      items = [View.text("a"), View.text("b")]
      try Test.eq(lines(View.col([View.list(items, 1), View.text("end")]), 3, 4), ["a  ", "b  ", "end", "   "])
      try Test.eq(Gr.of(View.list(items, 1, focus: some(BOLD)), 2, 2).rows[1][0].style, BOLD)
      Test.assert(Gr.of(View.list(items, 7), 2, 2).rows.all? { |row| row[0].style == St.Style() }, "none marked")
    end,
    Test.test("a long list takes only the room its siblings leave, also in a box") do
      items = (0...50).map { |i| View.text("item #{i}") }
      plain = View.col([View.text("head"), View.list(items, 20), View.text("foot")])
      try Test.eq(lines(plain, 7, 6), ["head   ", "item 18", "item 19", "item 20", "item 21", "foot   "])
      boxed = View.col([
        View.text("head"),
        View.box(View.list(items, 20), border: View.Border.Line),
        View.text("foot"),
      ])

      Test.eq(lines(boxed, 9, 6), ["head     ", "┌───────┐", "│item 19│", "│item 20│", "└───────┘", "foot     "])
    end,
    Test.test("two lists share a column, a short one taking only its items, and a spacer shares with a list") do
      long = (0...50).map { |i| View.text("L#{i}") }
      short = [View.text("s0")]
      try Test.eq(lines(View.col([View.list(long, 0), View.list(long, 0)]), 3, 4), ["L0 ", "L1 ", "L0 ", "L1 "])
      try Test.eq(lines(View.col([View.list(short, 0), View.list(long, 0)]), 3, 4), ["s0 ", "L0 ", "L1 ", "L2 "])
      Test.eq(
        lines(View.col([View.list(long, 0), View.spacer(), View.text("end")]), 3, 5),
        ["L0 ", "L1 ", "   ", "   ", "end"],
      )
    end,
    Test.test("a list in a row takes the width the others leave") do
      items = [View.text("abcdef")]
      try Test.eq(lines(View.row([View.list(items, 0), View.text("|x")]), 6, 1), ["abcd|x"])
      side = View.col([View.text("t"), View.list(items, 0)])
      Test.eq(lines(View.row([side, View.text("|x")]), 6, 2), ["t   |x", "abcd  "])
    end,
    Test.test("a list of 10000 items lays out without reading every item") do
      items = (0...10_000).map { |i| View.text("item #{i}") }
      node = View.col([View.text("head"), View.list(items, 5_000), View.text("foot")])
      started = Time.monotonic_ms()
      shown = lines(node, 20, 10)
      took = Time.monotonic_ms() - started
      try Test.eq([shown[0], shown[5], shown[9]], ["head" + " " * 16, "item 5000" + " " * 11, "foot" + " " * 16])
      Test.assert(took < 50, "layout took #{took} ms")
    end,
    Test.test("a click on a row of a list maps to its item with list_first") do
      items = (0...50).map { |i| View.text("item #{i}") }
      node = View.col([View.text("head"), View.list(items, 20), View.text("foot")])
      # The list starts on line 1 and has 6 - 2 lines; a click on line 3 is row 2 of the list.
      clicked = View.list_first(50, 20, 4) + 2
      try Test.eq(clicked, 20)
      Test.eq(lines(node, 7, 6)[3], "item #{clicked}")
    end,
    Test.test("a table aligns its columns to the widest cell or to the widths given, and cuts longer text") do
      cells = [["name", "size"], ["a.txt", "12"], ["中文", "3"]]
      try Test.eq(lines(View.col(Wg.table(cells)), 10, 3), ["name  size", "a.txt 12  ", "中文  3   "])
      Test.eq(lines(View.col(Wg.table(cells, widths: [3, 2])), 6, 3), ["nam si", "a.t 12", "中  3 "])
    end,
    Test.test("a table keeps an empty first cell, drops columns of no width and cells past the widths") do
      try Test.eq(lines(View.col(Wg.table([["", "b"], ["aaa", "c"]])), 5, 2), ["    b", "aaa c"])
      Test.eq(lines(View.col(Wg.table([["a", "b", "c", "d"]], widths: [1, 0, 1])), 4, 1), ["a c "])
    end,
    Test.test("a table narrower than its lines is cut, not wrapped, also inside a list") do
      cells = [["alpha", "beta", "gamma"], ["delta", "eps", "zeta"]]
      try Test.eq(lines(View.col(Wg.table(cells)), 9, 2), ["alpha bet", "delta eps"])
      grid = Gr.of(View.list(Wg.table(cells), 1), 9, 2)
      try Test.eq(lines(View.list(Wg.table(cells), 1), 9, 2), ["alpha bet", "delta eps"])
      Test.eq(grid.rows[1][0].style, REVERSE)
    end,
  ])
end

def lines(node: View.Node, width: Int, height: Int) -> List[String]
  Gr.of(node, width, height).rows.map { |row| row.map { |g| g.char }.join("") }
end
