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
v2 (CEO #30) adds a second table that turns on, one at a time, what the game has beyond v1: bale toss loading and the
Meadow field chute (Config/Chutes stock, refill and drop gap), the needle market (Prices.Market, as Market.luau), the
land loan for the plot (Prices.Bank) and a 2-player crew sharing one save's purchases and one line.
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
GLOVE_PRICE = line_sim.paced(line_sim.pairs(line_sim.block(PRICES, "Gloves")))
TRUCK_PRICE = line_sim.paced(line_sim.pairs(line_sim.block(PRICES, "Trucks")))
TRAILER_PRICE = line_sim.paced(line_sim.pairs(line_sim.block(PRICES, "Trailers")))
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


CHUTE = read("Chutes.luau")
CHUTE_AT = tuple(float(v) for v in re.search(r"Meadow = \{ at = Vector2.new\((-?[\d.]+), (-?[\d.]+)\)", CHUTE).groups())
CHUTE_STOCK, CHUTE_REFILL, CHUTE_GAP = num(CHUTE, "Stock"), num(CHUTE, "RefillSeconds"), num(CHUTE, "DropGap")
TOSS_LOAD = 3.0  # ASSUMED: seconds per bale tossed into a bed from beside it (Game Toss*: about a second of charge,
#                 a short walk to the next bale), against TRUCK_LOAD for carrying each one up and setting it down
MARKET = line_sim.block(PRICES, "Market")
SWING, HALF_LIFE, NORMAL, MIN_NORMAL = num(MARKET, "Swing"), num(MARKET, "HalfLifeSeconds"), num(MARKET, "NormalSales"), num(MARKET, "MinNormalSales")

QUEUE_CAP = 300  # ASSUMED: seconds of bales a player lets wait at the line before selling the rest raw

SCENARIOS = [
    # name, toss and chute, land loan, players, needle market
    ("v1 (solo, hand loading)", False, False, 1, False),
    ("+ toss + chute", True, False, 1, False),
    ("+ needle market", True, False, 1, True),
    ("+ land loan", True, True, 1, True),
    ("+ 2-player crew", True, True, 2, True),
]


class Market:
    """Market.luau for one needle type: sales push the price down, the push halves every HalfLifeSeconds."""

    def __init__(self, list_value):
        self.p, self.t = 0.0, 0.0
        self.k = max(MIN_NORMAL, NORMAL * 100 / list_value)

    def multiplier(self, now):
        self.p *= 0.5 ** ((now - self.t) / HALF_LIFE)
        self.t = now
        return 1 + SWING - 2 * SWING * self.p / (self.p + self.k)

    def sell(self, now, count):
        m = self.multiplier(now)
        self.p += count
        return m


REBIRTH = line_sim.block(PRICES, "Rebirth")
REBIRTH_BONUS = num(REBIRTH, "Bonus")
REBIRTH_KEPT = ("Work Gloves", "Leather Gloves", "Wheelbarrow")  # shovels and gear survive a rebirth (Prices.Rebirth)


def play(seed, hours, toss=False, land_loan=False, players=1, market=False, verbose=False, rebirths=0):
    rng = random.Random(seed)
    bales = scatter(rng)
    raw = line_sim.raw_bale("meadow")
    cash, owned, owed = 0.0, set(), {}
    landed = {}
    plan = list(PLAN)
    stage = "hands"
    if rebirths:
        # A rebirth keeps the plot, the shovels and the wheelbarrow, and every sale pays Bonus more per rebirth.
        owned.update(REBIRTH_KEPT)
        landed.update({name: 0.0 for name in REBIRTH_KEPT})
        plan = [(n, p - PLOT if n.startswith("Plot") else p, lo, tg) for n, p, lo, tg in plan if n not in REBIRTH_KEPT]
        stage = "barrow"
    sorter = None
    steel = Market(P["needle_value"][line_sim.NEEDLE_FOR_HAY["meadow"]])
    chute = {"stock": CHUTE_STOCK, "t": 0.0}
    free = [0.0] * players  # when each player is back from their trip
    line_free = [0.0]  # when the sorter line has worked through its queue
    hay_value = P["hay_per_bale"] * P["hay_price"]

    def earn(amount):
        nonlocal cash
        amount *= 1 + REBIRTH_BONUS * rebirths
        for kind in list(owed):
            pay = min(owed[kind], amount * LOAN[kind][1])
            owed[kind] -= pay
            amount -= pay
        cash += amount

    def chute_trip(t):
        # Refill since the last visit, then drop up to a bed's worth.
        chute["stock"] = min(CHUTE_STOCK, chute["stock"] + (t - chute["t"]) / CHUTE_REFILL)
        chute["t"] = t
        n = int(min(TRUCK_BALES, chute["stock"]))
        far = math.hypot(CHUTE_AT[0] - SELL_PAD[0], CHUTE_AT[1] - SELL_PAD[1])
        return n, TRUCK_OVERHEAD + n * CHUTE_GAP + 2 * far / TRUCK_SPEED

    while plan:
        who = min(range(players), key=lambda i: free[i])
        t = free[who]
        if t >= hours * 3600:
            break
        gloves = "leather" if "Leather Gloves" in owned else ("work" if "Work Gloves" in owned else "bare")
        # The crew shares one truck: the second player hauls by barrow (or by hand) while the first drives.
        mine = stage if who == 0 or stage != "truck" else ("barrow" if "Wheelbarrow" in owned else "hands")
        if mine == "truck":
            group = nearest(bales, t, TRUCK_BALES)
            far = sum(dist(b) for b in group) / max(1, len(group))
            trip = TRUCK_OVERHEAD + len(group) * (TOSS_LOAD if toss else TRUCK_LOAD) + 2 * far / TRUCK_SPEED
            moved = len(group)
            if toss:
                n, chute_time = chute_trip(t)
                if n / chute_time > moved / max(trip, 1):
                    group, moved, trip = [], n, chute_time
                    chute["stock"] -= n
        elif mine == "barrow":
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
            free[who] = t + 5
            continue
        for b in group:
            b[2] = t + REFILL  # gone, and a fresh one grows back
        free[who] = t + trip
        t += trip
        if sorter:
            # The line sorts R bales a minute for everyone. A delivery queues behind what is already waiting; bales
            # that would wait more than QUEUE_CAP go to the public shop raw instead.
            r = line_sim.line("meadow", sorter)
            per_bale_s = 60 / r["bales"]
            start = max(line_free[0], t)
            done = max(0, min(moved, int((t + QUEUE_CAP - start) / per_bale_s)))
            line_free[0] = start + done * per_bale_s
            found = done * r["needles"] / r["bales"]
            per_needle = (r["per_bale"] - hay_value) / max(r["needles"] / r["bales"], 1e-9)
            mult = steel.sell(t, found) if market else 1
            earn(done * hay_value + found * per_needle * mult + (moved - done) * raw)
        else:
            earn(moved * raw)

        # Buy whatever is next as soon as it is affordable (a loan needs DownPayment in cash).
        while plan:
            name, price, loan, target = plan[0]
            financed = 0
            if loan:
                financed = price
            elif land_loan and name.startswith("Plot"):
                loan, financed = "land", PLOT
            need = price - financed * (1 - DOWN) + (owed.get(loan, 0) if loan else 0)
            if cash < need:
                break
            cash -= need
            if loan:
                owed[loan] = financed * (1 - DOWN) * (1 + LOAN[loan][0])
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


def medians(results):
    out = {}
    for name, *_ in PLAN:
        times = sorted(r[name] for r in results if name in r)
        out[name] = times[len(times) // 2] if len(times) * 2 > len(results) else None
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--hours", type=float, default=3)
    ap.add_argument("--runs", type=int, default=20)
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--rebirths", action="store_true", help="also print the first hours of each rebirth climb")
    a = ap.parse_args()

    results = [play(seed, a.hours, verbose=a.verbose) for seed in range(1, a.runs + 1)]
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

    # v2 (CEO #30): the same save with the game's faster loading, a land loan, a crew and the needle market.
    print(f"\n### What changes it (minutes to each buy, median of {a.runs} maps)\n")
    cols = [medians([play(seed, a.hours, toss, land, players, market) for seed in range(1, a.runs + 1)])
            for _, toss, land, players, market in SCENARIOS]
    print("| Buy | Target | " + " | ".join(name for name, *_ in SCENARIOS) + " |")
    print("|---|---|" + "---|" * len(SCENARIOS))
    for name, _, _, target in PLAN:
        cells = [f"{c[name] * 60:.0f}" if c[name] is not None else f"over {a.hours * 60:.0f}" for c in cols]
        print(f"| {name} | {target * 60:.0f} | " + " | ".join(cells) + " |")
    print()
    print(f"Carrying a bale: {carry_speed('bare'):.1f} studs/s bare, {carry_speed('work'):.1f} with Work Gloves;"
          f" pushing a full barrow {carry_speed('work', BARROW_FEEL):.1f}. A raw Meadow bale sells for {line_sim.money(line_sim.raw_bale('meadow'))}."
          f" A crew's second player hauls by barrow while the first drives; the pickup carries {TRUCK_BALES} bales.")
    if a.rebirths:
        print(f"\n### After a rebirth (minutes to each buy, median of {a.runs} maps; shovels, wheelbarrow and plot kept)\n")
        cols = [medians([play(seed, a.hours, rebirths=n) for seed in range(1, a.runs + 1)]) for n in range(0, 6)]
        print("| Buy | First climb | " + " | ".join(f"Rebirth {n}" for n in range(1, 6)) + " |")
        print("|---|---|" + "---|" * 5)
        for name, _, _, _ in PLAN:
            cells = [("kept" if n and name in REBIRTH_KEPT else (f"{c[name] * 60:.0f}" if c[name] is not None else f"over {a.hours * 60:.0f}"))
                     for n, c in enumerate(cols)]
            print(f"| {name} | " + " | ".join(cells) + " |")
    if gaps:
        print("\nOff target by more than half (send to Economy):")
        for g in gaps:
            print("  - " + g)
        return 1
    print("\nEvery purchase lands within half of its target.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
