#!/usr/bin/env python3
"""Talk to a USB-connected Playdate over its serial console (macOS/Linux, stdlib only).

  pdserial.py "btn menu" "btn b"     send console commands, print replies
  pdserial.py --screen out.png       capture the device screen as a PNG
  PLAYDATE_PORT=/dev/cu.usbmodemXXX  override port auto-detection
"""
import glob, os, struct, sys, time, tty, zlib


def port():
    p = os.environ.get("PLAYDATE_PORT") or next(iter(sorted(glob.glob("/dev/cu.usbmodemPD*") + glob.glob("/dev/ttyACM*"))), None)
    if not p:
        sys.exit("No Playdate serial port found. Is it plugged in, unlocked, and not held by the Simulator/pdutil?")
    return p


def read(fd, secs):
    end, out = time.time() + secs, b""
    while time.time() < end:
        try:
            out += os.read(fd, 65536)
        except BlockingIOError:
            time.sleep(0.01)
    return out


def png(bits, path):
    rows = [b"\x00" + bytes(255 if (bits[y * 50 + x // 8] >> (7 - x % 8)) & 1 else 0 for x in range(400)) for y in range(240)]
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 400, 240, 8, 0, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")
    open(path, "wb").write(data)


def main(args):
    fd = os.open(port(), os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    tty.setraw(fd)
    read(fd, 0.3)
    if args[:1] == ["--screen"]:
        os.write(fd, b"screen\n")
        data = read(fd, 2.5)
        i = data.find(b"~screen:\n")
        if i < 0:
            sys.exit("No screen data received")
        png(data[i + 9 : i + 9 + 12000], args[1] if len(args) > 1 else "screen.png")
        return
    for cmd in args:
        os.write(fd, (cmd + "\n").encode())
        print(f"{cmd!r} -> {read(fd, 1.5).decode(errors='replace')[:1500]}")


if __name__ == "__main__":
    main(sys.argv[1:])
