# ebpf-net-experiments

netkit / veth 데이터 경로를 bpftrace와 eBPF로 관찰하는 실험 모음.

| 스크립트 | 내용 |
|---|---|
| `packet-monitor.sh` | veth, netkit, netkit + redirect BPF 세 구성에서 수신 측(`nkb1`)에 도착한 패킷의 헤더를 계층별로 덤프해 비교 |
| `backlog-count.sh` | netkit에서 redirect BPF 유무에 따라 `netif_rx`(backlog 큐 경유) 호출 횟수가 어떻게 달라지는지 비교 |

두 스크립트 모두 `ns1`(10.0.0.2) → `ns2`(10.0.0.3)로 ping을 보내면서 측정한다.

## 0. 환경 요구사항

- **Linux 커널 6.7 이상** — netkit 디바이스와 `netkit/peer` BPF attach가 6.7에서 들어왔다.
  - `CONFIG_NETKIT=y`
  - `CONFIG_DEBUG_INFO_BTF=y` (bpftrace가 `struct sk_buff` 등을 BTF로 해석)
- **iproute2 6.7 이상** — `ip link add ... type netkit`
- **libbpf 1.3 이상** — `bpf_program__attach_netkit()`
- **root 권한** — 네임스페이스 생성, BPF 로드, bpftrace 실행

확인:

```bash
uname -r
```

```bash
grep -E 'CONFIG_NETKIT|CONFIG_DEBUG_INFO_BTF' /boot/config-$(uname -r)
```

테스트한 환경:

| 항목 | 버전 |
|---|---|
| 배포판 | Ubuntu 26.04.1 LTS |
| 커널 | 7.0.0-43-generic |
| bpftrace | 0.25.0 |
| clang | 21.1.8 |
| bpftool / libbpf | 7.7.0 / 1.7 |
| iproute2 | 6.19.0 |

## 1. packet-monitor / backlog-count 실행

### 설치

```bash
sudo apt update
```

```bash
sudo apt install -y git make gcc clang llvm bpftool bpftrace libbpf-dev libelf-dev zlib1g-dev iproute2 iputils-ping
```

### 빌드

netkit primary에 redirect 프로그램을 붙이는 로더(`tools/nk_loader`)를 빌드한다.

```bash
git clone https://github.com/clapppp/ebpf-net-experiments.git
```

```bash
cd ebpf-net-experiments
```

```bash
make -C tools/nk_loader
```

### 실행

스크립트가 `./tools/...`를 상대 경로로 부르므로 **저장소 루트에서** 실행한다.

```bash
sudo ./packet-monitor.sh
```

```bash
sudo ./backlog-count.sh
```

> **주의** — 셋업 스크립트는 호스트의 sysctl을 바꾼다: IPv6 비활성화
> (`net.ipv6.conf.{all,default}.disable_ipv6=1`), IPv4 포워딩 활성화
> (`net.ipv4.ip_forward=1`). `tools/clean-up.sh`는 네임스페이스와 디바이스만
> 지우고 sysctl은 되돌리지 않는다. 실험 전용 머신이나 VM에서 돌리는 것을 권장한다.

## 2. VM 실험 환경 구성

측정 노이즈를 줄이기 위해 수신 측을 **전용 물리 코어에 고정한 KVM 게스트**로 띄운다.
아래 항목을 확인·구성한 뒤, 게스트 안에서 이 저장소를 clone해서 실험을 실행한다.

### 확인할 것

- **하드웨어 가상화** — CPU가 VT-x/AMD-V를 지원하고 BIOS에서 켜져 있는지
  (`/proc/cpuinfo`에 `vmx` 또는 `svm` 플래그).
- **KVM 사용 가능 여부** — `/dev/kvm`이 존재하는지, `kvm-ok`가 통과하는지.
- **CPU 토폴로지** — `lscpu -e=CPU,CORE`로 어떤 논리 CPU가 같은 물리 코어의
  SMT 형제인지 확인. 고정할 코어를 고를 때 필요하다.
- **libvirt 기본 네트워크** — `virsh net-list`에서 `default`가 활성 상태인지.

### 설치할 것

- QEMU/KVM과 libvirt: `qemu-system-x86`, `libvirt-daemon-system`, `libvirt-clients`, `virt-install`
- cloud-init 시드 이미지 생성용: `cloud-image-utils`
- KVM 점검용: `cpu-checker`
- 게스트 디스크로 쓸 Ubuntu cloud image (`wget`으로 내려받음)

### VM 구성

- 내려받은 cloud image를 실험에 필요한 크기로 늘려 게스트 디스크로 쓴다.
- cloud-init 시드 이미지로 계정과 SSH 키를 주입한다.
- vCPU 2개, 메모리 4GiB, CPU 모델은 `host-passthrough`.
- NIC은 virtio, libvirt `default` 네트워크(NAT)에 연결.
- 게스트 커널도 0번의 요구사항을 만족해야 한다.

### CPU 고정

- **호스트에서 코어 격리** — 커널 부트 파라미터 `isolcpus`로 실험용 코어를
  스케줄러에서 빼고, `irqaffinity`로 인터럽트를 나머지 코어에만 보낸다.
  격리할 때는 SMT 형제까지 같이 뺀다. 적용 후 `/sys/devices/system/cpu/isolated`로 확인.
- **vCPU 고정** — 격리한 코어에 vCPU를 1:1로 pin 한다 (`virsh vcpupin`).
  서로 다른 물리 코어에 올려 vCPU끼리 코어를 공유하지 않게 한다.

테스트 환경(6코어 12스레드) 기준 예시:

| 항목 | 값 |
|---|---|
| 격리 코어 | `isolcpus=1,3,4,7,9,10` (물리 코어 1, 3, 4와 SMT 형제) |
| IRQ | `irqaffinity=0,2,5,6,8,11` |
| vCPU 0 → 호스트 CPU | 3 |
| vCPU 1 → 호스트 CPU | 4 |

### 실행

VM이 뜨면 `virsh domifaddr <vm>`로 주소를 확인해 SSH로 접속하고,
게스트 안에서 1번의 설치·빌드 절차를 그대로 따라 저장소를 clone해 실행한다.
