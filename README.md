# ebpf-net-experiments

netkit / veth 데이터 경로를 bpftrace와 eBPF로 관찰하는 실험.

## 0. 요구사항

- Linux 커널 6.7 이상 (`CONFIG_NETKIT`, `CONFIG_DEBUG_INFO_BTF`)
- iproute2 6.7 이상, libbpf 1.3 이상
- root 권한

테스트 환경: Ubuntu 26.04, 커널 7.0.0-43

## 1. packet-monitor / backlog-count

```bash
sudo apt install -y git make gcc clang bpftool bpftrace libbpf-dev libelf-dev zlib1g-dev
```

```bash
make -C tools/nk_loader
```

## 2. VM 실험 환경

**확인**
- 하드웨어 가상화(VT-x/AMD-V)와 `/dev/kvm`
- CPU 토폴로지 (`lscpu -e=CPU,CORE`)

**설치**
- `qemu-system-x86`, `libvirt-daemon-system`, `virt-install`, `cloud-image-utils`
- Ubuntu cloud image

**VM 구성**
- cloud image를 필요한 크기로 늘려 디스크로 사용
- vCPU 2, 메모리 4GiB, `host-passthrough`, virtio NIC

**CPU 고정**
- 호스트: `isolcpus`로 실험용 코어 격리(SMT 형제 포함), `irqaffinity`로 IRQ 분리
- 게스트: 격리한 코어에 vCPU를 1:1로 pin (`virsh vcpupin`)
