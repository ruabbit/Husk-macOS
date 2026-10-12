/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HUSK_TL_THREADS_H
#define HUSK_TL_THREADS_H
#include <pthread.h>
#include <stdbool.h>
/* Track guest workers through kernel thread death, including pthread_exit and
   TLS destructors. Host lifecycle/render/mixer threads are joined separately. */
int tl_guest_thread_create(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
bool tl_guest_threads_quiescent(void);
#endif
