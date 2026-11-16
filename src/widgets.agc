## Views made of the view tree: a list with a selected item, and the lines of a table. Pure.

import St from "style"
import View from "view"
import Width from "width"

## The items that fit in `rows` lines, one line each, with the item at `selected` in the `focus` style (reverse when
## left out). A list longer than `rows` scrolls to keep the selected item in the middle, or as near as the ends allow.
def list(items: List[View.Node], selected: Int, rows: Int, focus: Optional[St.Style] = none) -> View.Node
  style = focus.unwrap_or(FOCUS)
  first = top(items.size, selected, rows)
  last = [first + [rows, 0].max.unwrap!, items.size].min.unwrap!
  View.col((first...last).map { |i| item(items[i], i == selected, style) })
end

## The lines of a table, one node for each row of `cells`. Column `i` is `widths[i]` columns wide (when `widths` is
## empty, the widest cell of the column), with one space before the next; longer text is cut.
def table(cells: List[List[String]], widths: List[Int] = []) -> List[View.Node]
  columns = widths
  if columns.empty?
    columns = natural(cells)
  end

  cells.map { |line| View.text(table_line(line, columns)) }
end

private

FOCUS = St.Style(reverse: true)

def top(size: Int, selected: Int, rows: Int) -> Int
  return 0 if rows <= 0 or size <= rows

  [[selected - rows / 2, 0].max.unwrap!, size - rows].min.unwrap!
end

def item(node: View.Node, selected: Bool, focus: St.Style) -> View.Node
  return View.box(node, style: focus) if selected

  node
end

def natural(cells: List[List[String]]) -> List[Int]
  count = cells.map { |line| line.size }.max.unwrap_or(0)
  (0...count).map { |i| cells.map { |line| Width.text(cell(line, i)) }.max.unwrap_or(0) }
end

def cell(line: List[String], i: Int) -> String
  return "" if i >= line.size

  line[i]
end

def table_line(line: List[String], columns: List[Int]) -> String
  parts = (0...columns.size).map { |i| fit(cell(line, i), columns[i]) }
  parts.join(" ")
end

# `text` cut to `columns` and filled with spaces up to it.
def fit(text: String, columns: Int) -> String
  return "" if columns <= 0

  head = Width.cut(text, columns)[0]
  head + List.repeat(" ", columns - Width.text(head)).join("")
end
