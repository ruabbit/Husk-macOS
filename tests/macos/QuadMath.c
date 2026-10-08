/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "husk-tl-bionic.h"
#include <stdlib.h>
#define assert(c) do {if(!(c)){fprintf(stderr,"check failed at line %d: %s\n",__LINE__,#c);exit(1);}} while(0)
#include <fenv.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
typedef unsigned long long quad __attribute__((ext_vector_type(2)));
void tl_log_line(const char *format,...) {(void)format;}
static void same(quad a,quad b) {assert(a[0]==b[0]&&a[1]==b[1]);}
int main(void)
{
    quad (*fraction)(quad,int *)=tl_bionic_find("frexpl");
    quad (*scale)(quad,int)=tl_bionic_find("ldexpl");
    assert(fraction&&scale);
    const quad one={0,0x3fff000000000000},half={0,0x3ffe000000000000},tiny={1,0};
    int e;
    same(fraction(one,&e),half);assert(e==1);
    same(fraction(tiny,&e),half);assert(e==-16493);
    same(scale(half,-16493),tiny);
    for(int exponent=-16494;exponent<=16383;exponent+=127){
        quad x=scale(one,exponent),f=fraction(x,&e);same(scale(f,e),x);
    }
    quad precise={0x123456789abcdef0,0x4010fedcba987654};
    same(scale(scale(precise,-24),24),precise);
    quad minusZero={0,0x8000000000000000},infinity={0,0x7fff000000000000},nan={123,0x7fff800000000000};
    same(fraction(minusZero,&e),minusZero);assert(e==0);
    same(scale(nan,INT_MAX),nan);same(scale(infinity,INT_MIN),infinity);
    same(scale(one,INT_MAX),infinity);same(scale(one,INT_MIN),(quad){0,0});
    same(scale(tiny,-1),(quad){0,0});
    same(scale((quad){3,0},-1),(quad){2,0});
    fesetround(FE_UPWARD);same(scale(tiny,INT_MIN),tiny);
    fesetround(FE_DOWNWARD);same(scale(one,INT_MAX),(quad){UINT64_MAX,0x7ffeffffffffffff});
    fesetround(FE_TONEAREST);
    puts("PASS binary128 exponent scaling, subnormals, precision, bounds and rounding");return 0;
}
