## A program that ends with System.exit while the terminal is open: the end of the run closes the screen, which
## restores the terminal.

import TUI from "../../tui"

def main() -> Void
  case TUI.open(&leave)
    ok(_) -> puts("not reached")
    error(message) -> IO.warn(message)
  end
end

def leave(screen: TUI.Screen) -> Result[Void]
  try TUI.write(screen, 0, 0, "drawn")
  try TUI.present(screen)
  System.exit(3)
  return ok()
end
