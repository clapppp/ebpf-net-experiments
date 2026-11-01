#include <stdio.h>          // printf, fprintf, perror
#include <unistd.h>         // pause
#include <net/if.h>         // if_nametoindex
#include <bpf/libbpf.h>     // libbpf API (attach 등)
#include "nk.skel.h"        // bpftool이 nk.bpf.o로 만들어준 스켈레톤

int main(void)
{
    /* 1. 디바이스 이름 → ifindex */
    int a = if_nametoindex("nka0");
    int b = if_nametoindex("nkb0");
    if (!a || !b) { perror("if_nametoindex"); return 1; }

    /* 2. open: BPF 오브젝트를 메모리에 읽기만 함 (커널에는rm 아직 안 올림) */
    struct nk_bpf *skel = nk_bpf__open();
    if (!skel) { fprintf(stderr, "open failed\n"); return 1; }

    /* 3. 로드 전에 BPF 쪽 const volatile 변수 채우기 */
    skel->rodata->ifidx_a = a;
    skel->rodata->ifidx_b = b;

    /* 4. load: 커널에 올림 → 이때 verifier 검사 */
    if (nk_bpf__load(skel)) { fprintf(stderr, "load failed\n"); return 1; }

    /* 5. attach: 같은 프로그램을 두 primary에 각각 붙임 */
    struct bpf_link *la = bpf_program__attach_netkit(skel->progs.nk_redirect, a, NULL);
    struct bpf_link *lb = bpf_program__attach_netkit(skel->progs.nk_redirect, b, NULL);
    if (!la || !lb) { perror("attach"); return 1; }

    printf("attached to nka0(%d), nkb0(%d). Ctrl+C to detach\n", a, b);

    /* 6. 신호가 올 때까지 대기. Ctrl+C → 프로세스 종료 → link 해제 → 자동 detach */
    pause();
    return 0;
}