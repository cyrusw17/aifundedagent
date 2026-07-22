#!/usr/bin/env python3
"""Quick probe: commodity ideas hitting 10%+ in both 2024 and 2025."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.config import PARAMS
from strategy.data_loader import RESEARCH_MAX_END, load_universe
from strategy.run_commodity_search import YEARS, eval_years, is_winner, make_params
from strategy.strategies.commodity_models import CmdCfg, make_cmd_fn


def main() -> None:
    u = load_universe(PARAMS.commodity_pairs, max_end=RESEARCH_MAX_END)
    ug = {k: u[k] for k in ("XAUUSD",)}
    ideas = []
    for tf in ("1h", "4h"):
        for don in (15, 20, 35):
            for rr in (3.5, 5.0):
                for lo in (True, False):
                    ideas.append(
                        CmdCfg(
                            tag=f"D{tf}_n{don}_rr{rr}_{'L' if lo else 'B'}",
                            model="don",
                            tf=tf,
                            don_len=don,
                            rr=rr,
                            long_only=lo,
                            max_hold_days=3 if tf == "1h" else 5,
                            session_only=True,
                            stop_atr=2.0,
                        )
                    )
        for ef, es in ((12, 48), (8, 21)):
            for rr in (3.5, 5.0):
                ideas.append(
                    CmdCfg(
                        tag=f"E{tf}_{ef}_{es}_rr{rr}_L",
                        model="ema",
                        tf=tf,
                        ema_fast=ef,
                        ema_slow=es,
                        rr=rr,
                        long_only=True,
                        max_hold_days=3 if tf == "1h" else 5,
                        session_only=True,
                        stop_atr=2.0,
                    )
                )
    hits = []
    for cfg in ideas:
        fn = make_cmd_fn(cfg)
        for uni, scope in ((ug, "XAU"), (u, "CMD3")):
            for risk in (0.01, 0.015, 0.02, 0.025):
                ev = eval_years(uni, fn, make_params(risk, cfg.max_hold_days))
                y = {yy: ev["years"][yy]["ann"] for yy in YEARS}
                ok = is_winner(ev)
                if y["2024"] >= 10 and y["2025"] >= 10:
                    print(
                        f"{'WIN' if ok else 'near'} {scope} {cfg.tag} r={risk*100:.1f}% {y} pf={ev['w2425']['pf']}",
                        flush=True,
                    )
                    if ok:
                        hits.append((cfg.tag, scope, risk, y, ev["w2425"]["pf"]))
    print(f"HITS {len(hits)}", flush=True)
    for h in hits:
        print(h, flush=True)


if __name__ == "__main__":
    main()
