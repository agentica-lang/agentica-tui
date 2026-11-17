/* The termbox2 implementation plus the functions the Agentica bindings
 * (src/termbox.agc) call. Built by `make native`.
 *
 * termbox2 keeps one terminal in global state and is not thread-safe, while
 * the VM runs tasks on several threads: a draw from one task and a wait for
 * input on a compute pool thread can run at once. So every function here
 * takes one mutex around its termbox2 calls, and tui_wait_event never holds
 * it while it sleeps. Every function but tui_init takes the screen token: the
 * VM then refuses a call after the screen is closed (RUNTIME-NATIVE-CLOSED)
 * and never frees the screen during a call. */

#include <errno.h>
#include <unistd.h>

/* termbox2 sends its output with one write(2) and gives up on a short one
 * (an EINTR from SIGWINCH during a large redraw on a slow terminal), keeping
 * the whole buffer: a second try would send its first bytes twice, in the
 * colors termbox2 thinks the terminal already has. So its writes go through
 * tui_write_all, which writes the rest after a partial write and tries again
 * after an EINTR; it is async-signal-safe, as termbox2's signal handler
 * writes too. */
static ssize_t tui_write_all(int fd, const void *buf, size_t len) {
    const char *at = buf;
    size_t left = len;
    while (left > 0) {
        ssize_t wrote = write(fd, at, left);
        if (wrote < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        at += wrote;
        left -= (size_t)wrote;
    }
    return (ssize_t)len;
}

#define write tui_write_all
#define TB_IMPL
#define TB_LIB_OPTS
#include "termbox2/termbox2.h"
#undef write

#include <langinfo.h>
#include <locale.h>
#include <pthread.h>
#include <time.h>

/* The longest wait of one tui_wait_event call, so that the Agentica side
 * sees a close soon and the VM never waits long for a call to end. */
#define TUI_SLICE_MS 50
/* The tty readable with no byte to read this many times in a row is its end
 * (a hang-up): termbox2 would read nothing and try again forever. */
#define TUI_EOF_HITS 3

static pthread_mutex_t tui_lock = PTHREAD_MUTEX_INITIALIZER;
/* Under tui_lock: tui_init opened the terminal and tui_shutdown did not close
 * it yet. */
static int tui_opened;

/* The address that stands for the open terminal: the Agentica resource Screen
 * needs a non-NULL pointer. */
static int tui_screen;

/* Bracketed paste: the terminal sends a paste between these, and
 * tui_wait_event gives it as one event of kind TUI_EVENT_PASTE, with its text
 * in tui_paste_text (under tui_lock, kept until the next paste). A paste
 * keeps its first TUI_PASTE_MAX bytes and drops the rest up to its end mark.
 * One with no end mark ends after TUI_PASTE_IDLE_MS with no new byte and
 * nothing waiting to be read. A lone end mark is dropped (an event of kind
 * TUI_EVENT_NONE, which the Agentica side skips). */
#define TUI_EVENT_PASTE 100
#define TUI_EVENT_NONE 101
#define TUI_PASTE_MAX (1024 * 1024)
#define TUI_PASTE_IDLE_MS 2000
static const char tui_paste_start[] = "\x1b[200~";
static const char tui_paste_end[] = "\x1b[201~";
#define TUI_PASTE_MARK (sizeof(tui_paste_start) - 1)
static char *tui_paste_text;
static size_t tui_paste_len;
/* The paste that has no end mark yet: the input length the scan reached, and
 * when that length last grew. */
static size_t tui_paste_scanned;
static long long tui_paste_grew_ms;
/* The paste passed TUI_PASTE_MAX: its first bytes are in tui_paste_text, and
 * the input keeps only the start mark and the bytes that may begin the end
 * mark. */
static int tui_paste_draining;

static long long now_ms(void);

/* The LC_CTYPE that tui_init replaced, put back by tui_shutdown. */
static char tui_saved_ctype[64];

static int utf8_ctype(void) {
    return strcmp(nl_langinfo(CODESET), "UTF-8") == 0;
}

/* termbox2 measures characters with wcwidth(3), which knows only ASCII in the
 * C locale (the VM never sets one): pick a UTF-8 LC_CTYPE, the user's first.
 * setlocale is process-wide, so the whole program has this LC_CTYPE while the
 * screen is open. */
static void use_utf8_ctype(void) {
    static const char *const names[] = {"", "C.UTF-8", "en_US.UTF-8", "UTF-8"};
    const char *old = setlocale(LC_CTYPE, NULL);
    snprintf(tui_saved_ctype, sizeof(tui_saved_ctype), "%s", old ? old : "C");
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        if (setlocale(LC_CTYPE, names[i]) && utf8_ctype()) {
            return;
        }
    }
    setlocale(LC_CTYPE, tui_saved_ctype);
}

static void send_now(const char *sequence) {
    bytebuf_puts(&global.out, sequence);
    bytebuf_flush(&global.out, global.wfd);
}

/* termbox2's hook before it reads an escape sequence: a whole paste, from its
 * start mark to its end mark, is one event, so that no key inside it is read
 * as a key. Called under tui_lock (from tb_peek_event). */
static int paste_event(struct tb_event *event, size_t *consumed, int type, size_t used) {
    tui_paste_scanned = 0;
    tui_paste_draining = 0;
    event->type = type;
    event->mod = 0;
    event->key = 0;
    event->ch = 0;
    *consumed = used;
    return TB_OK;
}

/* Keeps `len` bytes after the start mark as the paste text. */
static int keep_paste(size_t len) {
    char *text = realloc(tui_paste_text, len + 1);
    if (!text) {
        tui_paste_scanned = 0;
        tui_paste_draining = 0;
        return TB_ERR_MEM;
    }
    memcpy(text, global.in.buf + TUI_PASTE_MARK, len);
    text[len] = '\0';
    tui_paste_text = text;
    tui_paste_len = len;
    return TB_OK;
}

static int take_paste(struct tb_event *event, size_t *consumed, size_t len, size_t used) {
    if (!tui_paste_draining) {
        int rv = keep_paste(len);
        if (rv != TB_OK) {
            return rv;
        }
    }
    return paste_event(event, consumed, TUI_EVENT_PASTE, used);
}

static int nothing_waiting(void) {
    int pending = 0;
    return ioctl(global.rfd, FIONREAD, &pending) == 0 && pending == 0;
}

static int prefix_of(const char *mark, const struct bytebuf_t *in) {
    return memcmp(in->buf, mark, in->len) == 0;
}

static int extract_paste(struct tb_event *event, size_t *consumed) {
    struct bytebuf_t *in = &global.in;
    size_t mark = TUI_PASTE_MARK;
    if (in->len < mark) {
        return prefix_of(tui_paste_start, in) || prefix_of(tui_paste_end, in) ? TB_ERR_NEED_MORE : TB_ERR;
    }
    if (memcmp(in->buf, tui_paste_end, mark) == 0) {
        return paste_event(event, consumed, TUI_EVENT_NONE, mark);
    }
    if (memcmp(in->buf, tui_paste_start, mark) != 0) {
        return TB_ERR;
    }
    /* Each byte is scanned once: an end mark that starts before
     * tui_paste_scanned - mark + 1 would have been found already. */
    size_t from = mark;
    if (tui_paste_scanned > mark && tui_paste_scanned - mark + 1 > from) {
        from = tui_paste_scanned - mark + 1;
    }
    for (size_t at = from; at + mark <= in->len; at++) {
        if (memcmp(in->buf + at, tui_paste_end, mark) == 0) {
            size_t len = at - mark < TUI_PASTE_MAX ? at - mark : TUI_PASTE_MAX;
            return take_paste(event, consumed, len, at + mark);
        }
    }
    long long now = now_ms();
    if (in->len != tui_paste_scanned || !nothing_waiting()) {
        tui_paste_grew_ms = now;
    }
    if (!tui_paste_draining && in->len - mark >= TUI_PASTE_MAX) {
        int rv = keep_paste(TUI_PASTE_MAX);
        if (rv != TB_OK) {
            return rv;
        }
        tui_paste_draining = 1;
    }
    if (tui_paste_draining) {
        size_t keep = in->len - mark < mark - 1 ? in->len - mark : mark - 1;
        memmove(in->buf + mark, in->buf + in->len - keep, keep);
        in->len = mark + keep;
    }
    tui_paste_scanned = in->len;
    if (now - tui_paste_grew_ms >= TUI_PASTE_IDLE_MS) {
        return take_paste(event, consumed, in->len - mark, in->len);
    }
    return TB_ERR_NEED_MORE;
}

/* A CSI sequence longer than this with no final byte is dropped. */
#define TUI_CSI_MAX 32

/* The end of the CSI sequence at the start of `in` (after its final byte):
 * 1 when it is whole, 0 when more bytes may come, -1 when a byte that has no
 * place in a CSI cuts it at `end`. */
static int csi_end(const struct bytebuf_t *in, size_t *end) {
    for (size_t i = 2; i < in->len; i++) {
        unsigned char c = (unsigned char)in->buf[i];
        if (c >= 0x40 && c <= 0x7e) {
            *end = i + 1;
            return 1;
        }
        if (c < 0x20 || c > 0x3f) {
            *end = i;
            return -1;
        }
    }
    *end = in->len;
    return 0;
}

static int drop(struct tb_event *event, size_t *consumed, size_t end) {
    event->type = TUI_EVENT_NONE;
    event->mod = 0;
    event->key = 0;
    event->ch = 0;
    *consumed = end;
    return TB_OK;
}

static int clamp(int value, int size) {
    if (value >= size) {
        value = size - 1;
    }
    return value < 0 ? 0 : value;
}

static int read_number(const char *buf, size_t *at, size_t end, unsigned *n) {
    size_t start = *at;
    *n = 0;
    while (*at < end && buf[*at] >= '0' && buf[*at] <= '9' && *at - start < 6) {
        *n = *n * 10 + (unsigned)(buf[*at] - '0');
        (*at)++;
    }
    return *at > start;
}

static int read_separator(const char *buf, size_t *at, size_t end) {
    if (*at >= end || buf[*at] != ';') {
        return 0;
    }
    (*at)++;
    return 1;
}

/* termbox2's own reader of SGR (1006) and urxvt (1015) mouse reports drops
 * the rest of the input and reads any unknown CSI as one, so this reads them
 * first, strictly: `ESC [ < b ; x ; y` and M or m, or `ESC [ b ; x ; y M`,
 * with the cell clamped to the screen. A report split across reads waits for
 * its end, up to TUI_CSI_MAX bytes. A CSI that is neither a report nor a key
 * termbox2 knows is dropped (an event of kind TUI_EVENT_NONE). X10 reports
 * (`ESC [ M`) stay with termbox2. */
static int extract_mouse(struct tb_event *event, size_t *consumed) {
    struct bytebuf_t *in = &global.in;
    size_t end = 0;
    if (in->len < 3 || in->buf[0] != '\x1b' || in->buf[1] != '[' || in->buf[2] == 'M') {
        return TB_ERR;
    }
    int whole = csi_end(in, &end);
    if (whole == 0 && in->len < TUI_CSI_MAX) {
        return TB_ERR_NEED_MORE;
    }
    if (whole != 1) {
        return drop(event, consumed, end);
    }
    struct cap_trie_t *node = NULL;
    size_t depth = 0;
    if (cap_trie_find(in->buf, in->len, &node, &depth) == TB_OK && node->is_leaf) {
        return TB_ERR;
    }
    /* `ESC [` and a final byte with nothing between is Alt+[ (or Escape and [)
     * and a character: termbox2 reads it as those. */
    if (end == 3) {
        return TB_ERR;
    }
    int sgr = in->buf[2] == '<';
    size_t at = sgr ? 3 : 2;
    unsigned b = 0, x = 0, y = 0;
    char final = in->buf[end - 1];
    int report = read_number(in->buf, &at, end, &b) && read_separator(in->buf, &at, end) &&
        read_number(in->buf, &at, end, &x) && read_separator(in->buf, &at, end) &&
        read_number(in->buf, &at, end, &y) && at == end - 1 && x > 0 && y > 0 &&
        (final == 'M' || (sgr && final == 'm')) && (sgr || b >= 0x20);
    if (!report) {
        return drop(event, consumed, end);
    }
    event->mod = 0;
    event->ch = 0;
    *consumed = end;
    if (!sgr) {
        b -= 0x20;
    }
    static const uint16_t buttons[] = {TB_KEY_MOUSE_LEFT, TB_KEY_MOUSE_MIDDLE, TB_KEY_MOUSE_RIGHT,
        TB_KEY_MOUSE_RELEASE};
    event->key = buttons[b & 3];
    if ((b & 64) != 0 && (b & 3) < 2) {
        event->key = (b & 3) == 0 ? TB_KEY_MOUSE_WHEEL_UP : TB_KEY_MOUSE_WHEEL_DOWN;
    }
    if (final == 'm') {
        event->key = TB_KEY_MOUSE_RELEASE;
    }
    if ((b & 32) != 0) {
        event->mod |= TB_MOD_MOTION;
    }
    event->type = TB_EVENT_MOUSE;
    event->x = clamp((int)x - 1, global.width);
    event->y = clamp((int)y - 1, global.height);
    return TB_OK;
}

/* Alt and a key: a terminal sends Escape and the key in one write, which
 * termbox2 reads as Escape, then the key, when a lone Escape is a key. Read
 * together, Escape and a carriage return, a Backspace (DEL or BS) or a
 * printable ASCII character are that key with Alt; Escape alone stays a key.
 * '[' and 'O' start escape sequences and are left to termbox2. */
static int extract_alt_key(struct tb_event *event, size_t *consumed) {
    struct bytebuf_t *in = &global.in;
    if (in->len < 2 || in->buf[0] != '\x1b') {
        return TB_ERR;
    }
    unsigned char next = (unsigned char)in->buf[1];
    event->type = TB_EVENT_KEY;
    event->mod = TB_MOD_ALT;
    event->ch = 0;
    if (next == '\r' || next == TB_KEY_BACKSPACE || next == TB_KEY_BACKSPACE2) {
        event->key = next;
    } else if (next >= 0x20 && next < 0x7f && next != '[' && next != 'O') {
        event->key = 0;
        event->ch = next;
    } else {
        return TB_ERR;
    }
    *consumed = 2;
    return TB_OK;
}

/* termbox2's hook before it reads an escape sequence. */
static int extract_pre(struct tb_event *event, size_t *consumed) {
    int rv = extract_paste(event, consumed);
    if (rv != TB_ERR) {
        return rv;
    }
    rv = extract_alt_key(event, consumed);
    if (rv != TB_ERR) {
        return rv;
    }
    return extract_mouse(event, consumed);
}

/* tb_init, giving the screen token through `screen` on success. A second
 * open fails before it touches the locale. */
int tui_init(void **screen) {
    pthread_mutex_lock(&tui_lock);
    int rv = TB_ERR_INIT_ALREADY;
    if (!tui_opened) {
        use_utf8_ctype();
        rv = tb_init();
        if (rv == TB_OK) {
            tb_set_func(TB_FUNC_EXTRACT_PRE, extract_pre);
            send_now("\x1b[?2004h");
            tui_opened = 1;
            *screen = &tui_screen;
        } else {
            setlocale(LC_CTYPE, tui_saved_ctype);
        }
    }
    pthread_mutex_unlock(&tui_lock);
    return rv;
}

/* The free function of the resource Screen: it restores the terminal and the
 * locale. The VM calls it at Native.close, or at the end of the run when the
 * program did not close the screen (a crash too), after any call that holds
 * the screen has returned. */
void tui_shutdown(void *screen) {
    (void)screen;
    pthread_mutex_lock(&tui_lock);
    if (tui_opened) {
        tui_opened = 0;
        send_now("\x1b[?2004l");
        tb_shutdown();
        free(tui_paste_text);
        tui_paste_text = NULL;
        tui_paste_len = 0;
        tui_paste_scanned = 0;
        setlocale(LC_CTYPE, tui_saved_ctype);
    }
    pthread_mutex_unlock(&tui_lock);
}

/* The LC_CTYPE of the process now, for the tests. */
const char *tui_ctype(void) {
    pthread_mutex_lock(&tui_lock);
    const char *name = setlocale(LC_CTYPE, NULL);
    static char copy[64];
    snprintf(copy, sizeof(copy), "%s", name ? name : "");
    pthread_mutex_unlock(&tui_lock);
    return copy;
}

/* Returns `call`, made under the lock, or TB_ERR_NOT_INIT once closed. */
#define TUI_LOCKED(call)                                     \
    do {                                                     \
        pthread_mutex_lock(&tui_lock);                       \
        int rv_ = tui_opened ? (call) : TB_ERR_NOT_INIT;     \
        pthread_mutex_unlock(&tui_lock);                     \
        return rv_;                                          \
    } while (0)

int tui_width(void *screen) {
    (void)screen;
    TUI_LOCKED(tb_width());
}

int tui_height(void *screen) {
    (void)screen;
    TUI_LOCKED(tb_height());
}

int tui_clear(void *screen, uintattr_t fg, uintattr_t bg) {
    (void)screen;
    TUI_LOCKED(tb_set_clear_attrs(fg, bg) == TB_OK ? tb_clear() : TB_ERR);
}

int tui_present(void *screen) {
    (void)screen;
    TUI_LOCKED(tb_present());
}

int tui_set_cell(void *screen, int x, int y, uint32_t ch, uintattr_t fg,
    uintattr_t bg) {
    (void)screen;
    TUI_LOCKED(tb_set_cell(x, y, ch, fg, bg));
}

/* One cell of a character and the zero-width ones after it (combining marks,
 * ZWJ parts), as UTF-8 with a NUL: at most TUI_CLUSTER_MAX code points. */
#define TUI_CLUSTER_MAX 32
int tui_set_cluster(void *screen, int x, int y, const char *text,
    uintattr_t fg, uintattr_t bg) {
    uint32_t points[TUI_CLUSTER_MAX];
    size_t count = 0;
    (void)screen;
    while (*text != '\0') {
        int length;
        if (count == TUI_CLUSTER_MAX) {
            return TB_ERR;
        }
        length = tb_utf8_char_to_unicode(&points[count], text);
        if (length <= 0) {
            return TB_ERR;
        }
        text += length;
        count++;
    }
    if (count == 0) {
        return TB_ERR;
    }
    TUI_LOCKED(tb_set_cell_ex(x, y, points, count, fg, bg));
}

int tui_print(void *screen, int x, int y, uintattr_t fg, uintattr_t bg,
    size_t *out_w, const char *str) {
    (void)screen;
    TUI_LOCKED(tb_print_ex(x, y, fg, bg, out_w, str));
}

int tui_set_cursor(void *screen, int x, int y) {
    (void)screen;
    TUI_LOCKED(tb_set_cursor(x, y));
}

int tui_hide_cursor(void *screen) {
    (void)screen;
    TUI_LOCKED(tb_hide_cursor());
}

int tui_set_input_mode(void *screen, int mode) {
    (void)screen;
    TUI_LOCKED(tb_set_input_mode(mode));
}

int tui_set_output_mode(void *screen, int mode) {
    (void)screen;
    TUI_LOCKED(tb_set_output_mode(mode));
}

/* The text of a termbox2 error code (a constant string). */
const char *tui_strerror(int code) {
    return tb_strerror(code);
}

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* An event already read, or readable now, without waiting. `err` gets the
 * errno termbox2 kept for a failed select or read, read under the lock. */
static int peek_now(struct tb_event *event, int *err) {
    pthread_mutex_lock(&tui_lock);
    int rv = tui_opened ? tb_peek_event(event, 0) : TB_ERR_NOT_INIT;
    *err = tb_last_errno();
    pthread_mutex_unlock(&tui_lock);
    return rv;
}

/* The length in bytes of the text of the last paste event. */
int64_t tui_paste_length(void *screen) {
    (void)screen;
    pthread_mutex_lock(&tui_lock);
    int64_t len = (int64_t)tui_paste_len;
    pthread_mutex_unlock(&tui_lock);
    return len;
}

/* Copies at most `room` bytes of the text of the last paste event into
 * `dest`, under the lock; gives the bytes copied. */
int64_t tui_paste_copy(void *screen, char *dest, int64_t room) {
    (void)screen;
    pthread_mutex_lock(&tui_lock);
    size_t len = tui_paste_len < (size_t)room ? tui_paste_len : (size_t)room;
    if (len > 0) {
        memcpy(dest, tui_paste_text, len);
    }
    pthread_mutex_unlock(&tui_lock);
    return (int64_t)len;
}

/* Without the lock, waits up to `timeout_ms` for the tty or the resize pipe
 * to be readable. Gives 1 when the tty is readable with no byte to read (its
 * end), else 0 (readable, timed out, or cut short by a signal: the VM's
 * garbage collector sends them to every thread). */
static int wait_readable(int timeout_ms) {
    pthread_mutex_lock(&tui_lock);
    int tty = tui_opened ? global.rfd : -1;
    int resize = tui_opened ? global.resize_pipefd[0] : -1;
    pthread_mutex_unlock(&tui_lock);
    if (tty < 0 || resize < 0) {
        return 0;
    }
    /* The descriptors stay open meanwhile: the VM does not run tui_shutdown
     * during this call, which holds the screen. */
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(tty, &fds);
    FD_SET(resize, &fds);
    struct timeval tv = {timeout_ms / 1000, (timeout_ms % 1000) * 1000};
    int maxfd = tty > resize ? tty : resize;
    if (select(maxfd + 1, &fds, NULL, NULL, &tv) <= 0 || !FD_ISSET(tty, &fds)) {
        return 0;
    }
    int pending = 0;
    return ioctl(tty, FIONREAD, &pending) == 0 && pending == 0;
}

/* One event within `timeout_ms` (0 to TUI_SLICE_MS): TB_OK with `event`
 * filled, TB_ERR_NO_EVENT, TB_ERR_NOT_INIT once the screen is closed, or
 * another termbox2 error. The Agentica side calls it again for a longer
 * wait. */
int tui_wait_event(void *screen, struct tb_event *event, int timeout_ms) {
    (void)screen;
    if (timeout_ms > TUI_SLICE_MS) {
        timeout_ms = TUI_SLICE_MS;
    }
    long long deadline = now_ms() + (timeout_ms < 0 ? 0 : timeout_ms);
    int ends = 0;
    for (;;) {
        int err = 0;
        int rv = peek_now(event, &err);
        int incomplete = rv == TB_ERR || rv == TB_ERR_NEED_MORE;
        int interrupted = rv == TB_ERR_POLL && err == EINTR;
        if (!incomplete && !interrupted && rv != TB_ERR_NO_EVENT) {
            return rv;
        }
        long long rest = deadline - now_ms();
        if (rest <= 0) {
            return TB_ERR_NO_EVENT;
        }
        ends = wait_readable((int)rest) ? ends + 1 : 0;
        if (ends >= TUI_EOF_HITS) {
            return TB_ERR_READ;
        }
    }
}
