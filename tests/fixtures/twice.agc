## Opens the terminal while it is open (that open must fail and change nothing), then once more after the close.
## Prints LC_CTYPE before, inside and after, so the test sees it put back.

import TUI from "../../tui"

def main() -> Void
  before = tui_ctype()
  first = TUI.open(&nested)
  after = tui_ctype()
  again = TUI.open(&draw)
  puts("before #{before}")
  puts("first #{first}")
  puts("after #{after}")
  puts("again #{again}")
end

def nested(screen: TUI.Screen) -> Result[String]
  inner = TUI.open(&draw)
  try TUI.write(screen, 0, 0, "outer")
  try TUI.present(screen)
  ok("#{inner} inside #{tui_ctype()}")
end

def draw(screen: TUI.Screen) -> Result[String]
  try TUI.write(screen, 0, 0, "┌ again")
  try TUI.present(screen)
  ok("drawn")
end

# A test helper of native/tui.c.
extern "termbox2"
  def tui_ctype() -> C.String
end
