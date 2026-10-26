"""Generates the original, tileable PBR textures used by Project Phantom.

Run:  python3 tools/generate_textures.py
Outputs PNGs into assets/textures/. Every texture here is procedurally generated
by this script (no third-party imagery), so the project carries no asset licences.
"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
os.makedirs(OUT, exist_ok=True)
RNG = np.random.default_rng(1337)
S = 512


def smooth(t):
    return t * t * (3 - 2 * t)


def value_noise(size, cells, rng=RNG):
    """Periodic value noise in [0,1]."""
    g = rng.random((cells, cells))
    coords = np.arange(size) * cells / size
    i0 = np.floor(coords).astype(int) % cells
    i1 = (i0 + 1) % cells
    f = smooth(coords - np.floor(coords))
    a = g[np.ix_(i0, i0)]
    b = g[np.ix_(i0, i1)]
    c = g[np.ix_(i1, i0)]
    d = g[np.ix_(i1, i1)]
    fx = f[None, :]
    fy = f[:, None]
    top = a * (1 - fx) + b * fx
    bot = c * (1 - fx) + d * fx
    return top * (1 - fy) + bot * fy


def fbm(size, base=4, octaves=6, gain=0.5, rng=RNG):
    total = np.zeros((size, size))
    amp, norm, cells = 1.0, 0.0, base
    for _ in range(octaves):
        if cells > size:
            break
        total += value_noise(size, cells, rng) * amp
        norm += amp
        amp *= gain
        cells *= 2
    return total / norm


def ridged(size, base=4, octaves=5, rng=RNG):
    n = fbm(size, base, octaves, rng=rng)
    return 1.0 - np.abs(n * 2 - 1)


def normal_from_height(h, strength=4.0):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / ln, ny / ln, nz / ln], axis=-1)
    return ((n * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)


def save_rgb(name, rgb):
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name), optimize=True)


def save_gray(name, g):
    Image.fromarray((np.clip(g, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(OUT, name), optimize=True)


def save_normal(name, h, strength):
    Image.fromarray(normal_from_height(h, strength), "RGB").save(os.path.join(OUT, name), optimize=True)


def colorize(t, c0, c1):
    c0 = np.array(c0)[None, None, :]
    c1 = np.array(c1)[None, None, :]
    return c0 * (1 - t[..., None]) + c1 * t[..., None]


def grid_lines(size, cells_x, cells_y, width):
    y, x = np.mgrid[0:size, 0:size]
    gx = (x % (size // cells_x))
    gy = (y % (size // cells_y))
    lx = np.minimum(gx, size // cells_x - gx)
    ly = np.minimum(gy, size // cells_y - gy)
    d = np.minimum(lx, ly).astype(float)
    return np.clip(1 - d / width, 0, 1), lx, ly


def dots(size, positions, radius):
    y, x = np.mgrid[0:size, 0:size]
    out = np.zeros((size, size))
    for (px, py) in positions:
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                d = np.sqrt((x - px - ox) ** 2 + (y - py - oy) ** 2)
                out = np.maximum(out, np.clip(1 - d / radius, 0, 1))
    return out


# ---------------------------------------------------------------- concrete wall (precast panels)
def concrete_wall():
    n = fbm(S, 4, 7)
    fine = fbm(S, 64, 3)
    stains = np.clip((fbm(S, 3, 5) - 0.45) * 2.2, 0, 1)
    drips = np.clip(value_noise(S, 48)[:, :] ** 6 * 3, 0, 1)
    drips = np.repeat(drips[::8, :], 8, axis=0)[:S]
    seam, _, _ = grid_lines(S, 2, 2, 2.5)
    holes = dots(S, [(64, 64), (192, 64), (64, 192), (192, 192), (320, 64), (448, 64), (320, 192), (448, 192),
                     (64, 320), (192, 320), (64, 448), (192, 448), (320, 320), (448, 320), (320, 448), (448, 448)], 6)
    base = 0.62 + (n - 0.5) * 0.18 + (fine - 0.5) * 0.08 - stains * 0.12 - drips * 0.06 - seam * 0.25 - holes * 0.3
    alb = colorize(np.clip(base, 0, 1), (0.10, 0.09, 0.085), (0.98, 0.93, 0.86))
    save_rgb("concrete_wall_albedo.png", alb)
    h = n * 0.6 + fine * 0.4 - seam * 1.4 - holes * 1.2
    save_normal("concrete_wall_normal.png", h, 3.0)
    save_gray("concrete_wall_rough.png", 0.78 + (fine - 0.5) * 0.2 - stains * 0.1)


# ---------------------------------------------------------------- concrete floor (polished, cracks)
def concrete_floor():
    n = fbm(S, 3, 7)
    fine = fbm(S, 96, 3)
    cracks = np.clip((ridged(S, 6, 5) - 0.965) * 18, 0, 1) * 0.6
    seam, _, _ = grid_lines(S, 1, 1, 2.0)
    patches = np.clip((fbm(S, 5, 4) - 0.55) * 3, 0, 1)
    base = 0.56 + (n - 0.5) * 0.2 + (fine - 0.5) * 0.06 - cracks * 0.3 - seam * 0.3 + patches * 0.05
    alb = colorize(np.clip(base, 0, 1), (0.12, 0.11, 0.105), (0.92, 0.88, 0.82))
    save_rgb("concrete_floor_albedo.png", alb)
    save_normal("concrete_floor_normal.png", n * 0.4 + fine * 0.3 - cracks * 0.8 - seam, 2.5)
    save_gray("concrete_floor_rough.png", 0.55 + patches * 0.25 + (fine - 0.5) * 0.15)


# ---------------------------------------------------------------- metal diamond plate floor
def metal_floor():
    y, x = np.mgrid[0:S, 0:S].astype(float)
    period = 32.0
    u = (x + y) / period
    v = (x - y) / period
    fu = u - np.floor(u) - 0.5
    fv = v - np.floor(v) - 0.5
    lozenge = np.clip(1 - (np.abs(fu) * 7.0 + np.abs(fv) * 1.6), 0, 1)
    # alternate orientation every other cell
    cell = (np.floor(x / period) + np.floor(y / period)) % 2
    u2 = (x - y) / period
    v2 = (x + y) / period
    fu2 = u2 - np.floor(u2) - 0.5
    fv2 = v2 - np.floor(v2) - 0.5
    lozenge2 = np.clip(1 - (np.abs(fu2) * 7.0 + np.abs(fv2) * 1.6), 0, 1)
    plate = np.where(cell > 0, lozenge, lozenge2)
    plate = smooth(np.clip(plate * 1.6, 0, 1))
    n = fbm(S, 6, 6)
    scratches = np.clip((value_noise(S, 128) - 0.8) * 4, 0, 1) * 0.5
    seam, _, _ = grid_lines(S, 1, 1, 3)
    wear = plate * 0.18 + scratches * 0.12
    base = 0.36 + (n - 0.5) * 0.14 + wear - seam * 0.2
    alb = colorize(np.clip(base, 0, 1), (0.05, 0.055, 0.06), (0.78, 0.80, 0.82))
    save_rgb("metal_floor_albedo.png", alb)
    save_normal("metal_floor_normal.png", plate * 1.2 + n * 0.2 - seam, 3.5)
    save_gray("metal_floor_rough.png", np.clip(0.55 - plate * 0.25 + (n - 0.5) * 0.2, 0, 1))


# ---------------------------------------------------------------- painted metal wall panels
def metal_panel():
    n = fbm(S, 4, 6)
    seam, lx, ly = grid_lines(S, 2, 4, 2.0)
    rivet_pos = []
    for gx in range(2):
        for gy in range(4):
            x0, y0 = gx * 256, gy * 128
            for (ox, oy) in ((10, 10), (246, 10), (10, 118), (246, 118), (128, 10), (128, 118)):
                rivet_pos.append((x0 + ox, y0 + oy))
    rivets = dots(S, rivet_pos, 4.5)
    edge_wear = np.clip((1 - np.minimum(lx, ly) / 10.0), 0, 1) * np.clip((fbm(S, 16, 4) - 0.45) * 4, 0, 1)
    grime = np.clip((fbm(S, 3, 5) - 0.5) * 2, 0, 1)
    base = 0.72 + (n - 0.5) * 0.1 - seam * 0.45 - grime * 0.18 + edge_wear * 0.15 + rivets * 0.08
    alb = colorize(np.clip(base, 0, 1), (0.04, 0.045, 0.05), (0.95, 0.96, 0.97))
    save_rgb("metal_panel_albedo.png", alb)
    h = -seam * 1.5 + rivets * 1.2 + n * 0.15
    save_normal("metal_panel_normal.png", h, 4.0)
    save_gray("metal_panel_rough.png", np.clip(0.45 + grime * 0.3 - edge_wear * 0.2, 0, 1))


# ---------------------------------------------------------------- lab floor tiles
def tiles():
    n = fbm(S, 8, 5)
    seam, lx, ly = grid_lines(S, 4, 4, 2.2)
    tile_id = (np.mgrid[0:S, 0:S][0] // 128) * 4 + (np.mgrid[0:S, 0:S][1] // 128)
    tint = RNG.random(16)[tile_id] * 0.06
    dirt = np.clip((fbm(S, 4, 5) - 0.5) * 1.6, 0, 1)
    base = 0.8 + tint + (n - 0.5) * 0.05 - seam * 0.5 - dirt * 0.12
    alb = colorize(np.clip(base, 0, 1), (0.10, 0.12, 0.12), (0.93, 0.96, 0.95))
    save_rgb("tiles_albedo.png", alb)
    save_normal("tiles_normal.png", -seam * 1.2 + n * 0.05, 3.0)
    save_gray("tiles_rough.png", np.clip(0.25 + seam * 0.5 + dirt * 0.3, 0, 1))


# ---------------------------------------------------------------- asphalt
def asphalt():
    n = fbm(S, 6, 7)
    grit = RNG.random((S, S))
    grit = (grit > 0.93) * 0.25 + (grit < 0.04) * -0.15
    cracks = np.clip((ridged(S, 4, 5) - 0.972) * 20, 0, 1) * 0.5
    patches = np.clip((fbm(S, 3, 4) - 0.55) * 3, 0, 1)
    base = 0.32 + (n - 0.5) * 0.14 + grit - cracks * 0.2 - patches * 0.06
    alb = colorize(np.clip(base, 0, 1), (0.04, 0.04, 0.045), (0.62, 0.6, 0.58))
    save_rgb("asphalt_albedo.png", alb)
    save_normal("asphalt_normal.png", n * 0.5 + grit * 1.2 - cracks, 3.0)
    save_gray("asphalt_rough.png", np.clip(0.85 - patches * 0.1, 0, 1))


# ---------------------------------------------------------------- grass
def grass():
    n = fbm(S, 4, 6)
    blades = fbm(S, 128, 3)
    clumps = fbm(S, 12, 4)
    dry = np.clip((fbm(S, 3, 4) - 0.55) * 3, 0, 1)
    soil = np.clip((fbm(S, 8, 5) - 0.68) * 5, 0, 1)
    g = colorize(np.clip(n * 0.5 + blades * 0.5, 0, 1), (0.10, 0.22, 0.05), (0.38, 0.62, 0.16))
    dry_c = colorize(blades, (0.35, 0.33, 0.12), (0.62, 0.56, 0.25))
    soil_c = colorize(n, (0.18, 0.13, 0.08), (0.32, 0.24, 0.15))
    alb = g * (1 - dry[..., None] * 0.6) + dry_c * dry[..., None] * 0.6
    alb = alb * (1 - soil[..., None]) + soil_c * soil[..., None]
    alb *= (0.85 + clumps[..., None] * 0.3)
    save_rgb("grass_albedo.png", alb)
    save_normal("grass_normal.png", blades * 0.8 + clumps * 0.4, 4.0)


# ---------------------------------------------------------------- hazard stripes
def hazard():
    y, x = np.mgrid[0:S, 0:S].astype(float)
    stripe = ((x + y) / 64.0) % 2 < 1
    n = fbm(S, 8, 5)
    wear = np.clip((fbm(S, 12, 5) - 0.6) * 3.5, 0, 1)
    amber = np.array([0.98, 0.62, 0.12])
    dark = np.array([0.07, 0.07, 0.08])
    metal = np.array([0.45, 0.45, 0.46])
    alb = np.where(stripe[..., None], amber[None, None, :], dark[None, None, :])
    alb = alb * (0.88 + n[..., None] * 0.2)
    alb = alb * (1 - wear[..., None]) + metal[None, None, :] * wear[..., None] * (0.7 + n[..., None] * 0.4)
    save_rgb("hazard_albedo.png", alb)
    save_normal("hazard_normal.png", n * 0.3 - wear * 0.4, 2.0)


# ---------------------------------------------------------------- corrugated container steel
def corrugated():
    y, x = np.mgrid[0:S, 0:S].astype(float)
    ridges = 0.5 + 0.5 * np.sin(x / S * np.pi * 2 * 16)
    ridges = np.clip((ridges - 0.15) * 1.4, 0, 1)
    n = fbm(S, 4, 6)
    rust = np.clip((fbm(S, 6, 6) - 0.62) * 4, 0, 1) * (0.4 + 0.6 * (y / S))
    streak = np.repeat(value_noise(S, 64)[:1, :], S, axis=0) * (y / S) ** 2
    base = 0.82 + (n - 0.5) * 0.08 - ridges * 0.08 - streak * 0.2
    alb = colorize(np.clip(base, 0, 1), (0.1, 0.1, 0.1), (0.98, 0.98, 0.98))
    rust_c = np.array([0.42, 0.22, 0.10])
    alb = alb * (1 - rust[..., None] * 0.75) + rust_c[None, None, :] * rust[..., None] * 0.75
    save_rgb("corrugated_albedo.png", alb)
    save_normal("corrugated_normal.png", ridges * 2.0 + n * 0.1, 4.0)
    save_gray("corrugated_rough.png", np.clip(0.55 + rust * 0.35, 0, 1))


# ---------------------------------------------------------------- facade (exterior precast + band seams)
def facade():
    n = fbm(S, 4, 6)
    fine = fbm(S, 64, 3)
    y, x = np.mgrid[0:S, 0:S]
    hseam = np.clip(1 - np.abs((y % 128) - 0) / 2.5, 0, 1) + np.clip(1 - np.abs((y % 128) - 128) / 2.5, 0, 1)
    vseam = np.clip(1 - np.abs((x % 256) - 0) / 2.0, 0, 1)
    seam = np.clip(hseam + vseam, 0, 1)
    streaks = np.repeat(value_noise(S, 96)[:1, :], S, axis=0)
    streaks = np.clip((streaks - 0.6) * 2.5, 0, 1) * ((y % 128) / 128.0)
    base = 0.7 + (n - 0.5) * 0.12 + (fine - 0.5) * 0.06 - seam * 0.3 - streaks * 0.15
    alb = colorize(np.clip(base, 0, 1), (0.1, 0.1, 0.1), (0.97, 0.95, 0.92))
    save_rgb("facade_albedo.png", alb)
    save_normal("facade_normal.png", n * 0.3 + fine * 0.3 - seam * 1.3, 3.0)


# ---------------------------------------------------------------- crate panel (painted composite crate)
def crate():
    n = fbm(S, 6, 5)
    y, x = np.mgrid[0:S, 0:S].astype(float)
    border = np.minimum(np.minimum(x, S - 1 - x), np.minimum(y, S - 1 - y))
    frame = (border < 44).astype(float)
    bevel = np.clip(1 - np.abs(border - 44) / 4, 0, 1)
    d1 = np.abs(x - y) / np.sqrt(2)
    diag = ((d1 < 26) & (border >= 44)).astype(float)
    ribs = ((x % 128) < 4).astype(float) * (1 - frame) * (1 - diag)
    wear = np.clip((fbm(S, 16, 4) - 0.6) * 4, 0, 1) * (frame + diag)
    stencil = ((np.abs(x - 300) < 70) & (np.abs(y - 120) < 18) & (frame < 1) & (diag < 1)).astype(float)
    base = 0.62 + frame * 0.12 + diag * 0.12 + (n - 0.5) * 0.12 - bevel * 0.2 - ribs * 0.1 + wear * 0.15 - stencil * 0.25
    alb = colorize(np.clip(base, 0, 1), (0.05, 0.05, 0.05), (0.98, 0.98, 0.98))
    save_rgb("crate_albedo.png", alb)
    save_normal("crate_normal.png", frame * 1.0 + diag * 1.0 - bevel * 0.3 - ribs * 0.5 + n * 0.1, 3.0)


# ---------------------------------------------------------------- foliage (leaf clusters)
def foliage():
    n = fbm(S, 8, 6)
    leaves = fbm(S, 48, 3)
    alb = colorize(np.clip(n * 0.4 + leaves * 0.6, 0, 1), (0.10, 0.28, 0.08), (0.48, 0.76, 0.22))
    save_rgb("foliage_albedo.png", alb)
    save_normal("foliage_normal.png", leaves * 1.4 + n * 0.3, 5.0)


# ---------------------------------------------------------------- bark
def bark():
    y, x = np.mgrid[0:S, 0:S].astype(float)
    n = fbm(S, 6, 6)
    grooves = np.abs(np.sin((x / S * 2 * np.pi * 10) + n * 6))
    base = 0.4 + grooves * 0.3 + (n - 0.5) * 0.2
    alb = colorize(np.clip(base, 0, 1), (0.10, 0.07, 0.05), (0.52, 0.40, 0.30))
    save_rgb("bark_albedo.png", alb)
    save_normal("bark_normal.png", grooves * 1.5 + n * 0.4, 4.0)


# ---------------------------------------------------------------- RGBA effect sprites (small)
def rgba(name, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name), optimize=True)


def fx_textures():
    s = 128
    y, x = np.mgrid[0:s, 0:s].astype(float)
    cx, cy = (s - 1) / 2, (s - 1) / 2
    r = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / (s / 2)
    ang = np.arctan2(y - cy, x - cx)
    # bullet hole decal
    n = fbm(s, 8, 4)
    hole = np.clip(1 - r / 0.18, 0, 1)
    ring = np.clip(1 - np.abs(r - 0.32) / 0.2, 0, 1) * (0.4 + 0.6 * n)
    cracks = np.clip((np.abs(np.sin(ang * 7 + n * 3)) - 0.92) * 10, 0, 1) * np.clip(1 - r / 0.7, 0, 1)
    a = np.clip(hole + ring * 0.75 + cracks * 0.6, 0, 1) * np.clip((1 - r) * 3, 0, 1)
    col = np.stack([0.06 + 0 * r, 0.055 + 0 * r, 0.05 + 0 * r], -1)
    rgba("bullet_hole.png", np.concatenate([col, a[..., None]], -1))
    # soft smoke puff
    n2 = fbm(s, 4, 5, rng=np.random.default_rng(7))
    puff = np.clip(1 - r, 0, 1) ** 1.6 * (0.55 + 0.45 * n2)
    rgba("smoke_puff.png", np.concatenate([np.ones((s, s, 3)), puff[..., None]], -1))
    # muzzle flash star
    spikes = np.clip(1 - r * (0.55 + 1.5 * np.abs(np.sin(ang * 3 + 0.3))), 0, 1) ** 1.1
    glow = np.clip(1 - r, 0, 1) ** 2.0 * 0.75
    core = np.clip(1 - r / 0.32, 0, 1) ** 0.7
    fl = np.clip(spikes + glow + core, 0, 1)
    colf = np.stack([np.ones_like(r), 0.75 + 0.25 * core, 0.35 + 0.65 * core], -1)
    rgba("muzzle_flash.png", np.concatenate([colf, fl[..., None]], -1))
    # side flash (elongated)
    side = np.clip(1 - np.sqrt(((x - cx) / (s * 0.5)) ** 2 + ((y - cy) / (s * 0.16)) ** 2), 0, 1) ** 1.2 * (0.7 + 0.3 * n)
    rgba("muzzle_side.png", np.concatenate([colf, side[..., None]], -1))
    # spark / glow dot
    glow = np.clip(1 - r, 0, 1) ** 2.2
    rgba("glow.png", np.concatenate([np.ones((s, s, 3)), glow[..., None]], -1))
    # scorch decal
    scorch = np.clip(1 - r, 0, 1) ** 0.8 * (0.5 + 0.5 * n2)
    rgba("scorch.png", np.concatenate([np.stack([0.03 + 0 * r] * 3, -1), scorch[..., None] * 0.9], -1))
    # grass tuft card (alpha blades)
    tw, th = 128, 128
    yy, xx = np.mgrid[0:th, 0:tw].astype(float)
    card = np.zeros((th, tw, 4))
    brng = np.random.default_rng(11)
    for _ in range(26):
        bx = brng.uniform(12, tw - 12)
        lean = brng.uniform(-0.35, 0.35)
        h = brng.uniform(0.45, 0.98) * th
        w = brng.uniform(2.0, 4.0)
        t = np.clip((th - yy) / h, 0, 1)
        cxl = bx + lean * (th - yy) * (th - yy) / th
        width = w * (1 - t) + 0.4
        m = (np.abs(xx - cxl) < width) & ((th - yy) < h)
        shade = 0.55 + 0.45 * t
        g = np.array([0.22, 0.48, 0.10]) * brng.uniform(0.8, 1.2)
        card[m, 0] = g[0] * shade[m] * 1.1
        card[m, 1] = g[1] * shade[m]
        card[m, 2] = g[2] * shade[m]
        card[m, 3] = 1.0
    rgba("grass_tuft.png", card)


if __name__ == "__main__":
    for fn in (concrete_wall, concrete_floor, metal_floor, metal_panel, tiles, asphalt, grass, hazard,
               corrugated, facade, crate, foliage, bark, fx_textures):
        fn()
        print("generated", fn.__name__)
