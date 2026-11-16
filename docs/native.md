# Native library

The package calls termbox2 through the Agentica FFI. `native/termbox2/termbox2.h` is the termbox2 v2.5.0 release
file, unchanged: `native/termbox2/VERSION` has its tag, commit and sha256, and `make verify-vendor` checks it.
`native/tui.c` includes it and adds the `tui_*` functions that `src/termbox.agc` calls: the lock, the waits, the
bracketed paste and the mouse reports; its writes go on after a short write or an interrupt. A fix to termbox2's behavior goes in `native/tui.c`.

## The `.so`

`native/linux/libtermbox2.so` is committed, so `agentica add` and `agentica install` need no C compiler. It is
built on ubuntu-22.04 (glibc 2.35) and runs on glibc 2.33 or later. At this version its sha256 is
`dfb2731fce6b5b55cd7316977be9e094981b31b962dafa88fa9f4c6cdd063193`:

```sh
sha256sum native/linux/libtermbox2.so
```

The `native` job of CI builds `native/` again and fails unless the build is the committed file, byte for byte
(`make native-verify`). It uploads its build as the artifact `libtermbox2-linux-x86_64`.

## After a change of `native/`

1. `make native` rebuilds the library in place for local work. Do not commit it: it may need a newer glibc.
2. Push the change. The `native` job fails and uploads its build.
3. `gh run download RUN -n libtermbox2-linux-x86_64`, copy that file to `native/linux/libtermbox2.so`, and update
   its sha256 here and in the CHANGELOG.
4. Push again: CI is green when the committed file is the build of `native/`.

`make native-verify` on a machine whose gcc or glibc differs from ubuntu-22.04 fails and prints both sha256: only
the CI job is the judge.

Linux x86_64 only for now: there is no arm64, macOS or Windows library yet.
