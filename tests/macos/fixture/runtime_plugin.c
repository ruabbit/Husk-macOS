/* SPDX-License-Identifier: GPL-2.0-or-later */
static int loaded;
int JNI_OnLoad(void *vm,void *reserved) {if(!vm)return -1;loaded++;return 0x10006;}
int husk_plugin_count(void) {return loaded;}
#ifdef LUAJIT_FIXTURE
/* ABI fixture: proves the interpreter switch runs after openlibs, before app code. */
static int opened, disabled;
void luaL_openlibs(void *state) {opened=state!=0;disabled=0;}
int luaJIT_setmode(void *state,int index,int mode) {disabled=opened&&state&&index==0&&mode==0;return disabled;}
int husk_lua_interpreter(void) {return opened&&disabled;}
#endif
