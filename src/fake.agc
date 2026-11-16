## A backend with no terminal, for the tests of a program: the test sends the events and changes the size, and every
## call the program makes on the terminal is kept in order.

import Bd from "backend"
import Ev from "event"
import Gr from "grid"
import St from "style"
import View from "view"

## A call of the program on the fake terminal.
enum Call
  Modes(Bd.Modes)
  Cleared
  Drawn(List[View.Cell])
  Presented
  Cursor(Int, Int)
  CursorHidden
  Restored
end

struct Size
  width: Int
  height: Int
end

struct Fake
  ## The events the program reads; closed and empty, the terminal is gone.
  events: Channel[Ev.Event]
  calls: Channel[Call]
  # The size now, and the calls since the last clear: each a channel of one value, taken and put back.
  size: Channel[Size]
  shown: Channel[List[Call]]
end

## A fake terminal of `width` by `height`.
def new(width: Int, height: Int) -> Fake
  fake = Fake(events: Channel.new(EVENTS), calls: Channel.new(CALLS), size: Channel.new(1), shown: Channel.new(1))
  _ = fake.size.send(Size(width: width, height: height), 0)
  _ = fake.shown.send([], 0)
  fake
end

def backend(fake: Fake) -> Bd.Backend
  Bd.Backend(
    width: -> { size(fake).width },
    height: -> { size(fake).height },
    clear: -> { kept(fake, Call.Cleared) },
    draw: ->(cells) { kept(fake, Call.Drawn(cells)) },
    present: -> { kept(fake, Call.Presented) },
    next_event: ->(timeout_ms) { next_event(fake, timeout_ms) },
    set_modes: ->(modes) { set_modes(fake, modes) },
    set_cursor: ->(x, y) { kept(fake, Call.Cursor(x, y)) },
    hide_cursor: -> { kept(fake, Call.CursorHidden) },
  )
end

## The terminal takes a new size and sends its `Resize` event.
def resize(fake: Fake, width: Int, height: Int) -> Result[Void]
  _ = try fake.size.recv(WAIT_MS)
  try fake.size.send(Size(width: width, height: height), WAIT_MS)
  fake.events.send(Ev.Event.Resize(width, height), WAIT_MS)
end

## The calls made since the last time, in order, after waiting up to `wait_ms` for one when none waits. `screen`,
## `wait_for`, `cursor` and `style_at` read them too.
def calls(fake: Fake, wait_ms: Int = 0) -> List[Call] = taken(fake, wait_ms)

## The text of each row after `calls`, from the last clear: what the terminal shows. A wide character's covered cell
## adds nothing.
def rows(fake: Fake, calls: List[Call]) -> List[String]
  grid(size(fake), calls).rows.map { |row| trimmed(row.map { |glyph| glyph.char }.join("")) }
end

## What the terminal shows now: `rows` of every call since the last clear (it reads the new calls).
def screen(fake: Fake) -> List[String]
  _ = calls(fake)
  rows(fake, shown(fake))
end

## Waits up to `wait_ms` for the terminal to show rows that `done` takes, and gives them; an error with the rows it
## shows when the time runs out.
def wait_for(fake: Fake, done: Fn[List[String], Bool], wait_ms: Int = 5000) -> Result[List[String]]
  deadline = Time.monotonic_ms() + wait_ms
  shows = screen(fake)
  while not done.call(shows)
    left = deadline - Time.monotonic_ms()
    if left <= 0
      return error("tui: the fake terminal did not show it in #{wait_ms} ms; it shows:\n#{shows.join("\n")}")
    end

    _ = taken(fake, left)
    shows = rows(fake, shown(fake))
  end

  ok(shows)
end

## Where the cursor shows on the terminal now; none when it is hidden.
def cursor(fake: Fake) -> Optional[Bd.Cursor]
  _ = calls(fake)
  at: Optional[Bd.Cursor] = none
  for call in shown(fake)
    case call
      Call.Cursor(x, y) -> at = some(Bd.Cursor(x: x, y: y))
      Call.CursorHidden -> at = none
      _ -> next
    end
  end

  at
end

## The style of the cell at column x, row y on the terminal now; none outside it.
def style_at(fake: Fake, x: Int, y: Int) -> Optional[St.Style]
  _ = calls(fake)
  found = grid(size(fake), shown(fake))
  return none if y < 0 or y >= found.height or x < 0 or x >= found.width

  some(found.rows[y][x].style)
end

private

EVENTS = 4096
CALLS = 65_536
WAIT_MS = 1000

# The calls that wait, after waiting up to `wait_ms` for the first; what the screen shows takes them in.
def taken(fake: Fake, wait_ms: Int) -> List[Call]
  out: List[Call] = []
  got = fake.calls.recv(wait_ms)
  while got.ok?
    out = out.push(got.unwrap!)
    got = fake.calls.recv(0)
  end

  _ = fake.shown.send(since_clear(shown_taken(fake) + out), WAIT_MS)
  out
end

def size(fake: Fake) -> Size
  now = fake.size.recv(WAIT_MS).unwrap!
  _ = fake.size.send(now, WAIT_MS)
  now
end

def shown(fake: Fake) -> List[Call]
  now = shown_taken(fake)
  _ = fake.shown.send(now, WAIT_MS)
  now
end

def shown_taken(fake: Fake) -> List[Call]
  none_yet: List[Call] = []
  fake.shown.recv(WAIT_MS).unwrap_or(none_yet)
end

# The calls from the last clear on: the screen they draw is the same.
def since_clear(calls: List[Call]) -> List[Call]
  start = 0
  i = 0
  for call in calls
    if call == Call.Cleared
      start = i
    end

    i += 1
  end

  calls.drop(start)
end

def kept(fake: Fake, call: Call) -> Result[Void]
  return ok() if fake.calls.send(call, 0).ok?

  error("tui: the fake terminal keeps #{CALLS} calls: read them with Testing.calls or Testing.screen")
end

def next_event(fake: Fake, timeout_ms: Int) -> Result[Optional[Ev.Event]]
  case fake.events.recv(timeout_ms)
    ok(event) -> ok(some(event))
    error(_) if fake.events.closed? and fake.events.empty? -> error("tui: the fake terminal is closed")
    error(_) -> ok(none)
  end
end

def set_modes(fake: Fake, modes: Bd.Modes) -> Result[Fn[Result[Void]]]
  try kept(fake, Call.Modes(modes))
  ok(-> { kept(fake, Call.Restored) })
end

def grid(now: Size, calls: List[Call]) -> Gr.Grid
  out = Gr.blank(now.width, now.height)
  for call in calls
    out = after(now, out, call)
  end

  out
end

def after(now: Size, grid: Gr.Grid, call: Call) -> Gr.Grid
  case call
    Call.Cleared -> Gr.blank(now.width, now.height)
    Call.Drawn(cells) -> Gr.apply(grid, cells)
    _ -> grid
  end
end

def trimmed(row: String) -> String
  text = row
  while text.end_with?(" ")
    text = text.slice(0, text.length - 1)
  end

  text
end
