## The program tests/test_pty.py drives for combining marks: it renders "cafe", and after a key "cafe" with U+0301
## on the e, from the grid it drew. Then it tries a cell of two characters, and prints whether that failed.

import TUI from "../../tui"

# U+0301 COMBINING ACUTE ACCENT, alone.
ACUTE = "́"

def main() -> Void
  case TUI.Raw.open(&draw)
    ok(line) -> puts(line)
    error(e) -> IO.warn(e.message)
  end
end

def draw(screen: TUI.Raw.Screen) -> Result[String]
  first = try TUI.Raw.render(screen, TUI.line([TUI.span("cafe")]))
  _ = try TUI.Raw.poll_event(screen)
  _ = try TUI.Raw.render(screen, TUI.line([TUI.span("cafe#{ACUTE}!")]), some(first))
  two = TUI.Raw.set_cell(screen, 0, 1, "ab")
  _ = try TUI.Raw.poll_event(screen)
  ok("two characters: #{two.ok?}")
end
