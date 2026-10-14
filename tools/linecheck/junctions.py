#!/usr/bin/env python3
"""Splitter and merger junctions (CEO #38) on the real Conveyors.luau. See junctions.luau.

    python3 tools/linecheck/junctions.py [path/to/luau]     # exit code 1 on any failed check
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import run  # noqa: E402

run.MODULES["Services.Conveyors"] = "server/Services/Conveyors.luau"


def main():
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    path = os.path.join(HERE, ".junctions.luau")
    try:
        open(path, "w").write(run.bundle(os.path.join(HERE, "junctions.luau")))
        result = subprocess.run([luau, path], capture_output=True, text=True)
    finally:
        if os.path.exists(path):
            os.remove(path)
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    sys.exit(1 if result.returncode != 0 or "FAIL" in result.stdout else 0)


if __name__ == "__main__":
    main()
