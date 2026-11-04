"""Prueba desde fuera un servidor GSMDesk, sin instalar nada.

Comprueba que responde al test de NAT por UDP (P2P), que rechaza los paquetes con un
tamaño absurdo, que el relé rechaza a quien no tiene la llave y que une a dos conexiones
con la llave correcta.

Uso: python probar-servidor.py HOST LLAVE_PUBLICA
"""
import socket
import struct
import sys
import uuid

HBBS_PORT = 21116
HBBR_PORT = 21117
TIMEOUT = 6


def varint(n):
    out = bytearray()
    while n > 0x7F:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    out.append(n)
    return bytes(out)


def length_delimited(field, data):
    return varint((field << 3) | 2) + varint(len(data)) + data


def frame(body):
    """The length prefix of hbb_common's BytesCodec."""
    if len(body) <= 0x3F:
        return bytes([len(body) << 2]) + body
    return struct.pack("<H", (len(body) << 2) | 1) + body


def request_relay(relay_uuid, key):
    inner = length_delimited(2, relay_uuid.encode()) + length_delimited(6, key.encode())
    return frame(length_delimited(18, inner))  # RendezvousMessage.request_relay


def connect(host, port):
    return socket.create_connection((host, port), timeout=TIMEOUT)


def closes_soon(sock):
    try:
        return sock.recv(1) == b""
    except ConnectionError:
        return True
    except socket.timeout:
        return False


def udp_nat_test(host, _key):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.settimeout(2)
        for _ in range(3):
            s.sendto(bytes([0xA2, 0x01, 0x00]), (host, HBBS_PORT))  # test_nat_request
            try:
                data, _addr = s.recvfrom(2048)
            except socket.timeout:
                continue
            return data[:2] == bytes([0xAA, 0x01])  # test_nat_response
    return False


def rejects_huge_packet(host, port):
    huge = struct.pack("<I", (0x3F000000 << 2) | 3)  # claims about 1 GB
    with connect(host, port) as s:
        s.sendall(huge)
        if not closes_soon(s):
            return False
    with connect(host, port):
        return True


def relay_rejects(host, key):
    pair = uuid.uuid4().hex
    with connect(host, HBBR_PORT) as a, connect(host, HBBR_PORT) as b:
        a.sendall(request_relay(pair, key))
        b.sendall(request_relay(pair, key))
        return closes_soon(a) and closes_soon(b)


def relay_pairs(host, key):
    pair = uuid.uuid4().hex
    with connect(host, HBBR_PORT) as a, connect(host, HBBR_PORT) as b:
        a.sendall(request_relay(pair, key))
        a.settimeout(1)
        try:
            if a.recv(1) == b"":
                return False  # refused
        except socket.timeout:
            pass  # still waiting for its pair, as it should
        a.settimeout(TIMEOUT)
        b.sendall(request_relay(pair, key))
        ok = True
        for src, dst, text in ((a, b, b"de A a B"), (b, a, b"de B a A")):
            src.sendall(text)
            got = b""
            while len(got) < len(text):
                chunk = dst.recv(64)
                if not chunk:
                    break
                got += chunk
            ok = ok and got == text
        return ok


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    host, key = sys.argv[1:]
    tests = [
        ("El servidor de ID responde al test de NAT por UDP", lambda: udp_nat_test(host, key)),
        ("El servidor de ID rechaza un paquete de 1 GB y sigue vivo", lambda: rejects_huge_packet(host, HBBS_PORT)),
        ("El relé rechaza un paquete de 1 GB y sigue vivo", lambda: rejects_huge_packet(host, HBBR_PORT)),
        ("El relé rechaza una llave equivocada", lambda: relay_rejects(host, "llave-equivocada")),
        ("El relé rechaza una conexión sin llave", lambda: relay_rejects(host, "")),
        ("El relé une a dos conexiones con la llave correcta", lambda: relay_pairs(host, key)),
    ]
    failed = 0
    for name, test in tests:
        try:
            ok = test()
        except OSError as err:
            ok = False
            name += f" ({err})"
        print(("OK    " if ok else "FALLA ") + name)
        failed += not ok
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
