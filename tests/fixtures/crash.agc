## A program whose block stops with a runtime error while the terminal is open: `TUI.Raw.open` restores the terminal
## and gives the crash as an error.

import TUI from "../../tui"

def main() -> Void
  case TUI.Raw.open(&crash)
    ok(_) -> puts("not reached")
    error(e) -> fail(e.message)
  end
end

def crash(screen: TUI.Raw.Screen) -> Result[Void]
  try TUI.Raw.write(screen, 0, 0, "drawn")
  try TUI.Raw.present(screen)
  # A list index past the end halts the program (RUNTIME-INDEX-OUT-OF-RANGE).
  puts(System.args()[5])
  ok()
end

def fail(message: String) -> Void
  IO.warn(message)
  System.exit(1)
end
