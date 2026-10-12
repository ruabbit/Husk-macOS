/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <stdio.h>
#include <stdlib.h>
int tl_manifest_gles(const char *);
int main(int argc,char **argv) {
    if(argc<3||!(argc&1))return 64;
    for(int i=1;i<argc;i+=2) {
        int got=tl_manifest_gles(argv[i]),expected=(int)strtol(argv[i+1],NULL,0);
        if(got!=expected){fprintf(stderr,"FAIL %s: %#x != %#x\n",argv[i],got,expected);return 1;}
    }
    puts("PASS GLES manifest encoding, resource ID, maximum version and malformed bounds");return 0;
}
