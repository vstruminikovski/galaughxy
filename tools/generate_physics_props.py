"""Physics objects for the studio: smooth, palette-coloured props for rigid-body play.

Every object is centred on its collision shape (origin = centre of mass), so the Godot
RigidBody3D can use a simple primitive shape listed in godot/data/physics_props.json.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python tools/generate_physics_props.py -- godot/assets/props/physics [ids...]

Built with the roster kit (generate_roster.Char): smooth primitives, mirrored parts, same-colour
overlaps melted into one surface (CLAUDE.md sections 17 and 23). Blender axes: Z up.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_roster import Char, SILVER, GRAY, CREAM, BLUE, CORAL, AMBER, MINT  # noqa: E402


def shade(hexc, k):
    """Darker (k < 0) or lighter (k > 0) value of a palette colour."""
    h = hexc.lstrip("#")
    c = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    if k < 0:
        c = [int(v * (1.0 + k)) for v in c]
    else:
        c = [int(v + (255 - v) * k) for v in c]
    return "#%02X%02X%02X" % tuple(max(0, min(255, v)) for v in c)


WOOD = shade(AMBER, -0.32)
WOOD_LIGHT = AMBER
TERRACOTTA = shade(CORAL, -0.32)
MARBLE = shade(CREAM, 0.42)


def crate(c):
    c.box("Root", "Body", (0, 0, 0), (0.23, 0.23, 0.23), 0.02, WOOD)
    for x in (-1, 1):
        for y in (-1, 1):
            c.box("Root", "Post", (x * 0.225, y * 0.225, 0), (0.03, 0.03, 0.25), 0.012, WOOD_LIGHT)
            c.box("Root", "RimX", (0, y * 0.225, x * 0.225), (0.25, 0.03, 0.03), 0.012, WOOD_LIGHT)
            c.box("Root", "RimY", (x * 0.225, 0, y * 0.225), (0.03, 0.25, 0.03), 0.012, WOOD_LIGHT)
    for s in (-1, 1):   # diagonal brace on the front and back
        c.box("Root", "Brace", (0, s * 0.232, 0), (0.29, 0.012, 0.03), 0.01, WOOD_LIGHT, rot=(0, math.radians(45), 0))


def barrel(c):
    c.cyl("Root", "Body", (0, 0, 0), 0.2, 0.3, WOOD, bevel=0.03)
    c.ell("Root", "Belly", (0, 0, 0), (0.215, 0.215, 0.22), WOOD)
    for z in (-0.2, 0.2):
        c.torus("Root", "Hoop", (0, 0, z), 0.212, 0.014, GRAY)
    c.cyl("Root", "Lid", (0, 0, 0.297), 0.17, 0.006, WOOD_LIGHT, bevel=0.003)


def amphora(c):
    c.ell("Root", "Body", (0, 0, -0.03), (0.16, 0.16, 0.21), TERRACOTTA)
    c.cyl("Root", "Neck", (0, 0, 0.2), 0.055, 0.07, TERRACOTTA, bevel=0.01)
    c.torus("Root", "Lip", (0, 0, 0.27), 0.06, 0.016, TERRACOTTA)
    c.cyl("Root", "Foot", (0, 0, -0.26), 0.06, 0.03, TERRACOTTA, bevel=0.01)
    c.torus("Root", "Band", (0, 0, 0.05), 0.158, 0.012, shade(AMBER, 0.0))

    def handle(s, side):
        c.torus("Root", "Handle_" + side, (s * 0.1, 0, 0.17), 0.06, 0.013, TERRACOTTA, rot=(math.radians(90), 0, 0))
    c.pair(handle)


def column_drum(c):
    c.cyl("Root", "Drum", (0, 0, 0), 0.28, 0.25, MARBLE, bevel=0.02)
    for i in range(12):   # fluting
        a = i / 12.0 * math.tau
        c.cyl("Root", "Flute", (math.cos(a) * 0.285, math.sin(a) * 0.285, 0), 0.018, 0.23, shade(CREAM, 0.0), bevel=0.008)
    for z in (-0.245, 0.245):
        c.torus("Root", "Ring", (0, 0, z), 0.272, 0.012, shade(CREAM, 0.0))


def boulder(c):
    c.ell("Root", "Rock", (0, 0, 0), (0.34, 0.31, 0.29), shade(SILVER, -0.32))
    c.ell("Root", "Lump", (0.12, 0.08, 0.1), (0.2, 0.18, 0.17), shade(SILVER, -0.32))
    c.ell("Root", "Lump2", (-0.13, -0.06, -0.05), (0.21, 0.2, 0.18), shade(SILVER, -0.32))


def beach_ball(c):
    c.ell("Root", "Ball", (0, 0, 0), (0.24, 0.24, 0.24), CORAL)
    c.torus("Root", "Stripe", (0, 0, 0), 0.238, 0.03, shade(CREAM, 0.42))
    c.torus("Root", "Stripe2", (0, 0, 0), 0.238, 0.03, AMBER, rot=(math.radians(90), 0, 0))
    c.torus("Root", "Stripe3", (0, 0, 0), 0.238, 0.03, BLUE, rot=(0, math.radians(90), 0))


def bowling_pin(c):
    white = shade(CREAM, 0.42)
    c.ell("Root", "Body", (0, 0, -0.07), (0.062, 0.062, 0.11), white)
    c.cyl("Root", "Neck", (0, 0, 0.06), 0.03, 0.05, white, bevel=0.006)
    c.ell("Root", "Head", (0, 0, 0.13), (0.04, 0.04, 0.05), white)
    c.cyl("Root", "Base", (0, 0, -0.175), 0.04, 0.012, white, bevel=0.006)
    c.torus("Root", "Stripe", (0, 0, 0.05), 0.033, 0.008, CORAL)
    c.torus("Root", "Stripe2", (0, 0, 0.075), 0.031, 0.008, CORAL)


def bowling_ball(c):
    c.ell("Root", "Ball", (0, 0, 0), (0.11, 0.11, 0.11), shade(BLUE, -0.32))
    for x, z in ((-0.025, 0.06), (0.025, 0.06), (0.0, 0.025)):
        c.ell("Root", "Hole", (x, -0.1, z), (0.014, 0.012, 0.014), GRAY)


def domino(c):
    c.box("Root", "Tile", (0, 0, 0), (0.05, 0.018, 0.1), 0.008, shade(CREAM, 0.42))
    c.box("Root", "Bar", (0, -0.0185, 0), (0.035, 0.002, 0.003), 0.001, GRAY)
    for z in (0.05, -0.05):
        c.cyl("Root", "Pip", (0, -0.019, z), 0.009, 0.002, GRAY, rot=(math.radians(90), 0, 0), bevel=0.0)


def watermelon(c):
    c.ell("Root", "Melon", (0, 0, 0), (0.19, 0.15, 0.15), MINT)
    c.ell("Root", "Patch", (0, 0, -0.05), (0.15, 0.11, 0.11), shade(MINT, 0.42))   # pale underside
    c.cap("Root", "Stem", (0.18, 0, 0.0), (0.215, 0, 0.02), 0.01, shade(AMBER, -0.32))


def cone(c):
    c.cone("Root", "Cone", (0, 0, 0.02), 0.15, 0.035, 0.22, CORAL)
    c.torus("Root", "Band", (0, 0, 0.04), 0.1, 0.012, shade(CREAM, 0.42))
    c.box("Root", "Base", (0, 0, -0.225), (0.19, 0.19, 0.022), 0.015, shade(CORAL, -0.32))


PROPS = {
    "crate": crate, "barrel": barrel, "amphora": amphora, "column_drum": column_drum, "boulder": boulder,
    "beach_ball": beach_ball, "bowling_pin": bowling_pin, "bowling_ball": bowling_ball, "domino": domino,
    "watermelon": watermelon, "cone": cone,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "godot/assets/props/physics"
    ids = argv[1:] or list(PROPS)
    for pid in ids:
        c = Char(pid)
        PROPS[pid](c)
        c.export(out)


if __name__ == "__main__":
    main()
