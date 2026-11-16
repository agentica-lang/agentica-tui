## The Elm loop: a model, messages, and effects as values. `update` and `view` are pure; `program` alone draws,
## reads the terminal (a backend), keeps time and runs the commands.

import Bd from "backend"
import Ev from "event"
import Gr from "grid"
import St from "style"
import Tb from "termbox"
import View from "view"

## An effect for `program` to run.
enum Cmd[Msg]
  ## Calls the function in a task of its own and gives the message it returns to `update`.
  Run(Fn[Msg])
  ## Ends the loop.
  Quit
end

## What `program` listens to while `subscriptions` gives it.
enum Sub[Msg]
  ## The message every so many milliseconds (10 or more; a shorter period counts as 10).
  Tick(Int, Msg)
  ## Each terminal event (keys, mouse, paste, resize) as a message.
  Events(Fn[Ev.Event, Msg])
end

## What `update` gives: the next model and the commands to run.
struct Step[M, Msg]
  model: M
  cmds: List[Cmd[Msg]] = []
end

## A program: the first model, how a message changes it, what it shows and what it listens to, the commands to
## run at the start, where the terminal cursor shows (no `cursor`, or one that gives none, hides it), and the
## terminal modes: how Escape is read, whether mouse events come, and how colors are sent.
struct App[M, Msg]
  model: M
  update: Fn[M, Msg, Step[M, Msg]]
  view: Fn[M, View.Node]
  subscriptions: Fn[M, List[Sub[Msg]]]
  cmds: List[Cmd[Msg]] = []
  cursor: Optional[Fn[M, Optional[Bd.Cursor]]] = none
  input: Ev.InputMode = Ev.InputMode.Esc
  mouse: Bool = false
  output: St.OutputMode = St.OutputMode.Normal
end

## Opens the terminal, runs `app` on it with `program` and closes it. Gives the last model, or the error once the
## terminal is restored.
def run[M, Msg](app: App[M, Msg]) -> Result[M] = Tb.open(->(screen) { program(Tb.backend(screen), app) })

## Runs `app` on a terminal backend until a command is `Cmd.Quit`, and gives the last model. After the messages that
## came together it draws `view(model)`. Gives an error when the terminal fails or `update`, `view`,
## `subscriptions` or a `Cmd.Run` function stops with a runtime error. A key typed after the quit may be lost. The
## terminal gets back the modes it had before.
def program[M, Msg](backend: Bd.Backend, app: App[M, Msg]) -> Result[M]
  restore = try backend.set_modes.call(Bd.Modes(input: app.input, mouse: app.mouse, output: app.output))
  inbox: Channel[Input[Msg]] = Channel.new(INBOX)
  stop: Channel[Bool] = Channel.new(1)
  reader = Task.spawn do read_events(backend, inbox, stop) end
  # The loop runs in a task of its own so that a crash in the app's functions comes back as an error and the
  # reader still stops.
  result = Task.await(Task.spawn do loop(backend, app, inbox) end)
  # Not a cancel: a cancelled task's wait may still run in termbox2 after the await, take a key from the caller and
  # hold the screen open.
  stop.close
  Task.await(reader)
  restored = restore.call()
  return result if not result.ok?

  try restored
  result
end

private

# Messages that wait for `update` before senders wait.
INBOX = 1024
SEND_MS = 60_000
# How long the reader waits for an event before it checks that the loop still runs.
READ_MS = 50
# The shortest tick period.
MIN_TICK_MS = 10
# How long to wait for input with no tick to keep.
IDLE_MS = 60_000

enum Input[Msg]
  Event(Ev.Event)
  App(Msg)
  Failed(String)
end

def loop[M, Msg](backend: Bd.Backend, app: App[M, Msg], inbox: Channel[Input[Msg]]) -> Result[M]
  step = Step(model: app.model, cmds: app.cmds)
  shown: Optional[Gr.Grid] = none
  # When each tick period is due next, by period.
  dues: Map[Int, Int] = {}
  while true
    return ok(step.model) if step.cmds.any?(&quit?)

    start(step.cmds, inbox)
    drawn = try Bd.render(backend, app.view.call(step.model), shown, cursor_of(app, step.model))
    shown = some(drawn)
    subs = app.subscriptions.call(step.model)
    dues = scheduled(subs, dues, Time.monotonic_ms())
    inputs = pending(inbox, dues, Time.monotonic_ms())
    for input in inputs
      case input
        Input.Failed(message) -> return error(message)
        Input.Event(Ev.Event.Resize(_, _)) -> shown = none
        _ -> next
      end
    end

    # The due ticks go with the inputs, and only they move on: a tick is never skipped while input comes.
    now = Time.monotonic_ms()
    msgs = inputs.flat_map { |input| messages(input, subs) } + subs.flat_map { |sub| tick_message(sub, dues, now) }
    step = updated(app.update, step.model, msgs)
    dues = advanced(dues, now)
  end

  ok(step.model)
end

def cursor_of[M, Msg](app: App[M, Msg], model: M) -> Optional[Optional[Bd.Cursor]]
  app.cursor.map { |place| place.call(model) }
end

def start[Msg](cmds: List[Cmd[Msg]], inbox: Channel[Input[Msg]]) -> Void
  for cmd in cmds
    case cmd
      Cmd.Run(work) -> Task.spawn do run_work(work, inbox) end
      Cmd.Quit -> next
    end
  end
end

# The work runs in a task of its own so that a crash comes back as an error, not a crash of the loop.
def run_work[Msg](work: Fn[Msg], inbox: Channel[Input[Msg]]) -> Void
  input = case Task.await(Task.spawn do ok(work.call()) end)
    ok(msg) -> Input.App(msg)
    error(e) -> Input.Failed(e.message)
  end

  _ = inbox.send(input, SEND_MS)
end

def read_events[Msg](backend: Bd.Backend, inbox: Channel[Input[Msg]], stop: Channel[Bool]) -> Void
  while not stop.closed?
    case backend.next_event.call(READ_MS)
      ok(found) ->
        case found
          some(event) -> _ = inbox.send(Input.Event(event), SEND_MS)
          none -> next
        end

      error(e) ->
        _ = inbox.send(Input.Failed(e.message), SEND_MS)
        return
    end
  end
end

# The inputs that wait, or the first that comes before the next tick is due (none when it comes first).
def pending[Msg](inbox: Channel[Input[Msg]], dues: Map[Int, Int], now: Int) -> List[Input[Msg]]
  wait = IDLE_MS
  for due in dues.values
    wait = [wait, due - now].min.unwrap!
  end

  inputs: List[Input[Msg]] = []
  got = inbox.recv([wait, 0].max.unwrap!)
  while got.ok? and inputs.size < INBOX
    inputs = inputs.push(got.unwrap!)
    got = inbox.recv(0)
  end

  inputs
end

def messages[Msg](input: Input[Msg], subs: List[Sub[Msg]]) -> List[Msg]
  case input
    Input.App(msg) -> [msg]
    Input.Event(event) -> subs.flat_map { |sub| event_message(sub, event) }
    Input.Failed(_) -> []
  end
end

def event_message[Msg](sub: Sub[Msg], event: Ev.Event) -> List[Msg]
  case sub
    Sub.Events(message) -> [message.call(event)]
    Sub.Tick(_, _) -> []
  end
end

def tick_message[Msg](sub: Sub[Msg], dues: Map[Int, Int], now: Int) -> List[Msg]
  case sub
    Sub.Tick(ms, msg) ->
      return [msg] if due?(dues, period(ms), now)

      []
    Sub.Events(_) -> []
  end
end

def updated[M, Msg](update: Fn[M, Msg, Step[M, Msg]], model: M, msgs: List[Msg]) -> Step[M, Msg]
  step: Step[M, Msg] = Step(model: model)
  for msg in msgs
    # The messages after a quit never reach `update`.
    break if step.cmds.any?(&quit?)

    next_step = update.call(step.model, msg)
    step = Step(model: next_step.model, cmds: step.cmds + next_step.cmds)
  end

  step
end

# The due times of the tick periods of `subs`: a period kept keeps its time, a new one is due one period from now.
def scheduled[Msg](subs: List[Sub[Msg]], dues: Map[Int, Int], now: Int) -> Map[Int, Int]
  out: Map[Int, Int] = {}
  for sub in subs
    case sub
      Sub.Tick(ms, _) -> out = out.put(period(ms), dues.get(period(ms)).unwrap_or(now + period(ms)))
      Sub.Events(_) -> next
    end
  end

  out
end

# The periods that were due move one period on, or one period from now when the loop fell behind.
def advanced(dues: Map[Int, Int], now: Int) -> Map[Int, Int]
  out: Map[Int, Int] = {}
  for ms in dues.keys
    due = dues.get(ms).unwrap!
    if due <= now
      due = [due + ms, now + 1].max.unwrap!
    end

    out = out.put(ms, due)
  end

  out
end

def quit?[Msg](cmd: Cmd[Msg]) -> Bool
  case cmd
    Cmd.Quit -> true
    Cmd.Run(_) -> false
  end
end

def due?(dues: Map[Int, Int], ms: Int, now: Int) -> Bool = dues.get(ms).map { |due| due <= now }.unwrap_or(false)

def period(ms: Int) -> Int = [ms, MIN_TICK_MS].max.unwrap!
