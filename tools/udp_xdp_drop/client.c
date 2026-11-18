#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <arpa/inet.h>
#include <linux/if_packet.h>
#include <net/ethernet.h>
#include <net/if.h>
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <sys/ioctl.h>
#include <sys/socket.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static unsigned short ip_csum(void *hdr, int len) {
    unsigned short *p = hdr;
    unsigned int sum = 0;
    for (; len > 1; len -= 2)
        sum += *p++;
    while (sum >> 16)
        sum = (sum & 0xffff) + (sum >> 16);
    return ~sum;
}

/* client <ifname> <src-ip> <dst-mac> <dst-ip> <port> <초당 패킷 수> <보낼 시간 초>
 * AF_PACKET으로 tap(vnetX)에 이더넷 프레임을 직접 쓴다.
 * 호스트의 UDP/IP, 라우팅, netfilter, 브리지를 거치지 않아 send() 한 번의 비용이 줄어든다.
 * 프레임 크기는 이더넷 14 + IP 20 + UDP 8 + 페이로드 64 = 106바이트. CAP_NET_RAW 필요 */
int main(int argc, char **argv) {
    if (argc != 8) {
        fprintf(stderr, "usage: %s <ifname> <src-ip> <dst-mac> <dst-ip> <port> <pps> <sec>\n", argv[0]);
        return 1;
    }

    /* 프로토콜 0: 송신 전용, 수신 패킷은 받지 않는다 */
    int fd = socket(AF_PACKET, SOCK_RAW, 0);
    if (fd < 0) { perror("socket"); return 1; }
    int one = 1;
    setsockopt(fd, SOL_PACKET, PACKET_QDISC_BYPASS, &one, sizeof(one));

    struct ifreq ifr = {0};
    strncpy(ifr.ifr_name, argv[1], IFNAMSIZ - 1);
    if (ioctl(fd, SIOCGIFINDEX, &ifr) < 0) { perror("SIOCGIFINDEX"); return 1; }
    int ifindex = ifr.ifr_ifindex;
    if (ioctl(fd, SIOCGIFHWADDR, &ifr) < 0) { perror("SIOCGIFHWADDR"); return 1; }

    unsigned char f[14 + 20 + 8 + 64] = {0};
    struct ether_header *eth = (void *)f;
    struct iphdr *ip = (void *)(f + 14);
    struct udphdr *udp = (void *)(f + 34);

    unsigned char *d = eth->ether_dhost;
    if (sscanf(argv[3], "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx", &d[0], &d[1], &d[2], &d[3], &d[4], &d[5]) != 6) {
        fprintf(stderr, "bad mac: %s\n", argv[3]);
        return 1;
    }
    memcpy(eth->ether_shost, ifr.ifr_hwaddr.sa_data, 6);
    eth->ether_type = htons(ETH_P_IP);

    ip->version = 4;
    ip->ihl = 5;
    ip->ttl = 64;
    ip->protocol = IPPROTO_UDP;
    ip->tot_len = htons(20 + 8 + 64);
    inet_pton(AF_INET, argv[2], &ip->saddr);
    inet_pton(AF_INET, argv[4], &ip->daddr);
    ip->check = ip_csum(ip, 20);

    udp->source = htons(12345);
    udp->dest = htons(atoi(argv[5]));
    udp->len = htons(8 + 64);
    udp->check = 0;   /* IPv4 UDP는 체크섬 생략(0) 허용 */

    struct sockaddr_ll to = { .sll_family = AF_PACKET, .sll_protocol = htons(ETH_P_IP),
                              .sll_ifindex = ifindex, .sll_halen = 6 };
    memcpy(to.sll_addr, d, 6);

    double interval = 1e9 / atof(argv[6]);
    long long start = now_ns(), end = start + atoll(argv[7]) * 1000000000LL;
    for (long long i = 0; now_ns() < end; i++) {
        while (now_ns() < start + (long long)(i * interval)) ;
        sendto(fd, f, sizeof(f), 0, (struct sockaddr *)&to, sizeof(to));
    }
}
