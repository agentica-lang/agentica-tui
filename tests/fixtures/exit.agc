## A program that ends with System.exit while the terminal is open: the end of the run closes the screen, which
## restores the terminal.

import TUI from "../../tui"

def main() -> Void
  case TUI.Raw.open(&leave)
    ok(_) -> puts("not reached")
    error(e) -> IO.warn(e.message)
  end
end

def leave(screen: TUI.Raw.Screen) -> Result[Void]
  try TUI.Raw.write(screen, 0, 0, "drawn")
  try TUI.Raw.present(screen)
  System.exit(3)
  ok()
end
