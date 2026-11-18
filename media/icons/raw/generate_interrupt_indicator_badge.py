"""Generate 64x64 white rounded-square TGAs for the interrupt indicator badge.

Renders at 4x, box-filters to 64x64, and writes uncompressed 32-bit BGRA TGA
(bottom-left origin, matching the other icons in media/icons/).
"""

from __future__ import print_function

import math
import os

SIZE = 64
SS = 4
HI = SIZE * SS
RADIUS = 14
BORDER = 4
FOOTER = b"\x00\x00\x00\x00\x00\x00\x00\x00TRUEVISION-XFILE.\x00"


def sdf_round_rect(x, y, left, top, right, bottom, radius):
    cx = (left + right) * 0.5
    cy = (top + bottom) * 0.5
    hw = (right - left) * 0.5
    hh = (bottom - top) * 0.5
    px = abs(x - cx) - (hw - radius)
    py = abs(y - cy) - (hh - radius)
    outside = math.hypot(max(px, 0.0), max(py, 0.0))
    inside = min(max(px, py), 0.0)
    return outside + inside - radius


def render(left, top, right, bottom, radius):
    acc = [[0.0] * SIZE for _ in range(SIZE)]
    for y in range(HI):
        row = y // SS
        py = y + 0.5
        for x in range(HI):
            sdf = sdf_round_rect(x + 0.5, py, left, top, right, bottom, radius)
            if sdf <= 0.0:
                acc[row][x // SS] += 1.0
    scale = 1.0 / float(SS * SS)
    return [[acc[y][x] * scale for x in range(SIZE)] for y in range(SIZE)]


def write_tga(path, alpha):
    header = bytearray(18)
    header[2] = 2
    header[12] = SIZE & 255
    header[13] = (SIZE >> 8) & 255
    header[14] = SIZE & 255
    header[15] = (SIZE >> 8) & 255
    header[16] = 32
    header[17] = 8
    body = bytearray(SIZE * SIZE * 4)
    i = 0
    for y in range(SIZE - 1, -1, -1):
        row = alpha[y]
        for x in range(SIZE):
            a = int(round(row[x] * 255.0))
            if a < 0:
                a = 0
            elif a > 255:
                a = 255
            body[i] = 255
            body[i + 1] = 255
            body[i + 2] = 255
            body[i + 3] = a
            i += 4
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(body)
        handle.write(FOOTER)


def main():
    out_dir = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    outer = render(0.0, 0.0, float(HI), float(HI), RADIUS * SS)
    inset = BORDER * SS
    inner = render(inset, inset, HI - inset, HI - inset, (RADIUS - BORDER) * SS)
    border_path = os.path.join(out_dir, "interrupt_indicator_badge_border.tga")
    fill_path = os.path.join(out_dir, "interrupt_indicator_badge_fill.tga")
    write_tga(border_path, outer)
    write_tga(fill_path, inner)
    print("wrote", border_path)
    print("wrote", fill_path)


if __name__ == "__main__":
    main()
