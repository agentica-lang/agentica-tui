## A view tree and its layout: what a screen of `width` by `height` shows of a `Node`, as cells. Pure.
##
## A `Row` gives each child its own width and the height of the row; a `Col` gives each child the whole width and its
## own height. A `Spacer` takes an equal share of the room the others leave. Text wraps at spaces, and is cut where a
## word is longer than the line; a `Line` never wraps; widths are terminal columns (`src/width.agc`). Nothing is drawn
## outside the screen.

import St from "style"
import Width from "width"

## The border of a box.
enum Border
  None
  Line
end

## How a box draws around its child: `padding` cells (0 or more), a border, and the `style` that fills the box and is
## the base of the styles inside it (`merge`).
struct Frame
  padding: Int = 0
  border: Border = Border.None
  style: St.Style
end

## Text in one style, a part of a `Line`.
struct Span
  text: String
  style: St.Style
end

## A part of the screen.
enum Node
  ## Text, with its lines (`\n`) wrapped to the width it gets.
  Text(String, St.Style)
  ## Children side by side.
  Row(List[Node])
  ## Children one under another.
  Col(List[Node])
  ## A child in a frame.
  Box(Node, Frame)
  ## Free room in a `Row` or a `Col`.
  Spacer
  ## Spans on one line, never wrapped: cut at the width, spaces kept, a newline drawn as a space.
  Line(List[Span])
  ## Items one line each, the selected one (by index) in the style, scrolled to keep it in view.
  List(List[Node], Int, St.Style)
end

## A cell to draw: `char` at column `x` and line `y`; a wide character also covers the cell after it.
struct Cell
  x: Int
  y: Int
  char: String
  style: St.Style
end

## Text in `style`.
def text(text: String, style: St.Style = St.Style()) -> Node = Node.Text(text, style)

## Children side by side.
def row(children: List[Node]) -> Node = Node.Row(children)

## Children one under another.
def col(children: List[Node]) -> Node = Node.Col(children)

## `child` in a frame: `padding` cells (a negative one is 0), a border, and the style that fills it.
def box(child: Node, padding: Int = 0, border: Border = Border.None, style: St.Style = St.Style()) -> Node
  Node.Box(child, Frame(padding: padding, border: border, style: style))
end

## Free room in a row or a column.
def spacer() -> Node = Node.Spacer

## Spans on one line that never wraps: cut at the width, with leading spaces kept.
def line(spans: List[Span]) -> Node = Node.Line(spans)

## Text in `style`, a part of a `line`.
def span(text: String, style: St.Style = St.Style()) -> Span = Span(text: text, style: style)

## `items` one line each (a taller item shows its first line), with the item at `selected` in `focus` (reverse when
## left out). When they do not all fit, the list scrolls to keep the selected item in the middle, or as near as the
## ends allow. A `selected` outside the items marks none.
def list(items: List[Node], selected: Int, focus: Optional[St.Style] = none) -> Node
  Node.List(items, selected, focus.unwrap_or(FOCUS))
end

## The cells of `node` on a screen of `width` by `height`, in drawing order.
def layout(node: Node, width: Int, height: Int) -> List[Cell]
  draw(node, Area(x: 0, y: 0, width: width, height: height), St.Style(), [])
end

## The index of the first item a list of `count` items shows in `rows` lines, with the item at `selected` kept in
## view, so that row `r` of the list shows item `list_first(count, selected, rows) + r`.
def list_first(count: Int, selected: Int, rows: Int) -> Int
  return 0 if count <= rows or rows <= 0

  [[selected - rows / 2, 0].max.unwrap!, count - rows].min.unwrap!
end

## The lines of `text` in `width` columns: split at `\n`, wrapped at spaces, and cut where a word does not fit.
def wrap(text: String, width: Int) -> List[String]
  return [] if width <= 0

  text.split("\n").flat_map { |line| wrap_line(line, width) }
end

private

FOCUS = St.Style(reverse: true)
# The most lines a spacer may take.
UNBOUNDED = 1_000_000_000

struct Area
  x: Int
  y: Int
  width: Int
  height: Int
end

struct Size
  width: Int
  height: Int
end

# The fewest and the most lines a node takes in a column.
struct Extent
  least: Int
  most: Int
end

# `cells` with those of `node` after them. The cells are passed down, not joined: `xs + ys` copies both lists.
def draw(node: Node, area: Area, base: St.Style, cells: List[Cell]) -> List[Cell]
  return cells if area.width <= 0 or area.height <= 0

  case node
    Node.Text(text, style) -> text_cells(text, area, St.merge(base, style), cells)
    Node.Row(children) -> row_cells(children, area, base, cells)
    Node.Col(children) -> col_cells(children, area, base, cells)
    Node.Box(child, frame) -> box_cells(child, frame, area, St.merge(base, frame.style), cells)
    Node.Spacer -> cells
    Node.Line(spans) -> line_cells(spans, area, base, cells)
    Node.List(items, selected, focus) -> list_cells(items, selected, area, St.merge(base, focus), base, cells)
  end
end

# The size `node` takes when it may use at most `width` columns. Each node below is measured once.
def measure(node: Node, width: Int) -> Size
  return Size(width: 0, height: 0) if width <= 0

  case node
    Node.Text(text, _) ->
      lines = wrap(text, width)
      Size(width: lines.map { |line| Width.text(line) }.max.unwrap_or(0), height: lines.size)
    Node.Row(children) ->
      sizes = row_sizes(children, width)
      Size(width: sizes.map { |s| s.width }.sum, height: sizes.map { |s| s.height }.max.unwrap_or(0))
    Node.Col(children) ->
      sizes = children.map { |child| measure(child, width) }
      Size(width: sizes.map { |s| s.width }.max.unwrap_or(0), height: sizes.map { |s| s.height }.sum)
    Node.Box(child, frame) ->
      edge = inset(frame)
      inner = measure(child, width - 2 * edge)
      Size(width: [inner.width + 2 * edge, width].min.unwrap!, height: inner.height + 2 * edge)
    Node.Spacer -> Size(width: 0, height: 0)
    Node.Line(spans) ->
      Size(width: [spans.map { |span| Width.text(flat(span.text)) }.sum, width].min.unwrap!, height: 1)
    # A list never measures its items: it takes the width it gets.
    Node.List(items, _, _) -> Size(width: width, height: items.size)
  end
end

# How many lines `node` takes in a column `width` wide: spacers and lists grow with the room, other nodes do not.
def extent(node: Node, width: Int) -> Extent
  return Extent(least: 0, most: 0) if width <= 0

  case node
    Node.Spacer -> Extent(least: 0, most: UNBOUNDED)
    Node.List(items, _, _) -> Extent(least: 0, most: items.size)
    Node.Box(child, frame) ->
      edge = inset(frame)
      inner = extent(child, width - 2 * edge)
      Extent(least: inner.least + 2 * edge, most: [inner.most + 2 * edge, UNBOUNDED].min.unwrap!)
    Node.Col(children) ->
      parts = children.map { |child| extent(child, width) }
      most = [parts.map { |part| part.most }.sum, UNBOUNDED].min.unwrap!
      Extent(least: parts.map { |part| part.least }.sum, most: most)
    Node.Row(children) -> row_extent(children, width)
    _ ->
      height = measure(node, width).height
      Extent(least: height, most: height)
  end
end

# A row is as tall as its tallest child; a spacer in a row is free room across, not down.
def row_extent(children: List[Node], width: Int) -> Extent
  sizes = row_sizes(children, width)
  parts = (0...children.size).select { |i| children[i] != Node.Spacer }.map { |i| extent(children[i], sizes[i].width) }
  Extent(
    least: parts.map { |part| part.least }.max.unwrap_or(0),
    most: parts.map { |part| part.most }.max.unwrap_or(0),
  )
end

# True for a node that takes the room a row leaves instead of a width of its own: a spacer, or a node with a list,
# which takes any width it gets.
def stretches?(node: Node) -> Bool = node == Node.Spacer or has_list?(node)

def has_list?(node: Node) -> Bool
  case node
    Node.List(_, _, _) -> true
    Node.Box(child, _) -> has_list?(child)
    Node.Row(children) -> children.any?(&has_list?)
    Node.Col(children) -> children.any?(&has_list?)
    _ -> false
  end
end

# The size of each child of a row in `width` columns: each in order takes the width it needs of what is left, and
# the spacers and lists share the rest.
def row_sizes(children: List[Node], width: Int) -> List[Size]
  left = width
  sizes: List[Size] = []
  for child in children
    size = Size(width: 0, height: 0)
    if not stretches?(child)
      size = measure(child, left)
    end

    sizes = sizes.push(size)
    left = left - size.width
  end

  widths = shared(children, sizes.map { |s| s.width }, left)
  (0...sizes.size).map { |i| sizes[i].with(width: widths[i]) }
end

# Each child first gets the fewest lines it takes, in order while there is room. The rest goes to the children
# that grow up to a limit (lists), evenly, each up to the most it takes; what they leave goes to the spacers.
def col_heights(children: List[Node], width: Int, height: Int) -> List[Int]
  extents = children.map { |child| extent(child, width) }
  left = height
  heights: List[Int] = []
  for part in extents
    used = [part.least, left].min.unwrap!
    heights = heights.push(used)
    left = left - used
  end

  limited = (0...extents.size).select { |i| extents[i].most < UNBOUNDED }
  filled = grown(heights, extents, left, limited)
  free = (0...extents.size).select { |i| extents[i].most >= UNBOUNDED }
  grown(filled, extents, left - filled.sum + heights.sum, free)
end

# `heights` with `room` shared by the children at `indices`, evenly, each up to the most it takes.
def grown(heights: List[Int], extents: List[Extent], room: Int, indices: List[Int]) -> List[Int]
  out = heights
  left = room
  growing = indices.select { |i| extents[i].most > out[i] }
  while left > 0 and not growing.empty?
    share = left / growing.size
    if share == 0
      # Fewer lines than growing children: the first ones get one each.
      for i in growing.take(left)
        out = out.set(i, out[i] + 1)
      end

      return out
    end

    still: List[Int] = []
    for i in growing
      add = [share, extents[i].most - out[i]].min.unwrap!
      out = out.set(i, out[i] + add)
      left = left - add
      if out[i] < extents[i].most
        still = still.push(i)
      end
    end

    growing = still
  end

  out
end

# `room` split between the children that stretch, the first ones getting one more when it does not divide evenly.
def shared(children: List[Node], fixed: List[Int], room: Int) -> List[Int]
  count = children.select(&stretches?).size
  return fixed if count == 0 or room <= 0

  out: List[Int] = []
  seen = 0
  for i in 0...children.size
    if stretches?(children[i])
      extra = 0
      if seen < room % count
        extra = 1
      end

      out = out.push(room / count + extra)
      seen = seen + 1
    else
      out = out.push(fixed[i])
    end
  end

  out
end

def row_cells(children: List[Node], area: Area, base: St.Style, into: List[Cell]) -> List[Cell]
  sizes = row_sizes(children, area.width)
  cells = into
  x = area.x
  for i in 0...children.size
    part = Area(x: x, y: area.y, width: [sizes[i].width, area.x + area.width - x].min.unwrap!, height: area.height)
    cells = draw(children[i], part, base, cells)
    x = x + sizes[i].width
  end

  cells
end

def col_cells(children: List[Node], area: Area, base: St.Style, into: List[Cell]) -> List[Cell]
  heights = col_heights(children, area.width, area.height)
  cells = into
  y = area.y
  for i in 0...children.size
    part = Area(x: area.x, y: y, width: area.width, height: [heights[i], area.y + area.height - y].min.unwrap!)
    cells = draw(children[i], part, base, cells)
    y = y + heights[i]
  end

  cells
end

def box_cells(child: Node, frame: Frame, area: Area, style: St.Style, into: List[Cell]) -> List[Cell]
  lined = frame.border == Border.Line
  cells = into
  for y in area.y...(area.y + area.height)
    for x in area.x...(area.x + area.width)
      cells = cells.push(Cell(x: x, y: y, char: frame_char(lined, x, y, area), style: style))
    end
  end

  edge = inset(frame)
  inner = Area(x: area.x + edge, y: area.y + edge, width: area.width - 2 * edge, height: area.height - 2 * edge)

  draw(child, inner, style, cells)
end

# The cells between the edge of a box and its child; a negative padding counts as 0.
def inset(frame: Frame) -> Int
  padding = [frame.padding, 0].max.unwrap!
  return padding + 1 if frame.border == Border.Line

  padding
end

def frame_char(lined: Bool, x: Int, y: Int, area: Area) -> String
  return " " if not lined

  left = x == area.x
  right = x == area.x + area.width - 1
  top = y == area.y
  bottom = y == area.y + area.height - 1
  return "┌" if top and left
  return "┐" if top and right
  return "└" if bottom and left
  return "┘" if bottom and right
  return "─" if top or bottom
  return "│" if left or right

  " "
end

def text_cells(text: String, area: Area, style: St.Style, into: List[Cell]) -> List[Cell]
  lines = wrap(text, area.width).take(area.height)
  cells = into
  for row in 0...lines.size
    x = area.x
    start = cells.size
    for char in lines[row].split("")
      columns = Width.char(char)
      if columns == 0
        cells = marked(cells, start, char)
        next
      end

      break if x + columns > area.x + area.width

      cells = cells.push(Cell(x: x, y: area.y + row, char: char, style: style))
      x = x + columns
    end
  end

  cells
end

def line_cells(spans: List[Span], area: Area, base: St.Style, into: List[Cell]) -> List[Cell]
  cells = into
  x = area.x
  for span in spans
    style = St.merge(base, span.style)
    for char in flat(span.text).split("")
      columns = Width.char(char)
      if columns == 0
        cells = marked(cells, into.size, char)
        next
      end

      return cells if x + columns > area.x + area.width

      cells = cells.push(Cell(x: x, y: area.y, char: char, style: style))
      x = x + columns
    end
  end

  cells
end

# A zero-width character (a combining mark, a joiner) goes on the last cell drawn since `start`, as termbox2 draws
# it; with none, it is dropped. A variation selector is dropped too: many terminals draw a character with U+FE0F two
# columns wide, while termbox2 moves one column on, so the rest of the line would shift.
def marked(cells: List[Cell], start: Int, char: String) -> List[Cell]
  return cells if cells.size <= start or selector?(char)

  last = cells.last
  return cells if last.char.length >= Width.CELL_CHARS

  cells.set(cells.size - 1, last.with(char: last.char + char))
end

def selector?(char: String) -> Bool
  code = char.code
  (code >= 0xFE00 and code <= 0xFE0F) or (code >= 0xE0100 and code <= 0xE01EF)
end

def list_cells(
  items: List[Node],
  selected: Int,
  area: Area,
  focused: St.Style,
  base: St.Style,
  into: List[Cell],
) -> List[Cell]
  cells = into
  first = list_first(items.size, selected, area.height)
  last = [first + area.height, items.size].min.unwrap!
  for i in first...last
    part = area.with(y: area.y + i - first, height: 1)
    if i == selected
      cells = box_cells(items[i], Frame(style: St.Style()), part, focused, cells)
    else
      cells = draw(items[i], part, base, cells)
    end
  end

  cells
end

def flat(text: String) -> String = text.replace("\n", " ")

def wrap_line(line: String, width: Int) -> List[String]
  out: List[String] = []
  current = ""
  # The width of `current`, kept so that each word is measured once.
  used = 0
  for word in line.split(" ")
    columns = Width.text(word)
    if current == "" and columns <= width
      current = word
      used = columns
      next
    elsif current != "" and used + 1 + columns <= width
      current = "#{current} #{word}"
      used = used + 1 + columns
      next
    end

    if current != ""
      out = out.push(current)
    end

    current = word
    while Width.text(current) > width
      parts = Width.cut(current, width)
      if parts[0] == ""
        parts = [current.slice(0, 1), current.slice(1, current.length - 1)]
      end

      out = out.push(parts[0])
      current = parts[1]
    end

    used = Width.text(current)
  end

  out.push(current)
end
