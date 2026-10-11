// The Epic Online Services library in the Rust server closes fd 0. Mono still treats it as stdin
// and hands the number to the next file or socket it opens, then aborts with "duplicate File fd 0".
// The server never reads stdin, so ignoring close(0) is harmless. Loaded through LD_PRELOAD.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <unistd.h>

int close(int fd) {
    static int (*real_close)(int);
    if (fd == 0) {
        return 0;
    }
    if (!real_close) {
        real_close = (int (*)(int))dlsym(RTLD_NEXT, "close");
    }
    return real_close(fd);
}
