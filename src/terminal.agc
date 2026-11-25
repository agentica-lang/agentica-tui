## The terminal in Agentica alone: open it (raw mode, alternate screen), draw cells into a back buffer, show the buffer
## with VT sequences, read input events.
##
## `Terminal.raw` and `Terminal.size` come from the VM; the rest is bytes on standard input and output. Any task may
## draw while another waits for an event: the screen is a value behind one lock, taken and put back, which a wait never
## holds while it sleeps. A task reads standard input and a task watches the size.

import Ansi from "ansi"
import Bd from "backend"
import Ev from "event"
import Gr from "grid"
import In from "input"
import St from "style"
import View from "view"
import Width from "width"

## The open terminal. It stays valid after the close, and every call on it then gives an error.
struct Screen
  private

  live: Channel[Live]
  inbox: Channel[Item]
  reading: Channel[Reading]
  # The tasks and the subscription are kept outside the lock of `live`, so that the close ends them (and restores the
  # terminal) even when a task cancelled while it held the lock took the lock with it.
  reader: Channel[Reader]
  watcher: Task[Void]
  signals: Channel[System.Signal]
end

## Opens the terminal (full screen, raw input, no cursor), gives it to the block and closes it when the block ends,
## whatever it returns. Gives the block's result, an error when the terminal cannot be opened (standard input or
## output is not a terminal, one is open already), or `error("task crashed: ...")` when the block stops with a
## runtime error.
##
## Do not run it in a task that gets cancelled, and do not cancel a task that waits for an event or draws: a task
## cancelled while it holds the screen takes it along. The close then still gives the terminal back, but the screen is
## lost for the other tasks.
def open[T](body: Fn[Screen, Result[T]]) -> Result[T]
  screen = try start()
  # The block runs in a task of its own so that a crash comes back as an error, which the caller can show once the
  # terminal is restored: the VM's own report of a crash may land on the screen, which closing then wipes.
  result = Task.await(Task.spawn do body.call(screen) end)
  stopped = close(screen)
  return result if not result.ok?

  try stopped
  result
end

## The width of the terminal in columns. It changes after a `Resize` event.
def width(screen: Screen) -> Int = looked(screen).map { |live| live.width }.unwrap_or(0)

## The height of the terminal in rows.
def height(screen: Screen) -> Int = looked(screen).map { |live| live.height }.unwrap_or(0)

## Fills the back buffer with spaces of the style (default colors when left out).
def clear(screen: Screen, style: St.Style = St.Style()) -> Result[Void]
  try Ansi.check(style)
  drawing(screen, ->(live) { cleared(live, style) })
end

## Sets the cell at column x, row y (from 0) to one character, and the zero-width ones that go on it (combining
## marks, joiners), at most 32 in all.
def set_cell(screen: Screen, x: Int, y: Int, char: String, style: St.Style = St.Style()) -> Result[Void]
  return error("tui: set_cell needs one character: #{char.inspect}") if not cluster?(char)

  try Ansi.check(style)
  drawing(screen, ->(live) { cell_set(live, View.Cell(x: x, y: y, char: char, style: style)) })
end

## Writes text from column x, row y; what goes past the right edge is cut. Gives the width of the text in columns.
## A start outside the screen is an error.
def write(screen: Screen, x: Int, y: Int, text: String, style: St.Style = St.Style()) -> Result[Int]
  try Ansi.check(style)
  try drawing(screen, ->(live) { written(live, x, y, text, style) })
  ok(Width.text(text))
end

## Draws `node` over the whole screen and shows it. Only the cells that differ from `last` (what the screen shows) are
## written; with no `last`, the screen is cleared first. Gives what the screen shows now, for the next call.
def render(screen: Screen, node: View.Node, last: Optional[Gr.Grid] = none) -> Result[Gr.Grid]
  Bd.render(backend(screen), node, last)
end

## The screen as a backend of the program loop.
def backend(screen: Screen) -> Bd.Backend
  Bd.Backend(
    width: -> { width(screen) },
    height: -> { height(screen) },
    clear: -> { clear(screen) },
    draw: ->(cells) { draw(screen, cells) },
    present: -> { present(screen) },
    next_event: ->(timeout_ms) { peek_event(screen, timeout_ms) },
    set_modes: ->(modes) { set_modes(screen, modes) },
    set_cursor: ->(x, y) { set_cursor(screen, x, y) },
    hide_cursor: -> { hide_cursor(screen) },
    suspend: -> { suspend(screen) },
    resume: -> { resume(screen) },
  )
end

## Gives the terminal back as it was before `open` (main screen, its own modes), so that another program can use it;
## the screen stays open, and an event wait reads nothing until `resume`. Calling it again changes nothing.
def suspend(screen: Screen) -> Result[Void] = locked(screen, ->(live) { suspended(screen, live) })

## Takes the terminal again after `suspend`, with the modes it had, and reads its size again. Nothing drawn before
## shows: draw the whole screen again. Calling it again changes nothing.
def resume(screen: Screen) -> Result[Void] = locked(screen, ->(live) { resumed(screen, live) })

## Shows the back buffer on the terminal: nothing drawn appears before this.
def present(screen: Screen) -> Result[Void] = drawing(screen, &shown)

## Shows the cursor at column x, row y.
def set_cursor(screen: Screen, x: Int, y: Int) -> Result[Void]
  drawing(screen, ->(live) { Locked(live: live.with(cursor: some(Bd.Cursor(x: x, y: y))), value: ok()) })
end

## Hides the cursor (as `open` leaves it).
def hide_cursor(screen: Screen) -> Result[Void]
  drawing(screen, ->(live) { Locked(live: live.with(cursor: none), value: ok()) })
end

## Waits for the next event, or an error once another task closes the screen. Other tasks run (and may draw)
## meanwhile.
def poll_event(screen: Screen) -> Result[Ev.Event]
  while true
    case try wait_event(screen, IDLE_MS)
      some(event) -> return ok(event)
      none -> next
    end
  end

  error("tui: poll_event: no event")
end

## Waits up to timeout_ms milliseconds for an event: `none` when none came.
def peek_event(screen: Screen, timeout_ms: Int) -> Result[Optional[Ev.Event]]
  if timeout_ms < 0 or timeout_ms > MAX_TIMEOUT_MS
    return error("tui: peek_event timeout out of range 0..#{MAX_TIMEOUT_MS}: #{timeout_ms}")
  end

  wait_event(screen, timeout_ms)
end

## Sets how Escape is read, and whether mouse events come.
def set_input_mode(screen: Screen, mode: Ev.InputMode, mouse: Bool = false) -> Result[Void]
  drawing(screen, ->(live) { input_set(live, mode, mouse) })
end

## Sets how colors are sent (`Normal` at the start).
def set_output_mode(screen: Screen, mode: St.OutputMode) -> Result[Void]
  drawing(screen, ->(live) { Locked(live: live.with(output: mode), value: ok()) })
end

private

# The most input bytes that wait for the reader of events.
INBOX = 4096
# How many bytes one step of the reader of events takes from the inbox.
CHUNK = 4096
LOCK_MS = 60_000
# How long a read of the screen waits for it, and the close.
LOOK_MS = 5000
CLOSE_MS = 2000
# How long a stop waits for the answer of the terminal.
STOP_MS = 500
BYTE_BITS = 8
LAST_FOUR = 0xffff_ffff
SEND_MS = 60_000
# The longest wait of one receive of a task that has no deadline.
IDLE_MS = 60_000
MAX_TIMEOUT_MS = 2_147_483_647
# One screen at a time: the terminal belongs to the process.
IN_USE: ATS[String, Bool] = ATS.new()
IN_USE_KEY = "open"
CLOSED = "tui: the screen is closed"
BUSY = "tui: the screen is busy"
SUSPENDED = "tui: the terminal is suspended"

enum Phase
  Open
  Suspended
  Closed
end

# What the screen is: its size, the back buffer (what the program drew) and the front one (what the terminal shows,
# none when it is not known: after the open, a resume or a resize), the cursor, the modes and the tasks.
struct Live
  phase: Phase
  width: Int
  height: Int
  back: Gr.Grid
  front: Optional[Gr.Grid] = none
  cursor: Optional[Bd.Cursor] = none
  # Where the terminal has the cursor now.
  cursor_now: Optional[Bd.Cursor] = none
  input: Ev.InputMode = Ev.InputMode.Esc
  mouse: Bool = false
  output: St.OutputMode = St.OutputMode.Normal
end

# The task that reads standard input, and the channel whose close asks it to stop.
struct Reader
  task: Task[Void]
  gate: Channel[Bool]
end

# A change of the screen and what it gives back.
struct Locked
  live: Live
  value: Result[Void]
end

# What the tasks put in the inbox.
enum Item
  Byte(Int)
  Resized(Int, Int)
  Ended
end

# What an event wait keeps between two waits: the input parser, the events it made that nobody took yet, when the
# last byte came, and whether standard input ended.
struct Reading
  parser: In.Parser
  queued: List[Ev.Event] = []
  last_ms: Int = 0
  ended: Bool = false
end

struct Waited
  reading: Reading
  found: Result[Optional[Ev.Event]]
end

def start() -> Result[Screen]
  return error("tui: open failed: a screen is open already") if not IN_USE.put_new(IN_USE_KEY, true)

  case begun()
    ok(screen) -> ok(screen)
    error(e) ->
      IN_USE.delete(IN_USE_KEY)
      error("tui: open failed: #{e.message}")
  end
end

def begun() -> Result[Screen]
  return error("standard input is not a terminal") if not Terminal.tty?(Terminal.Stream.Stdin)
  return error("standard output is not a terminal") if not Terminal.tty?(Terminal.Stream.Stdout)

  signals = try System.subscribe([System.Signal.Winch])
  closed = Live(phase: Phase.Closed, width: 0, height: 0, back: Gr.blank(0, 0))
  case enter(closed)
    error(e) ->
      signals.close
      error(e.message)
    ok(live) ->
      slot: Channel[Live] = Channel.new(1)
      inbox: Channel[Item] = Channel.new(INBOX)
      watcher = Task.spawn do watch_size(slot, inbox, signals) end
      screen = Screen(
        live: slot,
        inbox: inbox,
        reading: Channel.new(1),
        reader: Channel.new(1),
        watcher: watcher,
        signals: signals,
      )

      try slot.send(live, LOCK_MS)
      try screen.reader.send(start_reader(inbox), LOCK_MS)
      try screen.reading.send(Reading(parser: In.Parser()), LOCK_MS)
      ok(screen)
  end
end

# Takes the terminal: raw input, the alternate screen, the paste and mouse reports, and its size. The caller starts the
# reader.
def enter(live: Live) -> Result[Live]
  size = try Terminal.size()
  try Terminal.raw()
  emit(Ansi.ENTER + mouse_bytes(live))
  ok(
    live.with(
      phase: Phase.Open,
      width: size.cols,
      height: size.rows,
      back: Gr.blank(size.cols, size.rows),
      front: none,
      cursor_now: none,
    ),
  )
end

# Gives the terminal back: the sequences that undo `enter`, then the mode it had before the first raw.
def leave(live: Live) -> Result[Void]
  emit(mouse_off(live) + Ansi.LEAVE)
  Terminal.raw(on: false)
end

def mouse_bytes(live: Live) -> String
  return Ansi.mouse(true) if live.mouse

  ""
end

def mouse_off(live: Live) -> String
  return Ansi.mouse(false) if live.mouse

  ""
end

# One write of the terminal's bytes, finished before the next task draws.
def emit(bytes: String) -> Void
  return if bytes.empty?

  print(bytes)
  IO.flush()
end

def close(screen: Screen) -> Result[Void]
  stopped = case held(screen.live, CLOSE_MS, ->(live) { closing(screen, live) })
    some(done) -> done
    none -> forced(screen)
  end

  screen.inbox.close
  IN_USE.delete(IN_USE_KEY)
  stopped
end

def closing(screen: Screen, live: Live) -> Locked
  return Locked(live: live, value: ok()) if live.phase == Phase.Closed

  stop_reader(screen)
  Task.cancel(screen.watcher)
  screen.signals.close
  left = ok()
  if live.phase == Phase.Open
    left = leave(live)
  end

  Locked(live: live.with(phase: Phase.Closed), value: left)
end

# The close when the screen could not be taken in time (a task cancelled while it held it): the tasks end and the
# terminal gets back what it can, without knowing the modes the screen had.
def forced(screen: Screen) -> Result[Void]
  stop_reader(screen)
  Task.cancel(screen.watcher)
  screen.signals.close
  emit(Ansi.mouse(false) + Ansi.LEAVE)
  try Terminal.raw(on: false)
  error("tui: the screen was busy at the close; the terminal is restored")
end

def suspended(screen: Screen, live: Live) -> Locked
  case live.phase
    Phase.Open ->
      stop_reader(screen)
      left = leave(live)
      Locked(live: live.with(phase: Phase.Suspended, front: none, cursor_now: none), value: left)
    Phase.Suspended -> Locked(live: live, value: ok())
    Phase.Closed -> Locked(live: live, value: error(CLOSED))
  end
end

def resumed(screen: Screen, live: Live) -> Locked
  case live.phase
    Phase.Suspended ->
      case enter(live)
        ok(back) ->
          _ = screen.reader.send(start_reader(screen.inbox), LOCK_MS)
          Locked(live: back, value: ok())
        error(e) -> Locked(live: live, value: error("tui: resume failed: #{e.message}"))
      end

    Phase.Open -> Locked(live: live, value: ok())
    Phase.Closed -> Locked(live: live, value: error(CLOSED))
  end
end

# Takes the screen, calls `change` on it and puts back what it gives. `change` never stops with a runtime error: the
# screen would stay taken.
def locked(screen: Screen, change: Fn[Live, Locked]) -> Result[Void]
  case held(screen.live, LOCK_MS, change)
    some(done) -> done
    none -> error(BUSY)
  end
end

# `locked` on the slot of the screen, waiting up to `wait_ms` for it: none when it did not come.
def held(slot: Channel[Live], wait_ms: Int, change: Fn[Live, Locked]) -> Optional[Result[Void]]
  case slot.recv(wait_ms)
    ok(live) ->
      step = change.call(live)
      _ = slot.send(step.live, LOCK_MS)
      some(step.value)
    error(_) -> none
  end
end

# `locked`, for a change that draws or sets a mode: it needs the terminal open.
def drawing(screen: Screen, change: Fn[Live, Locked]) -> Result[Void]
  locked(screen, ->(live) { guarded(live, change) })
end

def guarded(live: Live, change: Fn[Live, Locked]) -> Locked
  case live.phase
    Phase.Open -> change.call(live)
    Phase.Suspended -> Locked(live: live, value: error(SUSPENDED))
    Phase.Closed -> Locked(live: live, value: error(CLOSED))
  end
end

# The screen as it is, for a read of its size or modes.
def looked(screen: Screen) -> Optional[Live]
  case screen.live.recv(LOOK_MS)
    ok(live) ->
      _ = screen.live.send(live, LOCK_MS)
      some(live)
    error(_) -> none
  end
end

def cleared(live: Live, style: St.Style) -> Locked
  glyph = Gr.Glyph(char: " ", style: style)
  rows = List.repeat(List.repeat(glyph, live.width), live.height)
  Locked(live: live.with(back: Gr.Grid(width: live.width, height: live.height, rows: rows)), value: ok())
end

def cell_set(live: Live, cell: View.Cell) -> Locked
  if not inside?(live, cell.x, cell.y)
    return Locked(live: live, value: error("tui: set_cell outside the screen: #{cell.x},#{cell.y}"))
  end

  Locked(live: live.with(back: Gr.apply(live.back, [cell])), value: ok())
end

def written(live: Live, x: Int, y: Int, text: String, style: St.Style) -> Locked
  return Locked(live: live, value: error("tui: write outside the screen: #{x},#{y}")) if not inside?(live, x, y)

  cells = text_cells(text, x, y, live.width, style)
  Locked(live: live.with(back: Gr.apply(live.back, cells)), value: ok())
end

def inside?(live: Live, x: Int, y: Int) -> Bool = x >= 0 and y >= 0 and x < live.width and y < live.height

# The cells of a text from x, y: a character and the zero-width ones after it share a cell; what does not fit before
# the right edge is cut.
def text_cells(text: String, x: Int, y: Int, edge: Int, style: St.Style) -> List[View.Cell]
  out: List[View.Cell] = []
  at = x
  for part in clusters(text)
    columns = Width.cell(part)
    break if at + columns > edge

    out = out.push(View.Cell(x: at, y: y, char: part, style: style))
    at = at + columns
  end

  out
end

def clusters(text: String) -> List[String]
  out: List[String] = []
  for char in text.split("")
    last = out.size - 1
    if last >= 0 and Width.char(char) == 0 and out[last].length < Width.CELL_CHARS
      out = out.set(last, out[last] + char)
    else
      out = out.push(char)
    end
  end

  out
end

# One character and only zero-width ones after it.
def cluster?(char: String) -> Bool
  return false if char.empty? or char.length > Width.CELL_CHARS

  char.split("").drop(1).all? { |c| Width.char(c) == 0 }
end

def draw(screen: Screen, cells: List[View.Cell]) -> Result[Void]
  for cell in cells
    try Ansi.check(cell.style)
  end

  drawing(screen, ->(live) { Locked(live: live.with(back: Gr.apply(live.back, cells)), value: ok()) })
end

def shown(live: Live) -> Locked
  emit(Ansi.update(live.front, live.back, live.output) + Ansi.place(live.cursor_now, live.cursor))
  Locked(live: live.with(front: some(live.back), cursor_now: live.cursor), value: ok())
end

def input_set(live: Live, mode: Ev.InputMode, mouse: Bool) -> Locked
  if mouse != live.mouse
    emit(Ansi.mouse(mouse))
  end

  Locked(live: live.with(input: mode, mouse: mouse), value: ok())
end

# Sets the modes; the function it gives puts back those before.
def set_modes(screen: Screen, modes: Bd.Modes) -> Result[Fn[Result[Void]]]
  before = try looked(screen).to_result(BUSY)
  try set_input_mode(screen, modes.input, mouse: modes.mouse)
  try set_output_mode(screen, modes.output)
  ok(-> { restore_modes(screen, before) })
end

def restore_modes(screen: Screen, before: Live) -> Result[Void]
  try set_input_mode(screen, before.input, mouse: before.mouse)
  set_output_mode(screen, before.output)
end

def start_reader(inbox: Channel[Item]) -> Reader
  gate: Channel[Bool] = Channel.new(1)
  Reader(task: Task.spawn do read_input(inbox, gate) end, gate: gate)
end

# Stops the reader without leaving a read of standard input pending, which would take the first bytes another
# program (or this one, later) reads. A read that waits cannot be cancelled in time, so the terminal is asked to
# answer a status report: the reader sees the answer, which ends its pending read, and stops. A terminal that does
# not answer in STOP_MS leaves the read to the VM's cancel (agentica-lang/agentica#2013: the cancel does not end the
# read), and an answer that comes later reaches whoever reads the terminal then.
def stop_reader(screen: Screen) -> Void
  case screen.reader.recv(0)
    ok(reader) ->
      reader.gate.close
      emit(Ansi.STATUS_REQUEST)
      case Task.await(reader.task, STOP_MS)
        Await.Done(_) -> nil
        Await.TimedOut -> Task.cancel(reader.task)
      end

    error(_) -> nil
  end
end

# The reader of standard input: one byte at a time into the inbox, the VM buffers the rest. It stops when the screen
# closes the inbox, when the gate is closed and the terminal's status report arrives, or when the input ends.
def read_input(inbox: Channel[Item], gate: Channel[Bool]) -> Void
  last = 0
  while not inbox.closed?
    case IO.read_bytes(1)
      ok(bytes) ->
        if bytes.empty?
          _ = inbox.send(Item.Ended, SEND_MS)
          return
        end

        _ = inbox.send(Item.Byte(bytes[0]), SEND_MS)
        # The last four bytes, as a number.
        last = last.shift_left(BYTE_BITS).bit_and(LAST_FOUR).bit_or(bytes[0])
        return if gate.closed? and last == Ansi.STATUS_REPLY_CODE
      error(_) ->
        _ = inbox.send(Item.Ended, SEND_MS)
        return
    end
  end
end

# Gives the new size of the terminal, at each resize signal, to the screen and to the events.
def watch_size(slot: Channel[Live], inbox: Channel[Item], signals: Channel[System.Signal]) -> Void
  while not signals.closed?
    case signals.recv(IDLE_MS)
      ok(_) -> resized(slot, inbox)
      error(_) -> next
    end
  end
end

def resized(slot: Channel[Live], inbox: Channel[Item]) -> Void
  case Terminal.size()
    ok(size) ->
      if held(slot, LOCK_MS, ->(live) { sized(live, size) }) == some(ok())
        _ = inbox.send(Item.Resized(size.cols, size.rows), SEND_MS)
      end

    error(_) -> nil
  end
end

# A new size: the back buffer is blank and the terminal's content unknown. An error when the terminal is not open.
def sized(live: Live, size: Terminal.Size) -> Locked
  return Locked(live: live, value: error(SUSPENDED)) if live.phase != Phase.Open

  Locked(
    live: live.with(width: size.cols, height: size.rows, back: Gr.blank(size.cols, size.rows), front: none),
    value: ok(),
  )
end

# The next event, after at most timeout_ms. Waits take the reading one after the other.
def wait_event(screen: Screen, timeout_ms: Int) -> Result[Optional[Ev.Event]]
  deadline = Time.monotonic_ms() + timeout_ms
  seen = try looked(screen).to_result(BUSY)
  return error(CLOSED) if seen.phase == Phase.Closed

  case screen.reading.recv(timeout_ms)
    ok(reading) ->
      waited = collect(screen, reading, deadline)
      _ = screen.reading.send(waited.reading, LOCK_MS)
      waited.found
    error(_) ->
      return error(CLOSED) if screen.inbox.closed?

      ok(none)
  end
end

def collect(screen: Screen, start: Reading, deadline: Int) -> Waited
  reading = start
  while true
    if not reading.queued.empty?
      return Waited(reading: reading.with(queued: reading.queued.drop(1)), found: ok(some(reading.queued[0])))
    elsif reading.ended
      return Waited(reading: reading, found: error("tui: the input ended"))
    end

    now = Time.monotonic_ms()
    found = looked(screen)
    return Waited(reading: reading, found: error(BUSY)) if found.none?

    live = found.unwrap!
    flush_at = flush_time(reading, live.input)
    wait = [deadline, flush_at].min.unwrap! - now
    case screen.inbox.recv([wait, 0].max.unwrap!)
      ok(item) -> reading = absorbed(reading, live, [item] + more(screen.inbox))
      error(_) ->
        if screen.inbox.closed? and screen.inbox.empty?
          return Waited(reading: reading, found: error(CLOSED))
        elsif Time.monotonic_ms() >= flush_at
          reading = flushed(reading, live)
        elsif Time.monotonic_ms() >= deadline
          return Waited(reading: reading, found: ok(none))
        end
    end
  end

  Waited(reading: reading, found: ok(none))
end

# When what the parser holds is read as it is: never (a long time ahead) when it holds nothing to resolve.
def flush_time(reading: Reading, mode: Ev.InputMode) -> Int
  case In.wait_ms(reading.parser, mode)
    some(ms) -> reading.last_ms + ms
    none -> Time.monotonic_ms() + MAX_TIMEOUT_MS
  end
end

# The items that wait in the inbox, without waiting.
def more(inbox: Channel[Item]) -> List[Item]
  out: List[Item] = []
  while out.size < CHUNK
    got = inbox.recv(0)
    break if not got.ok?

    out = out.push(got.unwrap!)
  end

  out
end

# What the items add to the reading: bytes go to the parser together, a resize and the end of the input in their place
# among the events.
def absorbed(reading: Reading, live: Live, items: List[Item]) -> Reading
  state = reading
  chunk: List[Int] = []
  for item in items
    case item
      Item.Byte(byte) -> chunk = chunk.push(byte)
      Item.Resized(width, height) ->
        state = fed(state, live, chunk)
        chunk = []
        state = state.with(queued: state.queued.push(Ev.Event.Resize(width, height)))
      Item.Ended ->
        state = fed(state, live, chunk)
        chunk = []
        state = state.with(ended: true)
    end
  end

  fed(state, live, chunk)
end

def fed(reading: Reading, live: Live, chunk: List[Int]) -> Reading
  return reading if chunk.empty?

  # Every item of the chunk is a byte.
  parsed = In.feed(reading.parser, Bytes.from_list(chunk).unwrap!, live.input)
  reading.with(
    parser: parsed.parser,
    queued: reading.queued + parsed.events.map { |event| clamped(event, live) },
    last_ms: Time.monotonic_ms(),
  )
end

def flushed(reading: Reading, live: Live) -> Reading
  parsed = In.flush(reading.parser, live.input)
  reading.with(parser: parsed.parser, queued: reading.queued + parsed.events.map { |event| clamped(event, live) })
end

# A mouse report whose cell is outside the screen gives the nearest cell inside it.
def clamped(event: Ev.Event, live: Live) -> Ev.Event
  case event
    Ev.Event.Mouse(button, x, y, mods) ->
      Ev.Event.Mouse(button, [x, live.width - 1].min.unwrap!, [y, live.height - 1].min.unwrap!, mods)
    _ -> event
  end
end
