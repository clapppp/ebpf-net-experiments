#include <stdlib.h>
#include <time.h>
#include <arpa/inet.h>
#include <sys/socket.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

/* server <port> <패킷당 처리 시간 ns> */
int main(int argc, char **argv) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    int rcvbuf = 65536;
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));

    struct sockaddr_in addr = { .sin_family = AF_INET, .sin_port = htons(atoi(argv[1])) };
    bind(fd, (struct sockaddr *)&addr, sizeof(addr));

    long long service_ns = atoll(argv[2]);
    char buf[2048];
    for (;;) {
        recv(fd, buf, sizeof(buf), 0);
        long long t = now_ns();
        while (now_ns() - t < service_ns) ;
    }
}
