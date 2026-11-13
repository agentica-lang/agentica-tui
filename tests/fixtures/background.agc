## One task waits for an event while the block draws in 256 colors and true color and places the cursor, then the
## block ends with the wait still running: the close must end that wait with an error.

import TUI from "../../tui"

# Time for the waiting task to be inside its wait before the drawing starts.
SETTLE_MS = 200

def main() -> Void
  case TUI.open(&draw)
    ok(waiter) -> puts("waiter #{Task.await(waiter)}")
    error(e) -> puts("open #{e.message}")
  end
end

def draw(screen: TUI.Screen) -> Result[Task[Result[TUI.Event]]]
  waiter = Task.spawn(&wait, screen)
  Task.sleep(SETTLE_MS)
  try TUI.set_output_mode(screen, TUI.OutputMode.Colors256)
  try TUI.write(screen, 0, 0, "palette", TUI.Style(fg: TUI.Color.Index(196)))
  try TUI.present(screen)
  try TUI.set_output_mode(screen, TUI.OutputMode.Truecolor)
  try TUI.write(screen, 0, 1, "true color", TUI.Style(fg: TUI.Color.Rgb(255, 128, 0)))
  try TUI.set_cursor(screen, 5, 2)
  try TUI.present(screen)
  ok(waiter)
end

def wait(screen: TUI.Screen) -> Result[TUI.Event] = TUI.poll_event(screen)
