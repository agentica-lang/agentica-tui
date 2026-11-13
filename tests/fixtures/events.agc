## The program tests/test_pty.py drives: it draws a ready screen, then shows each event it reads and, once the
## terminal is closed, prints them on stdout, one per line. q quits.

import TUI from "../../tui"

def main() -> Void
  case TUI.open(&record)
    ok(lines) -> lines.each do |line| puts(line) end
    error(e) -> fail(e.message)
  end
end

def record(screen: TUI.Screen) -> Result[List[String]]
  try TUI.set_input_mode(screen, TUI.InputMode.Esc, true)
  quiet = try TUI.peek_event(screen, 50)
  lines = ["peek #{quiet}"]
  try show(screen, "ready #{TUI.width(screen)}x#{TUI.height(screen)}")
  while true
    event = try TUI.poll_event(screen)
    case event
      TUI.Event.Char("q", _) -> break
      _ -> lines = lines.push("#{event}")
    end

    try show(screen, "#{event}")
  end

  ok(lines)
end

def show(screen: TUI.Screen, text: String) -> Result[Void]
  try TUI.clear(screen)
  try TUI.set_cell(screen, 2, 1, "#", TUI.Style(fg: TUI.Color.Red, attrs: [TUI.Attr.Bold]))
  try TUI.write(screen, 0, 0, text)
  TUI.present(screen)
end

def fail(message: String) -> Void
  IO.warn(message)
  System.exit(1)
end
