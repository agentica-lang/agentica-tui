## Colors, text attributes and output modes. Pure.

## A foreground or background color.
enum Color
  ## The terminal's own color.
  Default
  Black
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
  ## A color of the 256-color palette, 0 to 255 (output mode `Colors256`).
  Index(Int)
  ## Red, green and blue, each 0 to 255 (output mode `Truecolor`).
  Rgb(Int, Int, Int)
end

## A text attribute. Terminals show some of them only.
enum Attr
  Bold
  Underline
  Reverse
  Italic
  Blink
  Dim
  ## Bright colors in output mode `Normal`.
  Bright
  Strikeout
  DoubleUnderline
  Overline
  Invisible
end

## How the terminal reads colors: `Normal` (the eight named ones), `Colors256` (`Color.Index`) or `Truecolor`
## (`Color.Rgb`). Named colors work in `Normal` only.
enum OutputMode
  Normal
  Colors256
  Truecolor
end

## The colors and attributes of a cell or a text. `attrs` holds the attributes that have no field of their own.
struct Style
  fg: Color = Color.Default
  bg: Color = Color.Default
  bold: Bool = false
  dim: Bool = false
  italic: Bool = false
  underline: Bool = false
  reverse: Bool = false
  attrs: List[Attr] = []
end

## `over` drawn on `base`: its colors where they are not `Default`, and the attributes of both.
def merge(base: Style, over: Style) -> Style
  Style(
    fg: on_top(base.fg, over.fg),
    bg: on_top(base.bg, over.bg),
    bold: base.bold or over.bold,
    dim: base.dim or over.dim,
    italic: base.italic or over.italic,
    underline: base.underline or over.underline,
    reverse: base.reverse or over.reverse,
    attrs: base.attrs + over.attrs.select { |attr| not base.attrs.include?(attr) },
  )
end

## The attributes of a style: those of its fields, then `attrs`.
def attrs_of(style: Style) -> List[Attr]
  flags = [
    Flag(on: style.bold, attr: Attr.Bold),
    Flag(on: style.dim, attr: Attr.Dim),
    Flag(on: style.italic, attr: Attr.Italic),
    Flag(on: style.underline, attr: Attr.Underline),
    Flag(on: style.reverse, attr: Attr.Reverse),
  ]

  flags.select { |flag| flag.on }.map { |flag| flag.attr } + style.attrs
end

private

struct Flag
  on: Bool
  attr: Attr
end

def on_top(base: Color, over: Color) -> Color
  return base if over == Color.Default

  over
end
