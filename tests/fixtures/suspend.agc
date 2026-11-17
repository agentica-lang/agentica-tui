## The program tests/test_pty.py drives for `Cmd.Suspend`: e gives the terminal to a shell that reads a line and
## writes it to the file that TUI_CHILD_FILE names; the screen shows the line back. q quits.

import TUI from "../../tui"

WAIT_MS = 30_000

enum Msg
  Key(TUI.Event)
  Back(String)
end

def main() -> Void
  app = TUI.App(
    model: "ready",
    update: &update,
    view: ->(text: String) { TUI.text(text) },
    subscriptions: ->(_text: String) { [TUI.Sub.Events(->(event) { Msg.Key(event) })] },
    mouse: true,
  )

  case TUI.run(app)
    ok(text) -> puts("last #{text}")
    error(e) -> fail(e.message)
  end
end

def update(text: String, msg: Msg) -> TUI.Step[String, Msg]
  case msg
    Msg.Key(TUI.Event.Char("e", _)) -> TUI.Step(model: text, cmds: [TUI.Cmd.Suspend(&child)])
    Msg.Key(TUI.Event.Char("q", _)) -> TUI.Step(model: text, cmds: [TUI.Cmd.Quit])
    Msg.Key(_) -> TUI.Step(model: text)
    Msg.Back(line) -> TUI.Step(model: "back #{line}")
  end
end

def child() -> Msg
  path = System.env("TUI_CHILD_FILE").unwrap_or("")
  script = "printf 'child> '; read line; printf %s \"$line\" > \"$1\""
  case Process.spawn_group("sh", ["-c", script, "sh", path])
    ok(running) ->
      _ = Process.wait(running, WAIT_MS)
      Msg.Back(File.read_text(path).unwrap_or("nothing"))
    error(e) -> Msg.Back("error #{e.message}")
  end
end

def fail(message: String) -> Void
  IO.warn(message)
  System.exit(1)
end
