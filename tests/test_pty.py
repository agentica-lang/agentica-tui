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
