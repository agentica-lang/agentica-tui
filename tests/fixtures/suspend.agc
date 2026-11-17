## The program tests/test_pty.py drives for `Cmd.Suspend`, in Truecolor: e gives the terminal to a shell that runs
## `stty` with TUI_CHILD_STTY (when set), reads a line and writes it to the file that TUI_CHILD_FILE names; the screen
## shows the line back, and whether a Ctrl+C came meanwhile (waited for when TUI_CHILD_INT is set: the signal comes in
## a little after the key). A paste shows its text; q quits.

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
    view: ->(text: String) { TUI.text(text, TUI.Style(fg: TUI.Color.Rgb(10, 20, 30))) },
    subscriptions: ->(_text: String) { [TUI.Sub.Events(->(event) { Msg.Key(event) })] },
    mouse: true,
    output: TUI.OutputMode.Truecolor,
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
    Msg.Key(TUI.Event.Paste(pasted)) -> TUI.Step(model: "pasted #{pasted}")
    Msg.Key(_) -> TUI.Step(model: text)
    Msg.Back(line) -> TUI.Step(model: "back #{line}")
  end
end

# A Ctrl+C reaches this program, not the shell, which runs in a session of its own: the subscription keeps it.
def child() -> Msg
  interrupts = System.subscribe([System.Signal.Int]).unwrap!
  path = System.env("TUI_CHILD_FILE").unwrap_or("")
  script = "[ -n \"$2\" ] && stty \"$2\"; printf 'child> '; read line; printf %s \"$line\" > \"$1\""
  case Process.spawn_group("sh", ["-c", script, "sh", path, System.env("TUI_CHILD_STTY").unwrap_or("")])
    ok(running) ->
      _ = Process.wait(running, WAIT_MS)
      wait_ms = 0
      if System.env("TUI_CHILD_INT").ok?
        wait_ms = WAIT_MS
      end

      caught = interrupts.recv(wait_ms).ok?
      Msg.Back("#{File.read_text(path).unwrap_or("nothing")}, ctrl+c #{caught}")
    error(e) -> Msg.Back("error #{e.message}")
  end
end

def fail(message: String) -> Void
  IO.warn(message)
  System.exit(1)
end
