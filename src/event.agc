## Input events: keys, characters, mouse, resize and paste.

## The modifier keys held with a key or a mouse event. `motion` is a mouse move with a button down.
struct Mods
  alt: Bool = false
  ctrl: Bool = false
  shift: Bool = false
  motion: Bool = false
end

## A key that is not a character.
enum Key
  Up
  Down
  Left
  Right
  Enter
  Escape
  Tab
  BackTab
  Backspace
  Insert
  Delete
  Home
  End
  PageUp
  PageDown
  ## A function key, 1 to 12.
  F(Int)
  ## Ctrl and a character in caret notation, lowercase for a letter: `Ctrl("c")`, `Ctrl("@")`.
  Ctrl(String)
  ## A key the backend reads but this library does not name, by the backend's code for it.
  Other(Int)
end

## A mouse button, or the wheel.
enum Mouse
  Left
  Right
  Middle
  Release
  WheelUp
  WheelDown
end

## An input event.
enum Event
  Key(Key, Mods)
  ## A typed character (a space too), with the modifiers.
  Char(String, Mods)
  ## A mouse button at the cell x, y (columns and rows from 0).
  Mouse(Mouse, Int, Int, Mods)
  ## The new width and height of the terminal.
  Resize(Int, Int)
  ## Pasted text, whole: the keys in it never come as `Key` or `Char` events. Line ends are `\n`.
  Paste(String)
end

## How a lone Escape byte is read: as `Key.Escape` (`Esc`, the default) or as Alt held with the next key (`Alt`).
enum InputMode
  Esc
  Alt
end
