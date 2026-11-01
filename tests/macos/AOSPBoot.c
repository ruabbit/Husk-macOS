/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-aosp.h"
#include "husk-tl-servicemanager.h"
#include "husk-tl-binder.h"
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
void tl_log_line(const char *fmt, ...) { (void)fmt; }
int main(int argc,char **argv) {
    assert(argc==4);char paths[20][1200];const char *boot[20];int expected=atoi(argv[2]);
    int n=husk_aosp_boot_jars(argv[1],paths,atoi(argv[3]),boot);assert(n==expected);
    if(n>0){assert(strstr(boot[0],"core-oj.jar"));assert(strstr(boot[n-1],"org.apache.http.legacy.jar"));
        assert(strstr(boot[7],n==9?"husk-framework.dex":"husk-framework-core.dex"));}
    if(n>=10)assert(strstr(boot[8],"aosp/framework.jar"));
    assert(husk_aosp_using()==(n>9));
    husk_aosp_set_session("org.husk.fixture",720,1280);
    husk_aosp_start_system();husk_binder_reply reply={0};
    assert(!husk_binder_transact(husk_sm_get("activity"),1,0,NULL,0,NULL,0,&reply));
    int32_t code;assert(reply.data_size>=4);memcpy(&code,reply.data,4);assert(code==-7);husk_binder_reply_free(&reply);
    const char *services[]={"activity","window","power","permission","package"};
    for(size_t i=0;i<5;i++) {
        uint32_t handle=husk_sm_get(services[i]);assert(handle);
        assert(!husk_binder_transact(handle,0x5f504e47u,0,NULL,0,NULL,0,&reply));
        assert(!reply.data_size&&!reply.n_offsets);husk_binder_reply_free(&reply);
        assert(!husk_binder_transact(handle,1,0,NULL,0,NULL,0,&reply));
        assert(reply.data_size==8);memcpy(&code,reply.data,4);assert(code==-7);husk_binder_reply_free(&reply);
        assert(!husk_binder_transact(handle,0x5f434d44u,0,NULL,0,NULL,0,&reply));
        memcpy(&code,reply.data,4);assert(code==-7);husk_binder_reply_free(&reply);
    }
    assert(!husk_binder_transact(husk_sm_get("activity"),0x5f4e5446u,0,NULL,0,NULL,0,&reply));
    const char *want="android.app.IActivityManager";
    memcpy(&code,reply.data,4);assert(code==(int32_t)strlen(want)&&reply.data_size>=4+(strlen(want)+1)*2);
    for(int32_t i=0;i<code;i++){uint16_t ch;memcpy(&ch,reply.data+4+i*2,2);assert(ch==(unsigned char)want[i]);}
    husk_binder_reply_free(&reply);
    puts("PASS complete boot path, AOSP descriptor/PING and unsupported method/permission/shell replies");return 0;
}
