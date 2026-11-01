#!/usr/bin/env python3
"""Convert a binary PPM (P6), as written by QEMU's screendump, to PNG. Stdlib only."""
import struct
import sys
import zlib


def read_ppm(path):
    data = open(path, "rb").read()
    # header: P6 <ws> width <ws> height <ws> maxval <single ws> pixels (comments possible)
    tokens, i = [], 0
    while len(tokens) < 4:
        while data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            while data[i:i + 1] not in (b"\n", b""):
                i += 1
            continue
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        tokens.append(data[i:j])
        i = j
    i += 1
    magic, w, h, maxval = tokens[0], int(tokens[1]), int(tokens[2]), int(tokens[3])
    if magic != b"P6" or maxval != 255:
        raise SystemExit("unsupported PPM")
    return w, h, data[i:i + w * h * 3]


def write_png(path, w, h, rgb):
    raw = b"".join(b"\x00" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def chunk(tag, body):
        c = tag + body
        return struct.pack(">I", len(body)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    w, h, rgb = read_ppm(src)
    write_png(dst, w, h, rgb)
    print(f"{dst} ({w}x{h})")
