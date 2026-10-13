"""Needlewood new-player pacing simulator (CEO #23). Plays the first hours of a new save, second by second, on the real
config numbers and the real Meadow layout, and prints when each purchase lands against the targets in docs/ECONOMY.md.

    python3 tools/pacing_sim.py                 # 3 hours, 20 seeded maps averaged
    python3 tools/pacing_sim.py --hours 4 --runs 50 --verbose

What is real (read from src/shared/Config):
- Bale scatter: Meadow BaleCell, BaleChance, BalesPerGroup over HalfSize, minus KeepClear rects and BuildingMargin.
- Bales regrow BaleRefillSeconds after you take one. The sell pad is where World.luau puts it, (22, -6).
- Walk 16 empty; carrying, Gloves SlowPerWeight x bale weight (PiecesPerBale x BaleWeightFactor) x (1 - relief)
  + carrySpeed, never under MinWalkSpeed. The wheelbarrow carries WheelbarrowBales and you feel WheelbarrowLoadFactor.
- Prices: gloves, wheelbarrow, trucks, trailers, plot, pieces, sorter speeds and recovery, needles per bale, hay and
  raw needle prices, loans (DownPayment, interest, repayShare).
What is assumed (marked ASSUMED below): seconds to lift or set a bale, seconds to load a truck by hand, truck trip
overhead and drive speed, and the order a sensible new player buys things in.
"""

import argparse
import math
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import line_sim  # noqa: E402  (shares the Prices parser)

P = line_sim.P
CONFIG = line_sim.CONFIG


def read(name):
    return line_sim.read(name)


def num(src, key):
    m = re.search(r"\b%s\s*=\s*([\d.]+)" % key, src)
    if not m:
        raise SystemExit("pacing_sim: %s not found" % key)
    return float(m.group(1))


GAME, GLOVES, MEADOW, PRICES = read("Game.luau"), read("Gloves.luau"), read("Meadow.luau"), line_sim.PRICES
PIECES_PER_BALE = num(GAME, "PiecesPerBale")
REFILL = num(GAME, "BaleRefillSeconds")
BARROW_BALES = int(num(GAME, "WheelbarrowBales"))
BARROW_FEEL = num(GAME, "WheelbarrowLoadFactor")
SLOW, MIN_WALK, BALE_WEIGHT = num(GLOVES, "SlowPerWeight"), num(GLOVES, "MinWalkSpeed"), num(GLOVES, "BaleWeightFactor")
GLOVE = {}
for gid, relief, carry in re.findall(r'id = "(\w+)",[^\n]*?relief = ([\d.]+),[^\n]*?carrySpeed = ([\d.]+)', block := line_sim.block(GLOVES, "Tiers")):
    GLOVE[gid] = (float(relief), float(carry))
CELL, CHANCE, HALF = num(MEADOW, "BaleCell"), num(MEADOW, "BaleChance"), num(MEADOW, "HalfSize")
MARGIN = num(MEADOW, "BuildingMargin")
GROUP = tuple(int(x) for x in re.search(r"BalesPerGroup = \{ (\d+), (\d+) \}", MEADOW).groups())
KEEP = [tuple(float(v) for v in m) for m in re.findall(r"min = Vector2.new\((-?[\d.]+), (-?[\d.]+)\), max = Vector2.new\((-?[\d.]+), (-?[\d.]+)\)", line_sim.block(MEADOW, "KeepClear"))]
BANK = line_sim.block(PRICES, "Bank")
DOWN = num(BANK, "DownPayment")
LOAN = {k: (float(i), float(r)) for k, i, r in re.findall(r"(\w+) = \{ name = \"[^\"]+\", interest = ([\d.]+), repayShare = ([\d.]+)", BANK)}
GLOVE_PRICE = line_sim.pairs(line_sim.block(PRICES, "Gloves"))
TRUCK_PRICE = line_sim.pairs(line_sim.block(PRICES, "Trucks"))
TRAILER_PRICE = line_sim.pairs(line_sim.block(PRICES, "Trailers"))
WHEELBARROW = line_sim.number(PRICES, "Wheelbarrow")
PLOT = line_sim.number(PRICES, "Plot")

SELL_PAD = (22.0, -6.0)
WALK = 16.0
HANDLE = 4.0  # ASSUMED: seconds to lift a bale and set it down on the pad
BARROW_LOAD = 4.0  # ASSUMED: seconds per bale to load the barrow (bales nearby are grabbed in one stop)
TRUCK_BALES = 9 + 2  # Rusty Pickup bed 3 x 3 a layer (Config/Trucks) + Wagon 1 x 2 (Config/Trailers)
TRUCK_LOAD = 9.0  # ASSUMED: seconds to hand-load one bale into a bed
TRUCK_SPEED = 30.0  # ASSUMED: average driving speed in the meadow, under the pickup's maxSpeed 46
TRUCK_OVERHEAD = 50.0  # ASSUMED: backing up, unloading at the dock, moving between groups (as in ECONOMY.md)

# The order a sensible new player buys things in, with the play time ECONOMY.md expects each to land (hours).
PLAN = [
    ("Work Gloves", GLOVE_PRICE["work"], None, 0.1),
    ("Wheelbarrow", WHEELBARROW, None, 0.2),
    ("Rusty Pickup", TRUCK_PRICE["rusty_pickup"], "truck", 0.3),
    ("Wagon Trailer", TRAILER_PRICE["wagon_trailer"], None, 0.5),
    ("Plot + Hand sieve + first line", PLOT + P["pieces"]["hand_sieve"] + 8 * P["pieces"]["belt"] + P["pieces"]["hay_buyer"], None, 1.0),
    ("Shaker table", P["pieces"]["shaker_table"], None, 1.4),
    ("Leather Gloves", GLOVE_PRICE["leather"], None, 1.8),
    ("Farm Flatbed", TRUCK_PRICE["farm_flatbed"], "truck", 2.0),
    ("Small Trailer", TRAILER_PRICE["small_trailer"], None, 2.5),
    ("Conveyor sorter", P["pieces"]["conveyor_sorter"], None, 4.0),
]


def scatter(rng):
    """Bale positions on one seeded Meadow, as MeadowDecor scatters them (flat-ground and road checks left out)."""
    bales = []
    n = int(2 * HALF // CELL)
    for i in range(n):
        for j in range(n):
            if rng.random() >= CHANCE:
                continue
            cx, cz = -HALF + (i + 0.5) * CELL, -HALF + (j + 0.5) * CELL
            if any(x0 - MARGIN <= cx <= x1 + MARGIN and z0 - MARGIN <= cz <= z1 + MARGIN for x0, z0, x1, z1 in KEEP):
                continue
            for _ in range(rng.randint(*GROUP)):
                bales.append([cx + rng.uniform(-6, 6), cz + rng.uniform(-6, 6), 0.0])  # x, z, ready at
    return bales


def carry_speed(gloves, feel=1.0):
    relief, bonus = GLOVE[gloves]
    return max(MIN_WALK, WALK - SLOW * PIECES_PER_BALE * BALE_WEIGHT * feel * (1 - relief) + bonus)


def nearest(bales, now, k, at=SELL_PAD):
    ready = [b for b in bales if b[2] <= now]
    ready.sort(key=lambda b: (b[0] - at[0]) ** 2 + (b[1] - at[1]) ** 2)
    return ready[:k]


def dist(b, at=SELL_PAD):
    return math.hypot(b[0] - at[0], b[1] - at[1])


def play(seed, hours, verbose=False):
    rng = random.Random(seed)
    bales = scatter(rng)
    raw = line_sim.raw_bale("meadow")
    t, cash, owned, owed = 0.0, 0.0, set(), {}
    landed = {}
    plan = list(PLAN)
    stage = "hands"
    sorter = None

    def earn(amount):
        nonlocal cash
        for kind in list(owed):
            pay = min(owed[kind], amount * LOAN[kind][1])
            owed[kind] -= pay
            amount -= pay
        cash += amount

    while t < hours * 3600 and plan:
        # One trip of the current stage.
        gloves = "leather" if "Leather Gloves" in owned else ("work" if "Work Gloves" in owned else "bare")
        if stage == "truck":
            group = nearest(bales, t, TRUCK_BALES)
            far = sum(dist(b) for b in group) / max(1, len(group))
            trip = TRUCK_OVERHEAD + len(group) * TRUCK_LOAD + 2 * far / TRUCK_SPEED
            moved = len(group)
        elif stage == "barrow":
            group = nearest(bales, t, BARROW_BALES)
            far = max((dist(b) for b in group), default=0)
            trip = far / WALK + far / carry_speed(gloves, BARROW_FEEL) + len(group) * BARROW_LOAD + HANDLE
            moved = len(group)
        else:
            group = nearest(bales, t, 1)
            far = dist(group[0]) if group else 0
            trip = far / WALK + far / carry_speed(gloves) + HANDLE
            moved = len(group)
        if moved == 0:
            t += 5
            continue
        for b in group:
            b[2] = t + REFILL  # gone, and a fresh one grows back
        t += trip
        if sorter:
            rate = P["bales_per_min"][sorter] * trip / 60  # bales the line can sort while you were out
            done = min(moved, rate)
            per = line_sim.line("meadow", sorter)["per_bale"]
            earn(done * per + (moved - done) * raw)
        else:
            earn(moved * raw)

        # Buy whatever is next as soon as it is affordable (a loan needs DownPayment in cash).
        while plan:
            name, price, loan, target = plan[0]
            need = price * DOWN + owed.get(loan, 0) if loan else price
            if cash < need:
                break
            cash -= need
            if loan:
                owed[loan] = price * (1 - DOWN) * (1 + LOAN[loan][0])
            owned.add(name)
            landed[name] = t / 3600
            plan.pop(0)
            if name == "Wheelbarrow":
                stage = "barrow"
            elif name == "Wagon Trailer":
                stage = "truck"
            elif name.startswith("Plot"):
                sorter = "hand_sieve"
            elif name == "Shaker table":
                sorter = "shaker_table"
            elif name == "Conveyor sorter":
                sorter = "conveyor_sorter"
            if verbose:
                print(f"  seed {seed}: {name} at {t / 60:.1f} min")
    return landed


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--hours", type=float, default=3)
    ap.add_argument("--runs", type=int, default=20)
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()

    results = [play(seed, a.hours, a.verbose) for seed in range(1, a.runs + 1)]
    print(f"\n### First {a.hours:g} hours of a new save ({a.runs} seeded Meadow maps)\n")
    print("| Buy | Price | Lands (median) | Range | ECONOMY.md target | Off by |")
    print("|---|---|---|---|---|---|")
    gaps = []
    for name, price, loan, target in PLAN:
        times = sorted(r[name] for r in results if name in r)
        if not times:
            print(f"| {name} | {line_sim.money(price)} | not within {a.hours:g} h | | {target:.1f} h | |")
            if target <= a.hours:
                gaps.append(f"{name}: never lands within {a.hours:g} h (target {target:.1f} h)")
            continue
        med = times[len(times) // 2]
        off = (med - target) / target
        flag = " **" if abs(off) > 0.5 and abs(med - target) > 0.1 else ""
        print(f"| {name}{' (loan)' if loan else ''} | {line_sim.money(price)} | {med:.2f} h ({med * 60:.0f} min) |"
              f" {times[0]:.2f} to {times[-1]:.2f} h | {target:.1f} h | {off:+.0%}{flag} |")
        if flag:
            gaps.append(f"{name}: lands at {med * 60:.0f} min, target {target * 60:.0f} min ({off:+.0%})")
    print()
    print(f"Carrying a bale: {carry_speed('bare'):.1f} studs/s bare, {carry_speed('work'):.1f} with Work Gloves;"
          f" pushing a full barrow {carry_speed('work', BARROW_FEEL):.1f}. A raw Meadow bale sells for {line_sim.money(line_sim.raw_bale('meadow'))}.")
    if gaps:
        print("\nOff target by more than half (send to Economy):")
        for g in gaps:
            print("  - " + g)
        return 1
    print("\nEvery purchase lands within half of its target.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
