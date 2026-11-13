## Colors, text attributes and output modes, and the termbox2 cell attribute value they make.
##
## The library is built with 64-bit attributes (`TB_LIB_OPTS` of termbox2.h): a color in the low 32 bits, the
## attributes above it.

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

## The colors and attributes of a cell or a text.
struct Style
  fg: Color = Color.Default
  bg: Color = Color.Default
  attrs: List[Attr] = []
end

## The termbox2 foreground value of a style: its color and its attributes.
def fg_value(style: Style) -> Result[Int]
  color = try color_value(style.fg)
  ok(style.attrs.reduce(color) do |bits, attr| bits.bit_or(attr_value(attr)) end)
end

## The termbox2 background value of a style: its color.
def bg_value(style: Style) -> Result[Int] = color_value(style.bg)

## The termbox2 color value, or an error for an index or channel out of range.
def color_value(color: Color) -> Result[Int]
  # The named colors are the values of output mode Normal, termbox2.h `TB_BLACK` to `TB_WHITE`.
  case color
    Color.Default -> ok(0)
    Color.Black -> ok(1)
    Color.Red -> ok(2)
    Color.Green -> ok(3)
    Color.Yellow -> ok(4)
    Color.Blue -> ok(5)
    Color.Magenta -> ok(6)
    Color.Cyan -> ok(7)
    Color.White -> ok(8)
    Color.Index(index) -> index_value(index)
    Color.Rgb(red, green, blue) -> rgb_value(red, green, blue)
  end
end

## The termbox2 value of an output mode (`TB_OUTPUT_*`).
def output_mode_value(mode: OutputMode) -> Int
  case mode
    OutputMode.Normal -> 1
    OutputMode.Colors256 -> 2
    OutputMode.Truecolor -> 5
  end
end

private

# Black in modes Colors256 and Truecolor, where the value 0 means the default color (`TB_HI_BLACK`).
HI_BLACK = 0x2000_0000
MAX_INDEX = 255
MAX_CHANNEL = 255

def index_value(index: Int) -> Result[Int]
  return error("tui: color index out of range 0..#{MAX_INDEX}: #{index}") if index < 0 or index > MAX_INDEX

  return ok(HI_BLACK) if index == 0

  ok(index)
end

def rgb_value(red: Int, green: Int, blue: Int) -> Result[Int]
  bad = [red, green, blue].select do |channel| channel < 0 or channel > MAX_CHANNEL end
  return error("tui: color channel out of range 0..#{MAX_CHANNEL}: #{bad[0]}") if bad.size > 0

  value = red.shift_left(16).bit_or(green.shift_left(8)).bit_or(blue)
  return ok(HI_BLACK) if value == 0

  ok(value)
end

# termbox2.h, `TB_OPT_ATTR_W == 64`.
def attr_value(attr: Attr) -> Int
  case attr
    Attr.Bold -> 0x0100_0000
    Attr.Underline -> 0x0200_0000
    Attr.Reverse -> 0x0400_0000
    Attr.Italic -> 0x0800_0000
    Attr.Blink -> 0x1000_0000
    Attr.Bright -> 0x4000_0000
    Attr.Dim -> 0x8000_0000
    Attr.Strikeout -> 0x1_0000_0000
    Attr.DoubleUnderline -> 0x2_0000_0000
    Attr.Overline -> 0x4_0000_0000
    Attr.Invisible -> 0x8_0000_0000
  end
end
