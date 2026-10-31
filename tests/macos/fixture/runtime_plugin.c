/* SPDX-License-Identifier: GPL-2.0-or-later */
static int loaded;
#ifdef IL2CPP_FIXTURE
static volatile int log_set, policy_set, term_set, constructor_ready;
void il2cpp_register_log_callback(void (*fn)(const char *)) { log_set=fn!=0;if(fn)fn("controlled late IL2CPP fixture"); }
void il2cpp_runtime_unhandled_exception_policy_set(int value) { policy_set=value==0; }
void set_terminate(void (*fn)(void)) { term_set=fn!=0; }
__attribute__((constructor)) static void initialize(void) { constructor_ready=1; }
int husk_il2_ready(void) {return constructor_ready&&log_set&&policy_set&&term_set&&loaded==1;}
#endif
int JNI_OnLoad(void *vm,void *reserved) {
    if(!vm)return -1;
#ifdef IL2CPP_FIXTURE
    if(!constructor_ready || !log_set || !policy_set || !term_set)return -1;
#endif
    loaded++;return 0x10006;
}
int husk_plugin_count(void) {return loaded;}
#ifdef LUAJIT_FIXTURE
/* ABI fixture: proves the interpreter switch runs after openlibs, before app code. */
static int opened, disabled;
void luaL_openlibs(void *state) {opened=state!=0;disabled=0;}
int luaJIT_setmode(void *state,int index,int mode) {disabled=opened&&state&&index==0&&mode==0;return disabled;}
int husk_lua_interpreter(void) {return opened&&disabled;}
#endif
