"""Needlewood economy model. Prints the earning-rate and price tables used in docs/ECONOMY.md.

Every input is an estimate written down so it can be argued with and re-run. Change a number, run
`python3 tools/economy_model.py`, and copy the tables back into the doc. The prices themselves live in
src/shared/Config/Prices.luau; this script mirrors them in PRICES below.
"""

HAY_PER_BALE = 90
HAY_PRICE = 0.50  # public shop and your own hay buyer
RAW_NEEDLE = 1  # what the public shop pays for a needle it finds in your hay

# Region: needles hidden per bale (avg), sorted needle value, round-trip drive minutes from a Meadow plot
REGIONS = {
    "Meadow": (2, 100, 0.5),
    "Pine Forest": (3, 110, 3),
    "Desert": (4, 140, 4),
    "Snow Peak": (5, 160, 5),
    "Swamp": (6, 170, 5),
    "Volcano": (8, 300, 6),
    "Cave": (10, 340, 6),
    "Sky Island": (12, 700, 8),
    "Haunted Grove": (14, 800, 7),
}

SORTERS = {  # recovery, bales per minute
    "none (public shop)": (0.0, 99),
    "Hand sieve": (0.15, 2),
    "Shaker table": (0.35, 4),
    "Conveyor sorter": (0.55, 8),
    "Magnet drum": (0.75, 16),
    "Optical sorter": (0.92, 30),
}

# Hauling. Hand: carry a bale ~110 studs at the loaded walk speed, walk back at 16, 4 s to lift and set down.
HAND_DIST = 110
LOADED_SPEED = {"bare": 7.4, "work": 9.1, "leather": 10.4}
# Trucks: bales per trip (truck + its usual trailer), seconds to hand-load one bale, fixed overhead per trip.
LOAD_SECONDS = 9
TRIP_OVERHEAD = 30 + 20  # moving between bale groups, backing up and unloading at the dock
TRUCKS = {
    "Rusty Pickup + Wagon": 9 + 2,
    "Farm Flatbed + Small": 9 + 4,
    "Box Truck + Medium": 24 + 10,
    "Heavy Hauler + Large": 30 + 36,
    "Semi + Double": 24 + 24,
}


def bale_value(region, recovery):
    needles, value, _ = REGIONS[region]
    if recovery == 0:
        return HAY_PER_BALE * HAY_PRICE + needles * RAW_NEEDLE
    return HAY_PER_BALE * HAY_PRICE + needles * recovery * value


def hand_rate(gloves):
    t = HAND_DIST / LOADED_SPEED[gloves] + HAND_DIST / 16 + 4
    return 60 / t


# Wheelbarrow (Hay tools thread): 3 bales a push, loaded by clicking (about 15 s to gather 3 from nearby groups),
# pushed at 8.2 studs/s (Gloves slowdown on 30% of three bales' weight), walked back at 16, 3 s to set down.
BARROW_BALES, BARROW_LOAD_SECONDS, BARROW_SPEED = 3, 15, 8.2


def barrow_rate(dist=HAND_DIST):
    t = BARROW_LOAD_SECONDS + dist / BARROW_SPEED + dist / 16 + 3
    return BARROW_BALES * 60 / t


def truck_rate(truck, region):
    bales = TRUCKS[truck]
    drive = REGIONS[region][2] * 60
    t = bales * LOAD_SECONDS + TRIP_OVERHEAD + drive
    return bales * 60 / t


def table(title, header, rows):
    print(f"\n### {title}\n")
    print("| " + " | ".join(header) + " |")
    print("|" + "---|" * len(header))
    for r in rows:
        print("| " + " | ".join(str(c) for c in r) + " |")


def money(x):
    return f"${x:,.0f}"


# Mirrors src/shared/Config/Prices.luau
PRICES = {
    "Hand sieve": 500, "Shaker table": 4000, "Conveyor sorter": 25000, "Magnet drum": 190000, "Optical sorter": 1350000,
}

# The stage ladder: what you own -> income per hour
STAGES = [
    ("1. Hands, bare", lambda: hand_rate("bare"), "Meadow", "none (public shop)"),
    ("2. Hands, Work Gloves", lambda: hand_rate("work"), "Meadow", "none (public shop)"),
    ("2b. Wheelbarrow, public shop", lambda: barrow_rate(), "Meadow", "none (public shop)"),
    ("3. Pickup, public shop", lambda: truck_rate("Rusty Pickup + Wagon", "Meadow"), "Meadow", "none (public shop)"),
    ("4. Pickup, plot + Hand sieve", lambda: truck_rate("Rusty Pickup + Wagon", "Meadow"), "Meadow", "Hand sieve"),
    ("5. Pickup, Shaker table", lambda: truck_rate("Rusty Pickup + Wagon", "Meadow"), "Meadow", "Shaker table"),
    ("6. Flatbed, Shaker, Pine", lambda: truck_rate("Farm Flatbed + Small", "Pine Forest"), "Pine Forest", "Shaker table"),
    ("7. Flatbed, Conveyor sorter, Desert", lambda: truck_rate("Farm Flatbed + Small", "Desert"), "Desert", "Conveyor sorter"),
    ("8. Box truck, Conveyor sorter, Snow", lambda: truck_rate("Box Truck + Medium", "Snow Peak"), "Snow Peak", "Conveyor sorter"),
    ("9. Box truck, Magnet drum, Swamp", lambda: truck_rate("Box Truck + Medium", "Swamp"), "Swamp", "Magnet drum"),
    ("10. Hauler, Magnet drum, Volcano", lambda: truck_rate("Heavy Hauler + Large", "Volcano"), "Volcano", "Magnet drum"),
    ("11. Hauler, Optical, Cave", lambda: truck_rate("Heavy Hauler + Large", "Cave"), "Cave", "Optical sorter"),
    ("12. Semi, Optical, Sky", lambda: truck_rate("Semi + Double", "Sky Island"), "Sky Island", "Optical sorter"),
]

# A first playthrough, one player, buying things in this order and spending everything earned. A purchase marked
# loan is financed at the bank: pay the down payment in cash, then the loan takes its share of every sale until it
# is paid off (Prices.Bank.Loans).
LOANS = {"truck": (0.20, 0.10, 0.25), "land": (0.20, 0.08, 0.20)}  # down payment, flat interest, repay share
PLAN = [
    ("Work Gloves", 250, 1, None),
    ("Wheelbarrow", 1000, 2, None),
    ("Rusty Pickup", 6000, 3, "truck"),
    ("Wagon Trailer", 1500, 4, None),
    ("Plot + Hand sieve + first line", 2500 + 500 + 8 * 25 + 400, 4, None),
    ("Shaker table", 4000, 5, None),
    ("Leather Gloves", 8000, 6, None),
    ("Farm Flatbed", 25000, 6, "truck"),
    ("Small Trailer", 8000, 7, None),
    ("Conveyor sorter", 25000, 7, None),
    ("Hay silo", 5000, 8, None),
    ("Box Truck", 90000, 8, "truck"),
    ("Reinforced Gloves", 45000, 9, None),
    ("Medium Trailer", 30000, 9, None),
    ("Magnet drum", 190000, 9, None),
    ("Iron Gauntlets", 75000, 10, None),
    ("Heavy Hauler", 350000, 10, "truck"),
    ("Large Trailer", 120000, 11, None),
    ("Optical sorter", 1350000, 11, None),
    ("Starlight Gloves", 400000, 12, None),
    ("Semi Rig", 1500000, 12, "truck"),
]


def stage_rate(i, mult=None):
    """Income per hour at stage i (1-based, STAGES order). mult(i, rate) can scale it (tools/boost_sim.py)."""
    name, supply, region, sorter = STAGES[i - 1]
    s = supply()
    rec, speed = SORTERS[sorter]
    done = min(s, speed)
    rate = (done * bale_value(region, rec) + (s - done) * bale_value(region, 0)) * 60
    return mult(i, rate) if mult else rate


def paced(name, price, scale=None):
    """Prices.PacingScale applied to a PLAN price (line_sim.pace; the Rusty Pickup is PacingKeep)."""
    import line_sim  # noqa: E402  (reads Prices.luau; only the pacing dial comes from there)
    return line_sim.pace("rusty_pickup" if name == "Rusty Pickup" else name, price, scale)


def timeline(mult=None, scale=None, kept=None):
    """The first playthrough: [(name, price, stage, hours to afford, total hours, gross earned so far, note)].
    Prices go through Prices.PacingScale (or scale, to try a value). kept: {name: dollars already owned} for a climb
    after a rebirth (tools/boost_sim.py), taken off that purchase's price."""
    rates = {i: stage_rate(i, mult) for i in range(1, len(STAGES) + 1)}
    clock, gross = 0.0, 0.0
    owed = {}  # loan kind -> amount still owed; one loan of each kind at a time, like the bank
    out = []
    for name, price, stage, loan in PLAN:
        price = max(0, paced(name, price, scale) - (kept or {}).get(name, 0))
        rate = rates[stage]
        need = price
        if loan:
            down, interest, _ = LOANS[loan]
            need = price * down + owed.get(loan, 0)  # pay off the last loan of this kind first
            owed[loan] = 0
        hours = 0.0
        while need > 0 and price > 0:
            step = 1 / 60
            earned = rate * step
            for kind in owed:
                pay = min(owed[kind], rate * step * LOANS[kind][2])
                owed[kind] -= pay
                earned -= pay
            need -= earned
            hours += step
        clock += hours
        gross += rate * hours
        note = ""
        if loan:
            owed[loan] = price * (1 - down) * (1 + interest)
            note = f"financed: {money(price * down)} down"
        out.append((name, price, stage, hours, clock, gross, note))
    return out


if __name__ == "__main__":
    import os
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    rows = []
    prev = SORTERS["none (public shop)"]
    for name, (rec, speed) in list(SORTERS.items())[1:]:
        extra = speed * (bale_value("Meadow", rec) - bale_value("Meadow", 0))
        rows.append([name, f"{rec:.0%}", speed, money(bale_value("Meadow", rec)), money(extra * 60), money(PRICES[name]),
                     f"{PRICES[name] / extra:.0f} min"])
    table("Sorter ladder (Meadow hay, sorter kept full)", ["Sorter", "Finds", "Bales/min", "Value/bale", "Extra $/hour over the public shop", "Price", "Payback"], rows)

    table(
        "Value of one bale",
        ["Region"] + list(SORTERS),
        [[r] + [money(bale_value(r, rec)) for rec, _ in SORTERS.values()] for r in REGIONS],
    )
    rows = []
    for g in LOADED_SPEED:
        rate = hand_rate(g)
        rows.append([f"By hand, {g} gloves", f"{rate:.1f}", money(rate * bale_value('Meadow', 0) * 60)])
    for dist in (HAND_DIST, 250):
        rate = barrow_rate(dist)
        rows.append([f"Wheelbarrow, {dist} studs", f"{rate:.1f}", money(rate * bale_value('Meadow', 0) * 60)])
    for t in TRUCKS:
        rate = truck_rate(t, "Meadow")
        rows.append([t, f"{rate:.1f}", money(rate * bale_value('Meadow', 0) * 60)])
    table("Hauling Meadow hay, sold raw at the public shop", ["How", "Bales/min", "$/hour"], rows)

    stages = STAGES
    rows = []
    for name, supply, region, sorter in stages:
        s = supply()
        rec, speed = SORTERS[sorter]
        sorted_rate = min(s, speed)
        extra = s - sorted_rate  # bales the sorter can't keep up with go to the public shop raw
        per_min = sorted_rate * bale_value(region, rec) + extra * bale_value(region, 0)
        rows.append([name, f"{s:.1f}", f"{sorted_rate:.1f}", money(per_min * 60)])
    table("Income per hour at each stage (one player)", ["Stage", "Bales/min hauled", "Bales/min sorted", "$/hour"], rows)

    rows = [[name, money(price), f"{hours * 60:.0f} min", f"{clock:.1f} h", note]
            for name, price, _, hours, clock, _, note in timeline()]
    table("First playthrough timeline", ["Buy", "Price", "Time to afford", "Total play time", "How"], rows)
