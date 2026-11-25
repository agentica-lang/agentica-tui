import St from "../src/style"

def main() -> Void
  Test.run([
    Test.test("merge puts the colors that are set on top and keeps the attributes of both") do
      base = St.Style(fg: St.Color.Red, bg: St.Color.Blue, bold: true, attrs: [St.Attr.Blink])
      over = St.Style(fg: St.Color.Green, underline: true, attrs: [St.Attr.Blink, St.Attr.Overline])
      merged = St.Style(
        fg: St.Color.Green,
        bg: St.Color.Blue,
        bold: true,
        underline: true,
        attrs: [St.Attr.Blink, St.Attr.Overline],
      )

      try Test.eq(St.merge(base, over), merged)
      Test.eq(St.merge(over, St.Style()), over)
    end,
  ])
end
