## Opens the terminal while it is open (that open must fail and change nothing), then once more after the close.
## Prints LC_CTYPE before, inside and after, so the test sees it put back.

import TUI from "../../tui"

def main() -> Void
  before = tui_ctype()
  first = TUI.Raw.open(&nested)
  after = tui_ctype()
  again = TUI.Raw.open(&draw)
  puts("before #{before}")
  puts("first #{first}")
  puts("after #{after}")
  puts("again #{again}")
end

def nested(screen: TUI.Raw.Screen) -> Result[String]
  inner = TUI.Raw.open(&draw)
  try TUI.Raw.write(screen, 0, 0, "outer")
  try TUI.Raw.present(screen)
  ok("#{inner} inside #{tui_ctype()}")
end

def draw(screen: TUI.Raw.Screen) -> Result[String]
  try TUI.Raw.write(screen, 0, 0, "┌ again")
  try TUI.Raw.present(screen)
  ok("drawn")
end

# A test helper of native/tui.c.
extern "termbox2"
  def tui_ctype() -> C.String
end
