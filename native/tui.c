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

#define TB_IMPL
#define TB_LIB_OPTS
#include "termbox2/termbox2.h"

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

/* tb_init, giving the screen token through `screen` on success. A second
 * open fails before it touches the locale. */
int tui_init(void **screen) {
    pthread_mutex_lock(&tui_lock);
    int rv = TB_ERR_INIT_ALREADY;
    if (!tui_opened) {
        use_utf8_ctype();
        rv = tb_init();
        if (rv == TB_OK) {
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
        tb_shutdown();
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

/* An event already read, or readable now, without waiting. */
static int peek_now(struct tb_event *event) {
    TUI_LOCKED(tb_peek_event(event, 0));
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
        int rv = peek_now(event);
        int incomplete = rv == TB_ERR || rv == TB_ERR_NEED_MORE;
        int interrupted = rv == TB_ERR_POLL && tb_last_errno() == EINTR;
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
