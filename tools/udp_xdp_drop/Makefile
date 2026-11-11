.PHONY: all host guest clean

all: host guest
host: client    # 송신 측 (호스트)
guest: server   # 수신 측 (VM)

client: client.c
	gcc -O2 -o $@ $<

server: server.c
	gcc -O2 -o $@ $<

clean:
	rm -f client server
