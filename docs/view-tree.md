# View tree

A view is a tree of `TUI.Node` values. `TUI.render(screen, node)` clears the screen, draws the tree over all of it
and presents it.

```ruby
import TUI from "pkg/tui/tui"

def view(count: Int) -> TUI.Node
  title = TUI.text("Counter", TUI.Style(bold: true))
  value = TUI.text("count: #{count}", TUI.Style(fg: TUI.Color.Green))
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

## Layout

`TUI.layout(node, width, height)` gives the cells of a tree on a screen of that size, with no terminal: a list of
`Cell(x:, y:, char:, style:)`. `render` draws those cells. Nothing is drawn outside the screen. Each node is
measured once per level of the tree, so the time grows with the size of the tree times its depth.

`TUI.wrap(text, width)` gives the lines that `text` wraps to.

## Widths

Widths are terminal columns, from the `wcwidth` table of glibc 2.41 (`src/width_table.agc`, made by
`scripts/width_table.py`): a wide character takes two columns, a combining mark none. termbox2 draws with the
`wcwidth` of the glibc it runs on, so on another glibc a character may take another width on screen than in the
layout.
