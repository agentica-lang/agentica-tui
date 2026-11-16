## The program tests/test_pty.py drives for combining marks: it renders "cafe" over a warning sign with U+FE0F, and
## after a key "cafe" with U+0301 on the e, from the grid it drew. Then it tries a cell of two characters, and
## prints whether that failed.

import TUI from "../../tui"

# U+0301 COMBINING ACUTE ACCENT, alone.
ACUTE = "́"
# U+26A0 WARNING SIGN and U+FE0F VARIATION SELECTOR-16, then "xyz".
WARNING = "⚠️xyz"

def main() -> Void
  case TUI.Raw.open(&draw)
    ok(line) -> puts(line)
    error(e) -> IO.warn(e.message)
  end
end

def draw(screen: TUI.Raw.Screen) -> Result[String]
  first = try TUI.Raw.render(screen, TUI.col([TUI.line([TUI.span("cafe")]), TUI.line([TUI.span(WARNING)])]))
  _ = try TUI.Raw.poll_event(screen)
  _ = try TUI.Raw.render(
    screen,
    TUI.col([TUI.line([TUI.span("cafe#{ACUTE}!")]), TUI.line([TUI.span(WARNING)])]),
    some(first),
  )

  two = TUI.Raw.set_cell(screen, 0, 1, "ab")
  _ = try TUI.Raw.poll_event(screen)
  ok("two characters: #{two.ok?}")
end
