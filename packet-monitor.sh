#!/bin/bash

PING='ip netns exec ns1 ping -q -c 1 -W 3 10.0.0.3'

echo "===== A. veth + host 라우팅 ====="
./tools/clean-up.sh
./tools/veth-setup.sh
bpftrace ./tools/hdr.bt -c "$PING" | grep -E '^(TX|RX)'

echo "===== B. netkit (BPF 없음) ====="
./tools/clean-up.sh
./tools/netkit-setup.sh
bpftrace ./tools/hdr.bt -c "$PING" | grep -E '^(TX|RX)'

echo "===== C. netkit + redirect BPF ====="
./tools/clean-up.sh
./tools/netkit-setup.sh
./tools/nk_loader/nk_loader &
LOADER=$!
sleep 1
bpftrace ./tools/hdr.bt -c "$PING" | grep -E '^(TX|RX)'
kill $LOADER
wait $LOADER

./tools/clean-up.sh