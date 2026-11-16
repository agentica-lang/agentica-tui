## The lines of a table, made of the view tree. Pure.

import View from "view"
import Width from "width"

## The lines of a table, one `line` node for each row of `cells`. Column `i` is `widths[i]` columns wide (when
## `widths` is empty, the widest cell of the column), with one space before the next. Longer text is cut, a newline
## is a space, a column of width 0 or less is left out, and the cells past the last width are dropped.
def table(cells: List[List[String]], widths: List[Int] = []) -> List[View.Node]
  columns = widths
  if columns.empty?
    columns = natural(cells)
  end

  cells.map { |row| View.line([View.span(table_line(row, columns))]) }
end

private

def natural(cells: List[List[String]]) -> List[Int]
  count = cells.map { |row| row.size }.max.unwrap_or(0)
  (0...count).map { |i| cells.map { |row| Width.text(cell(row, i)) }.max.unwrap_or(0) }
end

def cell(row: List[String], i: Int) -> String
  return "" if i >= row.size

  row[i].replace("\n", " ")
end

def table_line(row: List[String], columns: List[Int]) -> String
  shown = (0...columns.size).select { |i| columns[i] > 0 }
  shown.map { |i| fit(cell(row, i), columns[i]) }.join(" ")
end

# `text` cut to `columns` and filled with spaces up to it.
def fit(text: String, columns: Int) -> String
  head = Width.cut(text, columns)[0]
  head + List.repeat(" ", columns - Width.text(head)).join("")
end
