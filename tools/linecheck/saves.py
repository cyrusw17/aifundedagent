#!/usr/bin/env python3
"""Save round trip for a maxed-out line (CEO #34), on mapcheck's Roblox mock with the real Data.luau.

    python3 tools/linecheck/saves.py [path/to/luau]     # exit code 1 on any failed check
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import run  # noqa: E402

run.MODULES.update({
    "Services.Data": "server/Services/Data.luau",
    "Shared.Config.Game": "shared/Config/Game.luau",
    "Shared.Config.Land": "shared/Config/Land.luau",
    "Shared.Config.Alloys": "shared/Config/Alloys.luau",
    "Shared.NeedleIndex": "shared/NeedleIndex.luau",
})


def main():
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    path = os.path.join(HERE, ".saves.luau")
    try:
        # Data is real here, so drop the stub that stands in for it in the pocket fuzz.
        bundle = run.bundle(os.path.join(HERE, "saves.luau")).replace('MODULES["Services.Data"] = function()', 'MODULES["Services.DataStub"] = function()', 1)
        open(path, "w").write(bundle)
        result = subprocess.run([luau, path], capture_output=True, text=True)
    finally:
        if os.path.exists(path):
            os.remove(path)
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    sys.exit(1 if result.returncode != 0 or "FAIL" in result.stdout else 0)


if __name__ == "__main__":
    main()
