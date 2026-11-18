#!/bin/bash

# 사전에 호스트의 공개키를 vm에 등록후, 첫 연결로 vm 공개키를 받아와야함
# VM 이름과 사용자 계정, IP를 등록
VM=rx-vm
VM_USER=ubuntu
IP=$(virsh -c qemu:///system domifaddr $VM | awk '/ipv4/ { sub("/.*", "", $4); print $4 }')
# client가 프레임을 직접 쓸 호스트 tap(vnetX)과 VM MAC, 출발지 IP(브리지 주소)
read VNET VM_MAC < <(virsh -c qemu:///system domiflist $VM | awk 'NR > 2 && NF { print $1, $5; exit }')
SRC_IP=$(ip -4 -o addr show dev $(basename "$(readlink /sys/class/net/$VNET/master)") | awk '{ sub("/.*", "", $4); print $4 }')

# 호스트 경로
SRC=tools/udp_xdp_drop
# VM 경로
DST=udp_xdp_drop
# 1배 송신 속도 , 초당 5만패킷 : 한 패킷당 20us = 0,02ms = 0.00002초
BASE_PPS=50000
PORT=9000
# 측정 1회 길이 (초)
DURATION=6
# 사전에 격리한 cpu "cat /sys/devices/system/cpu/isolated" , "lscpu -e=CPU,CORE"
# client 고정 호스트 격리 CPU 1,3,4
CLIENT_CPU=1

g() { ssh "$VM_USER@$IP" "$@"; }

# 코드 배포, 빌드
g mkdir -p $DST
scp -q $SRC/Makefile $SRC/*.c $SRC/guest.sh $VM_USER@$IP:$DST/
g sudo $DST/guest.sh setup
make -s -C $SRC host
# AF_PACKET 송신 권한. 다시 빌드되면 사라지므로 없을 때만 부여
getcap $SRC/client | grep -q cap_net_raw || sudo setcap cap_net_raw+ep $SRC/client

# 트래픽 없을때 sock의 증가량 = cpu 100% 기준을 잼
g sudo $DST/guest.sh calib $PORT

# 측정: 소켓, XDP × 기준 속도의 1,4,8배로 송신
for mode in sock xdp; do
    for m in 1 4 8; do
        pps=$((BASE_PPS * m))
        echo "== $mode, $pps pps (${m} 배수) =="
        g sudo $DST/guest.sh start $PORT $mode
        taskset -c $CLIENT_CPU $SRC/client $VNET $SRC_IP $VM_MAC $IP $PORT $pps $DURATION > /dev/null
        { echo "sec arrived sock_drop xdp_drop irq soak_%"
          g sudo $DST/guest.sh stop $DURATION; } | column -t
    done
done
