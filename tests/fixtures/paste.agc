## The program tests/test_pty.py drives for bracketed paste: it shows the size of each paste and each other event on
## the top line, and prints them on stdout after the close. q quits.

import TUI from "../../tui"

def main() -> Void
  case TUI.open(&record)
    ok(lines) -> lines.each do |line| puts(line) end
    error(e) -> IO.warn(e.message)
  end
end

def record(screen: TUI.Screen) -> Result[List[String]]
  lines: List[String] = []
  try show(screen, "ready")
  while true
    event = try TUI.poll_event(screen)
    line = describe(event)
    case event
      TUI.Event.Char("q", _) -> break
      _ -> lines = lines.push(line)
    end

    try show(screen, line)
  end

  ok(lines)
end

def describe(event: TUI.Event) -> String
  case event
    TUI.Event.Paste(text) -> "paste #{text.length} #{text.slice(0, [text.length, 8].min.unwrap!).inspect}"
    _ -> "#{event}"
  end
end

def show(screen: TUI.Screen, text: String) -> Result[Void]
  try TUI.clear(screen)
  try TUI.write(screen, 0, 0, text)
  TUI.present(screen)
end
