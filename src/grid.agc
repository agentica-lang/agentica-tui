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

## The glyphs of a screen of `width` by `height`, line by line.
struct Grid
  width: Int
  height: Int
  glyphs: List[Glyph]
end

## A screen of `width` by `height` with only spaces of the default style, as a clear leaves it.
def blank(width: Int, height: Int) -> Grid
  Grid(width: width, height: height, glyphs: (0...(width * height)).map { |_i| BLANK })
end

## The screen that `node` draws on a screen of `width` by `height`.
def of(node: View.Node, width: Int, height: Int) -> Grid
  apply(blank(width, height), View.layout(node, width, height))
end

## The cells to write to turn `old` into `new`: those that differ, or every cell of `new` when the size differs.
def diff(old: Grid, new: Grid) -> List[View.Cell]
  same_size = old.width == new.width and old.height == new.height
  out: List[View.Cell] = []
  for i in 0...new.glyphs.size
    glyph = new.glyphs[i]
    next if glyph.char == ""
    next if same_size and old.glyphs[i] == glyph

    out = out.push(View.Cell(x: i % new.width, y: i / new.width, char: glyph.char, style: glyph.style))
  end

  out
end

## `grid` with `cells` drawn on it in order; a wide character also covers the cell after it, and the cell a removed
## wide character covered becomes a space.
def apply(grid: Grid, cells: List[View.Cell]) -> Grid
  drawn: Map[Int, Glyph] = {}
  for cell in cells
    next if cell.x < 0 or cell.y < 0 or cell.x >= grid.width or cell.y >= grid.height

    at = cell.y * grid.width + cell.x
    drawn = drawn.put(at, Glyph(char: cell.char, style: cell.style))
    next if cell.x + 1 >= grid.width

    if Width.char(cell.char) == 2
      drawn = drawn.put(at + 1, Glyph(char: "", style: cell.style))
    elsif drawn.get(at + 1).unwrap_or(grid.glyphs[at + 1]).char == ""
      # The wide character that covered the next cell is gone, so that cell shows a space.
      drawn = drawn.put(at + 1, BLANK)
    end
  end

  glyphs = (0...grid.glyphs.size).map { |i| drawn.get(i).unwrap_or(grid.glyphs[i]) }
  grid.with(glyphs: glyphs)
end

private

BLANK = Glyph(char: " ", style: St.Style())
