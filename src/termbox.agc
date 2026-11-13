## The terminal through termbox2 (native/termbox2/termbox2.h, built into libtermbox2 by `make native`): open it, draw
## cells and text into a back buffer, show the buffer, read input events.
##
## termbox2 keeps one terminal per process. Any task may draw while another waits for an event: native/tui.c puts
## every termbox2 call under one lock.

import Ev from "event"
import St from "style"

extern "termbox2"
  ## The open terminal. Closing it (`open` does) restores the terminal; so does the end of the program, a crash too.
  resource Screen, free: tui_shutdown

  # Every function takes the screen, so that the VM refuses a call after the close and never frees the screen
  # during a call.
  def tui_init(out screen: Screen) -> C.Int32
  compute def tui_wait_event(screen: Screen, event: C.Pointer, timeout_ms: C.Int32) -> C.Int32
  def tui_width(screen: Screen) -> C.Int32
  def tui_height(screen: Screen) -> C.Int32
  def tui_clear(screen: Screen, fg: C.Int64, bg: C.Int64) -> C.Int32
  def tui_present(screen: Screen) -> C.Int32
  def tui_set_cell(screen: Screen, x: C.Int32, y: C.Int32, ch: C.UInt32, fg: C.Int64, bg: C.Int64) -> C.Int32
  def tui_print(
    screen: Screen,
    x: C.Int32,
    y: C.Int32,
    fg: C.Int64,
    bg: C.Int64,
    out width: C.Int64,
    text: C.String,
  ) -> C.Int32
  def tui_set_cursor(screen: Screen, x: C.Int32, y: C.Int32) -> C.Int32
  def tui_hide_cursor(screen: Screen) -> C.Int32
  def tui_set_input_mode(screen: Screen, mode: C.Int32) -> C.Int32
  def tui_set_output_mode(screen: Screen, mode: C.Int32) -> C.Int32
  def tui_strerror(code: C.Int32) -> C.String
end

## Opens the terminal (full screen, raw input, no cursor), gives it to the block and closes it when the block ends,
## whatever it returns. Gives the block's result, an error when the terminal cannot be opened (no terminal, one
## already open), or `error("task crashed: ...")` when the block stops with a runtime error.
def open[T](body: Fn[Screen, Result[T]]) -> Result[T]
  try Native.load("termbox2")
  opened = tui_init()
  return error(failure("open", opened.result)) if opened.result != TB_OK

  # The block runs in a task of its own so that a crash comes back as an error, which the caller can show once the
  # terminal is restored: the VM's own report of a crash may land on the screen, which closing then wipes.
  screen = opened.screen
  result = Task.await(Task.spawn do body.call(screen) end)
  Native.close(screen)
  result
end

## The width of the terminal in columns. It changes after a `Resize` event, once the screen is cleared or shown.
def width(screen: Screen) -> Int = tui_width(screen)

## The height of the terminal in rows.
def height(screen: Screen) -> Int = tui_height(screen)

## Fills the back buffer with spaces of the style (default colors when left out).
def clear(screen: Screen, style: St.Style = St.Style()) -> Result[Void]
  fg = try St.fg_value(style)
  bg = try St.bg_value(style)
  check("clear", tui_clear(screen, fg, bg))
end

## Sets the cell at column x, row y (from 0) to one character.
def set_cell(screen: Screen, x: Int, y: Int, char: String, style: St.Style = St.Style()) -> Result[Void]
  return error("tui: set_cell needs one character: #{char.inspect}") if char.length != 1

  fg = try St.fg_value(style)
  bg = try St.bg_value(style)
  check("set_cell", tui_set_cell(screen, x, y, char.code, fg, bg))
end

## Writes text from column x, row y; what goes past the right edge is cut. Gives the width of the text in columns.
## A start outside the screen is an error.
def write(screen: Screen, x: Int, y: Int, text: String, style: St.Style = St.Style()) -> Result[Int]
  return error("tui: write cannot send a NUL character") if text.include?(String.from_code(0))

  fg = try St.fg_value(style)
  bg = try St.bg_value(style)
  printed = tui_print(screen, x, y, fg, bg, text)
  try check("write", printed.result)
  ok(printed.width)
end

## Shows the back buffer on the terminal: nothing drawn appears before this.
def present(screen: Screen) -> Result[Void] = check("present", tui_present(screen))

## Shows the cursor at column x, row y.
def set_cursor(screen: Screen, x: Int, y: Int) -> Result[Void] = check("set_cursor", tui_set_cursor(screen, x, y))

## Hides the cursor (as `open` leaves it).
def hide_cursor(screen: Screen) -> Result[Void] = check("hide_cursor", tui_hide_cursor(screen))

## Waits for the next event, or an error once another task closes the screen. Other tasks run (and may draw)
## meanwhile.
def poll_event(screen: Screen) -> Result[Ev.Event]
  found = try wait_event(screen, FOREVER)
  found.to_result("tui: poll_event: no event")
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
  check("set_input_mode", tui_set_input_mode(screen, Ev.input_mode_value(mode, mouse)))
end

## Sets how colors are sent (`Normal` at the start).
def set_output_mode(screen: Screen, mode: St.OutputMode) -> Result[Void]
  check("set_output_mode", tui_set_output_mode(screen, St.output_mode_value(mode)))
end

private

# termbox2.h return values.
TB_OK = 0
TB_ERR_NO_EVENT = -6
TB_ERR_NOT_INIT = -8
# struct tb_event: uint8_t type, uint8_t mod, uint16_t key, uint32_t ch, then int32_t w, h, x and y.
EVENT_BYTES = 24
# A wait with no timeout.
FOREVER = -1
MAX_TIMEOUT_MS = 2_147_483_647
# The longest wait of one tui_wait_event call (TUI_SLICE_MS of native/tui.c): a longer wait is several calls, so a
# close ends it soon and the VM never waits long for the call to return.
SLICE_MS = 50

# Waits in calls of at most SLICE_MS, checking between them that the screen is open. An event termbox2 does not
# make (Ev.decode gives none) is skipped.
def wait_event(screen: Screen, timeout_ms: Int) -> Result[Optional[Ev.Event]]
  deadline = Time.monotonic_ms() + timeout_ms
  Native.memory_pointer(EVENT_BYTES) do |buffer|
    while true
      # A close between this test and the call stops the task with RUNTIME-NATIVE-CLOSED (a rare race).
      return error("tui: the screen is closed") if Native.closed?(screen)

      code = tui_wait_event(screen, buffer, slice(deadline, timeout_ms))
      if code == TB_OK
        found = Ev.decode(read_event(buffer))
        return ok(found) if found.some?
      elsif code == TB_ERR_NOT_INIT
        return error("tui: the screen is closed")
      elsif code != TB_ERR_NO_EVENT
        return error(failure("wait_event", code))
      end

      return ok(none) if timeout_ms != FOREVER and Time.monotonic_ms() >= deadline
    end

    ok(none)
  end
end

def slice(deadline: Int, timeout_ms: Int) -> Int
  left = deadline - Time.monotonic_ms()
  if timeout_ms == FOREVER or left > SLICE_MS
    return SLICE_MS
  elsif left < 0
    return 0
  end

  left
end

def read_event(buffer: C.Pointer) -> Ev.Raw
  Ev.Raw(
    kind: Native.get_uint8(buffer, 0),
    mod: Native.get_uint8(buffer, 1),
    key: Native.get_uint16(buffer, 2),
    ch: Native.get_uint32(buffer, 4),
    width: Native.get_int32(buffer, 8),
    height: Native.get_int32(buffer, 12),
    x: Native.get_int32(buffer, 16),
    y: Native.get_int32(buffer, 20),
  )
end

def check(what: String, code: Int) -> Result[Void]
  return error(failure(what, code)) if code < TB_OK

  ok()
end

def failure(what: String, code: Int) -> String = "tui: #{what} failed: #{tui_strerror(code)} (#{code})"
