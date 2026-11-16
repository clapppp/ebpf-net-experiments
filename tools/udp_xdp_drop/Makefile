.PHONY: all host guest clean

all: host guest
host: client    # 송신 측 (호스트)
guest: server soak xdp_drop.bpf.o   # 수신 측 (VM)

client: client.c
	gcc -O2 -o $@ $<

server: server.c
	gcc -O2 -o $@ $<

soak: soak.c
	gcc -O2 -o $@ $<

vmlinux.h:
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@

xdp_drop.bpf.o: xdp_drop.bpf.c vmlinux.h
	clang -O2 -g -target bpf -c $< -o $@

clean:
	rm -f client server soak xdp_drop.bpf.o vmlinux.h
