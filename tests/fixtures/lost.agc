## A task that draws is cancelled while it holds the screen (blocked in a write the terminal does not read yet): the
## close must still restore the terminal, and gives an error.

import TUI from "../../tui"

SETTLE_MS = 1500

def main() -> Void
  case TUI.Raw.open(&body)
    ok(_) -> puts("closed ok")
    error(e) -> puts("closed #{e.message}")
  end
end

def draw(screen: TUI.Raw.Screen) -> Result[Void]
  i = 0
  while true
    i = i + 1
    # A whole screen of new text each frame: the pty fills in a few frames, on a slow machine as well.
    for row in 0...20
      try TUI.Raw.write(screen, 0, row, "frame #{i} row #{row} " + List.repeat("#{i}", 50).join(""))
    end

    try TUI.Raw.present(screen)
  end

  ok()
end

def body(screen: TUI.Raw.Screen) -> Result[Void]
  drawer = Task.spawn(&draw, screen)
  Task.sleep(SETTLE_MS)
  Task.cancel(drawer)
  ok()
end
