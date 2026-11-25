## Opens the terminal while it is open (that open must fail and change nothing), then once more after the close.

import TUI from "../../tui"

def main() -> Void
  first = TUI.Raw.open(&nested)
  again = TUI.Raw.open(&draw)
  puts("first #{first}")
  puts("again #{again}")
end

def nested(screen: TUI.Raw.Screen) -> Result[String]
  inner = TUI.Raw.open(&draw)
  try TUI.Raw.write(screen, 0, 0, "outer")
  try TUI.Raw.present(screen)
  ok("#{inner}")
end

def draw(screen: TUI.Raw.Screen) -> Result[String]
  try TUI.Raw.write(screen, 0, 0, "┌ again")
  try TUI.Raw.present(screen)
  ok("drawn")
end
