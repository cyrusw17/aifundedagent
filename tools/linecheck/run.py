#!/usr/bin/env python3
"""Offline edge-case fuzz for the needle pocket and line math (CEO #21), on mapcheck's Roblox mock.

    python3 tools/linecheck/run.py [path/to/luau]     # from the repo root; exit code 1 on any failed check or crash

It bundles tools/mapcheck/mock.luau, the stubs here, the real Needle, Market, LineMath and configs, then runs
fuzz.luau: thousands of random pocket sequences (give, take, sell, take best, offerings, vault-style moves, saves
with odd keys) asserting that no needle is lost or made, nothing is paid twice, and nothing errors. Physics-side
cases (a bale carried off the flap, two sorters on one bale) need the engine and live in SelfTests/Conveyor.luau.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "src")
MAPCHECK = os.path.join(HERE, "..", "mapcheck")
MODULES = {
    "Shared.LineMath": "shared/LineMath.luau",
    "Shared.Config.Prices": "shared/Config/Prices.luau",
    "Shared.Config.Needles": "shared/Config/Needles.luau",
    "Shared.Config.Factory": "shared/Config/Factory.luau",
    "Shared.Config.Gloves": "shared/Config/Gloves.luau",
    "Services.Market": "server/Services/Market.luau",
    "Services.Needle": "server/Services/Needle.luau",
}


def bundle(entry):
    out = [open(os.path.join(MAPCHECK, "mock.luau")).read(), open(os.path.join(HERE, "stubs.luau")).read()]
    for key, path in MODULES.items():
        src = open(os.path.join(SRC, path)).read()
        src = "\n".join(line for line in src.split("\n") if not line.startswith("--!"))
        out.append(f'MODULES["{key}"] = function(script)\n{src}\nend\n')
    out.append(open(entry).read())
    return "\n".join(out)


def main():
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    path = os.path.join(HERE, ".bundle.luau")
    open(path, "w").write(bundle(os.path.join(HERE, "fuzz.luau")))
    try:
        result = subprocess.run([luau, path], capture_output=True, text=True)
    finally:
        os.remove(path)
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    bad = result.returncode != 0 or "FAIL" in result.stdout or "WARN" in result.stdout
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
