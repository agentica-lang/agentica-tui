## The Elm loop: a model, messages, and effects as values. `update` and `view` are pure; `program` alone draws,
## reads the terminal, keeps time and runs the commands.

import Ev from "event"
import Gr from "grid"
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
  ## The message every so many milliseconds (1 or more).
  Tick(Int, Msg)
  ## Each terminal event (keys, mouse, paste, resize) as a message.
  Events(Fn[Ev.Event, Msg])
end

## What `update` gives: the next model and the commands to run.
struct Step[M, Msg]
  model: M
  cmds: List[Cmd[Msg]] = []
end

## A program: the first model, how a message changes it, what it shows and what it listens to, and the commands
## to run at the start.
struct App[M, Msg]
  model: M
  update: Fn[M, Msg, Step[M, Msg]]
  view: Fn[M, View.Node]
  subscriptions: Fn[M, List[Sub[Msg]]]
  cmds: List[Cmd[Msg]] = []
end

## Runs `app` on the screen until a command is `Cmd.Quit`, and gives the last model. After each change it draws
## `view(model)`. Gives an error when the terminal fails or a `Cmd.Run` function stops with a runtime error.
def program[M, Msg](screen: Tb.Screen, app: App[M, Msg]) -> Result[M]
  inbox: Channel[Input[Msg]] = Channel.new(INBOX)
  stop: Channel[Bool] = Channel.new(1)
  reader = Task.spawn do read_events(screen, inbox, stop) end
  result = run(screen, app, inbox)
  # Not a cancel: a cancelled task's wait may still run in termbox2 after the await, take a key from the caller and
  # hold the screen open.
  stop.close
  Task.await(reader)
  result
end

private

# Messages that wait for `update` before senders wait.
INBOX = 1024
SEND_MS = 60_000
# How long the reader waits for an event before it checks that the loop still runs.
READ_MS = 50
# How long to wait for input with no tick to keep.
IDLE_MS = 60_000

enum Input[Msg]
  Event(Ev.Event)
  App(Msg)
  Failed(String)
  Due
end

def run[M, Msg](screen: Tb.Screen, app: App[M, Msg], inbox: Channel[Input[Msg]]) -> Result[M]
  step = Step(model: app.model, cmds: app.cmds)
  shown: Optional[Gr.Grid] = none
  # When each tick period is due next, by period.
  dues: Map[Int, Int] = {}
  while true
    return ok(step.model) if step.cmds.any?(&quit?)

    start(step.cmds, inbox)
    drawn = try Tb.render(screen, app.view.call(step.model), shown)
    shown = some(drawn)
    subs = app.subscriptions.call(step.model)
    dues = scheduled(subs, dues, Time.monotonic_ms())
    input = next_input(inbox, dues, Time.monotonic_ms())
    case input
      Input.Failed(message) -> return error(message)
      Input.Event(Ev.Event.Resize(_, _)) -> shown = none
      _ -> shown = shown
    end

    now = Time.monotonic_ms()
    step = updated(app.update, step.model, messages(input, subs, dues, now))
    dues = advanced(dues, now)
  end

  ok(step.model)
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

def read_events[Msg](screen: Tb.Screen, inbox: Channel[Input[Msg]], stop: Channel[Bool]) -> Void
  while not stop.closed?
    case Tb.peek_event(screen, READ_MS)
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

# The input that comes before the first tick is due, or `Due`.
def next_input[Msg](inbox: Channel[Input[Msg]], dues: Map[Int, Int], now: Int) -> Input[Msg]
  wait = IDLE_MS
  for due in dues.values
    wait = [wait, due - now].min.unwrap!
  end

  case inbox.recv([wait, 0].max.unwrap!)
    ok(input) -> input
    error(_) -> Input.Due
  end
end

def messages[Msg](input: Input[Msg], subs: List[Sub[Msg]], dues: Map[Int, Int], now: Int) -> List[Msg]
  case input
    Input.App(msg) -> [msg]
    Input.Event(event) -> subs.flat_map { |sub| event_message(sub, event) }
    Input.Due -> subs.flat_map { |sub| tick_message(sub, dues, now) }
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

def period(ms: Int) -> Int = [ms, 1].max.unwrap!
