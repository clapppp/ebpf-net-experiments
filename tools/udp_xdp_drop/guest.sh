#!/bin/bash
# VM 안에서 root로 실행. 사용: guest.sh setup | start <service_ns> <port> | stop
# server와 NIC 수신 처리(softirq)는 vCPU0, 모니터와 bpftrace는 vCPU1
cd "$(dirname "$0")"
IF=$(ip -o -4 route show default | awk '{print $5}')

# vCPU0에서 NET_RX softirq가 쓴 시간(ns) 누적값을 10ms마다 출력
SOFTIRQ_BT='
tracepoint:irq:softirq_entry /cpu == 0 && args->vec == 3/ { @s = nsecs; }
tracepoint:irq:softirq_exit /cpu == 0 && args->vec == 3 && @s/ { @t = @t + (nsecs - @s); @s = 0; }
interval:ms:10 { printf("%lld\n", @t); }'

# 누적 카운터 한 줄: 시각(ns) 도착 처리 소켓드롭 softirq(ns)
snap() {
    echo $(date +%s%N) $(cat /sys/class/net/$IF/statistics/rx_packets) \
         $(awk '/^Udp:/ { if (n++) print $2, $6 }' /proc/net/snmp) \
         $(tail -n1 /tmp/softirq)
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
    pkill -x bpftrace
    rm -f /tmp/softirq
    taskset -c 1 bpftrace -B line -e "$SOFTIRQ_BT" > /tmp/softirq 2>&1 < /dev/null &
    until grep -q '^[0-9]' /tmp/softirq 2>/dev/null; do sleep 0.1; done
    taskset -c 0 ./server $3 $2 > /dev/null 2>&1 < /dev/null &
    taskset -c 1 ./guest.sh monitor > /tmp/samples 2>&1 < /dev/null &
    ;;
monitor)
    while :; do snap; sleep 1; done
    ;;
stop)
    pkill -f 'guest.sh monitor'
    snap >> /tmp/samples
    pkill -x server
    pkill -x bpftrace
    # 이웃한 두 줄의 차이를 초당 값으로: 초, 도착, 처리, 드롭, softirq%
    awk 'NR > 1 { dt = ($1 - p[1]) / 1e9
                  if (dt > 0.5) printf "%d %d %d %d %.1f\n", ++sec, ($2 - p[2]) / dt,
                         ($3 - p[3]) / dt, ($4 - p[4]) / dt, ($5 - p[5]) / dt / 1e7 }
         { for (i = 1; i <= 5; i++) p[i] = $i }' /tmp/samples
    ;;
esac
