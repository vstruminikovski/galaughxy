"""History maps (CLAUDE.md section 27): ancient architecture from 0 A.D. in kit-built dioramas.

  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \\
      --python tools/generate_history_maps.py -- [map_id ...]

Writes godot/assets/maps/<map_id>/<map_id>.glb (same naming contract as tools/generate_15_maps.py),
plus:
  Lowpoly_*   converted 0 A.D. buildings (tools/zeroad.py): faceted, one flat palette colour per face,
              inked in Godot with crease and silhouette edges (InkEdges.gd)

0 A.D. art is (C) Wildfire Games, CC-BY-SA 3.0. The converted buildings inside these map files stay
CC-BY-SA 3.0; see godot/assets/history/LICENSE.md. Everything built from the kit (ground, water, trees,
columns, props) is ours. Coordinates are Godot's: +X right, +Y up, +Z toward the camera.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Vector  # noqa: E402

from generate_15_maps import Map, sw, bl, OUT  # noqa: E402
from generate_roster import Char  # noqa: E402
import zeroad  # noqa: E402

SCALE = 0.3    # 0 A.D. metres -> our dioramas (monuments fill the backdrop without towering out of frame)


def building(m, actor, label, at, yaw_deg=0.0, scale=SCALE):
    """A converted 0 A.D. building under the Set group, base on the ground at `at` (Godot coords)."""
    o = zeroad.import_actor(actor, label, lambda h: m.mat(h), scale)
    o.parent = m.joints["Set"]
    o.location = Vector(bl(at)) - m.wpos["Set"]
    o.rotation_euler = (0, 0, math.radians(yaw_deg))
    return o


def ground(m, col, size=40.0):
    """A wide ground plane under everything: no void past the set's edges."""
    m.box((0, -0.16, 0), (size, 0.05, size), col, 0.05, prefix="Flat")


def palm(m, x, z, h=2.6, lean=0.0):
    trunk = sw("amber", "shade")
    for k in range(5):   # segmented trunk, leaning
        y = 0.25 + k * h / 5
        m.cyl((x + lean * k * 0.08, y, z), 0.09 - k * 0.008, h / 10 + 0.02, trunk, bevel=0.02)
    top = (x + lean * 0.4, h + 0.1, z)
    for i in range(7):   # fronds droop outward from the crown
        a = i / 7.0 * math.tau + 0.3
        c = (top[0] + math.cos(a) * 0.5, top[1] - 0.17, top[2] + math.sin(a) * 0.5)
        g, name = m._grp("Set", "Set")
        Char.ell(m, g, name, bl(c), (0.6, 0.17, 0.05), sw("mint"), rot=(0, math.radians(30), -a))
    m.ell(top, (0.2, 0.16, 0.2), sw("mint", "shade"))


def cypress(m, x, z, h=3.2):
    m.cyl((x, 0.25, z), 0.08, 0.25, sw("amber", "shade"), bevel=0.02)
    m.ell((x, 0.5 + h * 0.45, z), (0.42, h * 0.5, 0.42), sw("mint", "shade"))


def column(m, x, z, h=3.0, col=None):
    col = col or sw("cream", "light")
    m.cyl((x, 0.12, z), 0.36, 0.12, sw("cream"), bevel=0.03)
    m.cyl((x, 0.24 + h / 2, z), 0.26, h / 2, col, bevel=0.02)
    m.box((x, h + 0.36, z), (0.4, 0.12, 0.4), sw("cream"), 0.04)


def amphora_prop(m, group, x, z):
    j = m.prop(group, (x, 0, z))
    m.ell((x, 0.3, z), (0.16, 0.21, 0.16), sw("coral", "shade"), group=j, prefix="Part")
    m.cyl((x, 0.56, z), 0.055, 0.07, sw("coral", "shade"), group=j, prefix="Part", bevel=0.01)
    m.cyl((x, 0.05, z), 0.06, 0.04, sw("coral", "shade"), group=j, prefix="Part", bevel=0.01)
    return j


def stall(m, group, x, z, cloth):
    j = m.prop(group, (x, 0, z))
    m.box((x, 0.45, z), (0.7, 0.05, 0.4), sw("amber", "shade"), 0.03, group=j, prefix="Part")
    for sx in (1, -1):
        m.cyl((x + sx * 0.62, 0.75, z - 0.32), 0.03, 0.75, sw("amber", "shade"), group=j, prefix="Part", bevel=0.01)
        m.cyl((x + sx * 0.62, 0.22, z + 0.32), 0.03, 0.22, sw("amber", "shade"), group=j, prefix="Part", bevel=0.01)
    m.box((x, 1.52, z - 0.05), (0.78, 0.03, 0.5), cloth, 0.02, group=j, prefix="Part")
    for k in range(3):
        m.ell((x - 0.4 + k * 0.4, 0.58, z), (0.12, 0.09, 0.12), (sw("amber"), sw("coral"), sw("mint"))[k], group=j, prefix="Part")
    return j


# ── 1. The Roman Forum ────────────────────────────────────────────────────────────
def roman_forum(m):
    ground(m, sw("mint", "shade"))
    m.floor(18, 13, sw("cream", "light"), sw("cream"), size=1.5)
    m.box((0, 0.04, 2.2), (1.4, 0.04, 4.6), sw("cream"), 0.03, prefix="Flat")   # via sacra
    building(m, "structures/romans/temple_mars.xml", "temple_mars", (0, 0, -15.5))
    building(m, "structures/romans/triumphal_arch.xml", "triumphal_arch", (-6.8, 0, -7.0), 90)
    building(m, "structures/romans/sp_pantheon.xml", "pantheon", (10.5, 0, -12.5), -20)
    building(m, "structures/romans/temple_vesta.xml", "temple_vesta", (-11.0, 0, -13.0))
    building(m, "structures/romans/sp_forumbuilding_1.xml", "basilica", (-13.5, 0, -1.0), 90)
    for s_ in (1, -1):                     # colonnades down both sides, mirrored
        for k in range(5):
            column(m, s_ * 8.4, -5.0 + k * 2.6)
    for x, z in ((-9.6, -8.6), (9.6, -6.0), (10.6, 2.5), (-15.0, -15.0), (15.0, -3.0)):
        cypress(m, x, z)
    for k in range(4):                     # amphora rows by the market stalls (prop group)
        amphora_prop(m, "amphorae", -3.8 + k * 0.5, 3.6)
    stall(m, "stalls", -5.0, 1.8, sw("coral"))
    stall(m, "stalls", 5.8, 3.4, sw("bondi_blue"))
    for k in range(3):                     # senators' banners (props: they flap in the gust)
        j = m.prop("banners", (-2.0 + k * 2.0, 0, -4.6))
        m.cyl((-2.0 + k * 2.0, 1.4, -4.6), 0.03, 1.4, sw("amber", "shade"), group=j, prefix="Part", bevel=0.01)
        m.box((-2.0 + k * 2.0 + 0.3, 2.3, -4.6), (0.3, 0.45, 0.015), sw("coral", "shade"), 0.01, group=j, prefix="Part")
    m.spawns([(0.9, 2.2), (-0.9, 2.2), (1.8, 3.6), (-1.8, 3.6), (0.0, 1.0)])


# ── 2. Nile of the Pharaohs ───────────────────────────────────────────────────────
def nile_pyramids(m):
    ground(m, sw("amber", "light"), 50.0)
    m.floor(16, 11, sw("amber", "light"), sw("cream"), size=2.0)
    m.box((-10.5, -0.04, -6.0), (2.6, 0.04, 22.0), sw("bondi_blue"), 0.05, prefix="Flat")   # the Nile
    for k in range(9):                     # reeds on the bank
        x = -7.6 + (k % 2) * 0.3
        z = -14.0 + k * 3.1
        m.cyl((x, 0.45, z), 0.03, 0.45, sw("mint", "shade"), bevel=0.01)
        m.ell((x, 0.98, z), (0.06, 0.16, 0.06), sw("amber", "shade"))
    building(m, "structures/kushites/pyramid_large.xml", "pyramid_large", (-17.0, 0, -30.0), 15)
    building(m, "structures/kushites/pyramid_small.xml", "pyramid_small", (-8.0, 0, -32.0), 8)
    building(m, "structures/kushites/pyramid_small.xml", "pyramid_small_b", (17.0, 0, -24.0), -12)
    building(m, "structures/kushites/temple_amun.xml", "temple_amun", (1.0, 0, -19.5))
    building(m, "structures/ptolemies/statue_isis.xml", "statue_isis", (6.8, 0, -4.2), -25)
    building(m, "structures/ptolemies/merchant_ship.xml", "merchant_ship", (-10.4, 0.0, -7.0), 90)
    for x, z in ((-6.6, -4.0), (-6.9, 0.5), (-6.4, 4.6), (8.4, 1.8), (9.6, -6.0), (-5.4, -11.0)):
        palm(m, x, z, 2.4 + (abs(x * z) % 1.0) * 0.6, lean=0.6 if x < 0 else -0.6)
    for k in range(5):                     # amphorae by the dock (prop group)
        amphora_prop(m, "amphorae", -5.6 + (k % 3) * 0.45, 2.0 + (k // 3) * 0.45)
    stall(m, "stalls", 3.0, 3.0, sw("amber"))
    for k in range(4):                     # obelisk-lined avenue (props: they topple in the quake)
        for s in (1, -1):
            j = m.prop("obelisks", (s * 2.4, 0, -3.0 - k * 2.2))
            m.box((s * 2.4, 0.15, -3.0 - k * 2.2), (0.3, 0.15, 0.3), sw("cream"), 0.03, group=j, prefix="Part")
            m.box((s * 2.4, 1.3, -3.0 - k * 2.2), (0.16, 1.0, 0.16), sw("cream", "shade"), 0.02, group=j, prefix="Part")
            m.cone((s * 2.4, 2.42, -3.0 - k * 2.2), 0.16, 0.01, 0.12, sw("amber"), group=j, prefix="Part")
    m.spawns([(0.9, 2.2), (-0.9, 2.2), (1.8, 3.6), (-1.8, 3.6), (0.0, 1.0)])


MAPS = {"roman_forum": roman_forum, "nile_pyramids": nile_pyramids}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = set(argv)
    for mid, build in MAPS.items():
        if only and mid not in only:
            continue
        m = Map(mid)
        build(m)
        m.export(os.path.join(OUT, mid))


if __name__ == "__main__":
    main()
