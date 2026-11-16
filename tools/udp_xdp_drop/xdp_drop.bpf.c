// UDP 패킷의 목적지 소켓을 찾아, 수신 버퍼가 이미 넘쳤으면 XDP에서 버린다.
// 판단 기준은 커널 __udp_enqueue_schedule_skb의 첫 검사(rmem > rcvbuf → drop)와 같다.
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>
#include <bpf/bpf_core_read.h>

#define ETH_P_IP 0x0800
#define IPPROTO_UDP 17

extern void *bpf_rdonly_cast(void *obj, __u32 btf_id) __ksym;

SEC("xdp")
int xdp_rmem_drop(struct xdp_md *ctx)
{
    void *data = (void *)(long)ctx->data;
    void *end = (void *)(long)ctx->data_end;

    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > end || eth->h_proto != bpf_htons(ETH_P_IP))
        return XDP_PASS;

    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > end || ip->protocol != IPPROTO_UDP)
        return XDP_PASS;

    struct udphdr *udp = (void *)ip + ip->ihl * 4;
    if ((void *)(udp + 1) > end)
        return XDP_PASS;

    struct bpf_sock_tuple t = {
        .ipv4.saddr = ip->saddr, .ipv4.daddr = ip->daddr,
        .ipv4.sport = udp->source, .ipv4.dport = udp->dest,
    };
    struct bpf_sock *bsk = bpf_sk_lookup_udp(ctx, &t, sizeof(t.ipv4), BPF_F_CURRENT_NETNS, 0);
    if (!bsk)
        return XDP_PASS;

    struct sock *sk = bpf_rdonly_cast(bsk, bpf_core_type_id_kernel(struct sock));
    int full = sk->sk_backlog.rmem_alloc.counter > sk->sk_rcvbuf;
    bpf_sk_release(bsk);

    return full ? XDP_DROP : XDP_PASS;
}

char LICENSE[] SEC("license") = "GPL";
