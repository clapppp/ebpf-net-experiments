# ebpf-net-experiments

netkit / veth 데이터 경로를 bpftrace와 eBPF로 관찰하는 실험.

발표 자료와 자세한 설명: [clapppp.org](https://clapppp.org)

## 0. 요구사항

- Linux 커널 6.7 이상 (`CONFIG_NETKIT`, `CONFIG_DEBUG_INFO_BTF`)
- iproute2 6.7 이상, libbpf 1.3 이상
- root 권한

테스트 환경: Ubuntu 26.04, 커널 7.0.0-43

## 1. packet-monitor / backlog-count

`bpftrace`, `libbpf1` 필요

## 2. udp-xdp-drop

- 호스트: `isolcpus`로 코어 격리(SMT 형제 포함), `irqaffinity`로 IRQ 분리 후 재부팅
- VM: Ubuntu cloud image, vCPU 2개를 격리 코어에 1:1 pin (`virsh vcpupin`), 메모리 4GiB
- VM에 `gcc`, `make`, `bpftrace` 설치, 호스트 공개키를 VM에 등록 (`ssh-copy-id`)
