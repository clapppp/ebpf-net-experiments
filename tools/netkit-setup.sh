#!/bin/bash

# 1. 네임스페이스 생성
sudo ip netns add ns1
sudo ip netns add ns2

#ipv6의 제어패킷 방지
# (추가) ns 안의 IPv6 끄기 — 디바이스를 옮기기 전에
sudo ip netns exec ns1 sysctl -qw net.ipv6.conf.all.disable_ipv6=1
sudo ip netns exec ns1 sysctl -qw net.ipv6.conf.default.disable_ipv6=1
sudo ip netns exec ns2 sysctl -qw net.ipv6.conf.all.disable_ipv6=1
sudo ip netns exec ns2 sysctl -qw net.ipv6.conf.default.disable_ipv6=1

# (추가) host의 IPv6 끄기 — netkit 생성 전에
sudo sysctl -qw net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -qw net.ipv6.conf.default.disable_ipv6=1

# 2. netkit 쌍 생성 (둘 다 host에 생김) → peer만 각 ns로 이동
sudo ip link add nka0 type netkit mode l3 peer name nka1
sudo ip link add nkb0 type netkit mode l3 peer name nkb1
sudo ip link set nka1 netns ns1
sudo ip link set nkb1 netns ns2

# 3. host 쪽 primary 켜기
sudo ip link set nka0 up
sudo ip link set nkb0 up

# 4. ns1: IP 부여, 켜기, 기본 경로를 nka1로
sudo ip netns exec ns1 ip addr add 10.0.0.2/32 dev nka1
sudo ip netns exec ns1 ip link set nka1 up
sudo ip netns exec ns1 ip route add default dev nka1

# 5. ns2: 같은 설정
sudo ip netns exec ns2 ip addr add 10.0.0.3/32 dev nkb1
sudo ip netns exec ns2 ip link set nkb1 up
sudo ip netns exec ns2 ip route add default dev nkb1

# 6. host 라우팅 (BPF 없을 때 host가 중계하는 경로)
sudo ip route add 10.0.0.2/32 dev nka0
sudo ip route add 10.0.0.3/32 dev nkb0
sudo sysctl -qw net.ipv4.ip_forward=1

echo "setup done (netkit)"