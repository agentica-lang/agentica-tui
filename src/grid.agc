## A screen as a value: the character and style of every cell, and the cells that change from one screen to the
## next. Pure.

import St from "style"
import View from "view"
import Width from "width"

## What one cell shows. The cell after a wide character holds `""`: the wide character covers it.
struct Glyph
  char: String
  style: St.Style
end

## The glyphs of a screen of `width` by `height`, one row per line.
struct Grid
  width: Int
  height: Int
  rows: List[List[Glyph]]
end

## A screen of `width` by `height` with only spaces of the default style, as a clear leaves it.
def blank(width: Int, height: Int) -> Grid
  Grid(width: width, height: height, rows: List.repeat(List.repeat(BLANK, width), height))
end

## The screen that `node` draws on a screen of `width` by `height`.
def of(node: View.Node, width: Int, height: Int) -> Grid
  apply(blank(width, height), View.layout(node, width, height))
end

## The cells to write to turn `old` into `new`: those that differ, or every cell of `new` when the size differs. A
## covered cell (`""`) is written with the wide character before it, so a terminal that finds that character narrow
## shows a space there.
def diff(old: Grid, new: Grid) -> List[View.Cell]
  same_size = old.width == new.width and old.height == new.height
  out: List[View.Cell] = []
  for y in 0...new.height
    line = new.rows[y]
    next if same_size and old.rows[y] == line

    for x in 0...new.width
      next if same_size and not changed?(old.rows[y], line, x)

      out = out.push(View.Cell(x: x, y: y, char: line[x].char, style: line[x].style))
    end
  end

  out
end

## `grid` with `cells` drawn on it in order; a wide character also covers the cell after it, and the cell a
## wide character covered becomes a space when a narrow one replaces it.
def apply(grid: Grid, cells: List[View.Cell]) -> Grid
  rows = grid.rows
  # Cells come mostly row by row: the row being drawn is put back only when the next cell is on another row.
  y = -1
  line: List[Glyph] = []
  for cell in cells
    next if cell.x < 0 or cell.y < 0 or cell.x >= grid.width or cell.y >= grid.height

    if cell.y != y
      if y >= 0
        rows = rows.set(y, line)
      end

      y = cell.y
      line = rows[y]
    end

    line = drawn(line, cell)
  end

  if y >= 0
    rows = rows.set(y, line)
  end

  grid.with(rows: rows)
end

private

BLANK = Glyph(char: " ", style: St.Style())

def changed?(before: List[Glyph], after: List[Glyph], x: Int) -> Bool
  return true if before[x] != after[x]

  after[x].char == "" and x > 0 and before[x - 1] != after[x - 1]
end

def drawn(line: List[Glyph], cell: View.Cell) -> List[Glyph]
  out = line.set(cell.x, Glyph(char: cell.char, style: cell.style))
  # A covered cell (`""`, which `diff` gives) has no width of its own.
  return out if cell.x + 1 >= line.size or cell.char == ""

  return out.set(cell.x + 1, Glyph(char: "", style: cell.style)) if Width.char(cell.char) == 2

  return out.set(cell.x + 1, BLANK) if out[cell.x + 1].char == ""

  out
end
