#!/usr/bin/env python3
"""Render a VRAM dump as a tile sheet so graphics can be inspected visually."""

import argparse
import struct
import zlib
from pathlib import Path


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def decode_tile(data, bpp):
    """Return an 8x8 grid of palette indices from one SNES tile."""
    px = [[0] * 8 for _ in range(8)]
    planes = bpp
    for y in range(8):
        vals = []
        for pl in range(planes):
            # Planes are stored in interleaved pairs, 16 bytes per pair.
            group, within = divmod(pl, 2)
            idx = group * 16 + y * 2 + within
            vals.append(data[idx] if idx < len(data) else 0)
        for x in range(8):
            v = 0
            for pl, byte in enumerate(vals):
                v |= ((byte >> (7 - x)) & 1) << pl
            px[y][x] = v
    return px


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vram")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--bpp", type=int, default=4, choices=(2, 4))
    ap.add_argument("--cols", type=int, default=32)
    ap.add_argument("--start", type=lambda s: int(s, 0), default=0)
    ap.add_argument("--tiles", type=int, default=0, help="0 = to end of dump")
    ap.add_argument("--scale", type=int, default=1)
    args = ap.parse_args()

    data = Path(args.vram).read_bytes()
    tile_size = 8 * args.bpp
    avail = (len(data) - args.start) // tile_size
    count = avail if args.tiles == 0 else min(args.tiles, avail)

    cols = args.cols
    rows_of_tiles = (count + cols - 1) // cols
    width, height = cols * 8, rows_of_tiles * 8
    maxval = (1 << args.bpp) - 1

    canvas = [bytearray(width) for _ in range(height)]
    for t in range(count):
        off = args.start + t * tile_size
        px = decode_tile(data[off:off + tile_size], args.bpp)
        tx, ty = (t % cols) * 8, (t // cols) * 8
        for y in range(8):
            for x in range(8):
                canvas[ty + y][tx + x] = px[y][x] * 255 // maxval

    if args.scale > 1:
        k = args.scale
        scaled = []
        for row in canvas:
            wide = bytes(b for b in row for _ in range(k))
            scaled.extend([wide] * k)
        canvas, width, height = scaled, width * k, height * k

    write_png(args.out, width, height, [bytes(r) for r in canvas])
    print(f"wrote {args.out}: {count} tiles @ {args.bpp}bpp, {width}x{height}, "
          f"from offset 0x{args.start:04X}")


if __name__ == "__main__":
    main()
