# View tree

A view is a tree of `TUI.Node` values, which `TUI.run` draws ([Elm loop](elm-loop.md)). By hand,
`TUI.Raw.render(screen, node, last)` draws the tree over the whole screen and presents it, and gives the
`TUI.Raw.Grid` the screen now shows. With that grid as `last`, the next `render` writes only the cells that changed;
with no `last`, it clears the screen first. Pass a `last` only when the render that gave it succeeded and nothing was
drawn since.

```ruby
import TUI from "pkg/tui/tui"

def view(count: Int) -> TUI.Node
  title = TUI.text("Counter", style: TUI.Style(bold: true))
  value = TUI.text("count: #{count}", style: TUI.Style(fg: TUI.Color.Green))
  box = TUI.box(TUI.col([title, value]), padding: 1, border: TUI.Border.Line, style: TUI.Style(fg: TUI.Color.Cyan))
  TUI.col([box, TUI.spacer(), TUI.row([TUI.spacer(), TUI.text("q quits")])])
end
```

## Nodes

- `text(text, style)`: the lines of `text` (split at `\n`), wrapped at spaces to the width it gets; a word longer
  than the line is cut. `style` may be left out.
- `row(children)`: side by side. Each child, in order, takes the width it needs of what is left, and the height of
  the row.
- `col(children)`: one under another. Each child takes the whole width and the height it needs.
- `box(child, padding:, border:, style:)`: `padding` cells around the child (a negative padding is 0), a border
  (`Border.None`, the default, or `Border.Line`), and the box filled with `style`. The styles inside are drawn on
  `style` ([merge](styles.md)). Every option may be left out.
- `spacer()`: an equal share of the room that the other children of a row or a column leave.

These build the variants of `Node`: `Text(text, style)`, `Row(children)`, `Col(children)`, `Box(child, frame)` with
`Frame(padding:, border:, style:)`, and `Spacer`.

## Lists and tables

- `list(items, selected, rows, focus)`: the items that fit in `rows` lines, one line each, with the item at
  `selected` in `focus` (reverse when left out). A longer list scrolls to keep the selected item in the middle.
- `table(cells, widths)`: the lines of a table, one `Node` for each row of `cells`. Each column is as wide as its
  widest cell, or `widths[i]`; longer text is cut, and one space separates the columns.

The lines of a table go into `col` for a plain table, or into `list` to select a row:

```ruby
def view(files: Files) -> TUI.Node
  lines = TUI.table(files.rows.map { |f| [f.name, "#{f.size}"] })
  header = TUI.text("name, size", style: TUI.Style(bold: true))
  TUI.col([header, TUI.list(lines, files.selected, files.height - 1)])
end
```

The model keeps `selected` (moved by the arrow keys in `update`) and the height (from `Event.Resize`).

## Layout

`TUI.layout(node, width, height)` gives the cells of a tree on a screen of that size, with no terminal: a list of
`Cell(x:, y:, char:, style:)`. `render` draws those cells. Nothing is drawn outside the screen. Each node is
measured once per level of the tree, so the time grows with the size of the tree times its depth.

`TUI.Raw.diff(old, new)` gives the cells to write to turn one `Grid` into another: those that differ, or all of `new`
when the size differs.

`TUI.wrap(text, width)` gives the lines that `text` wraps to.

## Widths

Widths are terminal columns, from the `wcwidth` table of glibc 2.41 (`src/width_table.agc`, made by
`scripts/width_table.py`): a wide character takes two columns, a combining mark none. termbox2 draws with the
`wcwidth` of the glibc it runs on, so on another glibc a character may take another width on screen than in the
layout.
