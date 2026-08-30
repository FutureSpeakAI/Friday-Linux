#!/usr/bin/env python3
"""Friday Linux — CI-only TCP relay. See friday-boot-test-relay.service's
header comment for why this exists (loopback-bound friday.service +
QEMU slirp hostfwd cannot otherwise be reached from the host in CI).

Deliberately stdlib-only (no third-party dependency, no dependency on the
Agent-Friday venv, which this must run independently of) and deliberately
tiny: accept on (listen_host, listen_port), for each client connection open
one connection to (target_host, target_port), and pump bytes both ways
until either side closes. No parsing of the proxied protocol at all.
"""
from __future__ import annotations

import socket
import sys
import threading


def pump(src: socket.socket, dst: socket.socket) -> None:
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def handle(client: socket.socket, target_host: str, target_port: int) -> None:
    try:
        upstream = socket.create_connection((target_host, target_port), timeout=5)
    except OSError as exc:
        print(f"[boot-test-relay] upstream connect failed: {exc}", flush=True)
        client.close()
        return
    t1 = threading.Thread(target=pump, args=(client, upstream), daemon=True)
    t2 = threading.Thread(target=pump, args=(upstream, client), daemon=True)
    t1.start()
    t2.start()
    t1.join()
    t2.join()
    client.close()
    upstream.close()


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print(f"usage: {argv[0]} <listen_host> <listen_port> <target_host> <target_port>",
              file=sys.stderr)
        return 2
    listen_host, listen_port, target_host, target_port = (
        argv[1], int(argv[2]), argv[3], int(argv[4])
    )
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((listen_host, listen_port))
    server.listen(8)
    print(f"[boot-test-relay] {listen_host}:{listen_port} -> {target_host}:{target_port}",
          flush=True)
    while True:
        client, addr = server.accept()
        threading.Thread(target=handle, args=(client, target_host, target_port),
                          daemon=True).start()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
