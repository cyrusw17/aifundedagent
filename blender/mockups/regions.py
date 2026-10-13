"""Region palettes: the Rustic house palette with per-region swaps and one accent color each,
so regions read differently at a glance. Shared by the region style sheet and the hay types sheet,
and meant to be copied into game config (Lighting, terrain colors) by the map thread.

Colors are sRGB 0-1 (light, mid, dark), like blender/lib/style.py.
"""

REGIONS = {
    "meadow": {
        "name": "Meadow",
        "tier": "Starting region",
        "needle": "Steel",
        "ground": ((0.50, 0.56, 0.38), (0.44, 0.50, 0.32), (0.36, 0.42, 0.26)),
        "hay": None,  # the house hay
        "bark": None,
        "leaves": ((0.36, 0.46, 0.28), (0.30, 0.40, 0.23), (0.23, 0.31, 0.18)),
        "accent": ((0.62, 0.30, 0.24), (0.52, 0.24, 0.19), (0.36, 0.18, 0.14)),
        "accent_name": "barn red",
        "sky": (0.74, 0.78, 0.76),
        "props": "oak",
    },
    "pine": {
        "name": "Pine Forest",
        "tier": "Tier 1",
        "needle": "Pine",
        "ground": ((0.40, 0.46, 0.32), (0.33, 0.39, 0.26), (0.38, 0.32, 0.24)),  # dark moss, needle litter
        "hay": ((0.76, 0.74, 0.54), (0.62, 0.61, 0.40), (0.42, 0.42, 0.26)),
        "bark": ((0.34, 0.27, 0.21), (0.26, 0.20, 0.15), (0.14, 0.11, 0.08)),
        "leaves": ((0.24, 0.36, 0.28), (0.19, 0.30, 0.23), (0.13, 0.21, 0.16)),
        "accent": ((0.30, 0.48, 0.44), (0.24, 0.40, 0.37), (0.16, 0.28, 0.26)),
        "accent_name": "pine teal",
        "sky": (0.62, 0.69, 0.68),
        "props": "pine",
    },
    "desert": {
        "name": "Desert Dunes",
        "tier": "Tier 2",
        "needle": "Sand",
        "ground": ((0.82, 0.73, 0.56), (0.76, 0.66, 0.49), (0.62, 0.52, 0.38)),
        "hay": ((0.90, 0.85, 0.68), (0.82, 0.73, 0.52), (0.62, 0.53, 0.35)),
        "bark": ((0.58, 0.53, 0.46), (0.48, 0.43, 0.37), (0.32, 0.28, 0.24)),  # sun-bleached
        "leaves": ((0.50, 0.58, 0.42), (0.42, 0.50, 0.35), (0.30, 0.37, 0.26)),  # cactus
        "accent": ((0.74, 0.44, 0.30), (0.66, 0.38, 0.25), (0.46, 0.26, 0.18)),
        "accent_name": "terracotta",
        "sky": (0.88, 0.82, 0.72),
        "props": "cactus",
    },
    "snow": {
        "name": "Snow Peak",
        "tier": "Tier 3",
        "needle": "Ice",
        "ground": ((0.92, 0.93, 0.94), (0.84, 0.86, 0.88), (0.56, 0.56, 0.56)),  # snow over stone
        "hay": ((0.88, 0.86, 0.76), (0.75, 0.72, 0.58), (0.54, 0.51, 0.41)),
        "bark": ((0.36, 0.32, 0.29), (0.28, 0.25, 0.22), (0.15, 0.13, 0.12)),
        "leaves": ((0.26, 0.36, 0.33), (0.21, 0.30, 0.28), (0.14, 0.21, 0.20)),
        "accent": ((0.54, 0.68, 0.78), (0.44, 0.59, 0.70), (0.30, 0.42, 0.52)),
        "accent_name": "ice blue",
        "sky": (0.82, 0.86, 0.90),
        "props": "snowpine",
    },
    "swamp": {
        "name": "Swamp",
        "tier": "Tier 4",
        "needle": "Bog",
        "ground": ((0.40, 0.42, 0.29), (0.33, 0.35, 0.24), (0.24, 0.25, 0.18)),
        "hay": ((0.66, 0.64, 0.43), (0.52, 0.50, 0.31), (0.34, 0.32, 0.20)),
        "bark": ((0.30, 0.28, 0.24), (0.23, 0.21, 0.18), (0.12, 0.11, 0.10)),
        "leaves": ((0.36, 0.44, 0.26), (0.29, 0.36, 0.21), (0.20, 0.25, 0.15)),  # moss, reeds
        "accent": ((0.70, 0.76, 0.36), (0.60, 0.68, 0.28), (0.42, 0.48, 0.20)),
        "accent_name": "firefly green",
        "sky": (0.60, 0.64, 0.56),
        "props": "deadtree",
    },
}
ORDER = ["meadow", "pine", "desert", "snow", "swamp"]


def hexes(triple):
    return " ".join("#%02X%02X%02X" % tuple(round(c * 255) for c in col) for col in triple)


def rgb255(col):
    return ", ".join(str(round(c * 255)) for c in col)


if __name__ == "__main__":
    for key in ORDER:
        r = REGIONS[key]
        print(r["name"])
        for k in ("ground", "hay", "bark", "leaves", "accent"):
            if r[k]:
                print(f"  {k:7s} {hexes(r[k])}   mid RGB {rgb255(r[k][1])}")
        print(f"  sky     {hexes((r['sky'],))}")
