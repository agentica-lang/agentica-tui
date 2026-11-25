## Keeps the screen past the block that owns it: a draw after the close is an error.

import TUI from "../../tui"

def keep(screen: TUI.Raw.Screen) -> Result[TUI.Raw.Screen] = ok(screen)

def main() -> Void
  screen = TUI.Raw.open(&keep).unwrap!
  puts(TUI.Raw.write(screen, 0, 0, "late"))
  puts(TUI.Raw.poll_event(screen))
end
