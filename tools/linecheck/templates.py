#!/usr/bin/env python3
"""Starter line templates (CEO #37): walks each template in src/shared/LineTemplates.luau the way bales move and
checks it is a sound line, then prints what it earns from line_sim. Exit code 1 on any problem.

    python3 tools/linecheck/templates.py

The walk follows the game's rules: a silo drops bales on the cell in front of its anchor lane (Land buildSilo); a belt
carries them one cell along its direction; a sorter (1 x 2) takes them in at its anchor and puts them out past its
far cell, sorted; a splitter sends them out of its left and right sides in turn (Machines.splitter), onto any tile
that isn't running straight back at it; a hay buyer takes what reaches it from behind. A template passes when every
path from the silo ends in a buyer, every sorter gets unsorted hay, no sorter sits after another one (sorted bales
pass through unsorted, so it would do nothing), nothing loops, overlaps or leaves the 12 x 10 plot, and the total
is the sum of Prices.Pieces. line_sim.line gives each sorter's $/hour at the share of the silo's feed it gets.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import line_sim  # noqa: E402

SRC = os.path.join(HERE, "..", "..", "src", "shared")
DIRS = {"N": (0, -1), "S": (0, 1), "E": (1, 0), "W": (-1, 0)}
PLOT = (12, 10)
LAND = open(os.path.join(SRC, "Config", "Land.luau")).read()
PIECES = {}
for pid, kind, sx, sz in re.findall(r'\{ id = "(\w+)", kind = "(\w+)",.*?size = \{ (\d+), (\d+) \}', LAND):
    PIECES[pid] = (kind, int(sx), int(sz))
SILO_FEED = 60 / float(re.search(r"SiloFeedSeconds = ([\d.]+)", LAND).group(1))  # bales a minute


def templates():
    text = open(os.path.join(SRC, "LineTemplates.luau")).read()
    out = []
    for name, body in re.findall(r'name = "([^"]+)",\s*list = \{(.*?)\n\t\t\},', text, re.S):
        items = [dict(id=i, dx=int(x), dz=int(z), dir=d) for i, x, z, d in re.findall(r'id = "(\w+)", dx = (\d+), dz = (\d+), dir = "(\w)"', body)]
        out.append((name, items))
    return out


def cells(item):
    kind, across, along = PIECES[item["id"]]
    fx, fz = DIRS[item["dir"]]
    rx, rz = -fz, fx
    return [(item["dx"] + fx * a + rx * c, item["dz"] + fz * a + rz * c) for c in range(across) for a in range(along)]


def check(name, items):
    problems = []
    at = {}
    for it in items:
        if it["id"] not in PIECES:
            problems.append(f"unknown piece {it['id']}")
            continue
        for c in cells(it):
            if not (0 <= c[0] < PLOT[0] and 0 <= c[1] < PLOT[1]):
                problems.append(f"{it['id']} at {c} is off the plot")
            if c in at:
                problems.append(f"{it['id']} overlaps {at[c]['id']} at {c}")
            at[c] = it
    if problems:
        return problems, {}

    def accepts(cell, d):
        """The piece at cell takes a load arriving moving in direction d (not running straight back at it)."""
        it = at.get(cell)
        if not it:
            return None
        kind = PIECES[it["id"]][0]
        fd = DIRS[it["dir"]]
        if kind in ("belt", "splitter"):
            return it if (fd[0] + d[0], fd[1] + d[1]) != (0, 0) else None
        if kind in ("separator", "buyer"):
            # In only from behind, at the anchor cell.
            return it if cell == (it["dx"], it["dz"]) and fd == d else None
        return None

    feeds = {}  # sorter id@cell -> share of the silo's bales
    ends = []

    def walk(cell, d, share, sorted_, seen, came_from):
        if (cell, sorted_) in seen:
            problems.append(f"bales loop at {cell} ({came_from})")
            return
        seen = seen | {(cell, sorted_)}
        it = accepts(cell, d)
        if not it:
            problems.append(f"bales leaving {came_from} at {cell} fall off: nothing there takes them")
            return
        kind = PIECES[it["id"]][0]
        fd = DIRS[it["dir"]]
        if kind == "buyer":
            ends.append((it["id"], share, sorted_))
            return
        if kind == "belt":
            walk((cell[0] + fd[0], cell[1] + fd[1]), fd, share, sorted_, seen, f"belt {cell}")
        elif kind == "separator":
            key = f"{it['id']} at {cell}"
            if sorted_:
                problems.append(f"{key} only ever gets sorted bales: it sits after another sorter and does nothing")
            else:
                feeds[key] = feeds.get(key, 0) + share
            far = cells(it)[-1]
            walk((far[0] + fd[0], far[1] + fd[1]), fd, share, True, seen, key)
        elif kind == "splitter":
            left, right = (fd[1], -fd[0]), (-fd[1], fd[0])  # Conveyors.sides
            outs = [s for s in (left, right) if accepts((cell[0] + s[0], cell[1] + s[1]), s)]
            if not outs:
                problems.append(f"splitter at {cell} has no way out")
            for s in outs:
                walk((cell[0] + s[0], cell[1] + s[1]), s, share / len(outs), sorted_, seen, f"splitter {cell}")

    silos = [it for it in items if PIECES[it["id"]][0] == "silo"]
    if len(silos) != 1:
        problems.append(f"{len(silos)} silos; a template starts at one")
        return problems, {}
    s = silos[0]
    fd = DIRS[s["dir"]]
    along = PIECES[s["id"]][2]
    walk((s["dx"] + fd[0] * along, s["dz"] + fd[1] * along), fd, 1.0, False, frozenset(), "the silo")
    if not feeds:
        problems.append("no sorter gets any hay")
    if any(not sorted_ for _, _, sorted_ in ends):
        problems.append("some hay reaches a buyer without passing a sorter")
    return problems, feeds


def main():
    bad = 0
    found = templates()
    if len(found) != 3:
        print(f"FAIL expected 3 templates, found {len(found)}")
        bad += 1
    for name, items in found:
        problems, feeds = check(name, items)
        price = sum(line_sim.P["pieces"].get(it["id"], 0) for it in items)
        if problems:
            bad += 1
            print(f"FAIL {name}:")
            for p in problems:
                print("  - " + p)
            continue
        per_hour = 0
        parts = []
        for key, share in feeds.items():
            sorter = key.split(" at ")[0]
            r = line_sim.line("meadow", sorter, feed=SILO_FEED * share)
            per_hour += r["per_min"] * 60
            parts.append(f"{sorter} {r['bales']:g}/min")
        print(f"{name}: {len(items)} pieces, {line_sim.money(price)}; {', '.join(parts)}; {line_sim.money(per_hour)}/hour on Meadow hay")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
