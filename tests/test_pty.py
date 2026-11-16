"""End-to-end tests: Agentica programs under a pseudo-terminal.

Each test starts a program of tests/fixtures/ with the slave side of a new
pty as its controlling terminal (termbox2 opens /dev/tty), writes keys to the
master side and reads what the program sends to the screen. Standard library
only; `make native` must have built the library first. AGENTICA names the
binary (default: agentica on PATH).
"""

import fcntl
import os
import re
import select
import struct
import subprocess
import termios
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures"
AGENTICA = os.environ.get("AGENTICA", "agentica")
TIMEOUT = 10.0

# What termbox2 sends for xterm: enter and leave the alternate screen.
ENTER_SCREEN = b"\x1b[?1049h"
LEAVE_SCREEN = b"\x1b[?1049l"


# An escape sequence: CSI (ESC [ ... final byte) or ESC and one or two bytes.
ESCAPE = re.compile(r"\x1b(\[[0-?]*[ -/]*[@-~]|[()][0-9A-Za-z]|.)")


def set_size(fd: int, rows: int, cols: int) -> None:
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def screen_rows(output: bytes, rows: int = 24, cols: int = 80) -> list[str]:
    """The text a terminal shows after `output`: only what termbox2 sends to
    draw cells (cursor moves `ESC [ row ; col H`, clears, characters)."""
    grid = [[" "] * cols for _ in range(rows)]
    row = col = 0
    text = output.decode(errors="replace")
    at = 0
    while at < len(text):
        match = ESCAPE.match(text, at)
        if match:
            sequence = match.group(1)
            if sequence.endswith("H") and sequence.startswith("["):
                parts = (sequence[1:-1] or "1;1").split(";")
                row, col = int(parts[0]) - 1, int(parts[1]) - 1
            elif sequence == "[2J":
                grid = [[" "] * cols for _ in range(rows)]
            at = match.end()
            continue
        char = text[at]
        if char >= " " and row < rows and col < cols:
            grid[row][col] = char
            col += 1
        at += 1
    return ["".join(line).rstrip() for line in grid]


class Terminal:
    """A program running on a new pty of 80x24 with TERM=xterm."""

    def __init__(self, program: Path) -> None:
        self.master, self.slave = os.openpty()
        set_size(self.slave, 24, 80)
        self.modes_before = termios.tcgetattr(self.slave)
        self.output = b""
        self.process = subprocess.Popen(
            [AGENTICA, str(program)],
            cwd=ROOT,
            stdin=self.slave,
            stdout=self.slave,
            stderr=self.slave,
            env=dict(os.environ, TERM="xterm"),
            preexec_fn=self._own_terminal,
        )

    @staticmethod
    def _own_terminal() -> None:
        # A new session whose controlling terminal is the slave (stdin).
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    def wait_for_row(self, row: int, text: str) -> None:
        """Reads until row `row` of the screen starts with `text`."""
        deadline = time.monotonic() + TIMEOUT
        while True:
            screen = self.output[self.output.rfind(ENTER_SCREEN) :]
            shown = screen_rows(screen)[row]
            if shown.startswith(text):
                return
            if time.monotonic() > deadline:
                raise AssertionError(f"row {row} is {shown!r}, not {text!r}")
            self._read(0.05)

    def wait_for(self, data: bytes, start: int = 0) -> int:
        """Reads until `data` appears after offset `start`; gives the offset after it."""
        deadline = time.monotonic() + TIMEOUT
        while data not in self.output[start:]:
            if time.monotonic() > deadline:
                raise AssertionError(f"no {data!r} in {self.output[start:]!r}")
            self._read(0.05)
        return self.output.index(data, start) + len(data)

    def send(self, data: bytes) -> None:
        os.write(self.master, data)

    def finish(self) -> int:
        """Waits for the exit and reads the rest of the output; gives the exit code."""
        code = self.process.wait(TIMEOUT)
        while self._read(0.1):
            pass
        return code

    def close(self) -> None:
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        os.close(self.master)
        os.close(self.slave)

    def _read(self, wait: float) -> bool:
        ready, _, _ = select.select([self.master], [], [], wait)
        if not ready:
            return False
        chunk = os.read(self.master, 65536)
        self.output += chunk
        return bool(chunk)


class PtyTest(unittest.TestCase):
    def start(self, fixture: str) -> Terminal:
        terminal = Terminal(FIXTURES / fixture)
        self.addCleanup(terminal.close)
        return terminal

    def test_the_box_example_moves_with_the_arrow_keys(self) -> None:
        term = Terminal(ROOT / "examples" / "box.agc")
        self.addCleanup(term.close)
        term.wait_for_row(0, "size 80x24  last none")
        term.wait_for_row(2, "  ┌──────────┐")
        term.send(b"\x1bOC")
        term.wait_for_row(0, "size 80x24  last key Key.Right")
        term.wait_for_row(2, "   ┌──────────┐")
        term.send(b"q")

        self.assertEqual(term.finish(), 0)
        self.assertIn(b"bye", term.output[term.output.rindex(LEAVE_SCREEN) :])

    def test_the_view_example_renders_a_tree(self) -> None:
        term = Terminal(ROOT / "examples" / "view.agc")
        self.addCleanup(term.close)
        term.wait_for_row(0, "┌" + "─" * 78 + "┐")
        term.wait_for_row(3, "│ count: 0")
        term.wait_for_row(23, " " * 58 + "+ and - count, q quits")
        term.send(b"+")
        term.wait_for_row(3, "│ count: 1")
        term.send(b"q")

        self.assertEqual(term.finish(), 0)

    def test_the_loop_ticks_runs_commands_and_quits(self) -> None:
        term = self.start("loop.agc")
        term.wait_for_row(0, "ticks 3")
        # The subscription to the ticks ends at 3.
        term._read(0.3)
        self.assertEqual(screen_rows(term.output[term.output.rfind(ENTER_SCREEN) :])[0], "ticks 3")
        term.send(b"r")
        term.wait_for_row(1, "ran done")
        term.send(b"q")

        self.assertEqual(term.finish(), 0)
        self.assertIn(b"ticks 3, ran done", term.output[term.output.rindex(LEAVE_SCREEN) :])

    def test_a_crash_in_a_command_ends_the_loop_with_an_error(self) -> None:
        term = self.start("loop.agc")
        term.wait_for_row(0, "ticks 3")
        term.send(b"x")

        self.assertEqual(term.finish(), 1)
        self.assertIn(b"RUNTIME-INDEX-OUT-OF-RANGE", term.output[term.output.rindex(LEAVE_SCREEN) :])

    def test_events_are_decoded_and_the_terminal_restored(self) -> None:
        term = self.start("events.agc")
        term.wait_for_row(0, "ready 80x24")
        steps = [
            (b"\x1bOA", "Event.Key(Key.Up"),  # xterm in keypad mode, as termbox2 sets it
            (b"\x1bOD", "Event.Key(Key.Left"),
            (b"a", 'Event.Char("a"'),
            ("ñ".encode(), 'Event.Char("ñ"'),
            (b"\x03", 'Event.Key(Key.Ctrl("c")'),
            (b"\r", "Event.Key(Key.Enter"),
            (b"\x1bOS", "Event.Key(Key.F(4)"),
            (b"\x1b[<0;5;3M", "Event.Mouse(Mouse.Left, 4, 2"),  # SGR mouse, 1-based
        ]
        for keys, shown in steps:
            term.send(keys)
            term.wait_for_row(0, shown)
        set_size(term.master, 30, 100)
        term.wait_for_row(0, "Event.Resize(100, 30)")
        term.send(b"q")

        self.assertEqual(term.finish(), 0)
        after = term.output[term.output.rindex(LEAVE_SCREEN) :]
        lines = ESCAPE.sub("", after.decode()).split("\r\n")[:-1]
        mods = "Mods(alt: false, ctrl: {}, shift: false, motion: false)"
        plain, ctrl = mods.format("false"), mods.format("true")
        self.assertEqual(
            lines,
            [
                "peek none",
                f"Event.Key(Key.Up, {plain})",
                f"Event.Key(Key.Left, {plain})",
                f'Event.Char("a", {plain})',
                f'Event.Char("ñ", {plain})',
                f'Event.Key(Key.Ctrl("c"), {ctrl})',
                f"Event.Key(Key.Enter, {plain})",
                f"Event.Key(Key.F(4), {plain})",
                f"Event.Mouse(Mouse.Left, 4, 2, {plain})",
                "Event.Resize(100, 30)",
            ],
        )
        self.assertEqual(termios.tcgetattr(term.slave), term.modes_before)

    def test_a_paste_is_one_event_and_its_keys_never_arrive(self) -> None:
        term = self.start("events.agc")
        term.wait_for_row(0, "ready 80x24")
        self.assertIn(b"\x1b[?2004h", term.output)
        term.send(b"\x1b[200~hi \x03q\x1bOA\r")
        time.sleep(0.2)
        term.send("ñ\x1b[201~".encode())
        term.wait_for_row(0, "Event.Paste(")
        term.send(b"q")

        self.assertEqual(term.finish(), 0)
        after = term.output[term.output.rindex(LEAVE_SCREEN) - 64 :]
        self.assertIn(b"\x1b[?2004l", after)
        lines = ESCAPE.sub("", after[after.index(LEAVE_SCREEN) :].decode()).split("\r\n")[:-1]
        self.assertEqual(lines, ["peek none", 'Event.Paste("hi \\u0003q\\eOA\\nñ")'])

    def test_a_paste_with_no_end_mark_ends_after_two_quiet_seconds(self) -> None:
        term = self.start("paste.agc")
        term.wait_for_row(0, "ready")
        term.send(b"\x1b[200~abc")
        term.wait_for_row(0, 'paste 3 "abc"')
        term.send(b"q")

        self.assertEqual(term.finish(), 0)

    def test_a_paste_over_the_cap_keeps_its_first_mib_and_no_key_arrives(self) -> None:
        term = self.start("paste.agc")
        term.wait_for_row(0, "ready")
        term.send(b"\x1b[200~")
        for chunk in [b"x" * 65536] * 16 + [b"a\r\x03" * 20000]:
            term.send(chunk)
            term._read(0)
        term.send(b"\x1b[201~")
        term.wait_for_row(0, f'paste {1024 * 1024} "xxxxxxxx"')
        term.send(b"\x1b[201~z")
        term.wait_for_row(0, 'Event.Char("z"')
        term.send(b"q")

        self.assertEqual(term.finish(), 0)
        after = term.output[term.output.rindex(LEAVE_SCREEN) :]
        lines = ESCAPE.sub("", after.decode()).split("\r\n")[:-1]
        plain = "Mods(alt: false, ctrl: false, shift: false, motion: false)"
        self.assertEqual(lines, [f'paste {1024 * 1024} "xxxxxxxx"', f'Event.Char("z", {plain})'])

    def test_a_large_paste_is_read_in_linear_time(self) -> None:
        term = self.start("paste.agc")
        term.wait_for_row(0, "ready")
        size = 900 * 1024
        started = time.monotonic()
        term.send(b"\x1b[200~")
        for at in range(0, size, 4096):
            term.send(b"x" * min(4096, size - at))
            term._read(0)
        term.send(b"\x1b[201~")
        term.wait_for_row(0, f'paste {size} "xxxxxxxx"')
        self.assertLess(time.monotonic() - started, 5.0)
        term.send(b"q")

        self.assertEqual(term.finish(), 0)

    def test_a_mouse_report_keeps_the_input_after_it(self) -> None:
        term = self.start("events.agc")
        term.wait_for_row(0, "ready 80x24")
        writes = [
            (b"\x1b[<0;5;3Ma", 'Event.Char("a"'),
            (b"\x1b[<0;5;3M\x1b[<0;6;4m", "Event.Mouse(Mouse.Release, 5, 3"),
            (b"\x1b[<2;1;1M\x1b[200~hi\x1b[201~", 'Event.Paste("hi")'),
            (b"\x1b[32;7;8M\x1b[5;6;7Xb", 'Event.Char("b"'),
        ]
        for data, shown in writes:
            term.send(data)
            term.wait_for_row(0, shown)
        term.send(b"q")

        self.assertEqual(term.finish(), 0)
        after = term.output[term.output.rindex(LEAVE_SCREEN) :]
        lines = ESCAPE.sub("", after.decode()).split("\r\n")[:-1]
        plain = "Mods(alt: false, ctrl: false, shift: false, motion: false)"
        self.assertEqual(
            lines,
            [
                "peek none",
                f"Event.Mouse(Mouse.Left, 4, 2, {plain})",
                f'Event.Char("a", {plain})',
                f"Event.Mouse(Mouse.Left, 4, 2, {plain})",
                f"Event.Mouse(Mouse.Release, 5, 3, {plain})",
                f"Event.Mouse(Mouse.Right, 0, 0, {plain})",
                'Event.Paste("hi")',
                f"Event.Mouse(Mouse.Left, 6, 7, {plain})",
                f'Event.Char("b", {plain})',
            ],
        )

    def test_a_mouse_report_split_across_reads_is_one_report(self) -> None:
        term = self.start("events.agc")
        term.wait_for_row(0, "ready 80x24")
        term.send(b"\x1b[<0;5;")
        time.sleep(0.2)
        term.send(b"3Ma")
        term.wait_for_row(0, 'Event.Char("a"')
        many = b"\x1b[<64;10;10M" * 6 + b"\x1b[<0;-5;3M\x1b[<0;999;999Ma"
        term.send(many)
        term.wait_for_row(0, 'Event.Char("a"')
        term.send(b"q")

        self.assertEqual(term.finish(), 0)
        after = term.output[term.output.rindex(LEAVE_SCREEN) :]
        lines = ESCAPE.sub("", after.decode()).split("\r\n")[:-1]
        plain = "Mods(alt: false, ctrl: false, shift: false, motion: false)"
        self.assertEqual(
            lines,
            ["peek none", f"Event.Mouse(Mouse.Left, 4, 2, {plain})", f'Event.Char("a", {plain})']
            + [f"Event.Mouse(Mouse.WheelUp, 9, 9, {plain})"] * 6
            + [f"Event.Mouse(Mouse.Left, 79, 23, {plain})", f'Event.Char("a", {plain})'],
        )

    def test_alt_bracket_and_a_letter_keep_the_letter(self) -> None:
        term = self.start("events.agc")
        term.wait_for_row(0, "ready 80x24")
        term.send(b"\x1b[x")
        term.wait_for_row(0, 'Event.Char("x"')
        term.send(b"q")

        self.assertEqual(term.finish(), 0)
        after = term.output[term.output.rindex(LEAVE_SCREEN) :]
        lines = ESCAPE.sub("", after.decode()).split("\r\n")[:-1]
        plain = "Mods(alt: false, ctrl: false, shift: false, motion: false)"
        self.assertEqual(
            lines,
            ["peek none", f"Event.Key(Key.Escape, {plain})", f'Event.Char("[", {plain})', f'Event.Char("x", {plain})'],
        )

    def test_cells_and_text_reach_the_screen_with_their_style(self) -> None:
        term = self.start("events.agc")
        term.wait_for_row(0, "ready 80x24")
        screen = term.output[term.output.index(ENTER_SCREEN) :]
        self.assertEqual(screen_rows(screen)[:3], ["ready 80x24", "  #", ""])
        # '#' is bold and red (output mode Normal: SGR 31).
        self.assertIn(b"\x1b[1m\x1b[31m\x1b[2;3H#", screen)
        term.send(b"q")
        self.assertEqual(term.finish(), 0)

    def test_a_crash_inside_open_restores_the_terminal_and_is_an_error(self) -> None:
        term = self.start("crash.agc")
        term.wait_for(b"drawn")

        self.assertEqual(term.finish(), 1)
        after = term.output[term.output.rindex(LEAVE_SCREEN) :]
        self.assertIn(b"task crashed: RUNTIME-INDEX-OUT-OF-RANGE", after)
        self.assertEqual(termios.tcgetattr(term.slave), term.modes_before)

    def test_an_exit_inside_open_still_restores_the_terminal(self) -> None:
        term = self.start("exit.agc")
        at = term.wait_for(b"drawn")

        self.assertEqual(term.finish(), 3)
        self.assertIn(LEAVE_SCREEN, term.output[at:])
        self.assertEqual(termios.tcgetattr(term.slave), term.modes_before)

    def test_a_second_open_fails_and_changes_nothing(self) -> None:
        term = self.start("twice.agc")

        self.assertEqual(term.finish(), 0)
        self.assertEqual(term.output.count(ENTER_SCREEN), 2)
        lines = ESCAPE.sub("", term.output[term.output.rindex(LEAVE_SCREEN) :].decode()).split("\r\n")
        self.assertEqual(lines[0], "before C")
        self.assertRegex(lines[1], r'^first ok\("error\(.*initialized already.*\) inside .*UTF-8"\)$')
        self.assertEqual(lines[2:], ["after C", 'again ok("drawn")', ""])
        self.assertEqual(termios.tcgetattr(term.slave), term.modes_before)

    def test_drawing_while_a_wait_runs_and_closing_ends_the_wait(self) -> None:
        term = self.start("background.agc")

        self.assertEqual(term.finish(), 0)
        screen = term.output[: term.output.rindex(LEAVE_SCREEN)]
        self.assertIn(b"\x1b[38;5;196m\x1b[1;1Hpalette", screen)
        self.assertIn(b"\x1b[38;2;255;128;0m\x1b[2;1Htrue color", screen)
        self.assertIn(b"\x1b[3;6H", screen)  # the cursor at column 5, row 2
        after = term.output[term.output.rindex(LEAVE_SCREEN) :]
        self.assertIn(b'waiter error("tui: the screen is closed")', after)
        self.assertEqual(termios.tcgetattr(term.slave), term.modes_before)

    def test_a_draw_after_the_close_is_refused(self) -> None:
        term = self.start("closed.agc")

        self.assertEqual(term.finish(), 1)
        after = term.output[term.output.rindex(LEAVE_SCREEN) :]
        self.assertIn(b"RUNTIME-NATIVE-CLOSED", after)
        self.assertNotIn(b"late", after)

    def test_open_without_a_terminal_is_an_error(self) -> None:
        result = subprocess.run(
            [AGENTICA, str(FIXTURES / "events.agc")],
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            start_new_session=True,
            timeout=TIMEOUT,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"tui: open failed", result.stderr)


if __name__ == "__main__":
    unittest.main()
