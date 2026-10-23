/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "HuskCore.h"
#include <stdio.h>
int main(int argc, char **argv)
{
    if (argc != 4) return 64;
    char error[512] = "";
    if (!husk_archive_extract(argv[1], argv[2], argv[3], error, sizeof(error))) {
        fprintf(stderr, "%s\n", error); return 1;
    }
    return 0;
}
