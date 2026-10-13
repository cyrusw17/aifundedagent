#!/usr/bin/env python3
"""Static contract checks for Needlewood, run on every integration fold-in (Project health check).

    python3 tools/check_contracts.py          # from the repo root; exit code 1 if any ERROR

Checks (text-level, so it has false positives; every hit says where to look):
  1. Data.get nil-safety: a Data.get(...) result indexed without a nil check first.
  2. Prices keys: every Prices.X / Prices.X.Y read exists in Config/Prices.luau.
  3. Require cycles: top-level (module load time) requires between src modules form no cycle.
  4. Props names: every literal prop name (Props.make/has, Skins.dress, prop = "...") is in Config/Props.luau Sizes,
     because Props only looks for names listed there.
  5. Streaming safety (client): workspace children read with a plain dot, which breaks once StreamingEnabled is on.
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "src")

files = {}
for dirpath, _, names in os.walk(SRC):
    for name in names:
        if name.endswith(".luau") or name.endswith(".lua"):
            path = os.path.join(dirpath, name)
            files[os.path.relpath(path, ROOT)] = open(path, encoding="utf-8").read()

errors, warnings = [], []

# 0. No empty or conflict-marked source files (a bad merge resolution once emptied two client scripts).
for path, text in files.items():
    if not text.strip():
        errors.append(f"{path}: file is empty")
    elif re.search(r"^(<<<<<<<|>>>>>>>) ", text, re.M):
        errors.append(f"{path}: has merge conflict markers")


def strip_comments(line):
    i = line.find("--")
    return line if i < 0 else line[:i]


# 1. Data.get nil-safety ---------------------------------------------------------------------------------------------
for path, text in files.items():
    lines = text.split("\n")
    for n, raw in enumerate(lines):
        line = strip_comments(raw)
        if re.search(r"Data\.get\([^()]*\)\s*[.:\[]", line):
            errors.append(f"{path}:{n + 1}: Data.get(...) indexed directly (nil until a slot is picked)")
            continue
        m = re.match(r"\s*local\s+(\w+)\s*=\s*(?:\w+\s+and\s+)?Data\.get\([^()]*\)\s*$", line)
        if not m:
            continue
        var = m.group(1)
        guard = re.compile(
            rf"(not\s+{var}\b|\b{var}\s+and\b|\bif\s+{var}\b|\b{var}\s*==\s*nil|\b{var}\s*~=\s*nil|assert\({var}\b|\b{var}\s+or\b)"
        )
        use = re.compile(rf"\b{var}\s*[.\[:]")
        for k in range(n + 1, min(n + 40, len(lines))):
            later = strip_comments(lines[k])
            if guard.search(later):
                break
            if use.search(later):
                errors.append(f"{path}:{k + 1}: '{var}' from Data.get (line {n + 1}) is used before any nil check")
                break

# 2. Prices keys -----------------------------------------------------------------------------------------------------
prices_path = "src/shared/Config/Prices.luau"
prices = files.get(prices_path, "")
top = {}
for m in re.finditer(r"^Prices\.(\w+)\s*=\s*(\{)?", prices, re.M):
    key, is_table = m.group(1), m.group(2)
    sub = None
    if is_table:
        # The table literal's own keys, one level deep.
        depth, i, start = 0, m.end() - 1, m.end()
        while i < len(prices):
            if prices[i] == "{":
                depth += 1
            elif prices[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = prices[start:i]
        sub, d = set(), 0
        for line in body.split("\n"):
            if d == 0:
                km = re.match(r"\s*(\w+)\s*=", line)
                if km:
                    sub.add(km.group(1))
                km = re.match(r'\s*\[\s*"(\w+)"\s*\]\s*=', line)
                if km:
                    sub.add(km.group(1))
            code = strip_comments(line)
            d += code.count("{") - code.count("}")
    top[key] = sub
for m in re.finditer(r"^Prices\.(\w+)\.(\w+)\s*=", prices, re.M):
    if top.get(m.group(1)) is not None:
        top[m.group(1)].add(m.group(2))
METHODS = {"needleChance"}  # functions defined with `function Prices.x`
for m in re.finditer(r"^function\s+Prices\.(\w+)", prices, re.M):
    top[m.group(1)] = None
for path, text in files.items():
    if path == prices_path:
        continue
    aliases = set(re.findall(r"local\s+(\w+)\s*=\s*require\([^\n]*Prices[\"')]", text))
    if not aliases:
        continue
    for n, raw in enumerate(text.split("\n")):
        line = strip_comments(raw)
        for alias in aliases:
            for m in re.finditer(rf"\b{alias}\.(\w+)(?:\.(\w+))?", line):
                key, subkey = m.group(1), m.group(2)
                if key not in top:
                    errors.append(f"{path}:{n + 1}: Prices.{key} does not exist")
                elif subkey and top[key] is not None and subkey not in top[key]:
                    errors.append(f"{path}:{n + 1}: Prices.{key}.{subkey} does not exist")

# 3. Require cycles --------------------------------------------------------------------------------------------------
by_name = {}
for path in files:
    base = os.path.splitext(os.path.basename(path))[0]
    if base.endswith(".server") or base.endswith(".client"):
        continue
    by_name.setdefault(base, []).append(path)


def resolve(expr, here):
    names = re.findall(r"[\"']?(\w+)[\"']?", expr)
    if not names:
        return None
    name = names[-1]
    cands = by_name.get(name, [])
    if len(cands) <= 1:
        return cands[0] if cands else None
    want_config = "Config" in expr
    for c in cands:
        if ("/Config/" in c) == want_config:
            return c
    return cands[0]


graph = {}
for path, text in files.items():
    deps = set()
    for m in re.finditer(r"^local\s+\w+\s*=\s*require\((.*)\)\s*(?:--.*)?$", text, re.M):
        target = resolve(m.group(1), path)
        if target and target != path:
            deps.add(target)
    graph[path] = deps

seen_cycles = set()
state = {}


def dfs(node, stack):
    state[node] = 1
    stack.append(node)
    for nxt in graph.get(node, ()):
        if state.get(nxt) == 1:
            cyc = stack[stack.index(nxt):]
            key = frozenset(cyc)
            if key not in seen_cycles:
                seen_cycles.add(key)
                errors.append("require cycle at load time: " + " -> ".join(os.path.basename(c) for c in cyc + [nxt]))
        elif not state.get(nxt):
            dfs(nxt, stack)
    stack.pop()
    state[node] = 2


for node in graph:
    if not state.get(node):
        dfs(node, [])

# 4. Props names in Sizes --------------------------------------------------------------------------------------------
props_cfg = files.get("src/shared/Config/Props.luau", "")
m = re.search(r"Sizes\s*=\s*\{(.*?)\n\t\}", props_cfg, re.S)
sizes = set(re.findall(r"^\s*(\w+)\s*=", m.group(1), re.M)) if m else set()
for path, text in files.items():
    for n, raw in enumerate(text.split("\n")):
        line = strip_comments(raw)
        for pm in re.finditer(r'(?:Props\.(?:make|has|find)|Skins\.dress)\(\s*"(\w+)"|\bprop\s*=\s*"(\w+)"', line):
            name = pm.group(1) or pm.group(2)
            if name not in sizes:
                warnings.append(f"{path}:{n + 1}: prop '{name}' is not in Config/Props.luau Sizes, so its mesh is never used")

# 5. Streaming safety (client) ---------------------------------------------------------------------------------------
for path, text in files.items():
    if not path.startswith("src/client"):
        continue
    for n, raw in enumerate(text.split("\n")):
        line = strip_comments(raw)
        for sm in re.finditer(r"\b(?:workspace|Workspace)\.([A-Z]\w*)", line):
            if sm.group(1) in ("CurrentCamera", "Gravity", "Terrain", "DistributedGameTime", "DescendantAdded",
                               "DescendantRemoving", "ChildAdded", "ChildRemoved"):
                continue
            warnings.append(f"{path}:{n + 1}: workspace.{sm.group(1)} read directly (use WaitForChild for streaming)")

# 6. One-time rewards are tagged for Bank's sold-total gate ------------------------------------------------------------
# Bank counts every Bank.earn toward "sold" (the trade gate) unless its note starts with a ONE_TIME prefix. So every earn
# note must be either a ONE_TIME prefix (one-time reward) or a known repeatable sale below; anything else must be classified.
SALE_NOTES = ("Hay shop", "Farm sale", "Sorted needles", "Hay buyer", "Order: ", "Contract: ", "Bounty: ", "While you were away", "SelfTest")
bank_src = next((t for p, t in files.items() if p.replace(os.sep, "/").endswith("server/Services/Bank.luau")), "")
om = re.search(r"local ONE_TIME = \{(.*?)\}", bank_src)
ONE_TIME = tuple(re.findall(r'"((?:[^"\\]|\\.)*)"', om.group(1))) if om else ()
if bank_src and not ONE_TIME:
    errors.append("Bank.luau: local ONE_TIME = { ... } prefix list not found (check_contracts rule 6 reads it)")


def call_args(text, start):
    """Top-level comma-separated arguments of the call whose '(' is at text[start]."""
    depth, args, cur, i, quote = 0, [], "", start, None
    while i < len(text):
        c = text[i]
        if quote:
            cur += c
            if c == "\\":
                cur += text[i + 1]
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'":
            quote = c
            cur += c
        elif c in "([{":
            depth += 1
            if depth > 1:
                cur += c
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                args.append(cur.strip())
                return args
            cur += c
        elif c == "," and depth == 1:
            args.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    return args


for path, text in files.items():
    norm = path.replace(os.sep, "/")
    if norm.endswith("server/Services/Bank.luau"):
        continue
    for m in re.finditer(r"\b(Bank\.earn|Machines\.pay)\(", text):
        n = text.count("\n", 0, m.start()) + 1
        code = strip_comments(text.split("\n")[n - 1])
        if code.find(m.group(1)) < 0 or re.search(r"\bfunction\s+" + re.escape(m.group(1)) + r"\(", code):
            continue
        args = call_args(text, m.end() - 1)
        idx = 2 if m.group(1) == "Bank.earn" else 3
        if len(args) <= idx:
            if m.group(1) == "Machines.pay":
                continue  # defaults to "Farm sale"
            errors.append(f"{path}:{n}: Bank.earn without a note (the sold-total gate can't classify it)")
            continue
        note = args[idx]
        if norm.endswith("server/Services/Machines.luau") and note == 'note or "Farm sale"':
            continue  # Machines.pay's own pass-through; its callers are checked
        lm = re.match(r'\(?\s*"((?:[^"\\]|\\.)*)"', note)
        if not lm:
            errors.append(f"{path}:{n}: {m.group(1)} note is not a string literal ({note}); start it with a literal so the gate can classify it")
            continue
        lit = lm.group(1)
        if any(lit.startswith(p) for p in ONE_TIME) or any(lit.startswith(p) for p in SALE_NOTES):
            continue
        errors.append(f'{path}:{n}: {m.group(1)} note "{lit}" is neither a Bank ONE_TIME prefix (one-time reward) nor a known sale; '
                      "add the prefix to Bank.luau ONE_TIME or to SALE_NOTES in tools/check_contracts.py")

for e in errors:
    print("ERROR  " + e)
for w in warnings:
    print("WARN   " + w)
print(f"\n{len(errors)} errors, {len(warnings)} warnings across {len(files)} files")
sys.exit(1 if errors else 0)
