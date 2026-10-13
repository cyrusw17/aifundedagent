"""Stacked-boost week (CEO H13). Plays one week of the first playthrough with every boost on at once, the worst case
for pacing, and checks it against the plain game (tools/economy_model.py).

    python3 tools/boost_sim.py            # table + checks, exit 1 on a failure (tools/prepush.sh runs it)

Stacked, all week, at every stage: the festival on your own region's fields (WorldMap FestivalBoost), a friend on your
farm (Land TogetherBonus), thunderstorms (Weather StormMinutes every StormEveryMinutes, StormMutationOdds), rain all
week (Wet needles, Prices.WetMutation), the pity rule (Prices.Pity), the Hay Market (two bales every restock, only
the ones that pay at your sorter), daily contracts (one hour of play a day, so they are the biggest share they can
be) and the needle index milestone you reach at that stage. A bale's own boost and its extras go through the same
rule as the game, src/shared/Boosts.luau (mirrored in fit() below; tests/boosts.luau checks the Luau side).
Not counted: away earnings (Away.luau), because they only sort hay you already hauled into your silos; the haul is
what limits income here, so they move nothing.

Checks: the week's income is at most Prices.Boosts.Cap times the plain game's at every stage, and no purchase lands in
under half its target time (pacing_sim's targets for the early buys, the plain model's times for the rest).
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import economy_model as em  # noqa: E402
import line_sim  # noqa: E402
import pacing_sim  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "shared")


def read(*parts):
    with open(os.path.join(ROOT, *parts)) as f:
        return f.read()


def block(src, name):
    i = src.index(name)
    i = src.index("{", i)
    depth = 0
    for j in range(i, len(src)):
        depth += src[j] == "{"
        depth -= src[j] == "}"
        if depth == 0:
            return src[i:j + 1]
    raise SystemExit(f"boost_sim: {name} block not closed")


def num(src, key):
    m = re.search(r"\b%s\s*=\s*([\d.]+)" % re.escape(key), src)
    if not m:
        raise SystemExit(f"boost_sim: {key} not found")
    return float(m.group(1))


PRICES = read("Config", "Prices.luau")
CAP = num(block(PRICES, "Prices.Boosts ="), "Cap")
MUT = block(PRICES, "Prices.Mutation =")
CHANCE = 1 / num(MUT, "oneIn")
EXTRA = (num(MUT, "min") + num(MUT, "max")) / 2 - 1
PITY = block(PRICES, "Prices.Pity =")
WET = block(PRICES, "Prices.WetMutation =")
MARKET = block(PRICES, "Prices.HayMarket =")
NPB = {k: float(v) for k, v in re.findall(r"(\w+) = ([\d.]+)", block(PRICES, "Prices.NeedlesPerBale ="))}
NEEDLE = {k: float(v) for k, v in re.findall(r"(\w+) = ([\d.]+)", block(PRICES, "Prices.Needles ="))}
HAY = num(PRICES, "HayPerBale") * num(PRICES, "HayPrice")
TIERS = [(float(a), float(b), float(c)) for a, b, c in re.findall(
    r"fromSold = ([\d.]+),[^\n]*?reward = ([\d.]+), bonus = ([\d.]+)", block(PRICES, "Prices.DailyContracts ="))]
INDEX = [(float(a), float(b)) for a, b in re.findall(r"at = ([\d.]+), cash = ([\d.]+)", block(PRICES, "Prices.NeedleIndex ="))]
FESTIVAL = num(read("Config", "WorldMap.luau"), "FestivalBoost")
TOGETHER = num(read("Config", "Land.luau"), "TogetherBonus")
WEATHER = read("Config", "Weather.luau")
STORM_ODDS = num(WEATHER, "StormMutationOdds")
STORM_MIN = num(WEATHER, "StormMinutes")
gap = re.search(r"StormEveryMinutes = \{ ([\d.]+), ([\d.]+) \}", WEATHER).groups()
STORM_SHARE = STORM_MIN / (STORM_MIN + (float(gap[0]) + float(gap[1])) / 2)
PLAY_HOURS_A_DAY = 1  # contracts are the biggest share of income for a player who plays one hour a day
DAYS = 7

# Hay types the market sells -> (needle id, economy_model region or None)
MARKET_NEEDLE = {"meadow": "steel", "pine": "pine", "desert": "sand", "keys": "coral", "volcano": "obsidian", "bobbin": "brass"}
# Where the first playthrough reaches each needle index milestone (25% is the first few regions' plain needles)
INDEX_STAGE = {25: 8, 50: 10, 75: 12, 100: 13}


def value(n, m):
    """Boosts.value: a bale's needle value against a plain bale's, mutations included."""
    c = min(CHANCE * m, 0.5)
    return n * (1 + c * EXTRA) / (1 + CHANCE * EXTRA)


def fit(own, own_mut, extra, extra_mut):
    """Boosts.fit."""
    limit = max(CAP, value(own, own_mut))
    n, m = own * extra, own_mut * extra_mut
    if value(n, m) <= limit + 1e-9:
        return n, m
    m = own_mut
    if value(n, m) > limit:
        n = max(own, limit / value(1, m))
    return n, m


def market_profit_per_hour(recovery):
    """Profit from buying every Hay Market bale that pays at this recovery: PerPlayer a restock, every restock."""
    if recovery <= 0:
        return 0.0
    kinds = re.findall(r"(\w+) = \{ name = \"[^\"]+\", weight = ([\d.]+), needles = ([\d.]+), mutation = ([\d.]+) \}", MARKET)
    hays = {k: float(v) for k, v in re.findall(r"(\w+) = ([\d.]+)", block(MARKET, "HayTypes ="))}
    ref = num(MARKET, "ReferenceRecovery")
    share = num(MARKET, "PriceShare")
    total_k = sum(float(w) for _, w, _, _ in kinds)
    total_h = sum(hays.values())
    profit = 0.0
    for _, w, needles, mut in kinds:
        for hay, hw in hays.items():
            per = NPB[hay] * float(needles) * NEEDLE[MARKET_NEEDLE[hay]] * value(1, float(mut))
            price = round(share * (HAY + per * ref) / 10) * 10
            profit += float(w) / total_k * hw / total_h * max(0.0, HAY + per * recovery - price)
    per_hour = 3600 / num(MARKET, "RestockSeconds") * num(MARKET, "PerPlayer")
    return profit * per_hour


# Who the sims play. "stacked" is the worst case above. "typical" is a guess to tune PacingScale against, stated so it
# can be argued with: the festival is on your region 1 week in 11, a friend is on your farm a quarter of the time, it
# rains on your fields a third of the time, you're at camp for half the Hay Market restocks, and you play 2 hours a day
# and finish all three contracts.
STACKED = {"festival": 1, "together": 1, "rain": 1, "market": 1, "hours": 1}
TYPICAL = {"festival": 1 / 11, "together": 0.25, "rain": 1 / 3, "market": 0.5, "hours": 2}
TARGET_SEMI = 14.7  # hours: the plain model's climb (ECONOMY.md); Cyrus may still move it to 40


def boosted(i, rate, who=STACKED):
    """One hour at stage i with this player's boosts, averaged over the week (contracts and the index not included)."""
    _, supply, region, sorter = em.STAGES[i - 1]
    rec, speed = em.SORTERS[sorter]
    s = supply()
    done = min(s, speed)
    if rec == 0:
        needles_part = 0.0
    else:
        needles_part = done * 60 * (em.bale_value(region, rec) - HAY)  # $/h from sorted needles, plain game
    # Field bales carry the festival as their own boost; a friend and storms are the extras.
    needle_mult = 0.0
    for fest, pf in ((FESTIVAL, who["festival"]), (1, 1 - who["festival"])):
        for friend, pt in ((TOGETHER, who["together"]), (1, 1 - who["together"])):
            calm = value(*fit(fest, 1, friend, 1))
            storm = value(*fit(fest, 1, friend, STORM_ODDS))
            needle_mult += pf * pt * ((1 - STORM_SHARE) * calm + STORM_SHARE * storm)
    # Wet (while it rains) and pity add on top of the roll, per needle found.
    found = em.REGIONS[region][0] * rec * (who["festival"] * FESTIVAL + 1 - who["festival"])
    wet = who["rain"] * (num(WET, "mult") - 1) / num(WET, "oneIn") / (1 + CHANCE * EXTRA)
    pity = (num(PITY, "mult") - 1) / num(PITY, "bales") / max(found, 1e-9) if found else 0
    extra = needles_part * (needle_mult - 1 + wet + pity) + who["market"] * market_profit_per_hour(rec)
    return rate + extra


def tier_day(gross, scale=None):
    """A full day of contracts at this lifetime-sales mark (tier starts stretch with PacingScale, as in Prices)."""
    scale = line_sim.PACING_SCALE if scale is None else scale
    day = 0.0
    for start, reward, bonus in TIERS:
        if gross >= math.floor(start * scale + 0.5):
            day = 3 * reward + bonus
    return day


def week_mults(who, plain, scale=None):
    """Income per stage for this player against the plain game, over a week (contracts and the index included)."""
    entry = {}
    for _, _, stage, _, _, gross, _ in plain:
        entry.setdefault(stage, gross)
    mults = {}
    for i in range(1, len(em.STAGES) + 1):
        base = em.stage_rate(i)
        hours = DAYS * who["hours"]
        week = boosted(i, base, who) * hours + tier_day(entry.get(i, 0), scale) * DAYS
        week += sum(cash for at, cash in INDEX if INDEX_STAGE.get(int(at)) == i)
        mults[i] = week / (base * hours)
    return mults


def semi_at(who, scale=None):
    plain = em.timeline(scale=scale)
    mults = week_mults(who, plain, scale)
    return em.timeline(lambda i, rate: rate * mults[i], scale)[-1][4]


def main():
    plain = em.timeline(scale=1)  # the targets: the prices as written
    rows, failures = [], []
    mults = week_mults(STACKED, em.timeline())
    for i in range(1, len(em.STAGES) + 1):
        base = em.stage_rate(i)
        hours = DAYS * STACKED["hours"]
        mult = mults[i]
        week = mult * base * hours
        rows.append([em.STAGES[i - 1][0], em.money(base), em.money(week / hours), f"{mult:.2f}x"])
        if mult > CAP + 1e-9:
            failures.append(f"{em.STAGES[i - 1][0]}: a stacked week is {mult:.2f}x the plain game (cap {CAP:g}x)")
    em.table(f"A week with every boost stacked ({PLAY_HOURS_A_DAY} h a day)", ["Stage", "Plain $/h", "Stacked $/h", "Times plain"], rows)

    fast = em.timeline(lambda i, rate: rate * mults[i])  # at the current PacingScale
    targets = {name: target for name, _, _, target in pacing_sim.PLAN}
    rows = []
    for (name, _, _, _, clock, _, _), (_, _, _, _, quick, _, _) in zip(plain, fast):
        target = targets.get(name, clock)
        ok = quick >= 0.5 * target or target - quick <= 0.1
        rows.append([name, f"{target:.1f} h", f"{quick:.1f} h", "" if ok else "UNDER HALF"])
        if not ok:
            failures.append(f"{name}: lands at {quick:.2f} h with every boost, under half its {target:.1f} h target")
    em.table("When each purchase lands with every boost stacked", ["Buy", "Target", "Stacked", ""], rows)
    # PacingScale: where a typical player's Semi lands at each value, and the one Prices should use.
    rows, best = [], None
    for k in range(100, 201, 5):
        scale = k / 100
        semi = semi_at(TYPICAL, scale)
        rows.append([f"{scale:.2f}", f"{semi:.1f} h", f"{em.timeline(scale=scale)[-1][4]:.1f} h"])
        if best is None or abs(semi - TARGET_SEMI) < abs(best[1] - TARGET_SEMI):
            best = (scale, semi)
    em.table("PacingScale: when the Semi lands", ["PacingScale", "Typical player (boosts)", "Plain game"], rows)
    now = semi_at(TYPICAL)
    print(f"Prices.PacingScale = {line_sim.PACING_SCALE:g}: a typical player's Semi lands at {now:.1f} h"
          f" (target {TARGET_SEMI} h; {best[0]:.2f} would land it at {best[1]:.1f} h)\n")
    if abs(now - TARGET_SEMI) > 1.5:
        failures.append(f"PacingScale {line_sim.PACING_SCALE:g} lands a typical Semi at {now:.1f} h, not about {TARGET_SEMI} h (try {best[0]:.2f})")
    if failures:
        print("FAILED:\n  " + "\n  ".join(failures))
        return 1
    print(f"boost_sim: a stacked week stays under {CAP:g}x and every purchase lands in at least half its target time")
    return 0


if __name__ == "__main__":
    sys.exit(main())
