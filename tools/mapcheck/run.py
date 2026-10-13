#!/usr/bin/env python3
"""Dry-runs the Stitched Isles build (WorldMap.build) outside Roblox and checks what it makes.

    python3 tools/mapcheck/run.py [path/to/luau]     # from the repo root; needs the luau CLI (github.com/luau-lang/luau)

mock.luau is a small stand-in for the Roblox API (Vector3, CFrame, Instance, services, task); stubs.luau fakes the
services the map only calls into (Props, Bales, Data, Vehicles, WorldTerrain, Bank, WorldLabel). Any other Services
module it can't find becomes a do-nothing stub and is printed as STUB. check.luau builds the map, prints part counts
per region, and lists any solid part standing in a road lane. Exit code 1 on a crash, a warning, or a blocked lane.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "src")
MODULES = {
    "Shared.Config.WorldMap": "shared/Config/WorldMap.luau",
    "Shared.Config.Meadow": "shared/Config/Meadow.luau",
    "Shared.Config.Rustic": "shared/Config/Rustic.luau",
    "Shared.Config.Gloves": "shared/Config/Gloves.luau",
    "Shared.Config.Prices": "shared/Config/Prices.luau",
    "Services.MeadowTerrain": "server/Services/MeadowTerrain.luau",
    "Services.WorldShape": "server/Services/WorldShape.luau",
    "Services.Regions": "server/Services/Regions.luau",
    "Services.Highway": "server/Services/Highway.luau",
    "Services.Ferry": "server/Services/Ferry.luau",
    "Services.WorldMap": "server/Services/WorldMap.luau",
    "Services.DayNight": "server/Services/DayNight.luau",
    "Services.WorldClock": "server/Services/WorldClock.luau",
    "Shared.Config.Quests": "shared/Config/Quests.luau",
    "Shared.Config.Weather": "shared/Config/Weather.luau",
    "Services.Weather": "server/Services/Weather.luau",
    "Services.RegionEvents": "server/Services/RegionEvents.luau",
}


def bundle(entry):
    out = [open(os.path.join(HERE, "mock.luau")).read(), open(os.path.join(HERE, "stubs.luau")).read()]
    for key, path in MODULES.items():
        src = open(os.path.join(SRC, path)).read()
        src = "\n".join(line for line in src.split("\n") if not line.startswith("--!"))
        out.append(f'MODULES["{key}"] = function(script)\n{src}\nend\n')
    out.append(open(entry).read())
    return "\n".join(out)


def main():
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    path = os.path.join(HERE, ".bundle.luau")
    open(path, "w").write(bundle(os.path.join(HERE, "check.luau")))
    try:
        result = subprocess.run([luau, path], capture_output=True, text=True)
    finally:
        os.remove(path)
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    bad = result.returncode != 0 or "WARN" in result.stdout or "BLOCK" in result.stdout
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
