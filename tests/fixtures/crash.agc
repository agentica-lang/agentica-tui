## A program whose block stops with a runtime error while the terminal is open: `TUI.open` restores the terminal
## and gives the crash as an error.

import TUI from "../../tui"

def main() -> Void
  case TUI.open(&crash)
    ok(_) -> puts("not reached")
    error(e) -> fail(e.message)
  end
end

def crash(screen: TUI.Screen) -> Result[Void]
  try TUI.write(screen, 0, 0, "drawn")
  try TUI.present(screen)
  # A list index past the end halts the program (RUNTIME-INDEX-OUT-OF-RANGE).
  puts(System.args()[5])
  ok()
end

def fail(message: String) -> Void
  IO.warn(message)
  System.exit(1)
end
