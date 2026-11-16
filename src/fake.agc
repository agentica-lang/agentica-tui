## A backend with no terminal, for the tests of a program: the test sends the events, and every call the program
## makes on the terminal is kept in order.

import Bd from "backend"
import Ev from "event"
import View from "view"

## A call of the program on the fake terminal.
enum Call
  Modes(Bd.Modes)
  Cleared
  Drawn(List[View.Cell])
  Presented
  Restored
end

struct Fake
  width: Int
  height: Int
  ## The events the program reads; closed and empty, the terminal is gone.
  events: Channel[Ev.Event]
  calls: Channel[Call]
end

## A fake terminal of `width` by `height`.
def new(width: Int, height: Int) -> Fake
  Fake(width: width, height: height, events: Channel.new(CAPACITY), calls: Channel.new(CAPACITY))
end

def backend(fake: Fake) -> Bd.Backend
  Bd.Backend(
    width: -> { fake.width },
    height: -> { fake.height },
    clear: -> { kept(fake, Call.Cleared) },
    draw: ->(cells) { kept(fake, Call.Drawn(cells)) },
    present: -> { kept(fake, Call.Presented) },
    next_event: ->(timeout_ms) { next_event(fake, timeout_ms) },
    set_modes: ->(modes) { set_modes(fake, modes) },
    set_cursor: ->(_x, _y) { ok() },
    hide_cursor: -> { ok() },
  )
end

## The calls made since the last time, in order.
def calls(fake: Fake) -> List[Call]
  out: List[Call] = []
  got = fake.calls.recv(0)
  while got.ok?
    out = out.push(got.unwrap!)
    got = fake.calls.recv(0)
  end

  out
end

## The text of each row after `calls`, from the last clear: what the terminal shows.
def rows(fake: Fake, calls: List[Call]) -> List[String]
  grid = blank(fake)
  for call in calls
    grid = after(fake, grid, call)
  end

  grid.map { |row| trimmed(row) }
end

private

CAPACITY = 4096
SEND_MS = 1000

def kept(fake: Fake, call: Call) -> Result[Void] = fake.calls.send(call, SEND_MS)

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

def trimmed(row: String) -> String
  text = row
  while text.end_with?(" ")
    text = text.slice(0, text.length - 1)
  end

  text
end

def blank(fake: Fake) -> List[String] = (0...fake.height).to_a.map { |_| " " * fake.width }

def after(fake: Fake, grid: List[String], call: Call) -> List[String]
  case call
    Call.Cleared -> blank(fake)
    Call.Drawn(cells) -> cells.reduce(grid) do |rows, cell| put(rows, cell) end
    _ -> grid
  end
end

# One cell on a row of plain text: a wide character takes its cell and the covered one ("") after it.
def put(rows: List[String], cell: View.Cell) -> List[String]
  return rows if cell.y < 0 or cell.y >= rows.size or cell.char == ""

  row = rows[cell.y].split("")
  return rows if cell.x < 0 or cell.x >= row.size

  rows.set(cell.y, row.set(cell.x, cell.char).join(""))
end
