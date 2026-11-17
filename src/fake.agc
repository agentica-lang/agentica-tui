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
  Suspended
  Resumed
end

struct Size
  width: Int
  height: Int
end

# What the terminal shows (`front`, as the last present left it) and what the calls after that drew (`back`).
struct Term
  back: Gr.Grid
  back_cursor: Optional[Bd.Cursor] = none
  front: Gr.Grid
  front_cursor: Optional[Bd.Cursor] = none
  front_text: List[String]
end

struct Fake
  ## The events the program reads; closed and empty, the terminal is gone.
  events: Channel[Ev.Event]
  calls: Channel[Call]
  # The size now, and the terminal with the calls read so far: each a channel of one value, taken and put back.
  size: Channel[Size]
  term: Channel[Term]
end

## A fake terminal of `width` by `height`.
def new(width: Int, height: Int) -> Fake
  fake = Fake(events: Channel.new(EVENTS), calls: Channel.new(CALLS), size: Channel.new(1), term: Channel.new(1))
  _ = fake.size.send(Size(width: width, height: height), 0)
  blank = Gr.blank(width, height)
  _ = fake.term.send(Term(back: blank, front: blank, front_text: text(blank)), 0)
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
    suspend: -> { kept(fake, Call.Suspended) },
    resume: -> { kept(fake, Call.Resumed) },
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

## The text of each row that `calls` draw, from the last clear in them, presented or not. A wide character's covered
## cell adds nothing.
def rows(fake: Fake, calls: List[Call]) -> List[String]
  now = size(fake)
  text(calls.reduce(Gr.blank(now.width, now.height)) do |grid, call| drawn(now, grid, call) end)
end

## The text of each row the terminal shows now, as the last present left it (it reads the new calls).
def screen(fake: Fake) -> List[String]
  _ = calls(fake)
  shown(fake).front_text
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
    shows = shown(fake).front_text
  end

  ok(shows)
end

## Where the cursor shows on the terminal now; none when it is hidden.
def cursor(fake: Fake) -> Optional[Bd.Cursor]
  _ = calls(fake)
  shown(fake).front_cursor
end

## The style of the cell at column x, row y on the terminal now; none outside it.
def style_at(fake: Fake, x: Int, y: Int) -> Optional[St.Style]
  _ = calls(fake)
  found = shown(fake).front
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

  if not out.empty?
    now = size(fake)
    term = fake.term.recv(WAIT_MS).unwrap!
    _ = fake.term.send(out.reduce(term) do |t, call| after(now, t, call) end, WAIT_MS)
  end

  out
end

def size(fake: Fake) -> Size
  now = fake.size.recv(WAIT_MS).unwrap!
  _ = fake.size.send(now, WAIT_MS)
  now
end

def shown(fake: Fake) -> Term
  now = fake.term.recv(WAIT_MS).unwrap!
  _ = fake.term.send(now, WAIT_MS)
  now
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

# The terminal after one call: a present shows what was drawn; a clear, or a draw after a size change, starts from a
# blank screen.
def after(now: Size, term: Term, call: Call) -> Term
  case call
    Call.Presented -> term.with(front: term.back, front_cursor: term.back_cursor, front_text: presented_text(term))
    Call.Cursor(x, y) -> term.with(back_cursor: some(Bd.Cursor(x: x, y: y)))
    Call.CursorHidden -> term.with(back_cursor: none)
    _ -> term.with(back: drawn(now, term.back, call))
  end
end

def drawn(now: Size, grid: Gr.Grid, call: Call) -> Gr.Grid
  case call
    Call.Cleared -> Gr.blank(now.width, now.height)
    Call.Drawn(cells) if grid.width != now.width or grid.height != now.height ->
      Gr.apply(Gr.blank(now.width, now.height), cells)
    Call.Drawn(cells) -> Gr.apply(grid, cells)
    _ -> grid
  end
end

def text(grid: Gr.Grid) -> List[String] = grid.rows.map { |row| row_text(row) }

# Only the rows that changed since the last present are read again.
def presented_text(term: Term) -> List[String]
  return text(term.back) if term.back.height != term.front.height or term.back.width != term.front.width

  (0...term.back.height).to_a.map { |y| changed_text(term, y) }
end

def changed_text(term: Term, y: Int) -> String
  return term.front_text[y] if term.back.rows[y] == term.front.rows[y]

  row_text(term.back.rows[y])
end

# The characters of a row without the spaces at its end; the mark keeps the spaces at its start.
def row_text(row: List[Gr.Glyph]) -> String
  marked = ("|" + row.map { |glyph| glyph.char }.join("")).strip
  marked.slice(1, marked.length - 1)
end
