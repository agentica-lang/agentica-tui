## The terminal through termbox2 (native/termbox2/termbox2.h, built into libtermbox2 by `make native`): open it, draw
## cells and text into a back buffer, show the buffer, read input events.
##
## termbox2 keeps one terminal per process in global state: use a screen from one task at a time.

import Ev from "event"
import St from "style"

# termbox2.h return values.
TB_OK = 0
TB_ERR_NO_EVENT = -6
# struct tb_event: uint8_t type, uint8_t mod, uint16_t key, uint32_t ch, then int32_t w, h, x and y.
EVENT_BYTES = 24
# tb_poll_event: wait with no timeout.
FOREVER = -1
MAX_TIMEOUT_MS = 2_147_483_647

extern "termbox2"
  ## The open terminal. Closing it (`open` does) restores the terminal; so does the end of the program, a crash too.
  export resource Screen, free: tui_shutdown

  def tui_init(out screen: Screen) -> C.Int32
  compute def tui_wait_event(event: C.Pointer, timeout_ms: C.Int32) -> C.Int32
  def tb_width() -> C.Int32
  def tb_height() -> C.Int32
  def tb_clear() -> C.Int32
  def tb_set_clear_attrs(fg: C.Int64, bg: C.Int64) -> C.Int32
  def tb_present() -> C.Int32
  def tb_set_cell(x: C.Int32, y: C.Int32, ch: C.UInt32, fg: C.Int64, bg: C.Int64) -> C.Int32
  def tb_print_ex(x: C.Int32, y: C.Int32, fg: C.Int64, bg: C.Int64, out width: C.Int64, text: C.String) -> C.Int32
  def tb_set_cursor(x: C.Int32, y: C.Int32) -> C.Int32
  def tb_hide_cursor() -> C.Int32
  def tb_set_input_mode(mode: C.Int32) -> C.Int32
  def tb_set_output_mode(mode: C.Int32) -> C.Int32
  def tb_strerror(code: C.Int32) -> C.String
end

## Opens the terminal (full screen, raw input, no cursor), gives it to the block and closes it when the block ends,
## whatever it returns. Gives the block's result, an error when the terminal cannot be opened (no terminal, one
## already open), or `error("task crashed: ...")` when the block stops with a runtime error.
export def open[T](body: Fn[Screen, Result[T]]) -> Result[T]
  try Native.load("termbox2")
  opened = tui_init()
  if opened.result != TB_OK
    return error(failure("open", opened.result))
  end

  # The block runs in a task of its own so that a crash comes back as an error, which the caller can show once the
  # terminal is restored: the VM's own report of a crash may land on the screen, which closing then wipes.
  screen = opened.screen
  result = Task.await(Task.spawn do body.call(screen) end)
  Native.close(screen)
  return result
end

## The width of the terminal in columns. It changes after a `Resize` event, once the screen is cleared or shown.
export def width(screen: Screen) -> Int
  return tb_width()
end

## The height of the terminal in rows.
export def height(screen: Screen) -> Int
  return tb_height()
end

## Fills the back buffer with spaces of the style (default colors when left out).
export def clear(screen: Screen, style: St.Style = St.Style()) -> Result[Void]
  fg = try St.fg_value(style)
  bg = try St.bg_value(style)
  try check("clear", tb_set_clear_attrs(fg, bg))
  return check("clear", tb_clear())
end

## Sets the cell at column x, row y (from 0) to one character.
export def set_cell(screen: Screen, x: Int, y: Int, char: String, style: St.Style = St.Style()) -> Result[Void]
  if char.length != 1
    return error("tui: set_cell needs one character: #{char.inspect}")
  end

  fg = try St.fg_value(style)
  bg = try St.bg_value(style)
  return check("set_cell", tb_set_cell(x, y, char.code, fg, bg))
end

## Writes text from column x, row y; what goes past the right edge is cut. Gives the width of the text in columns.
## A start outside the screen is an error.
export def write(screen: Screen, x: Int, y: Int, text: String, style: St.Style = St.Style()) -> Result[Int]
  if text.include?(String.from_code(0))
    return error("tui: write cannot send a NUL character")
  end

  fg = try St.fg_value(style)
  bg = try St.bg_value(style)
  printed = tb_print_ex(x, y, fg, bg, text)
  try check("write", printed.result)
  return ok(printed.width)
end

## Shows the back buffer on the terminal: nothing drawn appears before this.
export def present(screen: Screen) -> Result[Void]
  return check("present", tb_present())
end

## Shows the cursor at column x, row y.
export def set_cursor(screen: Screen, x: Int, y: Int) -> Result[Void]
  return check("set_cursor", tb_set_cursor(x, y))
end

## Hides the cursor (as `open` leaves it).
export def hide_cursor(screen: Screen) -> Result[Void]
  return check("hide_cursor", tb_hide_cursor())
end

## Waits for the next event. Other tasks run meanwhile.
export def poll_event(screen: Screen) -> Result[Ev.Event]
  found = try wait_event(FOREVER)
  return found.to_result("tui: poll_event: no event")
end

## Waits up to timeout_ms milliseconds for an event: `none` when none came.
export def peek_event(screen: Screen, timeout_ms: Int) -> Result[Optional[Ev.Event]]
  if timeout_ms < 0 or timeout_ms > MAX_TIMEOUT_MS
    return error("tui: peek_event timeout out of range 0..#{MAX_TIMEOUT_MS}: #{timeout_ms}")
  end

  return wait_event(timeout_ms)
end

## Sets how Escape is read, and whether mouse events come.
export def set_input_mode(screen: Screen, mode: Ev.InputMode, mouse: Bool = false) -> Result[Void]
  return check("set_input_mode", tb_set_input_mode(Ev.input_mode_value(mode, mouse)))
end

## Sets how colors are sent (`Normal` at the start).
export def set_output_mode(screen: Screen, mode: St.OutputMode) -> Result[Void]
  return check("set_output_mode", tb_set_output_mode(St.output_mode_value(mode)))
end

def wait_event(timeout_ms: Int) -> Result[Optional[Ev.Event]]
  return Native.memory_pointer(EVENT_BYTES) do |buffer|
    code = tui_wait_event(buffer, timeout_ms)
    if code == TB_ERR_NO_EVENT
      return ok(none)
    end

    try check("wait_event", code)
    found = try Ev.decode(read_event(buffer))
    ok(some(found))
  end
end

def read_event(buffer: C.Pointer) -> Ev.Raw
  return Ev.Raw(
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
  if code < TB_OK
    return error(failure(what, code))
  end

  return ok()
end

def failure(what: String, code: Int) -> String
  return "tui: #{what} failed: #{tb_strerror(code)} (#{code})"
end
