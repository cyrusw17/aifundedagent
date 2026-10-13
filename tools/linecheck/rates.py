#!/usr/bin/env python3
"""In-game line rates against line_sim (CEO #28). Runs the real Shared/LineRate.luau, the formula behind each sorter's
sign, on sample layouts and compares every number with tools/line_sim.py line(). Exit code 1 on any difference.

    python3 tools/linecheck/rates.py [path/to/luau]
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import line_sim  # noqa: E402
import run  # noqa: E402

run.MODULES["Shared.LineRate"] = "shared/LineRate.luau"

# hay, sorter, feed (None = kept full), oiled, treated
LAYOUTS = [
    ("meadow", "hand_sieve", None, False, True),
    ("meadow", "conveyor_sorter", 6, False, True),
    ("pine", "shaker_table", None, True, True),
    ("snow", "magnet_drum", None, False, True),
    ("volcano", "optical_sorter", 12, True, False),  # ash penalty
    ("swamp", "magnet_drum", None, False, False),  # refused untreated
    ("desert", "optical_sorter", None, False, True),
]


def lua(v):
    return "nil" if v is None else ("true" if v is True else "false" if v is False else repr(v) if isinstance(v, (int, float)) else '"%s"' % v)


def main():
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    lines = ['local LineRate = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").LineRate)', "local bad = 0"]
    for hay, sorter, feed, oil, treated in LAYOUTS:
        want = line_sim.line(hay, sorter, feed, oil, treated)
        name = f"{hay} through {sorter}{' fed %g' % feed if feed else ''}{' oiled' if oil else ''}{'' if treated else ' untreated'}"
        lines.append(f"do local r = LineRate.line({lua(hay)}, {lua(sorter)}, {lua(feed)}, {lua(oil)}, {lua(treated)})")
        checks = [("bales", want["bales"]), ("needles", want["needles"]), ("perMin", want["per_min"])]
        if "per_bale" in want:
            checks.append(("perBale", want["per_bale"]))
        for key, value in checks:
            lines.append(
                f'  if math.abs(r.{key} - {value!r}) > 1e-6 * math.max(1, math.abs({value!r})) then bad += 1 print("FAIL {name}: {key} " .. r.{key} .. " in game, {value!r} in line_sim") end'
            )
        lines.append(f'  print("{name}: $" .. math.floor(r.perHour + 0.5) .. "/hour") end')
    # The sign's measured rate: 10 bales over two minutes is 5 a minute; a lone fresh bale averages over a full minute;
    # work older than the window drops out.
    lines.append("""do
  local log = {}
  for i = 1, 10 do table.insert(log, { i * 12, 1, 3, 600 }) end
  local b, n, d = LineRate.measured(log, 132, 120)
  if math.abs(b - 5) > 1e-9 or math.abs(n - 15) > 1e-9 or math.abs(d - 180000) > 1e-6 then bad += 1 print("FAIL measured: " .. b .. " " .. n .. " " .. d) end
  local one = { { 100, 1, 2, 50 } }
  b = LineRate.measured(one, 110, 120)
  if math.abs(b - 1) > 1e-9 then bad += 1 print("FAIL a fresh bale reads " .. b .. " bales/min, want 1") end
  b = LineRate.measured(one, 400, 120)
  if b ~= 0 or #one ~= 0 then bad += 1 print("FAIL old work did not drop out") end
end""")
    lines.append('print(("rates: %d layouts, %d differences"):format(' + str(len(LAYOUTS)) + ", bad))")
    entry = os.path.join(HERE, ".rates_entry.luau")
    open(entry, "w").write("\n".join(lines) + "\n")
    path = os.path.join(HERE, ".rates.luau")
    try:
        open(path, "w").write(run.bundle(entry))
        result = subprocess.run([luau, path], capture_output=True, text=True)
    finally:
        for p in (entry, path):
            if os.path.exists(p):
                os.remove(p)
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    sys.exit(1 if result.returncode != 0 or "FAIL" in result.stdout else 0)


if __name__ == "__main__":
    main()
