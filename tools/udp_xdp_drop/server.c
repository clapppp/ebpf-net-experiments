#include <stdlib.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

/* server <port> : bind만 하고 읽지 않는다. 수신 버퍼가 차면 이후 패킷은 전부 드롭된다 */
int main(int argc, char **argv) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    int rcvbuf = 65536; //64KB -> 실제 할당은 두배임
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));

    struct sockaddr_in addr = { .sin_family = AF_INET, .sin_port = htons(atoi(argv[1])) };
    bind(fd, (struct sockaddr *)&addr, sizeof(addr));

    for (;;)
        pause();
}
