#!/bin/bash

# server soak irq는 vCPU0, 측정은 vCPU1
# bpf로 irq에 모니터링했더니 자원 30% 씀 

# 첫 인자인 guest쉘이 있는 경로로 이동
cd "$(dirname "$0")"
# VM 인터페이스
IF=$(ip -o -4 route show default | awk '{print $5}')
# VM 디바이스 이름 가져오기 (virtio1)
VDEV=$(basename "$(readlink /sys/class/net/$IF/device)")
# soak 카운터
CNT=/dev/shm/soak
# 트래픽 없을 때 soak 초당 증가량 (100% 기준)
BASE=/tmp/soak_base

# 누적 카운터 한 줄: 시각(ns) 도착 소켓드롭 XDP드롭 NIC인터럽트수 soak카운터
snap() {
    echo $(date +%s%N) $(cat /sys/class/net/$IF/statistics/rx_packets) \
         $(awk '/^Udp:/ { if (n++) print $6 }' /proc/net/snmp) \
         $(ethtool -S $IF | awk '/rx_queue_[0-9]+_xdp_drops/ { s += $2 } END { print s + 0 }') \
         $(awk -v d="$VDEV-input" '$NF ~ d { s += $2 } END { print s + 0 }' /proc/interrupts) \
         $(od -An -tu8 -N8 $CNT)
}

# vm 안에 실행하던거 모니터, 서버, soak, (irq) 다 종료
kill_all() {
    pkill -f 'guest.sh monitor'
    pkill -x server
    pkill -x soak
    while pgrep -x 'server|soak' > /dev/null; do sleep 0.1; done
    ip link set dev $IF xdp off
}

# server, (xdp), soak 실행
launch() {
    kill_all
    rm -f $CNT
    taskset -c 0 ./server $1 > /dev/null 2>&1 < /dev/null &
    if [ "$2" = xdp ]; then
        ip link set dev $IF xdpdrv obj xdp_drop.bpf.o sec xdp || exit 1
    fi
    # sock이 백그라운드로 실행
    taskset -c 0 ./soak $CNT > /dev/null 2>&1 < /dev/null &
    # soak이 뭔가를 쓸때까지 기다림 = 시작
    until [ -s $CNT ]; do sleep 0.1; done
}

case $1 in
setup)
    make -s guest
    # irq 밸런싱을 끄고 irq가 돌아갈 cpu를 명시
    systemctl stop irqbalance 2>/dev/null
    for irq in $(awk -F: '/virtio.*-(input|output)/ { print $1 }' /proc/interrupts); do
        echo 0 > /proc/irq/$irq/smp_affinity_list 2>/dev/null
    done
    ;;

# 트래픽 없을때 = server, soak 측정
calib)
    launch $2 sock
    sleep 1
    
    a=$(snap); sleep 3; b=$(snap)
    kill_all
    base=$(echo $a $b | awk '{ printf "%.0f\n", ($12 - $6) / (($7 - $1) / 1e9) }')
    if [ "$base" -le 0 ]; then echo "calib 실패: $base" >&2; exit 1; fi
    echo $base > $BASE
    ;;

# samples에 snap으로 적어놓고 stop 호출시 samples 출력
start)
    launch $2 $3
    taskset -c 1 ./guest.sh monitor > /tmp/samples 2>&1 < /dev/null &
    ;;

monitor)
    while :; do snap; sleep 1; done
    ;;

stop)
    pkill -f 'guest.sh monitor'
    kill_all
    # 이웃한 두 줄의 차이를 초당 값으로. %는 vCPU0 기준
    # 초, 도착, 소켓드롭, XDP드롭, 인터럽트, soak
    awk -v base=$(cat $BASE) '
        NR > 1 { dt = ($1 - p[1]) / 1e9
                 if (dt > 0.5)
                     printf "%d %d %d %d %d %.1f\n", ++sec, ($2 - p[2]) / dt, ($3 - p[3]) / dt,
                         ($4 - p[4]) / dt, ($5 - p[5]) / dt, ($6 - p[6]) / dt / base * 100 }
        { for (i = 1; i <= 6; i++) p[i] = $i }' /tmp/samples | head -n $(( $2 - 1 ))
    ;;
esac
