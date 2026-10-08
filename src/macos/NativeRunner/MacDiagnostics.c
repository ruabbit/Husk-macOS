/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "MacDiagnostics.h"
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/ucontext.h>
#include <unistd.h>

void tl_log_line(const char *format, ...)
{
    va_list args; va_start(args, format);
    flockfile(stderr); vfprintf(stderr, format, args); fputc('\n', stderr); funlockfile(stderr);
    va_end(args);
}

/* Do not call Objective-C, malloc, stdio or the ELF symbolizer after a fault.
 * Preserve registers in the session log and exit with a failure status so the
 * parent can reap the guest without spawning a desktop crash-report dialog. */
static void number(const char *label, uint64_t value)
{
    char text[96]; size_t n = 0;
    while (*label && n < 60) text[n++] = *label++;
    text[n++] = '='; text[n++] = '0'; text[n++] = 'x';
    for (int shift = 60; shift >= 0; shift -= 4) text[n++] = "0123456789abcdef"[(value >> shift) & 15];
    text[n++] = '\n'; (void)write(STDERR_FILENO, text, n);
}
static void failure(int sig, siginfo_t *info, void *context)
{
    const char message[] = "Husk guest process failed; raw registers follow\n";
    (void)write(STDERR_FILENO, message, sizeof(message)-1);
    number("signal", sig); number("fault", (uintptr_t)info->si_addr);
    ucontext_t *uc = context; _STRUCT_ARM_THREAD_STATE64 *r = &uc->uc_mcontext->__ss;
    number("pc", r->__pc); number("lr", r->__lr); number("sp", r->__sp); number("fp", r->__fp);
    for (int i = 0; i < 29; ++i) {
        char label[] = "x00"; label[1] += i / 10; label[2] += i % 10;
        number(label, r->__x[i]);
    }
    _exit(128 + sig);
}
void mac_runtime_diagnostics_install(void)
{
    static unsigned char stack[65536];
    stack_t alternate = {.ss_sp=stack, .ss_size=sizeof(stack)};
    sigaltstack(&alternate, NULL);
    struct sigaction action = {0}; action.sa_sigaction=failure; action.sa_flags=SA_SIGINFO|SA_ONSTACK;
    const int signals[] = {SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP};
    for (unsigned i=0; i<sizeof(signals)/sizeof(signals[0]); ++i) sigaction(signals[i], &action, NULL);
}
