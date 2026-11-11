#include <stdlib.h>
#include <time.h>
#include <arpa/inet.h>
#include <sys/socket.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

/* client <ip> <port> <초당 패킷 수> <보낼 시간 초> : 64바이트 UDP를 일정 간격으로 보낸다 */
int main(int argc, char **argv) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in addr = { .sin_family = AF_INET, .sin_port = htons(atoi(argv[2])) };
    inet_pton(AF_INET, argv[1], &addr.sin_addr);
    connect(fd, (struct sockaddr *)&addr, sizeof(addr));

    double interval = 1e9 / atof(argv[3]);
    long long start = now_ns(), end = start + atoll(argv[4]) * 1000000000LL;
    char buf[64] = {0};
    for (long long i = 0; now_ns() < end; i++) {
        while (now_ns() < start + (long long)(i * interval)) ;
        send(fd, buf, sizeof(buf), 0);
    }
}
