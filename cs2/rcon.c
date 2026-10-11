/* Minimal Source RCON client: rcon <port> <command>, password from RCON_PASSWORD. */
#include <arpa/inet.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

enum { AUTH = 3, AUTH_RESPONSE = 2, EXEC = 2, RESPONSE = 0 };
enum { MAX_BODY = 8192, FIRST_WAIT_MS = 5000, IDLE_WAIT_MS = 400 };

static int sock;

static int write_all(const unsigned char *p, size_t n) {
  while (n > 0) {
    ssize_t w = write(sock, p, n);
    if (w <= 0) return -1;
    p += w;
    n -= (size_t)w;
  }
  return 0;
}

static int read_all(unsigned char *p, size_t n, int wait_ms) {
  while (n > 0) {
    struct pollfd pfd = {sock, POLLIN, 0};
    if (poll(&pfd, 1, wait_ms) <= 0) return -1;
    ssize_t r = read(sock, p, n);
    if (r <= 0) return -1;
    p += r;
    n -= (size_t)r;
  }
  return 0;
}

static int send_packet(int32_t id, int32_t type, const char *body) {
  size_t len = strlen(body);
  int32_t size = (int32_t)(10 + len);
  unsigned char *buf = malloc((size_t)size + 4);
  if (!buf) return -1;
  memcpy(buf, &size, 4);
  memcpy(buf + 4, &id, 4);
  memcpy(buf + 8, &type, 4);
  memcpy(buf + 12, body, len);
  buf[12 + len] = 0;
  buf[13 + len] = 0;
  int rc = write_all(buf, (size_t)size + 4);
  free(buf);
  return rc;
}

static int read_packet(int wait_ms, int32_t *id, int32_t *type, char *body) {
  int32_t size;
  if (read_all((unsigned char *)&size, 4, wait_ms) < 0) return -1;
  if (size < 10 || size > MAX_BODY + 10) return -1;
  unsigned char *buf = malloc((size_t)size);
  if (!buf) return -1;
  if (read_all(buf, (size_t)size, wait_ms) < 0) {
    free(buf);
    return -1;
  }
  memcpy(id, buf, 4);
  memcpy(type, buf + 4, 4);
  memcpy(body, buf + 8, (size_t)size - 10);
  body[size - 10] = 0;
  free(buf);
  return 0;
}

int main(int argc, char **argv) {
  const char *password = getenv("RCON_PASSWORD");
  if (argc != 3 || !password) {
    fprintf(stderr, "usage: RCON_PASSWORD=... rcon <port> <command>\n");
    return 64;
  }
  struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons((uint16_t)atoi(argv[1]))};
  inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
  sock = socket(AF_INET, SOCK_STREAM, 0);
  if (sock < 0 || connect(sock, (struct sockaddr *)&addr, sizeof addr) < 0) {
    fprintf(stderr, "could not reach the game console (is the server fully started?)\n");
    return 1;
  }

  static char body[MAX_BODY + 1];
  int32_t id, type;
  if (send_packet(1, AUTH, password) < 0) return 1;
  for (;;) {
    if (read_packet(FIRST_WAIT_MS, &id, &type, body) < 0) {
      fprintf(stderr, "the game console did not answer\n");
      return 1;
    }
    if (type == AUTH_RESPONSE) break;
  }
  if (id == -1) {
    fprintf(stderr, "the game console refused the password\n");
    return 2;
  }

  if (send_packet(2, EXEC, argv[2]) < 0) return 1;
  int wait_ms = FIRST_WAIT_MS;
  while (read_packet(wait_ms, &id, &type, body) == 0) {
    if (type == RESPONSE && body[0]) fputs(body, stdout);
    wait_ms = IDLE_WAIT_MS;
  }
  return 0;
}
