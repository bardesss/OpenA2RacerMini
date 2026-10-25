#!/usr/bin/env python3
"""Draw the OpenA2RacerMini box art: an original, plain title card.

Night sky, a road running to the horizon and the title in a blocky 5x7 font.
Every pixel is computed here from simple shapes; no Davilex artwork is used.
Standard library only (zlib + struct PNG writer).

Usage: python3 make_box_art.py OUTPUT.png
"""
import struct
import sys
import zlib

W, H = 250, 360
HORIZON = 210

# 5x7 glyphs, one string per row, '#' = set.
FONT = {
    "A": [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    "C": [" ####", "#    ", "#    ", "#    ", "#    ", "#    ", " ####"],
    "E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
    "I": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####"],
    "M": ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"],
    "N": ["#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #"],
    "O": [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    "P": ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
    "R": ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
    "2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
    " ": ["     "] * 7,
}


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw():
    px = [[(0, 0, 0)] * W for _ in range(H)]
    # Sky: deep blue to a warm band at the horizon.
    for y in range(HORIZON):
        t = y / HORIZON
        c = lerp((12, 16, 48), (40, 30, 90), t) if t < 0.75 else lerp(
            (40, 30, 90), (230, 120, 60), (t - 0.75) / 0.25)
        px[y] = [c] * W
    # Ground and a road narrowing to a point on the horizon.
    cx = W // 2
    for y in range(HORIZON, H):
        t = (y - HORIZON) / (H - HORIZON)
        half = int(4 + t * 150)
        stripe = int(t * t * 40) % 2
        for x in range(W):
            d = abs(x - cx)
            if d < half:
                c = (70, 70, 78)
                if d > half - max(2, half // 14):
                    c = (220, 60, 50) if stripe else (235, 235, 235)
                elif d < max(1, half // 40) and stripe:
                    c = (240, 210, 70)
            else:
                c = lerp((20, 60, 30), (35, 100, 45), t)
            px[y][x] = c
    return px


def text(px, s, scale, y, colour, shadow=(0, 0, 0)):
    width = (len(s) * 6 - 1) * scale
    x0 = (W - width) // 2
    for off, c in ((max(1, scale // 2), shadow), (0, colour)):
        for i, ch in enumerate(s):
            for r, row in enumerate(FONT[ch]):
                for k, bit in enumerate(row):
                    if bit != "#":
                        continue
                    for dy in range(scale):
                        for dx in range(scale):
                            yy = y + r * scale + dy + off
                            xx = x0 + (i * 6 + k) * scale + dx + off
                            if 0 <= xx < W and 0 <= yy < H:
                                px[yy][xx] = c


def png(px):
    raw = b"".join(b"\0" + bytes(v for p in row for v in p) for row in px)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    px = draw()
    text(px, "OPEN", 5, 30, (255, 255, 255))
    text(px, "A2", 12, 80, (255, 211, 90), (120, 40, 20))
    text(px, "RACER MINI", 3, 178, (255, 255, 255))
    with open(sys.argv[1], "wb") as f:
        f.write(png(px))


if __name__ == "__main__":
    main()
