// Keeps file descriptor 0 open.
//
// The Epic Online Services library inside the Rust server (EOS_Platform_Create) closes fd 0.
// Mono, the game's runtime, still has it registered as stdin, so the next file or socket the
// process opens is handed descriptor 0 and Mono aborts with "duplicate File fd 0" (or "Socket").
// Carbon trips over it by writing a file at startup, and Rust+ by opening a socket.
//
// The server never reads stdin (the console is WebRCON), so ignoring close(0) is harmless.
// Loaded with LD_PRELOAD by entrypoint.sh.
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
