#include <linux/bpf.h>        // struct __sk_buff
#include <linux/if_ether.h>   // struct ethhdr, ETH_P_IP
#include <linux/if_link.h>    // NETKIT_PASS 등 반환값
#include <linux/ip.h>         // struct iphdr
#include <bpf/bpf_helpers.h>  // SEC(), bpf_redirect()
#include <bpf/bpf_endian.h>   // bpf_htons(), bpf_htonl()

/* 로더가 로드 직전에 채워 넣는 ifindex */
const volatile int ifidx_a = 0;   /* nka0 */
const volatile int ifidx_b = 0;   /* nkb0 */

/* peer(ns 쪽)가 패킷을 보낼 때마다 실행됨. attach는 primary에 */
SEC("netkit/peer")
int nk_redirect(struct __sk_buff *skb)
{
    /* 패킷 시작/끝 주소: 32비트 필드 → long(64비트) → 주소 */
    void *data     = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;

    /* [Ethernet 14B][IP 20B]... 순서로 구조체 틀 씌우기 */
    struct ethhdr *eth = data;
    struct iphdr  *iph = (void *)(eth + 1);   /* eth 다음 = IP 헤더 */

    /* 경계 검사: 없으면 verifier가 로드를 거부함 */
    if ((void *)(iph + 1) > data_end)
        return NETKIT_PASS;

    /* IPv4가 아니면 그냥 통과 */
    if (eth->h_proto != bpf_htons(ETH_P_IP))
        return NETKIT_PASS;

    /* 상대 ns 주소면 host 라우팅을 건너뛰고 상대 primary로 바로 송신 */
    if (iph->daddr == bpf_htonl(0x0a000003))   /* 10.0.0.3 → nkb0 */
        return bpf_redirect(ifidx_b, 0);
    if (iph->daddr == bpf_htonl(0x0a000002))   /* 10.0.0.2 → nka0 */
        return bpf_redirect(ifidx_a, 0);

    /* 그 외: 원래 경로 (host netns로 올라가서 라우팅) */
    return NETKIT_PASS;
}

char LICENSE[] SEC("license") = "GPL";