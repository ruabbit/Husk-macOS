/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-bionic.h"
#include "husk-tl-threads.h"
#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL guest threads: %s\n",#x); return 1; } } while(0)
static atomic_bool entered, completed, release_worker;
static pthread_key_t key;
void tl_log_line(const char *format, ...) { (void)format; }
static void destructor(void *unused) { (void)unused; usleep(150000); atomic_store(&completed,true); }
static void *worker(void *hold) {
    pthread_setspecific(key,(void *)1); atomic_store(&entered,true);
    while(hold&&!atomic_load(&release_worker))usleep(1000);
    /* Exercise the path that never returns to the thunk, with TLS writes. */
    pthread_exit(NULL);
}
int main(int argc,char **argv) {
    bool hold=argc>1&&!strcmp(argv[1],"live");
    CHECK(!pthread_key_create(&key,destructor));
    int (*create)(pthread_t *,const void *,void *(*)(void *),void *)=tl_bionic_find("pthread_create");
    CHECK(create);pthread_t t;CHECK(!create(&t,NULL,worker,hold?(void *)1:NULL));
    while(!atomic_load(&entered))usleep(1000);
    bool closed=tl_guest_threads_quiescent();CHECK(closed!=hold);
    if(hold) { CHECK(!atomic_load(&completed)); atomic_store(&release_worker,true); }
    CHECK(!pthread_join(t,NULL));CHECK(atomic_load(&completed));
    CHECK(tl_guest_threads_quiescent());
    CHECK(create(&t,NULL,worker,NULL)!=0);
    pthread_key_delete(key);puts("PASS native guest thread gate, pthread_exit, TLS completion and live-worker refusal");return 0;
}
