/* SPDX-License-Identifier: GPL-2.0-or-later */
extern void luaL_openlibs(void *);
extern int husk_lua_interpreter(void);
extern char *getenv(const char *);
int Java_org_husk_lifecycle_Runtime31Checks_nativeLua(void *env,void *cls) {
    luaL_openlibs(env);
    return getenv("TL_NO_XMEM") ? (husk_lua_interpreter()?2:0) : 1;
}
