## How many terminal columns text takes, as termbox2 draws it: glibc's wcwidth(3) for each code point (the table of
## `width_table.agc`), 0 for combining marks and zero-width joiners, 2 for wide ones; a character that is not
## printable is drawn as U+FFFD, one column. A ZWJ emoji sequence takes the columns of each emoji, as termbox2 draws
## it. Pure.

import Table from "width_table"

FIRST_TABLED = 0x300

def char(c: String) -> Int
  code = c.code
  return 1 if code < FIRST_TABLED

  Table.WIDTHS[run(code)]
end

def text(s: String) -> Int = s.split("").map { |c| char(c) }.sum

## The longest start of `s` that fits in `columns`, and the rest.
def cut(s: String, columns: Int) -> List[String]
  chars = s.split("")
  used = 0
  count = 0
  for c in chars
    used = used + char(c)
    break if used > columns

    count = count + 1
  end

  [s.slice(0, count), s.slice(count, s.length - count)]
end

private

# The index of the last start at or below `code`.
def run(code: Int) -> Int
  low = 0
  high = Table.STARTS.size - 1
  while low < high
    middle = (low + high + 1) / 2
    if Table.STARTS[middle] <= code
      low = middle
    else
      high = middle - 1
    end
  end

  low
end
