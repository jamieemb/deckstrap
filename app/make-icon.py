#!/usr/bin/env python3
"""Generate app/icon.png (512x512) with the standard library only: a rounded
dark tile with a blue "d"-like mark, matching the installer's colours."""
import struct
import zlib
from pathlib import Path

W = H = 512
BG = (14, 17, 22)        # --bg
TILE = (23, 27, 36)      # --panel
ACCENT = (26, 159, 255)  # --accent
WHITE = (238, 241, 245)


def inside_round_rect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def inside_circle(x, y, cx, cy, r):
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


rows = []
for y in range(H):
    row = bytearray([0])
    for x in range(W):
        if not inside_round_rect(x, y, 16, 16, W - 17, H - 17, 96):
            c = (0, 0, 0, 0)                      # transparent corners
        else:
            c = (*TILE, 255)
            # the mark: a blue ring with a stem on the right, a loose "d"
            if inside_circle(x, y, 236, 300, 128) and not inside_circle(x, y, 236, 300, 72):
                c = (*ACCENT, 255)
            if 320 <= x <= 376 and 120 <= y <= 372:
                c = (*ACCENT, 255)
            if 320 <= x <= 376 and 120 <= y <= 150:
                c = (*WHITE, 255)
        row += bytes(c)
    rows.append(bytes(row))

raw = b"".join(rows)


def chunk(tag, body):
    c = tag + body
    return struct.pack(">I", len(body)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
out = Path(__file__).with_name("icon.png")
out.write_bytes(png)
print(f"wrote {out} ({len(png)} bytes)")
