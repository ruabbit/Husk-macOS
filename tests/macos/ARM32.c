/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-arm32.h"
#include "husk-tl-ld.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint8_t *read_file(const char *name,size_t *n){FILE *f=fopen(name,"rb");assert(f);fseek(f,0,SEEK_END);*n=ftell(f);rewind(f);uint8_t *b=malloc(*n);assert(b&&fread(b,1,*n,f)==*n);fclose(f);return b;}
static uint32_t get32(uint8_t *p){uint32_t n;memcpy(&n,p,4);return n;}
static void put32(uint8_t *p,uint32_t n){memcpy(p,&n,4);}
static void *symbol(tl_lib *l,const char *n){void *p=tl_a32_sym(l,n);assert(p&&tl_a32_is_fn(p));return p;}
int main(int argc,char **argv){
    assert(argc==3);size_t n;uint8_t *file=read_file(argv[1],&n);tl_lib *key=(void *)&key;
    assert(tl_a32_is_elf(file,n));
    uint8_t *bad=malloc(n);memcpy(bad,file,n);put32(bad+28,UINT32_MAX);assert(!tl_a32_map(key,"bad-header",bad,n));
    memcpy(bad,file,n);uint32_t ph=get32(bad+28);while(get32(bad+ph)!=1)ph+=32;put32(bad+ph+20,UINT32_MAX);assert(!tl_a32_map(key,"bad-span",bad,n));free(bad);
    assert(tl_a32_map(key,"libarm32.so",file,n));
    uint32_t value=tl_a32_va(symbol(key,"a32_value"));
    assert(tl_a32_call(value,0,0,0,0)==0&&!tl_a32_error());
    assert(tl_a32_init(key));assert(tl_a32_call(value,0,0,0,0)==37);
    assert(tl_a32_call(tl_a32_va(symbol(key,"a32_add")),5,7,0,0)==12&&!tl_a32_error());
    assert(tl_a32_jni_onload(key)==0x10006&&!tl_a32_error());
    assert(!tl_a32_alloc(UINT32_MAX));
    tl_a32_call(tl_a32_va(symbol(key,"a32_loop")),0,0,0,0);assert(tl_a32_error());assert(!tl_a32_init(key));
    tl_a32_reset();assert(!tl_a32_error()&&tl_a32_map(key,"reopen",file,n));
    assert(tl_a32_call(tl_a32_va(symbol(key,"a32_value")),0,0,0,0)==0);
    assert(tl_ld_add_apk(argv[2]));assert(!tl_ld_has_lib("libonly32.so"));
    assert(tl_ld_lib_apk("libonly32.so")==NULL);
    puts("PASS ARM32 ELF constructor, ARM/Thumb calls, bounded failure, reset and mixed ABI rejection; no game lifecycle claim");free(file);return 0;
}
