## A view tree and its layout: what a screen of `width` by `height` shows of a `Node`, as cells. Pure.
##
## A `Row` gives each child its own width and the height of the row; a `Col` gives each child the whole width and its
## own height. A `Spacer` takes an equal share of the room the others leave. Text wraps at spaces, and is cut where a
## word is longer than the line; widths are terminal columns (`src/width.agc`). Nothing is drawn outside the screen.

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
end

## A cell to draw: `char` at column `x` and line `y`; a wide character also covers the cell after it.
struct Cell
  x: Int
  y: Int
  char: String
  style: St.Style
end

def text(text: String, style: St.Style = St.Style()) -> Node = Node.Text(text, style)

def row(children: List[Node]) -> Node = Node.Row(children)

def col(children: List[Node]) -> Node = Node.Col(children)

def box(child: Node, padding: Int = 0, border: Border = Border.None, style: St.Style = St.Style()) -> Node
  Node.Box(child, Frame(padding: padding, border: border, style: style))
end

def spacer() -> Node = Node.Spacer

## The cells of `node` on a screen of `width` by `height`, in drawing order.
def layout(node: Node, width: Int, height: Int) -> List[Cell]
  draw(node, Area(x: 0, y: 0, width: width, height: height), St.Style())
end

## The lines of `text` in `width` columns: split at `\n`, wrapped at spaces, and cut where a word does not fit.
def wrap(text: String, width: Int) -> List[String]
  return [] if width <= 0

  text.split("\n").flat_map { |line| wrap_line(line, width) }
end

private

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

def draw(node: Node, area: Area, base: St.Style) -> List[Cell]
  return [] if area.width <= 0 or area.height <= 0

  case node
    Node.Text(text, style) -> text_cells(text, area, St.merge(base, style))
    Node.Row(children) -> row_cells(children, area, base)
    Node.Col(children) -> col_cells(children, area, base)
    Node.Box(child, frame) -> box_cells(child, frame, area, St.merge(base, frame.style))
    Node.Spacer -> []
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
  end
end

# The size of each child of a row in `width` columns: each in order takes the width it needs of what is left, and
# the spacers share the rest.
def row_sizes(children: List[Node], width: Int) -> List[Size]
  left = width
  sizes: List[Size] = []
  for child in children
    size = Size(width: 0, height: 0)
    if child != Node.Spacer
      size = measure(child, left)
    end

    sizes = sizes.push(size)
    left = left - size.width
  end

  widths = shared(children, sizes.map { |s| s.width }, left)
  (0...sizes.size).map { |i| sizes[i].with(width: widths[i]) }
end

def col_heights(children: List[Node], width: Int, height: Int) -> List[Int]
  left = height
  fixed: List[Int] = []
  for child in children
    used = 0
    if child != Node.Spacer
      used = [measure(child, width).height, left].min.unwrap!
    end

    fixed = fixed.push(used)
    left = left - used
  end

  shared(children, fixed, left)
end

# `room` split between the spacers, the first ones getting one more when it does not divide evenly.
def shared(children: List[Node], fixed: List[Int], room: Int) -> List[Int]
  spacers = children.select { |child| child == Node.Spacer }.size
  return fixed if spacers == 0 or room <= 0

  out: List[Int] = []
  seen = 0
  for i in 0...children.size
    if children[i] == Node.Spacer
      extra = 0
      if seen < room % spacers
        extra = 1
      end

      out = out.push(room / spacers + extra)
      seen = seen + 1
    else
      out = out.push(fixed[i])
    end
  end

  out
end

def row_cells(children: List[Node], area: Area, base: St.Style) -> List[Cell]
  sizes = row_sizes(children, area.width)
  cells: List[Cell] = []
  x = area.x
  for i in 0...children.size
    part = Area(x: x, y: area.y, width: [sizes[i].width, area.x + area.width - x].min.unwrap!, height: area.height)
    cells = cells + draw(children[i], part, base)
    x = x + sizes[i].width
  end

  cells
end

def col_cells(children: List[Node], area: Area, base: St.Style) -> List[Cell]
  heights = col_heights(children, area.width, area.height)
  cells: List[Cell] = []
  y = area.y
  for i in 0...children.size
    part = Area(x: area.x, y: y, width: area.width, height: [heights[i], area.y + area.height - y].min.unwrap!)
    cells = cells + draw(children[i], part, base)
    y = y + heights[i]
  end

  cells
end

def box_cells(child: Node, frame: Frame, area: Area, style: St.Style) -> List[Cell]
  lined = frame.border == Border.Line
  cells: List[Cell] = []
  for y in area.y...(area.y + area.height)
    for x in area.x...(area.x + area.width)
      cells = cells.push(Cell(x: x, y: y, char: frame_char(lined, x, y, area), style: style))
    end
  end

  edge = inset(frame)
  inner = Area(x: area.x + edge, y: area.y + edge, width: area.width - 2 * edge, height: area.height - 2 * edge)

  cells + draw(child, inner, style)
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

def text_cells(text: String, area: Area, style: St.Style) -> List[Cell]
  lines = wrap(text, area.width).take(area.height)
  cells: List[Cell] = []
  for row in 0...lines.size
    x = area.x
    for char in lines[row].split("")
      columns = Width.char(char)
      next if columns == 0
      break if x + columns > area.x + area.width

      cells = cells.push(Cell(x: x, y: area.y + row, char: char, style: style))
      x = x + columns
    end
  end

  cells
end

def wrap_line(line: String, width: Int) -> List[String]
  out: List[String] = []
  current = ""
  for word in line.split(" ")
    joined = "#{current} #{word}"
    if current == ""
      joined = word
    end

    if Width.text(joined) <= width
      current = joined
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
  end

  out.push(current)
end
