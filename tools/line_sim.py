"""Needlewood line simulator. Reads the live configs (Config/Prices, Sorters, Factory, Needles, Gloves) and prints what
a conveyor line earns: bales/min, needles/min and $/min for a layout, plus a check of every sorter payback that
docs/ECONOMY.md quotes.

    python3 tools/line_sim.py                      # every sorter on Meadow, the payback check, the region lines
    python3 tools/line_sim.py --hay snow --sorter magnet_drum --feed 12 --oil
    python3 tools/line_sim.py --check              # payback check only; exits 1 on a mismatch

The model is the same arithmetic the game runs (Machines.sorter, Needle.priceOf, Economy.rawLoadValue), averaged:
- a line sorts min(feed, sorter rate) bales a minute (oil makes the sorter Oil.speedup faster while it lasts),
- each bale hides NeedlesPerBale[hay] needles and the sorter finds recovery of them (times a region machine's penalty
  when the hay skipped it; Frozen hay and Bog reed are refused instead),
- a found needle sells for Needles[type] x (1 + NeedleGrades[grade of the sorter]) at list price (market = 1),
- the hay itself sells for HayPerBale x HayPrice either way, and the public shop pays RawNeedlePrice per needle.
"""

import argparse
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CONFIG = os.path.join(ROOT, "src", "shared", "Config")


def read(name):
    with open(os.path.join(CONFIG, name)) as f:
        return f.read()


def number(src, name):
    m = re.search(r"^Prices\.%s\s*=\s*([\d.]+)" % re.escape(name), src, re.M)
    if not m:
        raise SystemExit("line_sim: Prices.%s not found" % name)
    return float(m.group(1))


def block(src, name):
    """The { ... } after `Prices.Name =` or `Name = {` (balanced braces)."""
    m = re.search(r"(?:^Prices\.|\b)%s\s*=\s*\{" % re.escape(name), src, re.M)
    if not m:
        raise SystemExit("line_sim: table %s not found" % name)
    i, depth = m.end(), 1
    while depth:
        depth += {"{": 1, "}": -1}.get(src[i], 0)
        i += 1
    return src[m.end() : i - 1]


def pairs(text):
    """key = value pairs at the top level of a table body (numbers and strings)."""
    out = {}
    for k, v in re.findall(r"(\w+)\s*=\s*(\"[^\"]*\"|[\d.]+)", re.sub(r"--[^\n]*", "", text)):
        out[k] = v.strip('"') if v.startswith('"') else float(v)
    return out


PRICES = read("Prices.luau")
P = {
    "hay_per_bale": number(PRICES, "HayPerBale"),
    "hay_price": number(PRICES, "HayPrice"),
    "raw_needle": number(PRICES, "RawNeedlePrice"),
    "needles_per_bale": pairs(block(PRICES, "NeedlesPerBale")),
    "needle_value": pairs(block(PRICES, "Needles")),
    "pieces": pairs(block(PRICES, "Pieces")),
    "bales_per_min": pairs(block(PRICES, "SorterBalesPerMinute")),
    "oil": pairs(block(PRICES, "SorterOil")),
    "grades": pairs(block(PRICES, "NeedleGrades")),
    "sorter_grade": pairs(block(PRICES, "SorterGrade")),
}
SORTERS = [
    (sid, name, float(rec))
    for sid, name, rec in re.findall(r'id = "(\w+)", name = "([^"]+)", recovery = ([\d.]+)', read("Sorters.luau"))
    if sid != "alien_collector"
]
NEEDLE_FOR_HAY = {}  # hay type -> needle id, through the map name both configs share
_maps = {m: hid for hid, m in re.findall(r'(\w+) = \{ name = "[^"]+", map = "([^"]+)"', read("Gloves.luau"))}
for nid, m in re.findall(r'id = "(\w+)", name = "[^"]+", map = "([^"]+)"', read("Needles.luau")):
    if m in _maps:
        NEEDLE_FOR_HAY[_maps[m]] = nid
TREATMENTS = {}
for hay, body in re.findall(r"(\w+) = \{ (machine = [^}]*)\}", block(read("Factory.luau"), "Treatments")):
    t = pairs(body)
    t["required"] = "required = true" in body
    TREATMENTS[hay] = t


def raw_bale(hay):
    """What the public shop (or your own buyer, unsorted) pays for one bale."""
    return P["hay_per_bale"] * P["hay_price"] + P["needles_per_bale"][hay] * P["raw_needle"]


def line(hay="meadow", sorter="conveyor_sorter", feed=None, oil=False, treated=True):
    """One line: feed bales/min (None = keep the sorter full) of hay through one sorter into a buyer."""
    rec = dict((s, r) for s, _, r in SORTERS)[sorter]
    rate = P["bales_per_min"][sorter] * (1 + P["oil"]["speedup"] if oil else 1)
    bpm = rate if feed is None else min(feed, rate)
    t = TREATMENTS.get(hay)
    if t and not treated:
        if t["required"]:
            return {"bales": 0, "needles": 0, "per_min": 0, "note": "refused: needs a " + t["machine"]}
        rec *= t["penalty"]
    grade = P["sorter_grade"].get(sorter, "B")
    needle_price = P["needle_value"][NEEDLE_FOR_HAY[hay]] * (1 + P["grades"][grade])
    needles = P["needles_per_bale"][hay] * rec
    per_bale = P["hay_per_bale"] * P["hay_price"] + needles * needle_price
    return {"bales": bpm, "needles": needles * bpm, "per_bale": per_bale, "per_min": per_bale * bpm, "grade": grade}


def money(x):
    return "$" + format(round(x), ",")


def sorter_table(hay="meadow"):
    print(f"\n### Sorters on {hay} hay, kept full\n")
    print("| Sorter | Finds | Grade | Bales/min | Value/bale | $/min | Extra $/hour over the shop | Price | Payback |")
    print("|---|---|---|---|---|---|---|---|---|")
    rows = {}
    for sid, name, rec in SORTERS:
        r = line(hay, sid)
        extra = (r["per_bale"] - raw_bale(hay)) * r["bales"] * 60
        price = P["pieces"].get(sid, 0)
        payback = price / extra * 60 if extra > 0 else float("inf")
        rows[name] = (r["per_bale"], extra, payback)
        print(
            f"| {name} | {rec:.0%} | {r['grade']} | {r['bales']:g} | {money(r['per_bale'])} | {money(r['per_min'])} |"
            f" {money(extra)} | {money(price)} | {payback:.0f} min |"
        )
    return rows


def check_economy(rows, tolerance=0.10):
    """Compares the sorter table in docs/ECONOMY.md with the model. Returns the mismatches."""
    doc = open(os.path.join(ROOT, "docs", "ECONOMY.md")).read()
    problems = []
    for name, (per_bale, extra, payback) in rows.items():
        m = re.search(r"^\| %s \| [^|]+\| [^|]+\| \$([\d,]+) \| \$([\d,]+) \|.*\| (\d+) min \|" % re.escape(name), doc, re.M)
        if not m:
            problems.append(f"{name}: no row in ECONOMY.md's sorter table")
            continue
        doc_bale, doc_extra, doc_payback = (float(g.replace(",", "")) for g in m.groups())
        for what, got, want in (("value/bale", per_bale, doc_bale), ("extra $/hour", extra, doc_extra), ("payback min", payback, doc_payback)):
            if want and abs(got - want) / want > tolerance:
                problems.append(f"{name}: {what} is {got:,.0f} by the configs, ECONOMY.md says {want:,.0f}")
    return problems


def region_table():
    print("\n### Region lines (magnet drum, kept full)\n")
    print("| Hay | Needle | Without its machine | With it | Machine | Pays back in |")
    print("|---|---|---|---|---|---|")
    for hay, t in TREATMENTS.items():
        bare, good = line(hay, "magnet_drum", treated=False), line(hay, "magnet_drum")
        # A refused bale still sells raw at the end of the line.
        base = raw_bale(hay) * good["bales"] if bare.get("note") else bare["per_min"]
        gain = (good["per_min"] - base) * 60
        price = P["pieces"].get(t["machine"], 0)
        bare_text = (bare["note"] + f", sells raw for {money(base)}/min") if bare.get("note") else money(bare["per_min"]) + "/min"
        print(
            f"| {hay} | {NEEDLE_FOR_HAY[hay]} | {bare_text} | {money(good['per_min'])}/min | {t['machine']} {money(price)} |"
            f" {price / gain * 60:.0f} min |"
        )


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--hay", default=None)
    ap.add_argument("--sorter", default=None)
    ap.add_argument("--feed", type=float, default=None, help="bales a minute reaching the sorter (default: kept full)")
    ap.add_argument("--oil", action="store_true")
    ap.add_argument("--untreated", action="store_true", help="the hay skipped its region machine")
    ap.add_argument("--check", action="store_true", help="only check ECONOMY.md; exit 1 on a mismatch")
    a = ap.parse_args()

    if a.hay or a.sorter:
        r = line(a.hay or "meadow", a.sorter or "conveyor_sorter", a.feed, a.oil, not a.untreated)
        if r.get("note"):
            print(r["note"])
            return 0
        print(
            f"{a.hay or 'meadow'} through {a.sorter or 'conveyor_sorter'}: {r['bales']:.2f} bales/min,"
            f" {r['needles']:.2f} needles/min (grade {r['grade']}), {money(r['per_min'])}/min, {money(r['per_min'] * 60)}/hour"
        )
        return 0

    rows = sorter_table()
    problems = check_economy(rows)
    if not a.check:
        region_table()
    print()
    if problems:
        print("ECONOMY.md is out of step with the configs:")
        for p in problems:
            print("  - " + p)
        return 1
    print("ECONOMY.md matches the configs.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
