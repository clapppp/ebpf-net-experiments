#!/bin/bash

VM=rx-vm
VM_USER=ubuntu
IP=$(virsh -c qemu:///system domifaddr $VM | awk '/ipv4/ { sub("/.*", "", $4); print $4 }')

SRC=tools/udp_xdp_drop
DST=udp_xdp_drop
SERVICE_NS=20000    # server의 패킷당 처리 시간 → 처리율 μ = 1e9 / SERVICE_NS
PORT=9000
DURATION=10         # 측정 1회 길이 (초)
CLIENT_CPU=1        # client를 고정할 호스트 격리 CPU

g() { ssh "$VM_USER@$IP" "$@"; }

# 코드 배포, 빌드
g mkdir -p $DST
scp -q $SRC/Makefile $SRC/*.c $SRC/guest.sh $VM_USER@$IP:$DST/
g sudo $DST/guest.sh setup
make -s -C $SRC host

# 측정: 수신 처리율(μ)과 같은 속도, 4배 속도
MU=$((1000000000 / SERVICE_NS))
for m in 1 4; do
    pps=$((MU * m))
    echo "== $pps pps (${m} x μ) =="
    g sudo $DST/guest.sh start $SERVICE_NS $PORT
    taskset -c $CLIENT_CPU $SRC/client $IP $PORT $pps $DURATION > /dev/null
    { echo "sec arrived_pps goodput_pps sock_drop_pps softirq_% user_%"
      g sudo $DST/guest.sh stop; } | column -t
done
