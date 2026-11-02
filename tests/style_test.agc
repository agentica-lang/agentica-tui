import St from "../src/style"

# termbox2.h: TB_HI_BLACK, TB_BOLD and TB_UNDERLINE with 64-bit attributes.
HI_BLACK = 0x2000_0000
BOLD = 0x0100_0000
UNDERLINE = 0x0200_0000

def main() -> Void
  Test.run([
    Test.test("named colors use the values of output mode Normal") do
      try Test.eq(St.color_value(St.Color.Default), ok(0))
      try Test.eq(St.color_value(St.Color.Black), ok(1))
      Test.eq(St.color_value(St.Color.White), ok(8))
    end,
    Test.test("palette and true colors, black as TB_HI_BLACK") do
      try Test.eq(St.color_value(St.Color.Index(196)), ok(196))
      try Test.eq(St.color_value(St.Color.Index(0)), ok(HI_BLACK))
      try Test.eq(St.color_value(St.Color.Rgb(255, 128, 0)), ok(0xff8000))
      Test.eq(St.color_value(St.Color.Rgb(0, 0, 0)), ok(HI_BLACK))
    end,
    Test.test("colors out of range") do
      try Test.eq(St.color_value(St.Color.Index(256)), error("tui: color index out of range 0..255: 256"))
      Test.eq(St.color_value(St.Color.Rgb(0, -1, 0)), error("tui: color channel out of range 0..255: -1"))
    end,
    Test.test("attributes go on the foreground") do
      style = St.Style(fg: St.Color.Red, bg: St.Color.Blue, attrs: [St.Attr.Bold, St.Attr.Underline])
      try Test.eq(St.fg_value(style), ok(2 + BOLD + UNDERLINE))
      try Test.eq(St.bg_value(style), ok(5))
      Test.eq(St.fg_value(St.Style(attrs: [St.Attr.Invisible])), ok(0x8_0000_0000))
    end,
    Test.test("output modes") do
      try Test.eq(St.output_mode_value(St.OutputMode.Normal), 1)
      try Test.eq(St.output_mode_value(St.OutputMode.Colors256), 2)
      Test.eq(St.output_mode_value(St.OutputMode.Truecolor), 5)
    end,
  ])
end
