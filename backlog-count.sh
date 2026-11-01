#!/bin/bash

TRACE='tracepoint:net:netif_rx { @[str(args->name)] = count(); }'
PING='ip netns exec ns1 ping -q -c 10 10.0.0.3'

echo "===== BPF 없음 ====="
./tools/clean-up.sh
./tools/netkit-setup.sh
bpftrace -e "$TRACE" -c "$PING"

echo "===== BPF 있음 ====="
./tools/clean-up.sh
./tools/netkit-setup.sh
./nk_loader &
LOADER=$!
sleep 1
bpftrace -e "$TRACE" -c "$PING"
kill $LOADER
wait $LOADER

./tools/clean-up.sh