/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * One-process Binder: ioctl(BINDER_WRITE_READ) moves parcels between threads
 * of this process, or into a C handler registered on a handle.
 */
#include "husk-tl-binder.h"

#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/types.h>

void tl_log_line(const char *fmt, ...);

#define BINDER_WRITE_READ      0xC0306201UL
#define BINDER_SET_MAX_THREADS 0x40046205UL
#define BINDER_SET_CONTEXT_MGR 0x40046207UL
#define BINDER_THREAD_EXIT     0x40046208UL
#define BINDER_VERSION         0xC0046209UL

#define BC_TRANSACTION         0x40406300U
#define BC_REPLY               0x40406301U
#define BC_FREE_BUFFER         0x40086303U
#define BC_INCREFS             0x40046304U
#define BC_ACQUIRE             0x40046305U
#define BC_RELEASE             0x40046306U
#define BC_DECREFS             0x40046307U
#define BC_REGISTER_LOOPER     0x00006311U
#define BC_ENTER_LOOPER        0x00006312U
#define BC_EXIT_LOOPER         0x00006313U

#define BR_OK                  0x00007201U
#define BR_TRANSACTION         0x80407202U
#define BR_REPLY               0x80407203U
#define BR_DEAD_REPLY          0x00007205U
#define BR_TRANSACTION_COMPLETE 0x00007206U
#define BR_NOOP                0x0000720CU
#define BR_FAILED_REPLY        0x00007211U

#define TF_ONE_WAY             0x01U
#define BINDER_PROTOCOL        8

#define BINDER_TYPE_BINDER     0x73622a85U
#define BINDER_TYPE_WEAK_BINDER 0x77622a85U
#define BINDER_TYPE_HANDLE     0x73682a85U
#define BINDER_TYPE_WEAK_HANDLE 0x77682a85U

typedef struct {
    uint64_t write_size, write_consumed, write_buffer;
    uint64_t read_size, read_consumed, read_buffer;
} binder_write_read;

typedef struct {
    uint64_t handle;
    uint64_t cookie;
    uint32_t code, flags;
    int32_t sender_pid;
    uint32_t sender_euid;
    uint64_t data_size, offsets_size;
    uint64_t buffer, offsets;
} binder_txn;

typedef struct {
    uint32_t type, flags;
    union {
        uint64_t binder;
        uint32_t handle;
    };
    uint64_t cookie;
} flat_obj;

enum { MAX_SESS = 32, MAX_CALL = 64, MAX_NODE = 256, MAX_PARCEL = 1 << 20 };

typedef struct sess {
    bool used, initialized;
    atomic_bool closing;
    unsigned refs;
    int fd;
    uint8_t *map;
    size_t map_len, map_used;
    pthread_mutex_t lock;
    pthread_cond_t cv;
    uint8_t *in;
    size_t in_len, in_cap;
    bool looping;
} sess;

typedef struct node {
    bool used;
    sess *owner;
    husk_binder_local_fn local;
    void *cookie;
    void *ptr;
} node;

static sess g_sess[MAX_SESS];
static sess *g_mgr;
static sess *g_call[MAX_CALL];
static int g_ncall;
static node g_node[MAX_NODE];
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_changed = PTHREAD_COND_INITIALIZER;

static sess *by_fd(int fd)
{
    for (int i = 0; i < MAX_SESS; i++) if (g_sess[i].used && g_sess[i].fd == fd) return &g_sess[i];
    return NULL;
}

/* Sessions remain allocated; close wakes readers and waits for every admitted
 * ioctl before releasing buffers. Mutexes are not destroyed under waiters. */
static sess *acquire(int fd)
{
    pthread_mutex_lock(&g_lock);
    sess *s = by_fd(fd);
    if (s && !atomic_load(&s->closing)) s->refs++;
    else s = NULL;
    pthread_mutex_unlock(&g_lock);
    return s;
}
static void release(sess *s)
{
    pthread_mutex_lock(&g_lock);
    s->refs--; pthread_cond_broadcast(&g_changed);
    pthread_mutex_unlock(&g_lock);
}
static bool parcel_valid(const void *data, size_t len, const uint64_t *offsets, size_t count)
{
    if (len > MAX_PARCEL || (len && !data) || count > 4096 || (count && !offsets)) return false;
    for (size_t i = 0; i < count; ++i)
        if (offsets[i] > len || sizeof(flat_obj) > len - offsets[i] || offsets[i] % 4) return false;
    return true;
}

bool husk_binder_is_path(const char *path)
{
    return path && (!strcmp(path, "/dev/binder") || !strcmp(path, "/dev/hwbinder") || !strcmp(path, "/dev/vndbinder"));
}

int husk_binder_open(void)
{
    int p[2];
    if (pipe(p) != 0) return -1;
    close(p[1]);
    if (fcntl(p[0], F_SETFD, FD_CLOEXEC) < 0) { close(p[0]); return -1; }
    pthread_mutex_lock(&g_lock);
    sess *s = NULL;
    for (int i = 0; i < MAX_SESS; i++) if (!g_sess[i].used) { s = &g_sess[i]; break; }
    if (!s) { pthread_mutex_unlock(&g_lock); close(p[0]); errno = EMFILE; return -1; }
    if (!s->initialized) {
        pthread_mutex_init(&s->lock, NULL); pthread_cond_init(&s->cv, NULL);
        s->initialized = true;
    }
    s->used = true; s->refs = 0; atomic_store(&s->closing, false);
    s->fd = p[0]; s->looping = false;
    pthread_mutex_unlock(&g_lock);
    tl_log_line("binder: open fd %d", s->fd);
    return s->fd;
}

bool husk_binder_is_fd(int fd) { sess *s = acquire(fd); if (!s) return false; release(s); return true; }

void *husk_binder_mmap(int fd, size_t len)
{
    sess *s = acquire(fd);
    if (!s) { errno = EBADF; return MAP_FAILED; }
    if (!len || len > MAX_PARCEL) { release(s); errno = EINVAL; return MAP_FAILED; }
    if (len < 4096) len = 4096;
    pthread_mutex_lock(&s->lock);
    void *p = MAP_FAILED;
    if (s->map) errno = EBUSY;
    else {
        p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (p != MAP_FAILED) { s->map = p; s->map_len = len; s->map_used = 0; }
    }
    pthread_mutex_unlock(&s->lock); release(s);
    return p;
}

static void push(sess *s, const void *p, size_t n)
{
    if (n > MAX_PARCEL || s->in_len > MAX_PARCEL - n) { errno = ENOSPC; return; }
    if (s->in_len + n > s->in_cap) {
        size_t cap = s->in_cap ? s->in_cap * 2 : 4096;
        while (cap < s->in_len + n) cap *= 2;
        uint8_t *q = realloc(s->in, cap);
        if (!q) return;
        s->in = q;
        s->in_cap = cap;
    }
    memcpy(s->in + s->in_len, p, n);
    s->in_len += n;
    pthread_cond_broadcast(&s->cv);
}

static void *alloc_buf(sess *s, size_t n)
{
    if (n > MAX_PARCEL) return NULL;
    n = (n + 7) & ~(size_t)7;
    if (!s->map || n > s->map_len || s->map_used > s->map_len - n) return NULL;
    void *p = s->map + s->map_used;
    s->map_used += n;
    return p;
}

static uint32_t alloc_handle_locked(void)
{
    for (uint32_t i = 1; i < MAX_NODE; i++) if (!g_node[i].used) {
        memset(&g_node[i], 0, sizeof(g_node[i]));
        g_node[i].used = true;
        return i;
    }
    return 0;
}

uint32_t husk_binder_add_local(husk_binder_local_fn fn, void *cookie)
{
    pthread_mutex_lock(&g_lock);
    uint32_t h = alloc_handle_locked();
    if (h) {
        g_node[h].local = fn;
        g_node[h].cookie = cookie;
    }
    pthread_mutex_unlock(&g_lock);
    return h;
}

void husk_binder_set_local(uint32_t handle, husk_binder_local_fn fn, void *cookie)
{
    if (handle >= MAX_NODE) return;
    pthread_mutex_lock(&g_lock);
    g_node[handle].used = true;
    g_node[handle].local = fn;
    g_node[handle].cookie = cookie;
    pthread_mutex_unlock(&g_lock);
}

void husk_binder_set_ptr(uint32_t handle, void *ptr)
{
    if (handle >= MAX_NODE) return;
    pthread_mutex_lock(&g_lock);
    if (g_node[handle].used) g_node[handle].ptr = ptr;
    pthread_mutex_unlock(&g_lock);
}

void *husk_binder_ptr(uint32_t handle)
{
    if (handle >= MAX_NODE) return NULL;
    pthread_mutex_lock(&g_lock);
    void *p = g_node[handle].used ? g_node[handle].ptr : NULL;
    pthread_mutex_unlock(&g_lock);
    return p;
}

static void rewrite_objects(sess *from, uint8_t *data, size_t dlen, const uint64_t *offs, size_t n_off)
{
    if (!data || !offs) return;
    for (size_t i = 0; i < n_off; i++) {
        size_t at = (size_t)offs[i];
        if (at > dlen || sizeof(flat_obj) > dlen - at) continue;
        flat_obj o;
        memcpy(&o, data + at, sizeof(o));
        if (o.type == BINDER_TYPE_BINDER || o.type == BINDER_TYPE_WEAK_BINDER) {
            if (!o.binder) {
                o.type = (o.type == BINDER_TYPE_BINDER) ? BINDER_TYPE_HANDLE : BINDER_TYPE_WEAK_HANDLE;
                o.handle = 0;
                memcpy(data + at, &o, sizeof(o));
                continue;
            }
            pthread_mutex_lock(&g_lock);
            uint32_t h = 0;
            for (uint32_t n = 1; n < MAX_NODE; n++) {
                if (g_node[n].used && g_node[n].ptr == (void *)(uintptr_t)o.binder) { h = n; break; }
            }
            if (!h) {
                h = alloc_handle_locked();
                if (h) {
                    g_node[h].owner = from;
                    g_node[h].ptr = (void *)(uintptr_t)o.binder;
                    g_node[h].cookie = (void *)(uintptr_t)o.cookie;
                }
            }
            pthread_mutex_unlock(&g_lock);
            o.type = (o.type == BINDER_TYPE_BINDER) ? BINDER_TYPE_HANDLE : BINDER_TYPE_WEAK_HANDLE;
            o.handle = h;
            memcpy(data + at, &o, sizeof(o));
        }
    }
}

static void deliver_txn(sess *to, uint32_t br, const binder_txn *t, const void *data, const void *offs)
{
    binder_txn out = *t;
    /* This transport is local to this host process. Caller-supplied identity
     * fields must never become an Android root/system identity. */
    out.sender_pid = (int32_t)getpid();
    out.sender_euid = (uint32_t)geteuid();
    size_t need = (size_t)t->data_size + (size_t)t->offsets_size;
    void *buf = alloc_buf(to, need ? need : 8);
    if (!buf) { uint32_t failed = BR_FAILED_REPLY; push(to, &failed, sizeof(failed)); return; }
    if (buf && t->data_size) memcpy(buf, data, (size_t)t->data_size);
    if (buf && t->offsets_size) memcpy((uint8_t *)buf + (size_t)t->data_size, offs, (size_t)t->offsets_size);
    out.buffer = (uint64_t)(uintptr_t)buf;
    out.offsets = (uint64_t)(uintptr_t)((uint8_t *)buf + (size_t)t->data_size);
    uint32_t cmd = br;
    push(to, &cmd, 4);
    push(to, &out, sizeof(out));
}

static void reply_from_local(sess *s, uint32_t flags, husk_binder_reply *r)
{
    if (flags & TF_ONE_WAY) {
        husk_binder_reply_free(r);
        return;
    }
    if (!parcel_valid(r->data, r->data_size, r->offsets, r->n_offsets)) {
        pthread_mutex_lock(&s->lock); uint32_t fail = BR_FAILED_REPLY; push(s, &fail, 4); pthread_mutex_unlock(&s->lock);
        husk_binder_reply_free(r); return;
    }
    binder_txn t;
    memset(&t, 0, sizeof(t));
    t.data_size = r->data_size;
    t.offsets_size = r->n_offsets * 8;
    t.buffer = (uint64_t)(uintptr_t)r->data;
    t.offsets = (uint64_t)(uintptr_t)r->offsets;
    pthread_mutex_lock(&s->lock);
    deliver_txn(s, BR_REPLY, &t, r->data, r->offsets);
    pthread_mutex_unlock(&s->lock);
    husk_binder_reply_free(r);
}

/* Used when transact() calls a local handler and wants the reply bytes. */
static _Thread_local husk_binder_reply *t_reply_slot;

static bool dispatch(uint32_t handle, sess *from, binder_txn *t, const void *data, const void *offs)
{
    husk_binder_local_fn fn = NULL;
    void *cookie = NULL;
    sess *to = NULL;
    pthread_mutex_lock(&g_lock);
    if (handle < MAX_NODE && g_node[handle].used && g_node[handle].local) {
        fn = g_node[handle].local;
        cookie = g_node[handle].cookie;
    } else if (handle == 0 && g_mgr) {
        to = g_mgr;
    } else if (handle < MAX_NODE && g_node[handle].used) {
        to = g_node[handle].owner;
    }
    if (to && (!to->used || atomic_load(&to->closing))) to = NULL;
    if (to && from && !(t->flags & TF_ONE_WAY)) {
        if (g_ncall == MAX_CALL) to = NULL;
        else g_call[g_ncall++] = from;
    }
    if (to) to->refs++;
    pthread_mutex_unlock(&g_lock);

    if (fn) {
        size_t n_off = (size_t)t->offsets_size / 8;
        uint8_t *copy = NULL;
        if (t->data_size) {
            copy = malloc((size_t)t->data_size);
            if (copy) memcpy(copy, data, (size_t)t->data_size);
        }
        if (copy && offs && n_off) rewrite_objects(from, copy, (size_t)t->data_size, (const uint64_t *)offs, n_off);
        husk_binder_reply r = {0};
        fn(t->code, t->flags, copy ? copy : (const uint8_t *)data, (size_t)t->data_size,
           (const uint64_t *)offs, n_off, &r, cookie);
        free(copy);
        if (t_reply_slot) {
            *t_reply_slot = r;
            memset(&r, 0, sizeof(r));
        } else if (from) {
            reply_from_local(from, t->flags, &r);
        } else {
            husk_binder_reply_free(&r);
        }
        return true;
    }
    if (!to) return false;
    pthread_mutex_lock(&to->lock);
    size_t n_off = (size_t)t->offsets_size / 8;
    uint8_t *copy = NULL;
    if (t->data_size) {
        copy = malloc((size_t)t->data_size);
        if (copy) memcpy(copy, data, (size_t)t->data_size);
    }
    if (copy && offs && n_off) rewrite_objects(from, copy, (size_t)t->data_size, (const uint64_t *)offs, n_off);
    deliver_txn(to, BR_TRANSACTION, t, copy ? copy : data, offs);
    pthread_mutex_unlock(&to->lock);
    release(to);
    free(copy);
    return true;
}

int husk_binder_transact(uint32_t handle, uint32_t code, uint32_t flags,
                         const uint8_t *data, size_t data_size,
                         const uint64_t *offsets, size_t n_offsets,
                         husk_binder_reply *reply)
{
    if (!parcel_valid(data, data_size, offsets, n_offsets)) { errno = EINVAL; return -1; }
    binder_txn t;
    memset(&t, 0, sizeof(t));
    t.handle = handle;
    t.code = code;
    t.flags = flags;
    t.data_size = data_size;
    t.offsets_size = n_offsets * 8;
    husk_binder_reply slot = {0};
    husk_binder_reply *previous = t_reply_slot;
    t_reply_slot = reply ? &slot : NULL;
    bool ok = dispatch(handle, NULL, &t, data, offsets);
    t_reply_slot = previous;
    if (!ok) { errno = ESRCH; return -1; }
    if (!parcel_valid(slot.data, slot.data_size, slot.offsets, slot.n_offsets)) {
        husk_binder_reply_free(&slot); errno = EINVAL; return -1;
    }
    if (reply) *reply = slot;
    return 0;
}

void husk_binder_reply_free(husk_binder_reply *r)
{
    if (!r) return;
    free(r->data);
    free(r->offsets);
    memset(r, 0, sizeof(*r));
}

static int write_cmds(sess *s, const uint8_t *buf, size_t n)
{
    size_t i = 0;
    while (i + 4 <= n) {
        uint32_t cmd;
        memcpy(&cmd, buf + i, 4);
        i += 4;
        if (cmd == BC_ENTER_LOOPER || cmd == BC_REGISTER_LOOPER) {
            pthread_mutex_lock(&s->lock);
            s->looping = true;
            pthread_mutex_unlock(&s->lock);
            continue;
        }
        if (cmd == BC_EXIT_LOOPER) {
            pthread_mutex_lock(&s->lock);
            s->looping = false;
            pthread_mutex_unlock(&s->lock);
            continue;
        }
        if (cmd == BC_INCREFS || cmd == BC_ACQUIRE || cmd == BC_RELEASE || cmd == BC_DECREFS) {
            if (i + 4 > n) { errno = EINVAL; return -1; }
            i += 4;
            continue;
        }
        if (cmd == BC_FREE_BUFFER) {
            if (i + 8 > n) { errno = EINVAL; return -1; }
            i += 8;
            continue;
        }
        if (cmd == BC_TRANSACTION || cmd == BC_REPLY) {
            if (i + sizeof(binder_txn) > n) { errno = EINVAL; return -1; }
            binder_txn t;
            memcpy(&t, buf + i, sizeof(t));
            i += sizeof(t);
            const void *data = (const void *)(uintptr_t)t.buffer;
            const void *offs = (const void *)(uintptr_t)t.offsets;
            if (t.offsets_size % 8 || !parcel_valid(data, t.data_size, offs, t.offsets_size / 8)) {
                errno = EINVAL; return -1;
            }
            pthread_mutex_lock(&s->lock);
            uint32_t done = BR_TRANSACTION_COMPLETE;
            push(s, &done, 4);
            pthread_mutex_unlock(&s->lock);

            if (cmd == BC_REPLY) {
                sess *to = NULL;
                pthread_mutex_lock(&g_lock);
                if (g_ncall > 0) to = g_call[--g_ncall];
                if (to && (!to->used || atomic_load(&to->closing))) to = NULL;
                if (to) to->refs++;
                pthread_mutex_unlock(&g_lock);
                if (!to) {
                    pthread_mutex_lock(&s->lock);
                    uint32_t fail = BR_FAILED_REPLY;
                    push(s, &fail, 4);
                    pthread_mutex_unlock(&s->lock);
                    continue;
                }
                pthread_mutex_lock(&to->lock);
                deliver_txn(to, BR_REPLY, &t, data, offs);
                pthread_mutex_unlock(&to->lock);
                release(to);
                continue;
            }
            if (!dispatch((uint32_t)t.handle, s, &t, data, offs)) {
                pthread_mutex_lock(&s->lock);
                uint32_t fail = BR_FAILED_REPLY;
                if (!(t.flags & TF_ONE_WAY)) push(s, &fail, 4);
                pthread_mutex_unlock(&s->lock);
            }
            continue;
        }
        errno = EINVAL; return -1;
    }
    if (i != n) { errno = EINVAL; return -1; }
    return 0;
}

static int read_out(sess *s, uint8_t *dst, size_t cap, uint64_t *consumed, bool wait)
{
    pthread_mutex_lock(&s->lock);
    while (s->in_len == 0 && wait && !atomic_load(&s->closing)) pthread_cond_wait(&s->cv, &s->lock);
    if (atomic_load(&s->closing)) { pthread_mutex_unlock(&s->lock); errno = EBADF; return -1; }
    size_t n = s->in_len < cap ? s->in_len : cap;
    if (n) {
        memcpy(dst, s->in, n);
        memmove(s->in, s->in + n, s->in_len - n);
        s->in_len -= n;
    }
    pthread_mutex_unlock(&s->lock);
    *consumed = n;
    return 0;
}

static int session_ioctl(sess *s, unsigned long req, void *arg)
{
    int fd = s->fd;
    if (req == BINDER_VERSION) {
        if (!arg) { errno = EINVAL; return -1; }
        *(int32_t *)arg = BINDER_PROTOCOL;
        return 0;
    }
    if (req == BINDER_SET_MAX_THREADS) return 0;
    if (req == BINDER_THREAD_EXIT) return 0;
    if (req == BINDER_SET_CONTEXT_MGR) {
        pthread_mutex_lock(&g_lock);
        g_mgr = s;
        g_node[0].used = true;
        g_node[0].owner = s;
        pthread_mutex_unlock(&g_lock);
        tl_log_line("binder: context manager is fd %d", fd);
        return 0;
    }
    if (!arg) { errno = EINVAL; return -1; }
    if (req != BINDER_WRITE_READ) { errno = EINVAL; return -1; }
    binder_write_read wr;
    memcpy(&wr, arg, sizeof(wr));
    if (wr.write_size > MAX_PARCEL || wr.read_size > MAX_PARCEL ||
        (wr.write_size && !wr.write_buffer) || (wr.read_size && !wr.read_buffer)) { errno = EINVAL; return -1; }
    wr.write_consumed = 0;
    if (wr.write_size) {
        if (write_cmds(s, (const uint8_t *)(uintptr_t)wr.write_buffer, (size_t)wr.write_size) < 0) return -1;
        wr.write_consumed = wr.write_size;
    }
    wr.read_consumed = 0;
    if (wr.read_size) {
        bool wait = true;
        if (read_out(s, (uint8_t *)(uintptr_t)wr.read_buffer, (size_t)wr.read_size, &wr.read_consumed, wait) < 0) return -1;
    }
    memcpy(arg, &wr, sizeof(wr));
    return 0;
}

int husk_binder_ioctl(int fd, unsigned long req, void *arg)
{
    sess *s = acquire(fd); if (!s) { errno = EBADF; return -1; }
    int result = session_ioctl(s, req, arg); release(s); return result;
}

void husk_binder_close(int fd)
{
    pthread_mutex_lock(&g_lock);
    sess *s = by_fd(fd);
    if (!s || atomic_exchange(&s->closing, true)) { pthread_mutex_unlock(&g_lock); return; }
    if (g_mgr == s) g_mgr = NULL;
    for (int i = 0; i < MAX_NODE; i++) if (g_node[i].owner == s) memset(&g_node[i], 0, sizeof(node));
    for (int i = 0; i < g_ncall; i++) if (g_call[i] == s) g_call[i] = NULL;
    pthread_mutex_unlock(&g_lock);
    pthread_mutex_lock(&s->lock); pthread_cond_broadcast(&s->cv); pthread_mutex_unlock(&s->lock);
    pthread_mutex_lock(&g_lock);
    while (s->refs) pthread_cond_wait(&g_changed, &g_lock);
    if (s->map) munmap(s->map, s->map_len);
    free(s->in); s->map = NULL; s->map_len = s->map_used = s->in_len = s->in_cap = 0; s->in = NULL;
    s->used = false;
    pthread_mutex_unlock(&g_lock);
}
