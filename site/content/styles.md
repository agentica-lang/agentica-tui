---
title: Styles
weight: 5
description: Colors, attributes, output modes and merge.
---

A `Style` holds the colors and attributes of a cell or a text. Every field may be left out.

```agentica
import TUI from "pkg/tui/tui"

TITLE = TUI.Style(fg: TUI.Color.Yellow, bold: true)

def warning(text: String) -> TUI.Node
  TUI.text(text, TUI.merge(TITLE, TUI.Style(bg: TUI.Color.Red, underline: true)))
end
```

- `fg`, `bg`: a `Color`. `Default` is the terminal's own color. The eight named colors (`Black`, `Red`, `Green`, `Yellow`, `Blue`, `Magenta`, `Cyan`, `White`) are for output mode `Normal`; `Index(n)` (0 to 255) for `Colors256`; `Rgb(r, g, b)` (each 0 to 255) for `Truecolor`. A value out of range is an error when it is drawn.
- `bold`, `dim`, `italic`, `underline`, `reverse`: `Bool`.
- `attrs`: the attributes with no field of their own, from `Attr`: `Blink`, `Bright` (bright colors in mode `Normal`), `Strikeout`, `DoubleUnderline`, `Overline`, `Invisible`. Terminals show some of them only.

`TUI.App(..., output: mode)` picks how the terminal reads colors: `OutputMode.Normal`, `Colors256` or `Truecolor`.

## Merge

`TUI.merge(base, over)` puts `over` on top of `base`: the colors of `over` that are not `Default`, and the attributes of both. A [box](view-tree.md) merges its style under the styles inside it.
