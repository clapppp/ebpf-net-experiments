#!/bin/bash

# IPv6 끄기 (디바이스 만들기 전에)
sysctl -qw net.ipv6.conf.all.disable_ipv6=1
sysctl -qw net.ipv6.conf.default.disable_ipv6=1

# 1. 네임스페이스 생성
ip netns add ns1
ip netns add ns2
for ns in ns1 ns2; do
    ip netns exec $ns sysctl -qw net.ipv6.conf.all.disable_ipv6=1
    ip netns exec $ns sysctl -qw net.ipv6.conf.default.disable_ipv6=1
done

# 2. veth 쌍 생성 → peer만 각 ns로 이동
ip link add nka0 type veth peer name nka1
ip link add nkb0 type veth peer name nkb1
ip link set nka1 netns ns1
ip link set nkb1 netns ns2

# 3. host 쪽 켜기
ip link set nka0 up
ip link set nkb0 up

# 4. ns1 / ns2: IP 부여, 켜기, 기본 경로
ip netns exec ns1 ip addr add 10.0.0.2/32 dev nka1
ip netns exec ns1 ip link set nka1 up
ip netns exec ns1 ip route add default dev nka1
ip netns exec ns2 ip addr add 10.0.0.3/32 dev nkb1
ip netns exec ns2 ip link set nkb1 up
ip netns exec ns2 ip route add default dev nkb1

# 5. host 라우팅
ip route add 10.0.0.2/32 dev nka0
ip route add 10.0.0.3/32 dev nkb0
sysctl -qw net.ipv4.ip_forward=1

# 6. veth는 ARP를 하므로 host가 대신 응답하도록 proxy_arp 켜기
sysctl -qw net.ipv4.conf.nka0.proxy_arp=1
sysctl -qw net.ipv4.conf.nkb0.proxy_arp=1

echo "setup done (veth)"