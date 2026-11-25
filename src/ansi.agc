## The bytes a terminal takes: the cells that changed as cursor moves, colors and text, and the switches of its modes
## (alternate screen, cursor, paste, mouse). Pure.

import Bd from "backend"
import Gr from "grid"
import St from "style"
import View from "view"
import Width from "width"

ESC = String.from_code(27)

## Enters the alternate screen, hides the cursor and turns bracketed paste on.
ENTER = "#{ESC}[?1049h#{ESC}[?25l#{ESC}[?2004h"

## Gives the screen back: default colors, the cursor shown, paste and the main screen. Mouse reports are turned off
## with `mouse(false)` first.
LEAVE = "#{ESC}[0m#{ESC}[?25h#{ESC}[?2004l#{ESC}[?1049l"

## A request for the status of the terminal, which answers `ESC [ 0 n`: the answer ends a read of standard input that
## waits, and the reader stops after it (the four bytes as a number, `STATUS_REPLY_CODE`).
STATUS_REQUEST = "#{ESC}[5n"

STATUS_REPLY_CODE = 0x1b5b306e

## The switch of mouse reports: buttons, motion with a button down, and the SGR form of the reports.
def mouse(on: Bool) -> String
  return "#{ESC}[?1000h#{ESC}[?1002h#{ESC}[?1006h" if on

  "#{ESC}[?1006l#{ESC}[?1002l#{ESC}[?1000l"
end

## The bytes that turn what the terminal shows (`old`) into `new`: only the cells that differ. With no `old`, or one of
## another size, the screen is cleared first. The text of a cell with a control character shows U+FFFD.
def update(old: Optional[Gr.Grid], new: Gr.Grid, output: St.OutputMode) -> String
  case old
    some(shown) if shown.width == new.width and shown.height == new.height -> cells(Gr.diff(shown, new), output)
    _ -> "#{ESC}[0m#{ESC}[H#{ESC}[2J" + cells(Gr.diff(Gr.blank(new.width, new.height), new), output)
  end
end

## The bytes that move the cursor from where the terminal has it (`old`, none: hidden) to `new`. Drawing moves it, so a
## shown cursor is placed every time.
def place(old: Optional[Bd.Cursor], new: Optional[Bd.Cursor]) -> String
  case new
    some(at) ->
      shown = ""
      if old.none?
        shown = "#{ESC}[?25h"
      end

      move(at.x, at.y) + shown
    none ->
      return "" if old.none?

      "#{ESC}[?25l"
  end
end

## An error for a color outside its range, which a terminal would read as another color.
def check(style: St.Style) -> Result[Void]
  try check_color(style.fg)
  check_color(style.bg)
end

private

MAX_INDEX = 255
# The levels of one channel of the palette's color cube, the first index of the cube and of the gray ramp, and the
# ramp: 24 grays from 8, ten apart.
CUBE = [0, 95, 135, 175, 215, 255]
CUBE_START = 16
GRAY_START = 232
FIRST_GRAY = 8
GRAY_STEP = 10
LAST_GRAY_STEP = 23
MAX_CHANNEL = 255
REPLACEMENT = String.from_code(0xfffd)
FIRST_PRINTABLE = 0x20
DELETE = 0x7f
LAST_C1 = 0x9f
FOREGROUND = Ground(normal: 30, bright: 90)
BACKGROUND = Ground(normal: 40, bright: 100)

# The first SGR parameter of the eight named colors, and of their bright form.
struct Ground
  normal: Int
  bright: Int
end

def check_color(color: St.Color) -> Result[Void]
  case color
    St.Color.Index(index) if index < 0 or index > MAX_INDEX ->
      error("tui: color index out of range 0..#{MAX_INDEX}: #{index}")
    St.Color.Rgb(red, green, blue) ->
      bad = [red, green, blue].select { |channel| channel < 0 or channel > MAX_CHANNEL }
      return error("tui: color channel out of range 0..#{MAX_CHANNEL}: #{bad[0]}") if bad.size > 0

      ok()
    _ -> ok()
  end
end

# The changed cells in order: a move when the cursor is not already there, the colors when the style changes, then the
# text. A covered cell ("") is written by the wide character before it.
def cells(changed: List[View.Cell], output: St.OutputMode) -> String
  out: List[String] = []
  x = -1
  y = -1
  pen: Optional[St.Style] = none
  for cell in changed
    next if cell.char == ""

    if cell.y != y or cell.x != x
      out = out.push(move(cell.x, cell.y))
    end

    if pen != some(cell.style)
      out = out.push(sgr(cell.style, output))
      pen = some(cell.style)
    end

    out = out.push(printable(cell.char))
    # A terminal may count a wide character, or a character with marks on it, in another number of columns than the
    # width table: the next cell is placed by an absolute move.
    x = cell.x + Width.cell(cell.char)
    if cell.char.length > 1 or Width.cell(cell.char) != 1
      x = -1
    end

    y = cell.y
  end

  if pen.some? and pen != some(St.Style())
    out = out.push("#{ESC}[0m")
  end

  out.join("")
end

def move(x: Int, y: Int) -> String = "#{ESC}[#{y + 1};#{x + 1}H"

def printable(text: String) -> String
  code = text.at(0).code
  return REPLACEMENT if code < FIRST_PRINTABLE or (code >= DELETE and code <= LAST_C1)

  text
end

# All of a style: a reset, then its attributes and colors.
def sgr(style: St.Style, output: St.OutputMode) -> String
  attrs = St.attrs_of(style)
  bright = attrs.include?(St.Attr.Bright)
  params = ["0"] + attrs.select { |attr| attr != St.Attr.Bright }.map { |attr| attr_code(attr) }
  params = params + color_params(style.fg, output, FOREGROUND, bright)
  params = params + color_params(style.bg, output, BACKGROUND, bright)
  "#{ESC}[#{params.join(";")}m"
end

def attr_code(attr: St.Attr) -> String
  case attr
    St.Attr.Bold -> "1"
    St.Attr.Dim -> "2"
    St.Attr.Italic -> "3"
    St.Attr.Underline -> "4"
    St.Attr.Blink -> "5"
    St.Attr.Reverse -> "7"
    St.Attr.Invisible -> "8"
    St.Attr.Strikeout -> "9"
    St.Attr.DoubleUnderline -> "21"
    St.Attr.Overline -> "53"
    St.Attr.Bright -> ""
  end
end

# A color the output mode cannot show (a palette color in `Normal`, true color below `Truecolor`) is left to the
# terminal's own. `Bright` shows the eight named colors in their bright form, for the foreground and the background.
def color_params(color: St.Color, output: St.OutputMode, ground: Ground, bright: Bool) -> List[String]
  case color
    St.Color.Default -> []
    St.Color.Index(index) -> extended(ground, ["5", "#{index}"], output != St.OutputMode.Normal)
    St.Color.Rgb(red, green, blue) -> rgb_params(ground, output, red, green, blue)
    St.Color.Black -> named(ground, 0, bright)
    St.Color.Red -> named(ground, 1, bright)
    St.Color.Green -> named(ground, 2, bright)
    St.Color.Yellow -> named(ground, 3, bright)
    St.Color.Blue -> named(ground, 4, bright)
    St.Color.Magenta -> named(ground, 5, bright)
    St.Color.Cyan -> named(ground, 6, bright)
    St.Color.White -> named(ground, 7, bright)
  end
end

def rgb_params(ground: Ground, output: St.OutputMode, red: Int, green: Int, blue: Int) -> List[String]
  case output
    St.OutputMode.Truecolor -> extended(ground, ["2", "#{red}", "#{green}", "#{blue}"], true)
    St.OutputMode.Colors256 -> extended(ground, ["5", "#{nearest_index(red, green, blue)}"], true)
    St.OutputMode.Normal -> []
  end
end

# The color of the 256-color palette nearest to a true color: the 6x6x6 cube (16 to 231) or the gray ramp (232 to 255),
# whichever is closer.
def nearest_index(red: Int, green: Int, blue: Int) -> Int
  cube_red = level(red)
  cube_green = level(green)
  cube_blue = level(blue)
  cube = distance([red, green, blue], [CUBE[cube_red], CUBE[cube_green], CUBE[cube_blue]])
  step = [
    [(red + green + blue) / 3 - FIRST_GRAY + GRAY_STEP / 2, 0].max.unwrap! / GRAY_STEP,
    LAST_GRAY_STEP,
  ].min.unwrap!

  shade = FIRST_GRAY + step * GRAY_STEP
  gray = distance([red, green, blue], [shade, shade, shade])
  return GRAY_START + step if gray < cube

  CUBE_START + 36 * cube_red + 6 * cube_green + cube_blue
end

# The index in CUBE of the level nearest to a channel.
def level(value: Int) -> Int
  return 0 if value < 48
  return 1 if value < 115

  [(value - 35) / 40, 5].min.unwrap!
end

def distance(a: List[Int], b: List[Int]) -> Int
  (0...3).reduce(0) do |total, i| total + (a[i] - b[i]) * (a[i] - b[i]) end
end

# The first parameter of a palette or true color is 38 for the foreground and 48 for the background.
def extended(ground: Ground, params: List[String], shown: Bool) -> List[String]
  return [] if not shown

  ["#{ground.normal + 8}"] + params
end

def named(ground: Ground, index: Int, bright: Bool) -> List[String]
  return ["#{ground.bright + index}"] if bright

  ["#{ground.normal + index}"]
end
