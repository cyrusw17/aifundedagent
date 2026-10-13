#!/usr/bin/env bash
# Every offline check, in one go. Run from the repo root before pushing a branch:
#   tools/prepush.sh [path/to/luau] [path/to/luau-lsp] [path/to/globalTypes.d.luau]
# luau and luau-lsp come from the luau-lang and JohnnyMorganz releases; rojo must be on PATH (or set ROJO).
# Exit code 1 if any check fails. HEADLESS=1 also boots the whole server offline (tools/headless, about 3 minutes).
set -u
LUAU=${1:-luau}
LSP=${2:-luau-lsp}
DEFS=${3:-globalTypes.d.luau}
ROJO=${ROJO:-rojo}
TMP=$(mktemp -d)
fail=0
step() { echo "== $1"; }
bad() { echo "FAILED: $1"; fail=1; }

step "rojo build"
"$ROJO" build default.project.json -o "$TMP/place.rbxl" >/dev/null || bad "rojo build"
step "luau-lsp analyze"
if "$ROJO" sourcemap default.project.json -o "$TMP/sourcemap.json" >/dev/null && [ -f "$DEFS" ]; then
	out=$("$LSP" analyze --definitions="$DEFS" --sourcemap="$TMP/sourcemap.json" src 2>&1 | grep "^src/")
	[ -n "$out" ] && { echo "$out"; echo "$out" | grep -q "Error" && bad "luau-lsp"; }
else
	echo "skipped (no sourcemap or $DEFS)"
fi
step "contracts";     python3 tools/check_contracts.py | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || bad "check_contracts"
step "mapcheck";      python3 tools/mapcheck/run.py "$LUAU" | grep -E "^TOTAL|^blocking"; [ "${PIPESTATUS[0]}" = 0 ] || bad "mapcheck"
step "linecheck";     python3 tools/linecheck/run.py "$LUAU" | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || bad "linecheck"
step "line rates";    python3 tools/linecheck/rates.py "$LUAU" | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || bad "linecheck/rates.py"
step "line saves";    python3 tools/linecheck/saves.py "$LUAU" | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || bad "linecheck/saves.py"
step "junctions";     python3 tools/linecheck/junctions.py "$LUAU" | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || bad "linecheck/junctions.py"
step "templates";     python3 tools/linecheck/templates.py | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || bad "linecheck/templates.py"
step "rate limit";    "$LUAU" tests/rate_limit.luau | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || bad "tests/rate_limit.luau"
step "line math";     "$LUAU" tests/line_math.luau | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || bad "tests/line_math.luau"
step "away";          "$LUAU" tests/away.luau | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || bad "tests/away.luau"
step "pity";          "$LUAU" tests/pity.luau | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || bad "tests/pity.luau"
step "haycheck";      python3 tools/haycheck/run.py "$LUAU" --fuzz | grep -E "passed|FAIL" | tail -3; [ "${PIPESTATUS[0]}" = 0 ] || bad "haycheck"
step "line_sim";      python3 tools/line_sim.py --check >/dev/null || { python3 tools/line_sim.py --check | tail -6; bad "line_sim --check"; }

if [ "${HEADLESS:-0}" = 1 ]; then
	step "headless boot (about 3 min)"; python3 tools/headless/run.py "$LUAU" | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || bad "tools/headless"
fi

rm -rf "$TMP"
[ $fail = 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $fail
