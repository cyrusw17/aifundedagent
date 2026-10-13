#!/usr/bin/env python3
"""Headless checks for the hay math (src/shared/HayMath.luau) against the real configs, outside Roblox.

    python3 tools/haycheck/run.py [path/to/luau]     # from the repo root; needs the luau CLI (github.com/luau-lang/luau)

Bundles mapcheck's Roblox mock (tools/mapcheck/mock.luau) with Config/Game, Config/Gloves, Config/Prices and HayMath,
then runs check.luau (unit checks and a walk-speed table by glove tier and hay type) and, with --fuzz, fuzz.luau (the
hand loop played at random by four fake players: lift, double carry, set down, throw, barrow, leave and rejoin, finds kept
and traded). Exit code 1 on any FAIL or crash.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "src")
MOCK = os.path.join(HERE, "..", "mapcheck", "mock.luau")
MODULES = {
    "Shared.Config.Prices": "shared/Config/Prices.luau",
    "Shared.Config.Game": "shared/Config/Game.luau",
    "Shared.Config.Gloves": "shared/Config/Gloves.luau",
    "Shared.HayMath": "shared/HayMath.luau",
    "Shared.ToolGuide": "shared/ToolGuide.luau",
    "Shared.Config.HayLooks": "shared/Config/HayLooks.luau",
    "Shared.Config.Finds": "shared/Config/Finds.luau",
    "Shared.Config.Needles": "shared/Config/Needles.luau",
    "Shared.Config.Props": "shared/Config/Props.luau",
    "Services.Hay": "server/Services/Hay.luau",
    "Services.Bales": "server/Services/Bales.luau",
    "Services.Finds": "server/Services/Finds.luau",
}


def bundle(entry):
    out = [open(MOCK).read()]
    for key, path in MODULES.items():
        src = open(os.path.join(SRC, path)).read()
        src = "\n".join(line for line in src.split("\n") if not line.startswith("--!"))
        out.append(f'MODULES["{key}"] = function(script)\n{src}\nend\n')
    out.append(open(entry).read())
    return "\n".join(out)


def run(luau, entry):
    path = os.path.join(HERE, ".bundle.luau")
    open(path, "w").write(bundle(entry))
    try:
        result = subprocess.run([luau, path], capture_output=True, text=True)
    finally:
        os.remove(path)
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    return result.returncode == 0 and "FAIL" not in result.stdout


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    luau = args[0] if args else "luau"
    ok = run(luau, os.path.join(HERE, "check.luau"))
    if "--fuzz" in sys.argv:
        ok = run(luau, os.path.join(HERE, "fuzz.luau")) and ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
