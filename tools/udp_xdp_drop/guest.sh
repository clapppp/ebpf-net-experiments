#!/bin/bash
# VM 안에서 root로 실행. 사용: guest.sh setup | start <service_ns> <port> | stop
# server와 NIC 수신 처리(softirq)는 vCPU0, 모니터는 vCPU1
cd "$(dirname "$0")"
IF=$(ip -o -4 route show default | awk '{print $5}')

# 누적 카운터 한 줄: 시각(ns) 도착 처리 소켓드롭 softirq틱 user틱 (CPU0)
snap() {
    echo $(date +%s%N) $(cat /sys/class/net/$IF/statistics/rx_packets) \
         $(awk '/^Udp:/ { if (n++) print $2, $6 }' /proc/net/snmp) \
         $(awk '$1 == "cpu0" { print $8, $2 }' /proc/stat)
}

case $1 in
setup)
    make -s guest
    systemctl stop irqbalance 2>/dev/null
    for irq in $(awk -F: '/virtio.*-(input|output)/ { print $1 }' /proc/interrupts); do
        echo 0 > /proc/irq/$irq/smp_affinity_list 2>/dev/null
    done
    ;;
start)
    pkill -x server
    taskset -c 0 ./server $3 $2 > /dev/null 2>&1 < /dev/null &
    taskset -c 1 ./guest.sh monitor > /tmp/samples 2>&1 < /dev/null &
    ;;
monitor)
    while :; do snap; sleep 1; done
    ;;
stop)
    pkill -f 'guest.sh monitor'
    pkill -x server
    snap >> /tmp/samples
    # 이웃한 두 줄의 차이를 초당 값으로: 초, 도착, 처리, 드롭, softirq%, user% (틱 100/초 = 100%)
    awk 'NR > 1 { dt = ($1 - p[1]) / 1e9
                  if (dt > 0.5) printf "%d %d %d %d %.1f %.1f\n", ++sec, ($2 - p[2]) / dt,
                         ($3 - p[3]) / dt, ($4 - p[4]) / dt, ($5 - p[5]) / dt, ($6 - p[6]) / dt }
         { for (i = 1; i <= 6; i++) p[i] = $i }' /tmp/samples
    ;;
esac
