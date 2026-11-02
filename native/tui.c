/* The termbox2 implementation plus the few functions the Agentica bindings
 * (src/termbox.agc) need that termbox2 lacks. Built by `make native`. */

#define TB_IMPL
#define TB_LIB_OPTS
#include "termbox2/termbox2.h"

#include <langinfo.h>
#include <locale.h>
#include <time.h>

/* The address that stands for the open terminal: the Agentica resource Screen
 * needs a non-NULL pointer, and termbox2 keeps its state in globals. */
static int tui_screen;

/* The LC_CTYPE that tui_init replaced, put back by tui_shutdown. */
static char tui_saved_ctype[64];

static int utf8_ctype(void) {
    return strcmp(nl_langinfo(CODESET), "UTF-8") == 0;
}

/* termbox2 measures characters with wcwidth(3), which knows only ASCII in the
 * C locale (the VM never sets one): pick a UTF-8 LC_CTYPE, the user's first. */
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

/* tb_init, giving the screen token through `screen` on success. */
int tui_init(void **screen) {
    use_utf8_ctype();
    int rv = tb_init();
    if (rv == TB_OK) {
        *screen = &tui_screen;
    } else {
        setlocale(LC_CTYPE, tui_saved_ctype);
    }
    return rv;
}

/* The free function of the resource Screen: it restores the terminal. The
 * Agentica VM calls it at Native.close, or at the end of the run when the
 * program did not close the screen (a crash too). */
void tui_shutdown(void *screen) {
    (void)screen;
    tb_shutdown();
    setlocale(LC_CTYPE, tui_saved_ctype);
}

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* tb_peek_event (tb_poll_event for a negative timeout) that waits again,
 * for the time left, when a signal cuts select(2) short (the VM's garbage
 * collector sends signals to every thread) or when the bytes read so far are
 * not a whole event yet. */
int tui_wait_event(struct tb_event *event, int timeout_ms) {
    long long deadline = now_ms() + (timeout_ms < 0 ? 0 : timeout_ms);
    int left = timeout_ms;
    for (;;) {
        int rv = tb_peek_event(event, left);
        int again = rv == TB_ERR || rv == TB_ERR_NEED_MORE ||
            (rv == TB_ERR_POLL && tb_last_errno() == EINTR);
        if (!again) {
            return rv;
        }
        if (timeout_ms >= 0) {
            long long rest = deadline - now_ms();
            if (rest <= 0) {
                return TB_ERR_NO_EVENT;
            }
            left = (int)rest;
        }
    }
}
