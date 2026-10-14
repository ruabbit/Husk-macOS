/* SPDX-License-Identifier: GPL-2.0-or-later */
/* A tiny Android loader, not a copy of Geode. Proves constructors and JNI run. */
extern char *getenv(const char *);
extern void *fopen(const char *, const char *);
extern unsigned long fwrite(const void *, unsigned long, unsigned long, void *);
extern int fclose(void *);
static void record(char event) {
    const char *path=getenv("HUSK_GEODE_RECEIPT");
    if(!path) return;
    void *f=fopen(path,"ab");
    if(f){fwrite(&event,1,1,f);fclose(f);}
}
__attribute__((constructor)) static void initialize(void){record('C');}
int JNI_OnLoad(void *vm, void *reserved) {
    (void)vm;(void)reserved;record('J');
#ifdef JNI_ERROR
    return -1;
#else
    return 0x10006;
#endif
}
