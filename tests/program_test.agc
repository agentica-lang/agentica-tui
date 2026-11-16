import Bd from "../src/backend"
import Ev from "../src/event"
import Fk from "../src/fake"
import Pg from "../src/program"
import St from "../src/style"
import View from "../src/view"
import Width from "../src/width"

WAIT_MS = 5000
FRAMES = 300

enum Msg
  Key(Ev.Event)
  Tick
  Done
end

def main() -> Void
  Test.run([
    Test.test("keys reach update, the view is drawn and a quit gives the model and restores the modes") do
      fake = Fk.new(10, 2)
      runner = Task.spawn do Pg.program(Fk.backend(fake), counter([])) end
      try sent(fake, [char("a"), char("a")])
      calls = try seen(fake, [], ->(rows: List[String]) { rows[0] == "2 keys" })
      try sent(fake, [char("q")])
      try Test.eq(Task.await(runner), ok(2))
      calls = calls + Fk.calls(fake)
      try Test.eq(calls.first, Fk.Call.Modes(Bd.Modes()))
      Test.eq(calls.last, Fk.Call.Restored)
    end,
    Test.test("a resize clears the screen and draws it again at the new size") do
      fake = Fk.new(10, 2)
      runner = Task.spawn do Pg.program(Fk.backend(fake), counter([])) end
      first = try seen(fake, [], ->(rows: List[String]) { rows[0] == "0 keys" })
      try Fk.resize(fake, 6, 3)
      calls = try seen(fake, first, ->(rows: List[String]) { rows[0] == "1 keys" })
      try Test.eq(Fk.screen(fake), ["1 keys", "", ""])
      try sent(fake, [char("q")])
      _ = Task.await(runner)
      Test.eq(calls.select { |call| call == Fk.Call.Cleared }.size, 2)
    end,
    Test.test("the screen shows wide characters, the styles and the cursor the program places") do
      fake = Fk.new(6, 2)
      bold = St.Style(fg: St.Color.Red, attrs: [St.Attr.Bold])
      app = Pg.App(
        model: "中文",
        update: ->(text: String, msg: Msg) { Pg.Step(model: "#{text}x", cmds: quit_on_done(msg)) },
        view: ->(text: String) { View.text(text, bold) },
        subscriptions: ->(_text: String) { [Pg.Sub.Events(->(event) { Msg.Key(event) })] },
        cursor: some(->(text: String) { cursor_after(text) }),
      )

      runner = Task.spawn do Pg.program(Fk.backend(fake), app) end
      try Fk.wait_for(fake, ->(rows: List[String]) { rows[0] == "中文" })
      try Test.eq(Fk.style_at(fake, 1, 0), some(bold))
      try Test.eq(Fk.style_at(fake, 6, 0), none)
      try Test.eq(Fk.cursor(fake), none)
      try sent(fake, [char("a")])
      try Fk.wait_for(fake, ->(rows: List[String]) { rows[0] == "中文x" })
      try Test.eq(Fk.cursor(fake), some(Bd.Cursor(x: 5, y: 0)))
      try sent(fake, [Ev.Event.Paste("done")])
      Test.eq(Task.await(runner), ok("中文xx"))
    end,
    Test.test("the screen is read after each of 300 frames on 80 by 24 within the step budget") do
      fake = Fk.new(80, 24)
      runner = Task.spawn do Pg.program(Fk.backend(fake), counter([])) end
      for count in 1..FRAMES
        try sent(fake, [char("a")])
        try Fk.wait_for(fake, ->(rows: List[String]) { rows[0] == "#{count} keys" })
      end

      try sent(fake, [char("q")])
      Test.eq(Task.await(runner), ok(FRAMES))
    end,
    Test.test("the screen and the cursor show what was drawn once it is presented") do
      fake = Fk.new(4, 1)
      backend = Fk.backend(fake)
      try backend.draw.call([View.Cell(x: 0, y: 0, char: "a", style: St.Style())])
      try backend.set_cursor.call(1, 0)
      try Test.eq(Fk.screen(fake), [""])
      try Test.eq(Fk.cursor(fake), none)
      try backend.present.call()
      try Test.eq(Fk.screen(fake), ["a"])
      Test.eq(Fk.cursor(fake), some(Bd.Cursor(x: 1, y: 0)))
    end,
    Test.test("a full call buffer gives an error that says how to read it") do
      fake = Fk.new(1, 1)
      while fake.calls.send(Fk.Call.Presented, 0).ok?
        next
      end

      result = Fk.backend(fake).present.call()
      Test.assert(result.message.include?("Testing.calls"), "a call past the buffer is an error")
    end,
    Test.test("ticks come while the subscriptions ask for them, and a command gives its message") do
      fake = Fk.new(10, 1)
      try Test.eq(Pg.program(Fk.backend(fake), counter([Pg.Sub.Tick(10, Msg.Tick)])), ok(3))
      app = counter([]).with(cmds: [Pg.Cmd.Run(-> { Msg.Done })])
      Test.eq(Pg.program(Fk.backend(fake), app), ok(100))
    end,
    Test.test("a terminal that is gone ends the program with an error, and the modes are still restored") do
      fake = Fk.new(10, 1)
      fake.events.close
      try Test.eq(Pg.program(Fk.backend(fake), counter([])), error("tui: the fake terminal is closed"))
      Test.eq(Fk.calls(fake).last, Fk.Call.Restored)
    end,
  ])
end

# Counts the keys and the ticks: q quits, the third tick quits, and Done quits with 100.
def counter(more: List[Pg.Sub[Msg]]) -> Pg.App[Int, Msg]
  Pg.App(
    model: 0,
    update: &update,
    view: ->(count: Int) { View.text("#{count} keys") },
    subscriptions: ->(_count: Int) { [Pg.Sub.Events(->(event) { Msg.Key(event) })] + more },
  )
end

def update(count: Int, msg: Msg) -> Pg.Step[Int, Msg]
  case msg
    Msg.Key(Ev.Event.Char("q", _)) -> Pg.Step(model: count, cmds: [Pg.Cmd.Quit])
    Msg.Key(_) -> Pg.Step(model: count + 1)
    Msg.Tick if count == 2 -> Pg.Step(model: 3, cmds: [Pg.Cmd.Quit])
    Msg.Tick -> Pg.Step(model: count + 1)
    Msg.Done -> Pg.Step(model: 100, cmds: [Pg.Cmd.Quit])
  end
end

def quit_on_done(msg: Msg) -> List[Pg.Cmd[Msg]]
  case msg
    Msg.Key(Ev.Event.Paste(_)) -> [Pg.Cmd.Quit]
    _ -> []
  end
end

# No cursor before the first key, then after the text.
def cursor_after(text: String) -> Optional[Bd.Cursor]
  return none if text == "中文"

  some(Bd.Cursor(x: Width.text(text), y: 0))
end

def char(c: String) -> Ev.Event = Ev.Event.Char(c, Ev.Mods())

def sent(fake: Fk.Fake, events: List[Ev.Event]) -> Result[Void]
  for event in events
    try fake.events.send(event, WAIT_MS)
  end

  ok()
end

# The calls after `before` until the screen shows what `done` wants.
def seen(fake: Fk.Fake, before: List[Fk.Call], done: Fn[List[String], Bool]) -> Result[List[Fk.Call]]
  calls = before
  while not done.call(Fk.rows(fake, calls))
    more = Fk.calls(fake, WAIT_MS)
    return error("no call in #{WAIT_MS} ms") if more.empty?

    calls = calls + more
  end

  ok(calls)
end
