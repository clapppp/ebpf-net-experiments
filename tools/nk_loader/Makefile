ARCH  := $(shell uname -m | sed 's/x86_64/x86/;s/aarch64/arm64/')
MARCH := $(shell uname -m)

all: nk_loader

nk.bpf.o: nk.bpf.c
	clang -O2 -g -target bpf -D__TARGET_ARCH_$(ARCH) \
	  -I/usr/include/$(MARCH)-linux-gnu -c $< -o $@

nk.skel.h: nk.bpf.o
	bpftool gen skeleton $< > $@

nk_loader: nk_loader.c nk.skel.h
	gcc -O2 -g -o $@ nk_loader.c -lbpf -lelf -lz

clean:
	rm -f *.o *.skel.h nk_loader