## A box that moves with the arrow keys or a mouse click; the top line shows the size of the terminal and the last
## event. q or Escape quits.
##
## Run it from the repository after `make native`: `agentica examples/box.agc`.

import TUI from "../tui"

BOX_WIDTH = 12
BOX_HEIGHT = 5
# The box never covers the status line.
TOP = 1

struct Demo
  x: Int
  y: Int
  last: String
end

def main() -> Void
  case TUI.open(&run)
    ok(_) -> puts("bye")
    error(e) -> IO.warn(e.message)
  end
end

def run(screen: TUI.Screen) -> Result[Void]
  try TUI.set_input_mode(screen, TUI.InputMode.Esc, true)
  demo = Demo(x: 2, y: 2, last: "none")
  while true
    try draw(screen, demo)
    event = try TUI.poll_event(screen)
    break if quit?(event)

    demo = place(screen, step(demo, event)).with(last: describe(event))
  end

  ok()
end

def draw(screen: TUI.Screen, demo: Demo) -> Result[Void]
  try TUI.clear(screen)
  width = TUI.width(screen)
  height = TUI.height(screen)
  status = "size #{width}x#{height}  last #{demo.last}  arrows move, q quits"
  try TUI.write(screen, 0, 0, status, TUI.Style(attrs: [TUI.Attr.Bold]))
  border = TUI.Style(fg: TUI.Color.Cyan)
  inner = List.repeat(" ", BOX_WIDTH - 2).join("")
  line = List.repeat("─", BOX_WIDTH - 2).join("")
  for row in 0...BOX_HEIGHT
    y = demo.y + row
    if y < height and demo.x < width
      text = box_row(row, inner, line)
      try TUI.write(screen, demo.x, y, text, border)
    end
  end

  TUI.present(screen)
end

def box_row(row: Int, inner: String, line: String) -> String
  if row == 0
    return "┌#{line}┐"
  elsif row == BOX_HEIGHT - 1
    return "└#{line}┘"
  end

  "│#{inner}│"
end

def quit?(event: TUI.Event) -> Bool
  case event
    TUI.Event.Char("q", _) -> true
    TUI.Event.Key(TUI.Key.Escape, _) -> true
    TUI.Event.Key(TUI.Key.Ctrl("c"), _) -> true
    _ -> false
  end
end

def step(demo: Demo, event: TUI.Event) -> Demo
  case event
    TUI.Event.Key(TUI.Key.Up, _) -> demo.with(y: demo.y - 1)
    TUI.Event.Key(TUI.Key.Down, _) -> demo.with(y: demo.y + 1)
    TUI.Event.Key(TUI.Key.Left, _) -> demo.with(x: demo.x - 1)
    TUI.Event.Key(TUI.Key.Right, _) -> demo.with(x: demo.x + 1)
    TUI.Event.Mouse(TUI.Mouse.Left, x, y, _) -> demo.with(x: x, y: y)
    _ -> demo
  end
end

# Keeps the box on the screen, below the status line, also after a resize.
def place(screen: TUI.Screen, demo: Demo) -> Demo
  x = within(demo.x, 0, TUI.width(screen) - BOX_WIDTH)
  y = within(demo.y, TOP, TUI.height(screen) - BOX_HEIGHT)
  demo.with(x: x, y: y)
end

def within(value: Int, low: Int, high: Int) -> Int
  if value < low or high < low
    return low
  elsif value > high
    return high
  end

  value
end

def describe(event: TUI.Event) -> String
  case event
    TUI.Event.Key(key, _) -> "key #{key}"
    TUI.Event.Char(char, _) -> "char #{char}"
    TUI.Event.Mouse(button, x, y, _) -> "mouse #{button} #{x},#{y}"
    TUI.Event.Resize(width, height) -> "resize #{width}x#{height}"
  end
end
