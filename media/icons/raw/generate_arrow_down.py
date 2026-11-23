"""Generate a 64x32 faceted downward dart TGA for the interrupt-chain playhead.

Renders at 8x, box-filters to 64x32, and writes uncompressed 32-bit BGRA TGA
(bottom-left origin, matching the other icons in media/icons/). Grayscale RGB
stays tintable via SetVertexColor; the baked drop shadow is pure black.
"""

from __future__ import print_function

import math
import os

WIDTH = 64
HEIGHT = 32
SS = 8
SHADOW_OFFSET = 2
SHADOW_PEAK = 0.42
SHADOW_SIGMA = 1.15
FOOTER = b"\x00\x00\x00\x00\x00\x00\x00\x00TRUEVISION-XFILE.\x00"

# Screen-space vertices as pixel centers (y grows downward).
LEFT_WING = (10.5, 6.5)
RIGHT_WING = (54.5, 6.5)
NOTCH = (32.5, 12.5)
TIP = (32.5, 26.5)
RIDGE_X = 32.0


def orient(ax, ay, bx, by, cx, cy):
    return (ax - cx) * (by - cy) - (bx - cx) * (ay - cy)


def in_triangle(px, py, a, b, c):
    d1 = orient(px, py, a[0], a[1], b[0], b[1])
    d2 = orient(px, py, b[0], b[1], c[0], c[1])
    d3 = orient(px, py, c[0], c[1], a[0], a[1])
    has_neg = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
    has_pos = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
    return not (has_neg and has_pos)


def in_dart(px, py):
    return in_triangle(px, py, LEFT_WING, NOTCH, TIP) or in_triangle(
        px, py, RIGHT_WING, NOTCH, TIP
    )


def long_edge_x(y, wing):
    t = (y - wing[1]) / (TIP[1] - wing[1])
    return wing[0] + (TIP[0] - wing[0]) * t


def shade(px, py):
    if px < RIDGE_X:
        span = RIDGE_X - long_edge_x(py, LEFT_WING)
        u = 0.0 if span <= 1e-6 else max(0.0, min(1.0, (RIDGE_X - px) / span))
        return 255.0 - 20.0 * u
    span = long_edge_x(py, RIGHT_WING) - RIDGE_X
    u = 0.0 if span <= 1e-6 else max(0.0, min(1.0, (px - RIDGE_X) / span))
    return 215.0 - 25.0 * u


def render_dart():
    coverage = [[0.0] * WIDTH for _ in range(HEIGHT)]
    gray = [[0.0] * WIDTH for _ in range(HEIGHT)]
    inv = 1.0 / float(SS * SS)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            inside = 0
            shade_sum = 0.0
            for sy in range(SS):
                py = y + (sy + 0.5) / float(SS)
                for sx in range(SS):
                    px = x + (sx + 0.5) / float(SS)
                    if in_dart(px, py):
                        inside += 1
                        shade_sum += shade(px, py)
            coverage[y][x] = inside * inv
            if inside > 0:
                gray[y][x] = shade_sum / float(inside)
    return coverage, gray


def gaussian_kernel(sigma):
    radius = int(math.ceil(sigma * 3.0))
    values = []
    total = 0.0
    for i in range(-radius, radius + 1):
        v = math.exp(-(i * i) / (2.0 * sigma * sigma))
        values.append(v)
        total += v
    return [v / total for v in values]


def convolve_axis(src, kernel, horizontal):
    radius = len(kernel) // 2
    out = [[0.0] * WIDTH for _ in range(HEIGHT)]
    for y in range(HEIGHT):
        for x in range(WIDTH):
            acc = 0.0
            for i, weight in enumerate(kernel):
                if horizontal:
                    xx = x + i - radius
                    if xx < 0:
                        xx = 0
                    elif xx >= WIDTH:
                        xx = WIDTH - 1
                    acc += src[y][xx] * weight
                else:
                    yy = y + i - radius
                    if yy < 0:
                        yy = 0
                    elif yy >= HEIGHT:
                        yy = HEIGHT - 1
                    acc += src[yy][x] * weight
            out[y][x] = acc
    return out


def shadow_from(coverage):
    shifted = [[0.0] * WIDTH for _ in range(HEIGHT)]
    for y in range(HEIGHT):
        dest = y + SHADOW_OFFSET
        if dest >= HEIGHT:
            continue
        row = coverage[y]
        dest_row = shifted[dest]
        for x in range(WIDTH):
            dest_row[x] = row[x]
    kernel = gaussian_kernel(SHADOW_SIGMA)
    blurred = convolve_axis(convolve_axis(shifted, kernel, True), kernel, False)
    peak = 0.0
    for y in range(HEIGHT):
        row = blurred[y]
        for x in range(WIDTH):
            if row[x] > peak:
                peak = row[x]
    if peak > 0.0:
        scale = SHADOW_PEAK / peak
        for y in range(HEIGHT):
            row = blurred[y]
            for x in range(WIDTH):
                row[x] *= scale
    return blurred


def clamp_byte(value):
    rounded = int(round(value))
    if rounded < 0:
        return 0
    if rounded > 255:
        return 255
    return rounded


def composite(coverage, gray, shadow):
    pixels = []
    for y in range(HEIGHT):
        row = []
        for x in range(WIDTH):
            dart_a = coverage[y][x]
            shadow_a = shadow[y][x]
            out_a = dart_a + shadow_a * (1.0 - dart_a)
            if out_a <= 0.0 or x == 0 or y == 0 or x == WIDTH - 1 or y == HEIGHT - 1:
                row.append((0, 0))
            else:
                out_g = (gray[y][x] * dart_a) / out_a
                row.append((out_g, out_a))
        pixels.append(row)
    return pixels


def write_tga(path, pixels):
    header = bytearray(18)
    header[2] = 2
    header[12] = WIDTH & 255
    header[13] = (WIDTH >> 8) & 255
    header[14] = HEIGHT & 255
    header[15] = (HEIGHT >> 8) & 255
    header[16] = 32
    header[17] = 8
    body = bytearray(WIDTH * HEIGHT * 4)
    i = 0
    for y in range(HEIGHT - 1, -1, -1):
        row = pixels[y]
        for x in range(WIDTH):
            gray, alpha = row[x]
            g = clamp_byte(gray)
            a = clamp_byte(alpha * 255.0)
            body[i] = g
            body[i + 1] = g
            body[i + 2] = g
            body[i + 3] = a
            i += 4
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(body)
        handle.write(FOOTER)


def main():
    coverage, gray = render_dart()
    shadow = shadow_from(coverage)
    pixels = composite(coverage, gray, shadow)
    out_dir = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    path = os.path.join(out_dir, "arrow_down.tga")
    write_tga(path, pixels)
    print("wrote", path)


if __name__ == "__main__":
    main()
