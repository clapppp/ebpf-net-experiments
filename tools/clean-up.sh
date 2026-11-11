#!/bin/bash

# 1. 네임스페이스 삭제 (안의 nka1, nkb1도 같이 사라짐)
for ns in ns1 ns2; do
    ip netns del "$ns" 2>/dev/null
done

# 2. host에 남은 netkit 디바이스 삭제
for dev in nka0 nkb0 nk0; do
    ip link del "$dev" 2>/dev/null
done

# 3. 확인
ip netns list
ip -br link | grep '^nk' || echo clean
