"""Galaughxy map kit: every new episode map, built headless in Blender in the Studio Vinyl style.

  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \\
      --python tools/generate_15_maps.py -- [map_id ...]

Writes godot/assets/maps/<map_id>/<map_id>.glb plus one <map_id>__<expansion>.glb per expansion.

Naming contract with Godot (godot/scripts/maps/GlbMap.gd):
  Set_*            static set dressing (gets ink)
  Flat_*           floors and tiles (no ink: they would only add grid lines)
  Glow_*           emissive (no ink); can be flickered by chaos
  Prop_<group>_<n> a movable slapstick prop, pivot at its base; chaos FX move whole groups
  Spawn_<n>        character spawn marks
Props are moved by deterministic chaos FX, not physics, so shots stay scrubbable and retakes repeat.

Style (CLAUDE.md sections 17 and 20): smooth bevelled primitives only, every colour one of the 21
palette swatches, left/right pieces mirrored, nothing cutting through the floor.
Coordinates below are Godot's: +X right, +Y up, +Z toward the camera; the back wall is at -Z.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_roster import Char  # noqa: E402  (the shared smooth-primitive kit)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "maps")
BASE = {"silver": "#E5E7EB", "space_gray": "#2C2E33", "cream": "#F5F2EB", "bondi_blue": "#4A90E2",
        "coral": "#FF5F56", "amber": "#FFBD2E", "mint": "#27C93F"}


def sw(name, value="base"):
    """Palette swatch hex: sw('coral'), sw('mint', 'light'), sw('bondi_blue', 'shade')."""
    h = BASE[name]
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5))
    if value == "light":
        r, g, b = (c + (1 - c) * 0.42 for c in (r, g, b))
    elif value == "shade":
        r, g, b = (c * 0.68 for c in (r, g, b))
    return "#%02X%02X%02X" % tuple(round(c * 255) for c in (r, g, b))


def bl(p):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return (p[0], -p[2], p[1])


class Map(Char):
    """Char kit with Godot coordinates, set / prop / glow groups and spawn marks."""

    def __init__(self, mid):
        super().__init__(mid)
        for g in ("Set", "Props", "Glow", "Spawns"):
            self.joint(g, "Root", (0, 0, 0))
        self.n = 0

    def _name(self, prefix):
        self.n += 1
        return "%s_%03d" % (prefix, self.n)

    def _grp(self, group, prefix):
        return group, self._name(prefix)

    # primitives (centre c, half sizes h in Godot space; yaw in radians about +Y)
    def box(self, c, h, col, r=0.04, group="Set", prefix="Set", emit=0.0, yaw=0.0, alpha=1.0):
        g, name = self._grp(group, prefix)
        return Char.box(self, g, name, bl(c), (h[0], h[2], h[1]), r, col, rot=(0, 0, yaw), emit=emit, alpha=alpha)

    def cyl(self, c, radius, half_h, col, group="Set", prefix="Set", axis="y", bevel=0.015, emit=0.0):
        g, name = self._grp(group, prefix)
        rot = {"y": None, "x": (0, math.radians(90), 0), "z": (math.radians(90), 0, 0)}[axis]
        return Char.cyl(self, g, name, bl(c), radius, half_h, col, rot=rot, bevel=bevel, emit=emit)

    def ell(self, c, r, col, group="Set", prefix="Set", emit=0.0, alpha=1.0):
        g, name = self._grp(group, prefix)
        return Char.ell(self, g, name, bl(c), (r[0], r[2], r[1]), col, emit=emit, alpha=alpha)

    def cap(self, a, b, r, col, group="Set", prefix="Set", emit=0.0):
        g, name = self._grp(group, prefix)
        return Char.cap(self, g, name, bl(a), bl(b), r, col, emit=emit)

    def torus(self, c, major, minor, col, group="Set", prefix="Set", axis="y", emit=0.0):
        g, name = self._grp(group, prefix)
        rot = {"y": None, "x": (0, math.radians(90), 0), "z": (math.radians(90), 0, 0)}[axis]
        return Char.torus(self, g, name, bl(c), major, minor, col, rot=rot, emit=emit)

    def cone(self, c, r1, r2, half_h, col, group="Set", prefix="Set"):
        g, name = self._grp(group, prefix)
        return Char.cone(self, g, name, bl(c), r1, r2, half_h, col)

    def glow_box(self, c, h, col, r=0.02):
        return self.box(c, h, col, r, group="Glow", prefix="Glow", emit=2.2)

    def glow_ell(self, c, r, col):
        return self.ell(c, r, col, group="Glow", prefix="Glow", emit=2.2)

    def prop(self, group, at):
        """Starts a movable prop. Returns the joint; build its parts with group=<that joint>."""
        self.n += 1
        j = "Prop_%s_%03d" % (group, self.n)
        self.joint(j, "Props", bl(at))
        return j

    def spawns(self, points):
        for i, (x, z) in enumerate(points):
            self.joint("Spawn_%d" % (i + 1), "Spawns", bl((x, 0, z)))

    # ── rooms ───────────────────────────────────────────────────────────────────
    def floor(self, w, d, base, tile=None, size=1.0, y=0.0):
        self.box((0, y - 0.06, 0), (w / 2, 0.06, d / 2), base, 0.05, prefix="Flat")
        if tile:
            nx, nz = int(w / size), int(d / size)
            for i in range(nx):
                for k in range(nz):
                    if (i + k) % 2 == 0:
                        x = -w / 2 + (i + 0.5) * size
                        z = -d / 2 + (k + 0.5) * size
                        self.box((x, y + 0.004, z), (size / 2 - 0.012, 0.004, size / 2 - 0.012), tile, 0.003, prefix="Flat")

    def walls(self, w, d, h, col, trim=None, sides=True):
        self.box((0, h / 2, -d / 2 - 0.07), (w / 2 + 0.14, h / 2, 0.07), col, 0.05)
        if trim:
            self.box((0, 0.07, -d / 2 + 0.02), (w / 2, 0.07, 0.03), trim, 0.02)
        if sides:
            for s in (1, -1):
                self.box((s * (w / 2 + 0.07), h / 2, 0), (0.07, h / 2, d / 2 + 0.14), col, 0.05)
                if trim:
                    self.box((s * (w / 2 - 0.02), 0.07, 0), (0.03, 0.07, d / 2), trim, 0.02)

    # ── furniture kit (all mirrored / symmetric) ────────────────────────────────
    def table(self, x, z, w, d, h, top, legs, group="Set"):
        prefix = "Set" if group == "Set" else "Part"
        self.box((x, h - 0.03, z), (w / 2, 0.03, d / 2), top, 0.025, group=group, prefix=prefix)
        for sx in (1, -1):
            for sz in (1, -1):
                self.cyl((x + sx * (w / 2 - 0.08), (h - 0.06) / 2, z + sz * (d / 2 - 0.08)), 0.03, (h - 0.06) / 2, legs, group=group, prefix=prefix, bevel=0.01)

    def stool(self, x, z, seat, post, group="Set"):
        prefix = "Set" if group == "Set" else "Part"
        self.cyl((x, 0.66, z), 0.17, 0.04, seat, group=group, prefix=prefix, bevel=0.03)
        self.cyl((x, 0.33, z), 0.035, 0.31, post, group=group, prefix=prefix, bevel=0.01)
        self.cyl((x, 0.02, z), 0.16, 0.02, post, group=group, prefix=prefix, bevel=0.01)

    def plant(self, x, z, pot=None, leaf=None, s=1.0):
        pot = pot or sw("coral")
        leaf = leaf or sw("mint")
        self.cyl((x, 0.18 * s, z), 0.16 * s, 0.18 * s, pot, bevel=0.03)
        self.ell((x, 0.55 * s, z), (0.26 * s, 0.24 * s, 0.26 * s), leaf)
        for sx in (1, -1):
            self.ell((x + sx * 0.14 * s, 0.68 * s, z), (0.13 * s, 0.13 * s, 0.13 * s), leaf)

    def screen(self, c, half_w, half_h, frame, glow, depth=0.05):
        self.box(c, (half_w + 0.06, half_h + 0.06, depth), frame, 0.05)
        self.glow_box((c[0], c[1], c[2] + depth + 0.005), (half_w, half_h, 0.012), glow, 0.03)

    def can(self, at, col, group):
        j = self.prop(group, at)
        self.cyl((at[0], at[1] + 0.09, at[2]), 0.055, 0.09, col, group=j, prefix="Part", bevel=0.01)
        self.cyl((at[0], at[1] + 0.09, at[2]), 0.057, 0.025, sw("silver"), group=j, prefix="Part", bevel=0.005)
        return j

    def crowd(self, x, z, col, group="crowd"):
        """A bean-shaped background shopper (prop)."""
        j = self.prop(group, (x, 0, z))
        self.cap((x, 0.3, z), (x, 0.95, z), 0.18, col, group=j, prefix="Part")
        self.ell((x, 1.22, z), (0.15, 0.15, 0.15), sw("cream"), group=j, prefix="Part")
        return j

    def export(self, out_dir, name=None):
        os.makedirs(out_dir, exist_ok=True)
        saved = self.id
        if name:
            self.id = name
        Char.export(self, out_dir)
        self.id = saved


STD_SPAWNS = [(0.9, 1.4), (-0.9, 1.4), (0.9, 2.3), (-0.9, 2.3), (0.0, 2.8)]


# ── 1. The iFruit Keynote Store ───────────────────────────────────────────────────
def apple_store_showroom(m):
    m.floor(10, 8, sw("silver"), sw("silver", "light"), 1.0)
    m.walls(10, 8, 3.4, sw("cream"), trim=sw("silver", "shade"))
    m.screen((0, 2.0, -3.85), 2.4, 1.05, sw("space_gray"), sw("bondi_blue"))
    for s in (1, -1):
        m.box((s * 3.4, 1.4, -3.9), (0.5, 0.5, 0.06), sw("space_gray"), 0.06)   # wall posters
        m.glow_box((s * 3.4, 1.4, -3.83), (0.42, 0.42, 0.012), sw("mint") if s > 0 else sw("coral"))
        m.plant(s * 4.3, -3.3, pot=sw("silver"))
    # three display tables (props) with glowing devices on top
    for i, x in enumerate((-2.4, 0.0, 2.4)):
        j = m.prop("tables", (x, 0, -0.9))
        m.table(x, -0.9, 1.8, 0.8, 0.86, sw("cream"), sw("silver", "shade"), group=j)
        for k, dx in enumerate((-0.55, 0.0, 0.55)):
            d = m.prop("devices", (x + dx, 0.86, -0.9))
            if k == 1:   # a laptop
                m.box((x + dx, 0.875, -0.85), (0.2, 0.012, 0.14), sw("silver"), 0.01, group=d, prefix="Part")
                m.box((x + dx, 1.0, -0.98), (0.2, 0.13, 0.012), sw("silver"), 0.01, group=d, prefix="Part")
                m.box((x + dx, 1.0, -0.966), (0.17, 0.11, 0.004), sw("bondi_blue", "light"), 0.004, group=d, prefix="Part", emit=1.6)
            else:        # a phone on a stand
                m.box((x + dx, 0.99, -0.9), (0.05, 0.11, 0.008), sw("space_gray"), 0.02, group=d, prefix="Part")
                m.box((x + dx, 0.99, -0.89), (0.042, 0.095, 0.003), sw("mint", "light") if k == 0 else sw("coral", "light"), 0.015, group=d, prefix="Part", emit=1.6)
    for k, x in enumerate((-4.0, -3.4, 3.4, 4.0)):
        m.crowd(x, 2.6 + (k % 2) * 0.4, sw("bondi_blue") if k % 2 else sw("coral"))
    m.spawns(STD_SPAWNS)


def apple_store_showroom__genius_repair_bar(m):
    m.box((3.6, 0.55, 1.6), (0.35, 0.55, 1.5), sw("bondi_blue"), 0.06)
    m.box((3.6, 1.12, 1.6), (0.42, 0.03, 1.58), sw("cream"), 0.03)
    for z in (0.6, 1.6, 2.6):
        m.stool(2.95, z, sw("silver"), sw("space_gray"))
        m.glow_box((3.6, 1.3, z), (0.12, 0.08, 0.01), sw("mint"))
    m.box((3.6, 2.5, 1.6), (0.05, 0.3, 1.2), sw("space_gray"), 0.05)
    m.glow_box((3.54, 2.5, 1.6), (0.012, 0.22, 1.05), sw("bondi_blue", "light"))


# ── 2. aisle 7 Supermarket ────────────────────────────────────────────────────────
def chaotic_supermarket(m):
    m.floor(10, 8, sw("cream"), sw("mint", "light"), 1.0)
    m.walls(10, 8, 3.2, sw("mint", "light"), trim=sw("mint", "shade"))
    m.glow_box((0, 2.75, -3.9), (2.2, 0.22, 0.012), sw("coral"))   # "aisle 7" sign strip
    for s in (1, -1):   # two shelf aisles, mirrored
        x = s * 2.7
        m.box((x, 0.9, -1.8), (0.32, 0.9, 1.5), sw("silver"), 0.05)
        for y in (0.42, 0.98, 1.54):
            m.box((x, y, -1.8), (0.36, 0.02, 1.52), sw("silver", "shade"), 0.012)
            for k in range(6):
                col = (sw("coral"), sw("amber"), sw("bondi_blue"))[(k + int(y * 10)) % 3]
                m.box((x - s * 0.2, y + 0.12, -3.0 + k * 0.48), (0.09, 0.1, 0.16), col, 0.03)
    # can pyramid (props) at centre
    cols = (sw("coral"), sw("amber"), sw("bondi_blue"), sw("mint"))
    rows = [(4, 0.0), (3, 0.18), (2, 0.36), (1, 0.54)]
    k = 0
    for count, y in rows:
        for i in range(count):
            x = (i - (count - 1) / 2) * 0.12
            m.can((x, y, -0.6), cols[k % 4], "cans")
            k += 1
    for i in range(4):   # a second, front row of loose cans
        m.can(((i - 1.5) * 0.12, 0.0, -0.45), cols[(i + 2) % 4], "cans")
    # checkout conveyor (belt + items as props)
    m.box((-2.0, 0.42, 1.3), (1.1, 0.42, 0.32), sw("space_gray"), 0.05)
    m.box((-2.0, 0.86, 1.3), (1.0, 0.02, 0.26), sw("space_gray", "shade"), 0.015)
    for i in range(4):
        j = m.prop("belt", (-2.8 + i * 0.5, 0.88, 1.3))
        m.box((-2.8 + i * 0.5, 0.96, 1.3), (0.09, 0.08, 0.09), cols[i], 0.03, group=j, prefix="Part")
    # shopping cart (prop)
    j = m.prop("cart", (2.0, 0, 1.2))
    m.box((2.0, 0.72, 1.2), (0.32, 0.22, 0.45), sw("silver", "shade"), 0.04, group=j, prefix="Part")
    m.cap((1.7, 1.0, 1.65), (2.3, 1.0, 1.65), 0.025, sw("coral"), group=j, prefix="Part")
    for sx in (1, -1):
        for sz in (1, -1):
            m.cyl((2.0 + sx * 0.25, 0.08, 1.2 + sz * 0.35), 0.07, 0.03, sw("space_gray"), group=j, prefix="Part", axis="x", bevel=0.01)
    m.spawns(STD_SPAWNS)


def chaotic_supermarket__bakery_deli(m):
    m.box((-3.6, 0.5, 1.6), (0.4, 0.5, 1.5), sw("cream"), 0.06)
    m.box((-3.6, 1.02, 1.6), (0.46, 0.03, 1.56), sw("amber", "shade"), 0.03)
    m.box((-3.55, 1.25, 1.6), (0.36, 0.2, 1.4), sw("bondi_blue", "light"), 0.03, alpha=0.4)
    for z in (0.6, 1.2, 1.8, 2.4):
        m.ell((-3.6, 1.1, z), (0.14, 0.06, 0.09), sw("amber"))
        m.torus((-3.6, 1.12, z + 0.25), 0.07, 0.03, sw("amber", "shade"))
    m.glow_box((-4.05, 2.3, 1.6), (0.012, 0.25, 1.0), sw("amber"))


# ── 3. Bondi Blue Diner ───────────────────────────────────────────────────────────
def retro_diner(m):
    m.floor(10, 8, sw("cream"), sw("space_gray"), 0.6)
    m.walls(10, 8, 3.2, sw("bondi_blue", "light"), trim=sw("coral"))
    m.glow_box((0, 2.7, -3.9), (2.6, 0.07, 0.012), sw("coral"))      # neon stripe
    m.glow_box((0, 2.45, -3.9), (2.6, 0.04, 0.012), sw("mint"))
    # counter with stools
    m.box((0, 0.52, -2.6), (2.8, 0.52, 0.35), sw("bondi_blue"), 0.06)
    m.box((0, 1.06, -2.6), (2.9, 0.035, 0.42), sw("cream"), 0.03)
    for i in range(6):
        m.stool(-2.25 + i * 0.9, -1.95, sw("coral"), sw("silver"))
    # milkshake glasses + blender on the counter (props)
    for i, x in enumerate((-1.6, -0.6, 0.6, 1.6)):
        j = m.prop("shakes", (x, 1.095, -2.6))
        m.cone((x, 1.22, -2.6), 0.04, 0.07, 0.12, sw("cream"), group=j, prefix="Part")
        m.ell((x, 1.36, -2.6), (0.07, 0.04, 0.07), sw("coral", "light"), group=j, prefix="Part")
        m.ell((x, 1.42, -2.6), (0.025, 0.025, 0.025), sw("coral"), group=j, prefix="Part")
    j = m.prop("blender", (2.4, 1.095, -2.6))
    m.cyl((2.4, 1.16, -2.6), 0.1, 0.06, sw("silver", "shade"), group=j, prefix="Part")
    m.cone((2.4, 1.38, -2.6), 0.08, 0.11, 0.16, sw("bondi_blue", "light"), group=j, prefix="Part")
    # two mirrored booths
    for s in (1, -1):
        x = s * 3.4
        m.table(x, 0.5, 0.9, 1.2, 0.78, sw("cream"), sw("silver"))
        for dz in (-0.95, 0.95):
            m.box((x, 0.25, 0.5 + dz), (0.55, 0.25, 0.22), sw("coral"), 0.08)
            m.box((x, 0.75, 0.5 + dz + (0.18 if dz > 0 else -0.18)), (0.55, 0.38, 0.08), sw("coral"), 0.08)
    # jukebox
    m.box((-4.4, 0.85, -1.4), (0.42, 0.85, 0.32), sw("amber"), 0.12)
    m.ell((-4.4, 1.7, -1.4), (0.42, 0.28, 0.32), sw("amber"))
    m.glow_box((-4.08, 1.0, -1.4), (0.012, 0.4, 0.22), sw("coral"))
    m.glow_ell((-4.1, 1.62, -1.4), (0.02, 0.18, 0.24), sw("mint"))
    m.spawns(STD_SPAWNS)


def retro_diner__drive_thru(m):
    m.box((0, -0.07, 6.5), (6.0, 0.05, 2.4), sw("space_gray"), 0.04, prefix="Flat")
    for x in (-3.0, 0.0, 3.0):
        m.box((x, -0.012, 6.5), (0.06, 0.008, 1.2), sw("cream"), 0.004, prefix="Flat")
    m.cyl((4.6, 1.2, 5.2), 0.06, 1.2, sw("silver"))
    m.box((4.6, 2.5, 5.2), (0.6, 0.35, 0.08), sw("coral"), 0.1)
    m.glow_box((4.6, 2.5, 5.29), (0.48, 0.24, 0.01), sw("amber"))


# ── 4. The Hot-Take Podcast Set ───────────────────────────────────────────────────
def podcast_studio(m):
    m.floor(9, 7, sw("space_gray"), sw("space_gray", "shade"), 1.0)
    m.walls(9, 7, 3.0, sw("space_gray", "shade"))
    for i in range(7):         # acoustic foam panels, back wall
        for k in range(3):
            m.box((-3.0 + i * 1.0, 0.8 + k * 0.7, -3.52), (0.42, 0.3, 0.05), sw("bondi_blue", "shade") if (i + k) % 2 else sw("coral", "shade"), 0.12)
    m.glow_box((0, 2.55, -3.48), (1.3, 0.16, 0.012), sw("coral"))    # ON AIR neon
    # round table and four mics (props)
    m.cyl((0, 0.74, -0.6), 1.0, 0.035, sw("amber", "shade"), bevel=0.03)
    m.cyl((0, 0.37, -0.6), 0.12, 0.37, sw("space_gray"))
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        x, z = math.sin(a) * 0.65, -0.6 + math.cos(a) * 0.65
        j = m.prop("mics", (x, 0.775, z))
        m.cyl((x, 0.79, z), 0.08, 0.015, sw("space_gray"), group=j, prefix="Part")
        m.cap((x, 0.8, z), (x * 0.8, 1.02, -0.6 + (z + 0.6) * 0.8), 0.012, sw("silver"), group=j, prefix="Part")
        m.cap((x * 0.8, 1.05, -0.6 + (z + 0.6) * 0.8), (x * 0.8, 1.15, -0.6 + (z + 0.6) * 0.8), 0.045, sw("silver", "shade"), group=j, prefix="Part")
        j = m.prop("mugs", (x * 0.55, 0.775, -0.6 + (z + 0.6) * 0.55))
        m.cyl((x * 0.55, 0.83, -0.6 + (z + 0.6) * 0.55), 0.045, 0.055, sw("cream"), group=j, prefix="Part", bevel=0.01)
        m.stool(x * 1.55, -0.6 + (z + 0.6) * 1.55, sw("coral"), sw("silver"))
    # mixing desk
    m.box((2.8, 0.45, -2.6), (0.7, 0.45, 0.4), sw("space_gray"), 0.05)
    for i in range(6):
        m.glow_box((2.35 + i * 0.18, 0.92, -2.55), (0.03, 0.01, 0.12), sw("mint") if i % 2 else sw("amber"))
    # ceiling light rig (props: they drop in stage 3)
    m.box((0, 2.9, -0.6), (2.0, 0.04, 0.04), sw("silver", "shade"), 0.02)
    for x in (-1.5, -0.5, 0.5, 1.5):
        j = m.prop("lights", (x, 2.55, -0.6))
        m.cyl((x, 2.7, -0.6), 0.12, 0.13, sw("space_gray"), group=j, prefix="Part")
        m.cyl((x, 2.56, -0.6), 0.1, 0.012, sw("amber", "light"), group=j, prefix="Part", emit=2.0)
    m.spawns(STD_SPAWNS)


def podcast_studio__green_screen(m):
    m.box((-3.4, 1.4, 1.4), (0.05, 1.4, 1.4), sw("mint"), 0.04)
    m.box((-3.4, 0.03, 1.4), (1.0, 0.03, 1.4), sw("mint"), 0.02, prefix="Flat")
    m.box((-1.8, 0.5, 2.6), (0.6, 0.5, 0.3), sw("space_gray"), 0.05)
    m.screen((-1.8, 1.3, 2.5), 0.5, 0.28, sw("space_gray"), sw("mint", "light"))


# ── 5. Tranquility Mac Base (moon) ────────────────────────────────────────────────
def lunar_moon_base(m):
    m.floor(14, 11, sw("silver"), None)
    for (x, z, r) in ((-3.2, 1.2, 0.9), (3.6, 0.4, 0.7), (-0.4, 3.2, 0.5), (4.5, 3.0, 0.45), (-5.0, -1.0, 0.6)):
        m.torus((x, 0.02, z), r, 0.12, sw("silver", "shade"))       # crater rims
        m.cyl((x, 0.004, z), r - 0.05, 0.004, sw("silver", "shade"), bevel=0.002, prefix="Flat")
    # the dome and its airlock
    m.ell((0, 0.0, -3.2), (2.4, 2.1, 2.4), sw("cream"))
    m.torus((0, 0.15, -3.2), 2.38, 0.12, sw("silver", "shade"))
    m.box((0, 0.85, -0.95), (0.6, 0.85, 0.55), sw("silver"), 0.2)
    m.box((0, 0.8, -0.38), (0.36, 0.68, 0.03), sw("space_gray"), 0.1)
    m.glow_box((0, 1.62, -0.36), (0.3, 0.04, 0.01), sw("mint"))
    for s in (1, -1):
        m.glow_ell((s * 1.6, 1.4, -1.7), (0.18, 0.18, 0.04), sw("bondi_blue", "light"))   # portholes
        m.cyl((s * 2.8, 0.9, -2.4), 0.05, 0.9, sw("silver"))          # antenna masts
        m.ell((s * 2.8, 1.9, -2.4), (0.28, 0.1, 0.28), sw("silver", "light"))
    # loose moon props: crates, rocks, flag
    for i, (x, z) in enumerate(((-2.0, 0.2), (-1.4, 0.6), (2.0, 0.0), (2.5, 0.7), (1.1, 2.0), (-2.4, 2.4))):
        j = m.prop("crates", (x, 0, z))
        if i % 2:
            m.ell((x, 0.18, z), (0.24, 0.18, 0.2), sw("silver", "shade"), group=j, prefix="Part")
        else:
            m.box((x, 0.2, z), (0.2, 0.2, 0.2), sw("amber"), 0.05, group=j, prefix="Part")
    j = m.prop("flag", (-1.2, 0, -0.6))
    m.cyl((-1.2, 0.8, -0.6), 0.02, 0.8, sw("silver"), group=j, prefix="Part", bevel=0.005)
    m.box((-0.95, 1.4, -0.6), (0.24, 0.16, 0.01), sw("coral"), 0.02, group=j, prefix="Part")
    m.spawns([(0.9, 1.6), (-0.9, 1.6), (0.9, 2.6), (-0.9, 2.6), (0.0, 3.2)])


def lunar_moon_base__rover_pad(m):
    m.cyl((4.4, 0.03, -2.4), 1.4, 0.03, sw("space_gray"), bevel=0.02)
    m.torus((4.4, 0.07, -2.4), 1.3, 0.025, sw("amber"), emit=2.0)
    m.box((4.4, 0.45, -2.4), (0.55, 0.15, 0.85), sw("cream"), 0.12)
    m.box((4.4, 0.72, -2.55), (0.4, 0.14, 0.35), sw("bondi_blue", "light"), 0.1, alpha=0.6)
    for sx in (1, -1):
        for sz in (1, -1):
            m.cyl((4.4 + sx * 0.62, 0.22, -2.4 + sz * 0.6), 0.2, 0.08, sw("space_gray"), axis="x", bevel=0.03)


# ── 6. Maple Street Cul-de-Sac ────────────────────────────────────────────────────
def house(m, x, z, wall, roof, door):
    m.box((x, 1.2, z), (1.6, 1.2, 1.3), wall, 0.08)
    for s in (1, -1):   # pitched roof: two mirrored slabs
        g, name = m._grp("Set", "Set")
        Char.box(m, g, name, bl((x + s * 0.85, 2.75, z)), (1.05, 1.4, 0.07), 0.05, roof, rot=(0, s * math.radians(38), 0))
    m.box((x, 0.55, z + 1.32), (0.32, 0.55, 0.04), door, 0.06)
    for s in (1, -1):
        m.box((x + s * 0.95, 1.4, z + 1.32), (0.32, 0.3, 0.03), sw("cream"), 0.04)
        m.box((x + s * 0.95, 1.4, z + 1.34), (0.26, 0.24, 0.01), sw("bondi_blue", "light"), 0.03)


def suburban_cul_de_sac(m):
    m.floor(14, 11, sw("mint"), sw("mint", "shade"), 1.4)
    m.cyl((0, 0.012, 0.8), 2.6, 0.012, sw("silver", "shade"), bevel=0.005, prefix="Flat")   # the cul-de-sac circle
    m.box((0, 0.012, 4.2), (1.4, 0.012, 1.4), sw("silver", "shade"), 0.005, prefix="Flat")
    house(m, -3.6, -2.6, sw("coral", "light"), sw("coral", "shade"), sw("bondi_blue"))
    house(m, 3.6, -2.6, sw("bondi_blue", "light"), sw("bondi_blue", "shade"), sw("coral"))
    for s in (1, -1):    # picket fences
        for i in range(9):
            x = s * (1.9 + i * 0.28)
            m.box((x, 0.36, -0.6), (0.05, 0.36, 0.025), sw("cream"), 0.03)
        m.box((s * 3.0, 0.5, -0.6), (1.2, 0.03, 0.02), sw("cream"), 0.015)
    j = m.prop("mailbox", (-1.6, 0, -0.2))
    m.cyl((-1.6, 0.5, -0.2), 0.04, 0.5, sw("silver", "shade"), group=j, prefix="Part")
    m.box((-1.6, 1.08, -0.2), (0.13, 0.11, 0.2), sw("bondi_blue"), 0.1, group=j, prefix="Part")
    m.box((-1.45, 1.18, -0.28), (0.012, 0.09, 0.03), sw("coral"), 0.01, group=j, prefix="Part")
    # compact car
    j = m.prop("car", (2.6, 0, 1.6))
    m.box((2.6, 0.48, 1.6), (0.75, 0.3, 0.45), sw("amber"), 0.2, group=j, prefix="Part")
    m.box((2.55, 0.9, 1.6), (0.45, 0.2, 0.4), sw("amber"), 0.16, group=j, prefix="Part")
    m.box((2.55, 0.92, 1.6), (0.47, 0.15, 0.36), sw("bondi_blue", "light"), 0.1, group=j, prefix="Part")
    for sx in (1, -1):
        for sz in (1, -1):
            m.cyl((2.6 + sx * 0.48, 0.2, 1.6 + sz * 0.44), 0.18, 0.06, sw("space_gray"), group=j, prefix="Part", axis="z", bevel=0.03)
    # sprinklers, lawnmower and hydrant (props)
    for x in (-3.0, 3.0):
        j = m.prop("sprinklers", (x, 0, 0.8))
        m.cyl((x, 0.05, 0.8), 0.07, 0.05, sw("silver"), group=j, prefix="Part")
        m.cap((x - 0.18, 0.12, 0.8), (x + 0.18, 0.12, 0.8), 0.018, sw("silver", "shade"), group=j, prefix="Part")
    j = m.prop("mower", (-2.2, 0, 2.6))
    m.box((-2.2, 0.2, 2.6), (0.3, 0.12, 0.38), sw("coral"), 0.1, group=j, prefix="Part")
    m.cap((-2.2, 0.3, 2.95), (-2.2, 0.85, 3.35), 0.02, sw("space_gray"), group=j, prefix="Part")
    for sx in (1, -1):
        m.cyl((-2.2 + sx * 0.3, 0.09, 2.6), 0.09, 0.03, sw("space_gray"), group=j, prefix="Part", axis="x", bevel=0.01)
    j = m.prop("hydrant", (1.6, 0, -0.2))
    m.cyl((1.6, 0.32, -0.2), 0.12, 0.32, sw("coral"), group=j, prefix="Part", bevel=0.03)
    m.ell((1.6, 0.66, -0.2), (0.13, 0.08, 0.13), sw("coral"), group=j, prefix="Part")
    m.cyl((1.6, 0.4, -0.2), 0.045, 0.2, sw("silver"), group=j, prefix="Part", axis="x", bevel=0.01)
    j = m.prop("geyser", (1.6, 0.66, -0.2))
    m.cyl((1.6, 1.4, -0.2), 0.11, 0.7, sw("bondi_blue", "light"), group=j, prefix="Part", bevel=0.05)
    m.spawns([(0.9, 1.6), (-0.9, 1.6), (0.9, 2.6), (-0.9, 2.6), (0.0, 3.2)])


def suburban_cul_de_sac__treehouse(m):
    m.cyl((-5.2, 1.2, 1.6), 0.22, 1.2, sw("amber", "shade"), bevel=0.04)
    m.ell((-5.2, 3.1, 1.6), (1.1, 0.9, 1.1), sw("mint"))
    m.box((-5.2, 2.35, 1.6), (0.7, 0.45, 0.6), sw("amber"), 0.06)
    m.box((-5.2, 2.85, 1.6), (0.8, 0.06, 0.7), sw("coral"), 0.04)
    for i in range(6):
        m.cap((-4.75, 0.3 + i * 0.32, 2.15), (-4.45, 0.3 + i * 0.32, 2.15), 0.025, sw("amber", "shade"))


# ── 7. Sunday Living Room ─────────────────────────────────────────────────────────
def cozy_living_room(m):
    m.floor(10, 8, sw("amber", "light"), sw("amber"), 1.0)
    m.walls(10, 8, 3.1, sw("cream"), trim=sw("amber", "shade"))
    m.cyl((0, 0.008, -0.4), 2.0, 0.008, sw("coral", "light"), bevel=0.004, prefix="Flat")   # round rug
    # TV on the left wall, sofa on the right facing it, coffee table between
    m.box((-4.55, 0.3, -0.4), (0.3, 0.3, 1.3), sw("amber", "shade"), 0.05)
    m.box((-4.86, 1.4, -0.4), (0.05, 0.78, 1.3), sw("space_gray"), 0.05)
    m.glow_box((-4.8, 1.4, -0.4), (0.012, 0.68, 1.2), sw("bondi_blue", "light"))
    m.box((2.6, 0.25, -0.4), (0.5, 0.25, 1.6), sw("bondi_blue"), 0.12)
    m.box((3.0, 0.75, -0.4), (0.14, 0.35, 1.6), sw("bondi_blue"), 0.12)
    for s2 in (1, -1):
        m.box((2.6, 0.45, -0.4 + s2 * 1.65), (0.55, 0.45, 0.18), sw("bondi_blue", "shade"), 0.12)
        m.box((2.58, 0.56, -0.4 + s2 * 0.78), (0.44, 0.08, 0.74), sw("bondi_blue", "light"), 0.08)
    m.table(-0.4, -0.4, 0.8, 1.4, 0.42, sw("cream"), sw("amber", "shade"))
    j = m.prop("bowl", (-0.4, 0.42, -0.4))
    m.ell((-0.4, 0.5, -0.4), (0.24, 0.1, 0.24), sw("coral"), group=j, prefix="Part")
    for k in range(10):
        a = k * 2.4
        j = m.prop("popcorn", (-0.4 + math.cos(a) * 0.12, 0.58, -0.4 + math.sin(a) * 0.12))
        m.ell((-0.4 + math.cos(a) * 0.12, 0.6, -0.4 + math.sin(a) * 0.12), (0.035, 0.03, 0.035), sw("cream"), group=j, prefix="Part")
    # bookshelves and plants, mirrored on the back wall
    for s in (1, -1):
        x = s * 2.2
        m.box((x, 1.1, -3.6), (0.7, 1.1, 0.25), sw("amber", "shade"), 0.05)
        for y in (0.5, 1.1, 1.7):
            for k in range(5):
                m.box((x - 0.5 + k * 0.24, y + 0.18, -3.3), (0.08, 0.16, 0.1), (sw("coral"), sw("mint"), sw("bondi_blue"), sw("amber"), sw("cream"))[k], 0.02)
        m.plant(s * 3.9, -3.2, pot=sw("cream"))
    # ceiling fan (prop) and the roomba (prop)
    j = m.prop("fan", (0, 2.5, -0.6))
    m.cyl((0, 2.8, -0.6), 0.03, 0.25, sw("silver"), group=j, prefix="Part")
    m.cyl((0, 2.52, -0.6), 0.14, 0.06, sw("cream"), group=j, prefix="Part")
    for k in range(4):
        a = k * math.pi / 2
        m.box((math.cos(a) * 0.55, 2.52, -0.6 + math.sin(a) * 0.55), (0.42 if k % 2 == 0 else 0.07, 0.012, 0.07 if k % 2 == 0 else 0.42), sw("amber", "shade"), 0.02, group=j, prefix="Part")
    j = m.prop("roomba", (1.6, 0, 1.2))
    m.cyl((1.6, 0.05, 1.2), 0.22, 0.04, sw("space_gray"), group=j, prefix="Part", bevel=0.02)
    m.cyl((1.6, 0.095, 1.2), 0.12, 0.008, sw("mint"), group=j, prefix="Part", emit=1.6)
    m.spawns(STD_SPAWNS)


def cozy_living_room__sunroom(m):
    # a bright corner nook inside the room: tiles, railing, two loungers, big plants
    m.box((3.6, 0.012, 2.4), (1.2, 0.012, 1.3), sw("silver", "light"), 0.01, prefix="Flat")
    for i in range(5):
        m.cyl((4.75, 0.5, 1.3 + i * 0.5), 0.03, 0.5, sw("cream"), bevel=0.01)
    m.box((4.75, 1.02, 2.3), (0.05, 0.03, 1.05), sw("cream"), 0.02)
    for z in (1.8, 3.0):
        m.box((3.5, 0.35, z), (0.6, 0.05, 0.32), sw("coral", "light"), 0.05)
    m.plant(4.3, 3.4, pot=sw("coral"), s=1.3)
    m.plant(2.7, 3.4, pot=sw("coral"), s=1.0)


# ── 8. St. Glitch Clinic ──────────────────────────────────────────────────────────
def mad_science_hospital(m):
    m.floor(10, 8, sw("silver", "light"), sw("mint", "light"), 1.0)
    m.walls(10, 8, 3.2, sw("mint", "light"), trim=sw("mint", "shade"))
    m.screen((-2.2, 1.7, -3.85), 1.2, 0.8, sw("space_gray"), sw("bondi_blue", "light"))   # X-ray screen
    for k in range(4):   # the ribcage on the X-ray, as glow arcs
        m.torus((-2.2, 1.55 + k * 0.17, -3.77), 0.32 - k * 0.04, 0.018, sw("cream"), axis="z", emit=2.0)
    # exam table
    m.box((0.8, 0.72, -1.2), (1.0, 0.07, 0.42), sw("cream"), 0.06)
    m.box((0.8, 0.36, -1.2), (0.7, 0.36, 0.3), sw("silver", "shade"), 0.06)
    m.ell((0.0, 0.85, -1.2), (0.2, 0.07, 0.3), sw("cream"))
    # medicine cabinet with bottles
    m.box((3.6, 1.2, -3.7), (0.7, 0.9, 0.2), sw("silver"), 0.05)
    for y in (0.6, 1.2, 1.8):
        for k in range(4):
            m.cyl((3.15 + k * 0.3, y + 0.1, -3.6), 0.06, 0.1, (sw("coral"), sw("amber"), sw("mint"), sw("bondi_blue"))[k], bevel=0.01)
    m.glow_box((3.6, 2.2, -3.48), (0.2, 0.06, 0.01), sw("coral"))   # red cross bar
    m.glow_box((3.6, 2.2, -3.47), (0.06, 0.2, 0.01), sw("coral"))
    # rolling gurney (prop)
    j = m.prop("gurney", (-2.2, 0, 1.0))
    m.box((-2.2, 0.75, 1.0), (0.35, 0.05, 0.95), sw("silver"), 0.05, group=j, prefix="Part")
    m.box((-2.2, 0.83, 1.0), (0.32, 0.04, 0.9), sw("cream"), 0.05, group=j, prefix="Part")
    for sx in (1, -1):
        for sz in (1, -1):
            m.cyl((-2.2 + sx * 0.28, 0.38, 1.0 + sz * 0.8), 0.02, 0.33, sw("silver", "shade"), group=j, prefix="Part", bevel=0.005)
            m.cyl((-2.2 + sx * 0.28, 0.06, 1.0 + sz * 0.8), 0.06, 0.025, sw("space_gray"), group=j, prefix="Part", axis="x", bevel=0.01)
    # gas tanks (props, they wobble in the fog stage)
    for x in (4.2, 4.5):
        j = m.prop("tanks", (x, 0, 0.6))
        m.cap((x, 0.2, 0.6), (x, 1.0, 0.6), 0.13, sw("mint"), group=j, prefix="Part")
        m.cyl((x, 1.18, 0.6), 0.04, 0.05, sw("silver"), group=j, prefix="Part")
    m.spawns(STD_SPAWNS)


def mad_science_hospital__mri(m):
    m.torus((3.4, 1.0, 2.6), 0.9, 0.32, sw("cream"), axis="x")
    m.box((3.4, 0.3, 2.6), (0.9, 0.3, 0.5), sw("silver", "shade"), 0.08)
    m.box((2.0, 0.55, 2.6), (0.9, 0.06, 0.32), sw("cream"), 0.05)
    m.torus((3.4, 1.0, 2.6), 0.62, 0.03, sw("bondi_blue"), axis="x", emit=2.0)


# ── 9. Cubicle Farm 9-to-5 ────────────────────────────────────────────────────────
def corporate_office(m):
    m.floor(10, 8, sw("silver"), sw("silver", "shade"), 1.0)
    m.walls(10, 8, 3.0, sw("silver", "light"), trim=sw("space_gray"))
    m.box((0, 1.6, -3.88), (1.6, 0.8, 0.03), sw("cream"), 0.04)           # whiteboard
    m.cap((-1.2, 1.9, -3.84), (0.6, 1.5, -3.84), 0.012, sw("coral"))
    m.cap((-1.0, 1.3, -3.84), (0.9, 1.35, -3.84), 0.012, sw("bondi_blue"))
    for s in (1, -1):    # four cubicles, mirrored pairs
        for row in (-2.3, -0.6):
            x = s * 2.4
            m.box((x, 0.6, row - 0.7), (0.9, 0.6, 0.05), sw("space_gray"), 0.04)
            m.box((x + s * 0.88, 0.6, row), (0.05, 0.6, 0.7), sw("space_gray"), 0.04)
            m.table(x, row - 0.25, 1.5, 0.6, 0.74, sw("cream"), sw("silver", "shade"))
            m.screen((x, 1.0, row - 0.45), 0.24, 0.15, sw("space_gray"), sw("bondi_blue", "light"), depth=0.02)
            j = m.prop("papers", (x + 0.4, 0.74, row - 0.2))
            m.box((x + 0.4, 0.76, row - 0.2), (0.12, 0.02, 0.16), sw("cream"), 0.008, group=j, prefix="Part")
    # copier and watercooler (props)
    j = m.prop("copier", (-0.6, 0, 1.4))
    m.box((-0.6, 0.5, 1.4), (0.5, 0.5, 0.42), sw("silver"), 0.08, group=j, prefix="Part")
    m.box((-0.6, 1.04, 1.4), (0.46, 0.04, 0.38), sw("space_gray"), 0.03, group=j, prefix="Part")
    m.box((-0.6, 0.7, 1.84), (0.3, 0.02, 0.1), sw("cream"), 0.01, group=j, prefix="Part")
    m.glow_box((-0.25, 0.92, 1.83), (0.04, 0.03, 0.01), sw("mint"))
    j = m.prop("cooler", (0.8, 0, 1.4))
    m.box((0.8, 0.5, 1.4), (0.22, 0.5, 0.22), sw("cream"), 0.08, group=j, prefix="Part")
    m.cap((0.8, 1.08, 1.4), (0.8, 1.42, 1.4), 0.17, sw("bondi_blue", "light"), group=j, prefix="Part")
    m.spawns(STD_SPAWNS)


def corporate_office__boardroom(m):
    # glass boardroom in the front-right corner of the floor
    m.box((2.3, 1.1, 2.3), (0.03, 1.1, 1.3), sw("bondi_blue", "light"), 0.02, alpha=0.35)
    m.box((3.6, 0.74, 2.3), (0.55, 0.04, 1.0), sw("space_gray"), 0.04)
    m.box((3.6, 0.36, 2.3), (0.2, 0.36, 0.4), sw("space_gray", "shade"), 0.04)
    for s in (1, -1):
        for k in range(3):
            m.stool(3.6 + s * 0.85, 1.6 + k * 0.7, sw("coral"), sw("space_gray"))


# ── 10. Pixel-Smooth Pier ─────────────────────────────────────────────────────────
def beach_boardwalk(m):
    m.floor(14, 6, sw("amber", "light"), None)                         # sand
    m.box((0, -0.08, -6.0), (8.0, 0.05, 3.0), sw("bondi_blue"), 0.05, prefix="Flat")   # sea floor tint
    for i in range(5):    # ocean waves (props, they bob)
        j = m.prop("waves", (-6.0 + i * 3.0, 0, -4.2))
        m.ell((-6.0 + i * 3.0, 0.0, -4.2), (1.7, 0.16, 0.5), sw("bondi_blue", "light"), group=j, prefix="Part")
        m.ell((-6.0 + i * 3.0 + 0.4, 0.1, -4.0), (0.6, 0.06, 0.2), sw("cream"), group=j, prefix="Part")
    for i in range(14):   # boardwalk planks
        m.box((-6.5 + i * 1.0, 0.1, 1.4), (0.47, 0.06, 1.2), sw("amber") if i % 2 else sw("amber", "shade"), 0.03)
    for s in (1, -1):     # umbrellas and deck chairs, mirrored
        x = s * 3.2
        m.cyl((x, 1.1, -1.6), 0.035, 1.1, sw("silver"), bevel=0.01)
        m.cone((x, 2.25, -1.6), 1.0, 0.05, 0.25, sw("coral") if s > 0 else sw("mint"))
        g, name = m._grp("Set", "Set")
        Char.box(m, g, name, bl((x + 0.7, 0.32, -1.3)), (0.28, 0.6, 0.04), 0.03, sw("bondi_blue", "light"), rot=(math.radians(-55), 0, 0))
    # ice-cream cart (props: scoops melt)
    m.box((0.0, 0.6, -1.0), (0.6, 0.35, 0.4), sw("cream"), 0.08)
    m.cyl((0.0, 1.3, -1.0), 0.03, 0.4, sw("silver"), bevel=0.01)
    m.box((0.0, 1.72, -1.0), (0.7, 0.04, 0.5), sw("coral", "light"), 0.04)
    for sx in (1, -1):
        m.cyl((sx * 0.5, 0.2, -1.0), 0.2, 0.05, sw("space_gray"), axis="z", bevel=0.03)
    for k, col in enumerate((sw("coral", "light"), sw("mint", "light"), sw("amber", "light"))):
        j = m.prop("scoops", (-0.3 + k * 0.3, 0.95, -1.0))
        m.cone((-0.3 + k * 0.3, 1.02, -1.0), 0.02, 0.06, 0.08, sw("amber", "shade"), group=j, prefix="Part")
        m.ell((-0.3 + k * 0.3, 1.15, -1.0), (0.07, 0.07, 0.07), col, group=j, prefix="Part")
    m.spawns([(0.9, 1.4), (-0.9, 1.4), (0.9, 2.2), (-0.9, 2.2), (0.0, 0.6)])


def beach_boardwalk__arcade_shack(m):
    m.box((5.2, 1.2, 0.4), (1.2, 1.2, 1.0), sw("bondi_blue"), 0.08)
    m.box((5.2, 2.5, 0.4), (1.4, 0.1, 1.2), sw("coral"), 0.06)
    m.glow_box((4.0, 2.0, 0.4), (0.012, 0.18, 0.8), sw("amber"))
    m.box((4.05, 1.0, 0.4), (0.04, 0.8, 0.45), sw("space_gray"), 0.04)


# ── 11. 8-Bit Vinyl Arcade ────────────────────────────────────────────────────────
def cabinet(m, x, z, body, yaw=0.0, group="Set"):
    prefix = "Set" if group == "Set" else "Part"
    m.box((x, 0.85, z), (0.36, 0.85, 0.36), body, 0.06, group=group, prefix=prefix, yaw=yaw)
    m.box((x, 1.85, z - 0.04), (0.38, 0.15, 0.38), body, 0.06, group=group, prefix=prefix, yaw=yaw)
    m.box((x, 1.3, z + 0.37), (0.28, 0.22, 0.012), sw("bondi_blue", "light"), 0.03, group=group, prefix=prefix, emit=1.8)
    m.box((x, 0.95, z + 0.42), (0.3, 0.04, 0.1), sw("space_gray"), 0.02, group=group, prefix=prefix)
    m.ell((x - 0.1, 1.02, z + 0.42), (0.035, 0.035, 0.035), sw("coral"), group=group, prefix=prefix)
    m.ell((x + 0.1, 1.0, z + 0.44), (0.03, 0.03, 0.03), sw("amber"), group=group, prefix=prefix)


def retro_arcade(m):
    m.floor(10, 8, sw("space_gray"), sw("space_gray", "shade"), 0.5)
    m.walls(10, 8, 3.0, sw("space_gray", "shade"))
    for i in range(5):
        m.glow_box((-3.6 + i * 1.8, 2.6, -3.9), (0.5, 0.05, 0.012), (sw("coral"), sw("bondi_blue"), sw("mint"), sw("amber"), sw("coral"))[i])
    for i in range(6):   # two rows of cabinets (props: they topple like dominoes)
        x = -2.75 + i * 1.1
        j = m.prop("cabinets", (x, 0, -3.1))
        cabinet(m, x, -3.1, sw("bondi_blue") if i % 2 else sw("coral"), group=j)
    for s in (1, -1):
        j = m.prop("cabinets", (s * 4.2, 0, -1.2))
        cabinet(m, s * 4.2, -1.2, sw("mint"), yaw=s * math.radians(90), group=j)
    # claw machine with a claw (prop) and plush prizes (props)
    m.box((-2.4, 0.45, 0.2), (0.6, 0.45, 0.6), sw("coral"), 0.08)
    m.box((-2.4, 1.5, 0.2), (0.58, 0.6, 0.58), sw("bondi_blue", "light"), 0.06, alpha=0.3)
    m.box((-2.4, 2.15, 0.2), (0.62, 0.06, 0.62), sw("coral"), 0.05)
    j = m.prop("claw", (-2.4, 1.9, 0.2))
    m.cap((-2.4, 2.1, 0.2), (-2.4, 1.85, 0.2), 0.012, sw("silver"), group=j, prefix="Part")
    for k in range(3):
        a = k * 2 * math.pi / 3
        m.cap((-2.4, 1.85, 0.2), (-2.4 + math.cos(a) * 0.09, 1.72, 0.2 + math.sin(a) * 0.09), 0.012, sw("silver"), group=j, prefix="Part")
    for k, col in enumerate((sw("mint"), sw("amber"), sw("bondi_blue"), sw("cream"))):
        j = m.prop("plush", (-2.6 + (k % 2) * 0.35, 0.9, 0.05 + (k // 2) * 0.3))
        m.ell((-2.6 + (k % 2) * 0.35, 1.0, 0.05 + (k // 2) * 0.3), (0.1, 0.1, 0.1), col, group=j, prefix="Part")
    # ticket counter
    m.box((2.6, 0.5, 0.4), (1.0, 0.5, 0.35), sw("amber"), 0.06)
    m.box((2.6, 1.02, 0.4), (1.06, 0.03, 0.4), sw("cream"), 0.03)
    for k in range(5):
        j = m.prop("tickets", (2.1 + k * 0.25, 1.05, 0.4))
        m.box((2.1 + k * 0.25, 1.07, 0.4), (0.08, 0.012, 0.04), sw("coral", "light"), 0.006, group=j, prefix="Part")
    m.spawns(STD_SPAWNS)


def retro_arcade__bowling_lane(m):
    # one bowling lane down the right side, pins at the back (props), a ball at the front
    m.box((3.9, 0.02, 1.0), (0.55, 0.02, 2.4), sw("amber", "light"), 0.01, prefix="Flat")
    for s in (1, -1):
        m.box((3.9 + s * 0.65, 0.03, 1.0), (0.1, 0.03, 2.4), sw("space_gray", "light"), 0.02, prefix="Flat")
    m.glow_box((3.9, 0.05, 3.3), (0.5, 0.008, 0.02), sw("coral"))
    rows = [(1, -0.95), (2, -1.1), (3, -1.25), (4, -1.4)]
    for count, z in rows:
        for i in range(count):
            x = 3.9 + (i - (count - 1) / 2) * 0.13
            j = m.prop("pins", (x, 0.04, z))
            m.cap((x, 0.08, z), (x, 0.3, z), 0.045, sw("cream"), group=j, prefix="Part")
            m.torus((x, 0.24, z), 0.04, 0.008, sw("coral"), group=j, prefix="Part")
    j = m.prop("ball", (3.9, 0.04, 2.9))
    m.ell((3.9, 0.15, 2.9), (0.11, 0.11, 0.11), sw("bondi_blue", "shade"), group=j, prefix="Part")


# ── 12. The Express Dining Car ────────────────────────────────────────────────────
def train_dining_car(m):
    w, d, h = 12.0, 5.0, 2.8
    m.floor(w, d, sw("coral", "shade"), sw("coral"), 0.5)
    # back wall with four windows: low wall, high wall, and pillars between the windows
    m.box((0, 0.5, -2.57), (6.1, 0.5, 0.07), sw("amber", "shade"), 0.04)
    m.box((0, 2.35, -2.57), (6.1, 0.45, 0.07), sw("cream"), 0.04)
    for (x0, x1) in ((-6.1, -4.3), (-2.9, -1.9), (-0.5, 0.5), (1.9, 2.9), (4.3, 6.1)):
        m.box(((x0 + x1) / 2, 1.45, -2.57), ((x1 - x0) / 2, 0.45, 0.07), sw("cream"), 0.04)
    for x in (-3.6, -1.2, 1.2, 3.6):
        m.box((x, 1.02, -2.48), (0.72, 0.03, 0.06), sw("silver"), 0.02)          # window sills
        m.box((x, 1.88, -2.48), (0.72, 0.03, 0.06), sw("silver"), 0.02)
    for s in (1, -1):    # end walls
        m.box((s * 6.07, h / 2, 0), (0.07, h / 2, 2.6), sw("cream"), 0.05)
    m.box((0, 0.06, -2.48), (6.0, 0.06, 0.03), sw("amber"), 0.02)
    # booths: a table between two benches at every window
    for x in (-3.6, -1.2, 1.2, 3.6):
        m.table(x, -1.6, 0.8, 0.9, 0.76, sw("cream"), sw("silver", "shade"))
        for dx in (-0.62, 0.62):
            m.box((x + dx, 0.24, -1.6), (0.2, 0.24, 0.5), sw("coral"), 0.06)
            m.box((x + dx + (0.16 if dx > 0 else -0.16), 0.7, -1.6), (0.06, 0.3, 0.5), sw("coral"), 0.05)
        for dz in (-0.2, 0.2):
            j = m.prop("dishes", (x + dz, 0.76, -1.6 + dz))
            m.cyl((x + dz, 0.77, -1.6 + dz), 0.12, 0.008, sw("cream"), group=j, prefix="Part", bevel=0.004)
            m.cyl((x + dz + 0.06, 0.82, -1.6 + dz), 0.035, 0.05, sw("bondi_blue", "light"), group=j, prefix="Part", bevel=0.008)
    # luggage rack above the windows with suitcases (props)
    m.box((0, 2.12, -2.25), (5.9, 0.02, 0.24), sw("silver"), 0.01)
    cols = (sw("amber"), sw("bondi_blue"), sw("mint"), sw("coral", "light"), sw("space_gray", "light"))
    for i in range(9):
        x = -5.0 + i * 1.25
        j = m.prop("luggage", (x, 2.14, -2.25))
        m.box((x, 2.32, -2.25), (0.3, 0.18, 0.16), cols[i % 5], 0.05, group=j, prefix="Part")
        m.cap((x - 0.1, 2.53, -2.25), (x + 0.1, 2.53, -2.25), 0.018, sw("space_gray"), group=j, prefix="Part")
    # scenery outside the windows (props: an idle conveyor scrolls them past)
    for i in range(10):
        x = -9.0 + i * 2.0
        j = m.prop("scenery", (x, 0, -4.6 - (i % 2) * 0.8))
        if i % 3 == 0:
            m.ell((x, 0.6, -4.6 - (i % 2) * 0.8), (1.0, 1.1, 0.5), sw("mint", "shade"), group=j, prefix="Part")
        else:
            m.cyl((x, 0.8, -4.6 - (i % 2) * 0.8), 0.08, 0.8, sw("amber", "shade"), group=j, prefix="Part")
            m.ell((x, 1.9, -4.6 - (i % 2) * 0.8), (0.45, 0.6, 0.45), sw("mint"), group=j, prefix="Part")
    m.box((0, -0.3, -5.5), (14.0, 0.3, 2.4), sw("mint", "light"), 0.05, prefix="Flat")
    m.spawns([(0.9, 0.6), (-0.9, 0.6), (2.4, 1.2), (-2.4, 1.2), (0.0, 1.6)])


def train_dining_car__engine_cab(m):
    # the locomotive cab at the right end of the car
    m.box((5.2, 0.55, 0.6), (0.7, 0.55, 0.9), sw("space_gray"), 0.06)
    for k in range(4):
        m.glow_ell((4.85 + k * 0.22, 1.18, 0.1), (0.07, 0.07, 0.02), (sw("mint"), sw("amber"), sw("coral"), sw("bondi_blue"))[k])
    for k in range(3):
        m.cap((4.8 + k * 0.3, 1.1, 0.9), (4.8 + k * 0.3, 1.5, 1.05), 0.025, sw("silver"))
        m.ell((4.8 + k * 0.3, 1.52, 1.06), (0.05, 0.05, 0.05), sw("coral"))
    m.cyl((5.5, 1.5, 1.6), 0.35, 0.35, sw("space_gray", "light"), axis="z", bevel=0.05)
    m.stool(4.6, 1.6, sw("coral"), sw("space_gray"))


# ── 13. Judge Bot's Courtroom ─────────────────────────────────────────────────────
def courtroom_drama(m):
    m.floor(10, 8, sw("amber", "light"), sw("amber"), 1.0)
    m.walls(10, 8, 3.4, sw("cream"), trim=sw("amber", "shade"))
    m.box((0, 0.6, -3.88), (5.0, 0.6, 0.05), sw("amber", "shade"), 0.03)          # wainscot
    m.glow_ell((0, 2.6, -3.86), (0.42, 0.42, 0.02), sw("amber"))                    # the seal
    m.torus((0, 2.6, -3.84), 0.45, 0.04, sw("amber", "shade"), axis="z")
    for s in (1, -1):    # columns
        m.cyl((s * 2.2, 1.7, -3.6), 0.18, 1.7, sw("silver"), bevel=0.04)
    # raised judge bench, chair behind
    m.box((0, 0.2, -3.0), (2.2, 0.2, 0.8), sw("amber", "shade"), 0.05)
    m.box((0, 0.95, -2.55), (1.8, 0.55, 0.3), sw("amber", "shade"), 0.06)
    m.box((0, 1.52, -2.6), (1.9, 0.04, 0.38), sw("amber"), 0.03)
    m.box((0, 1.3, -3.4), (0.45, 0.9, 0.12), sw("coral"), 0.12)
    j = m.prop("gavel", (0.7, 1.56, -2.55))
    m.cyl((0.7, 1.58, -2.55), 0.09, 0.025, sw("amber", "shade"), group=j, prefix="Part", bevel=0.01)
    m.cyl((0.7, 1.68, -2.55), 0.05, 0.09, sw("amber", "shade"), group=j, prefix="Part", axis="x", bevel=0.015)
    m.cap((0.7, 1.68, -2.55), (0.95, 1.7, -2.4), 0.018, sw("amber"), group=j, prefix="Part")
    # witness stand (left) and evidence table (right)
    m.box((-2.8, 0.55, -2.0), (0.6, 0.55, 0.5), sw("amber", "shade"), 0.05)
    m.box((-2.8, 1.12, -2.0), (0.66, 0.03, 0.56), sw("amber"), 0.02)
    m.table(2.8, -1.8, 1.4, 0.7, 0.8, sw("amber"), sw("amber", "shade"))
    for k in range(5):
        x = 2.4 + (k % 3) * 0.38
        y = 0.8 + (k // 3) * 0.26
        j = m.prop("evidence", (x, y, -1.8))
        m.box((x, y + 0.12, -1.8), (0.17, 0.12, 0.15), sw("cream"), 0.03, group=j, prefix="Part")
        m.box((x, y + 0.12, -1.64), (0.1, 0.05, 0.005), sw("coral"), 0.005, group=j, prefix="Part")
    for k in range(4):
        j = m.prop("papers", (2.4 + k * 0.25, 0.8, -1.45))
        m.box((2.4 + k * 0.25, 0.81, -1.45), (0.1, 0.006, 0.13), sw("cream"), 0.004, group=j, prefix="Part")
    # spectator pews down both sides, mirrored
    for s in (1, -1):
        for z in (0.2, 1.3, 2.4):
            m.box((s * 3.6, 0.24, z), (0.9, 0.06, 0.24), sw("amber", "shade"), 0.04)
            m.box((s * 3.6, 0.55, z + 0.22), (0.9, 0.3, 0.05), sw("amber", "shade"), 0.04)
            for sx in (1, -1):
                m.box((s * 3.6 + sx * 0.88, 0.2, z), (0.04, 0.2, 0.2), sw("amber", "shade"), 0.02)
    m.spawns(STD_SPAWNS)


def courtroom_drama__jury_room(m):
    # the jury box, front right: a rail and two rows of seats
    m.box((3.4, 0.12, 2.6), (1.2, 0.12, 0.9), sw("amber", "shade"), 0.03)
    m.box((2.2, 0.55, 2.6), (0.05, 0.4, 0.9), sw("amber"), 0.03)
    for k in range(3):
        for row, (y, x) in enumerate(((0.24, 3.0), (0.24, 3.9))):
            m.stool(x, 2.0 + k * 0.6, sw("bondi_blue"), sw("amber", "shade"))


# ── 14. The Minimalist Museum ─────────────────────────────────────────────────────
def art_gallery_heist(m):
    m.floor(10, 8, sw("silver", "light"), sw("silver"), 2.0)
    m.walls(10, 8, 3.6, sw("cream"), trim=sw("silver", "shade"))
    for k, x in enumerate((-3.0, 0.0, 3.0)):   # paintings: palette blocks in frames
        m.box((x, 2.0, -3.88), (0.75, 0.55, 0.04), sw("amber"), 0.03)
        m.box((x, 2.0, -3.84), (0.65, 0.45, 0.01), sw("cream"), 0.01)
        m.box((x - 0.25, 2.1, -3.82), (0.25, 0.2, 0.01), (sw("coral"), sw("bondi_blue"), sw("mint"))[k], 0.01)
        m.ell((x + 0.25, 1.85, -3.82), (0.18, 0.18, 0.01), (sw("bondi_blue"), sw("amber"), sw("coral"))[k])
    # plinths with vinyl sculptures (both props: the trapdoor drops them through the floor)
    shapes = ("torus", "ball", "cone", "capsule")
    for k, (x, z) in enumerate(((-2.4, -1.4), (-0.8, -0.4), (0.8, -0.4), (2.4, -1.4))):
        j = m.prop("plinths", (x, 0, z))
        m.box((x, 0.5, z), (0.3, 0.5, 0.3), sw("cream"), 0.03, group=j, prefix="Part")
        j = m.prop("sculptures", (x, 1.0, z))
        if shapes[k] == "torus":
            m.torus((x, 1.32, z), 0.22, 0.08, sw("coral"), group=j, prefix="Part", axis="z")
        elif shapes[k] == "ball":
            m.ell((x, 1.25, z), (0.24, 0.24, 0.24), sw("bondi_blue"), group=j, prefix="Part")
        elif shapes[k] == "cone":
            m.cone((x, 1.28, z), 0.22, 0.02, 0.28, sw("amber"), group=j, prefix="Part")
        else:
            m.cap((x, 1.12, z), (x, 1.42, z), 0.12, sw("mint"), group=j, prefix="Part")
        m.glow_ell((x, 3.4, z), (0.18, 0.05, 0.18), sw("amber", "light"))           # spotlights
        for sx in (1, -1):    # velvet rope posts around each plinth
            m.cyl((x + sx * 0.6, 0.45, z + 0.6), 0.03, 0.45, sw("amber"), bevel=0.01)
            m.ell((x + sx * 0.6, 0.93, z + 0.6), (0.045, 0.045, 0.045), sw("amber"))
        m.cap((x - 0.6, 0.85, z + 0.6), (x + 0.6, 0.85, z + 0.6), 0.02, sw("amber", "shade"))
    # laser beams (props, glowing)
    for k in range(5):
        y = 0.35 + k * 0.22
        j = m.prop("lasers", (0, y, 0.9))
        m.cap((-4.8, y, 0.9 - k * 0.3), (4.8, y, 0.4 + k * 0.25), 0.012, sw("coral"), group=j, prefix="Part", emit=3.0)
    # security shutters (hidden props; the alarm slams them down)
    for x in (-3.0, 0.0, 3.0):
        j = m.prop("shutters", (x, 3.0, -3.75))
        m.box((x, 2.0, -3.75), (0.85, 1.0, 0.03), sw("space_gray", "light"), 0.02, group=j, prefix="Part")
    m.spawns(STD_SPAWNS)


def art_gallery_heist__skylight_vault(m):
    # a round vault door in the right wall and a skylight frame glowing above
    m.box((4.75, 1.3, 1.6), (0.2, 1.3, 1.1), sw("silver", "shade"), 0.06)
    m.cyl((4.53, 1.3, 1.6), 0.85, 0.05, sw("silver"), axis="x", bevel=0.03)
    m.torus((4.47, 1.3, 1.6), 0.7, 0.05, sw("amber"), axis="x")
    for k in range(3):
        a = k * 2 * math.pi / 3
        m.cap((4.45, 1.3, 1.6), (4.42, 1.3 + math.cos(a) * 0.35, 1.6 + math.sin(a) * 0.35), 0.03, sw("space_gray"))
    m.glow_box((0, 3.55, -1.0), (1.6, 0.02, 1.0), sw("bondi_blue", "light"))
    m.box((0, 3.6, -1.0), (1.7, 0.04, 1.1), sw("silver", "shade"), 0.02)


# ── 15. Dusty Clockwork Attic ─────────────────────────────────────────────────────
def haunted_attic(m):
    m.floor(10, 8, sw("amber", "shade"), sw("amber"), 0.5)
    m.box((0, 1.8, -4.07), (5.1, 1.8, 0.07), sw("space_gray", "light"), 0.05)       # gable wall
    m.glow_ell((0, 2.4, -4.0), (0.55, 0.55, 0.02), sw("bondi_blue", "light"))        # round moon window
    m.torus((0, 2.4, -3.97), 0.58, 0.06, sw("amber", "shade"), axis="z")
    m.cap((-0.58, 2.4, -3.96), (0.58, 2.4, -3.96), 0.03, sw("amber", "shade"))
    m.cap((0, 1.82, -3.96), (0, 2.98, -3.96), 0.03, sw("amber", "shade"))
    for s in (1, -1):    # slanted roof slabs and rafters, mirrored
        g, name = m._grp("Set", "Set")
        Char.box(m, g, name, bl((s * 2.65, 2.3, 0)), (2.9, 4.1, 0.08), 0.04, sw("space_gray", "light"), rot=(0, s * math.radians(27), 0))
        for z in (-3.0, -1.6, -0.2, 1.2):
            g, name = m._grp("Set", "Set")
            Char.box(m, g, name, bl((s * 2.5, 2.25, z)), (2.95, 0.1, 0.12), 0.03, sw("amber", "shade"), rot=(0, s * math.radians(27), 0))
    m.box((0, 3.62, 0), (0.14, 0.12, 4.2), sw("amber", "shade"), 0.03)                # ridge beam
    # grandfather clock (prop) with its pendulum (prop)
    j = m.prop("clock", (-3.2, 0, -3.3))
    m.box((-3.2, 1.0, -3.3), (0.32, 1.0, 0.22), sw("amber", "shade"), 0.06, group=j, prefix="Part")
    m.box((-3.2, 2.15, -3.3), (0.38, 0.22, 0.25), sw("amber", "shade"), 0.08, group=j, prefix="Part")
    m.cyl((-3.2, 2.15, -3.04), 0.18, 0.01, sw("cream"), group=j, prefix="Part", axis="z", bevel=0.005)
    m.cap((-3.2, 2.15, -3.02), (-3.2, 2.27, -3.02), 0.008, sw("space_gray"), group=j, prefix="Part")
    m.cap((-3.2, 2.15, -3.02), (-3.12, 2.1, -3.02), 0.008, sw("space_gray"), group=j, prefix="Part")
    j = m.prop("pendulum", (-3.2, 1.75, -3.06))
    m.cap((-3.2, 1.75, -3.06), (-3.2, 1.15, -3.06), 0.01, sw("amber"), group=j, prefix="Part")
    m.cyl((-3.2, 1.12, -3.06), 0.08, 0.012, sw("amber"), group=j, prefix="Part", axis="z", bevel=0.005)
    # antique trunks (props, the poltergeist lifts them)
    for k, (x, z) in enumerate(((1.6, -2.8), (2.7, -2.4), (-1.6, -2.6), (3.4, -0.6))):
        j = m.prop("trunks", (x, 0, z))
        col = (sw("coral", "shade"), sw("amber"), sw("bondi_blue", "shade"), sw("mint", "shade"))[k]
        m.box((x, 0.25, z), (0.45, 0.25, 0.28), col, 0.05, group=j, prefix="Part")
        m.cyl((x, 0.5, z), 0.28, 0.45, col, group=j, prefix="Part", axis="x", bevel=0.03)
        for sx in (1, -1):
            m.box((x + sx * 0.3, 0.38, z), (0.03, 0.38, 0.3), sw("silver", "shade"), 0.01, group=j, prefix="Part")
    # sheet-covered furniture (ghostly lumps)
    for (x, z, r) in ((-1.0, -1.4, 0.5), (0.4, -2.9, 0.45)):
        m.ell((x, r * 0.8, z), (r, r * 0.9, r * 0.8), sw("cream"))
    # cobweb chandeliers hanging from the ridge (props)
    for z in (-1.6, 0.6):
        j = m.prop("chandeliers", (0, 2.4, z))
        m.cap((0, 3.55, z), (0, 2.6, z), 0.01, sw("space_gray"), group=j, prefix="Part")
        m.torus((0, 2.5, z), 0.4, 0.03, sw("amber", "shade"), group=j, prefix="Part")
        for k in range(4):
            a = k * math.pi / 2
            m.cyl((math.cos(a) * 0.4, 2.6, z + math.sin(a) * 0.4), 0.025, 0.07, sw("cream"), group=j, prefix="Part", bevel=0.008)
            m.ell((math.cos(a) * 0.4, 2.71, z + math.sin(a) * 0.4), (0.02, 0.035, 0.02), sw("amber", "light"), group=j, prefix="Part", emit=2.5)
            m.cap((math.cos(a) * 0.4, 2.5, z + math.sin(a) * 0.4), (math.cos(a) * 0.15, 2.2, z + math.sin(a) * 0.15), 0.006, sw("cream"), group=j, prefix="Part")
    m.spawns(STD_SPAWNS)


def haunted_attic__bell_tower(m):
    # a ladder up through a hatch to the bell, front right
    for s in (1, -1):
        m.cap((3.6 + s * 0.22, 0.0, 1.8), (3.6 + s * 0.22, 3.3, 1.5), 0.03, sw("amber", "shade"))
    for k in range(8):
        y = 0.35 + k * 0.38
        m.cap((3.38, y, 1.8 - k * 0.035), (3.82, y, 1.8 - k * 0.035), 0.022, sw("amber"))
    m.cone((3.6, 3.05, 1.4), 0.38, 0.12, 0.3, sw("amber"))
    m.ell((3.6, 2.72, 1.4), (0.07, 0.07, 0.07), sw("space_gray"))
    m.cap((3.6, 3.35, 1.4), (3.6, 3.6, 1.4), 0.02, sw("space_gray"))


MAPS = {
    "apple_store_showroom": (apple_store_showroom, {"genius_repair_bar": apple_store_showroom__genius_repair_bar}),
    "chaotic_supermarket": (chaotic_supermarket, {"bakery_deli": chaotic_supermarket__bakery_deli}),
    "retro_diner": (retro_diner, {"drive_thru": retro_diner__drive_thru}),
    "podcast_studio": (podcast_studio, {"green_screen": podcast_studio__green_screen}),
    "lunar_moon_base": (lunar_moon_base, {"rover_pad": lunar_moon_base__rover_pad}),
    "suburban_cul_de_sac": (suburban_cul_de_sac, {"treehouse": suburban_cul_de_sac__treehouse}),
    "cozy_living_room": (cozy_living_room, {"sunroom": cozy_living_room__sunroom}),
    "mad_science_hospital": (mad_science_hospital, {"mri_room": mad_science_hospital__mri}),
    "corporate_office": (corporate_office, {"boardroom": corporate_office__boardroom}),
    "beach_boardwalk": (beach_boardwalk, {"arcade_shack": beach_boardwalk__arcade_shack}),
    "retro_arcade": (retro_arcade, {"bowling_lane": retro_arcade__bowling_lane}),
    "train_dining_car": (train_dining_car, {"engine_cab": train_dining_car__engine_cab}),
    "courtroom_drama": (courtroom_drama, {"jury_room": courtroom_drama__jury_room}),
    "art_gallery_heist": (art_gallery_heist, {"skylight_vault": art_gallery_heist__skylight_vault}),
    "haunted_attic": (haunted_attic, {"bell_tower": haunted_attic__bell_tower}),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = set(argv)
    for mid, (build, expansions) in MAPS.items():
        if only and mid not in only:
            continue
        out = os.path.join(OUT, mid)
        m = Map(mid)
        build(m)
        m.export(out)
        for eid, ebuild in expansions.items():
            e = Map(mid)
            ebuild(e)
            e.export(out, "%s__%s" % (mid, eid))


if __name__ == "__main__":
    main()
