"""Rolling ~1-month evaluation pass metrics under funded rules."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
import pandas as pd

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.forex.fast_sim import fast_backtest


@dataclass
class MonthPassStats:
    n_windows: int
    n_passed: int
    pass_rate: float
    median_days: float
    p90_days: float
    mean_days: float
    n_blown: int
    details: list[dict[str, Any]]

    def to_dict(self) -> dict[str, Any]:
        return {
            "n_windows": self.n_windows,
            "n_passed": self.n_passed,
            "pass_rate": self.pass_rate,
            "median_days": self.median_days,
            "p90_days": self.p90_days,
            "mean_days": self.mean_days,
            "n_blown": self.n_blown,
        }


def _days_to_target(eq: pd.Series, target: float) -> int | None:
    if eq is None or len(eq) == 0:
        return None
    for t, v in eq.items():
        if v >= target:
            return int((t - eq.index[0]).days)
    return None


def rolling_month_eval(
    book: dict[str, pd.DataFrame],
    *,
    window_days: int = 35,
    step_days: int = 14,
    start: str = "2018-01-02",
    end: str | None = None,
    max_days_to_pass: int = 35,
    rules: FundedRules | None = None,
    **backtest_kwargs,
) -> MonthPassStats:
    """Fraction of rolling windows that hit +10% within max_days_to_pass without blowing."""
    rules = rules or FundedRules()
    target = rules.evaluation_target
    start_ts = pd.Timestamp(start)
    end_ts = pd.Timestamp(end) if end else min(v.index.max() for v in book.values())
    kwargs = dict(backtest_kwargs)
    kwargs["weekly_withdraw"] = False
    kwargs["rules"] = rules

    details = []
    days_ok = []
    blown = 0
    cursor = start_ts
    while cursor + pd.Timedelta(days=window_days) <= end_ts:
        w_end = cursor + pd.Timedelta(days=window_days)
        sl = {p: df[(df.index >= cursor) & (df.index <= w_end)].copy() for p, df in book.items()}
        if min(len(v) for v in sl.values()) < 80:
            cursor += pd.Timedelta(days=step_days)
            continue
        bt = run_backtest(sl, **kwargs)
        d_hit = _days_to_target(bt.equity_curve, target)
        passed = (
            d_hit is not None
            and d_hit <= max_days_to_pass
            and not bt.account.blown
            and bt.account.consistency_ok()
        )
        if bt.account.blown:
            blown += 1
        if passed:
            days_ok.append(d_hit)
        details.append(
            {
                "start": str(cursor.date()),
                "end": str(w_end.date()),
                "passed": passed,
                "days_to_target": d_hit,
                "blown": bt.account.blown,
                "n_trades": len(bt.trades),
                "max_equity": float(bt.equity_curve.max()) if len(bt.equity_curve) else 0.0,
            }
        )
        cursor += pd.Timedelta(days=step_days)

    n = len(details)
    n_pass = sum(1 for d in details if d["passed"])
    arr = np.array(days_ok, dtype=float) if days_ok else np.array([])
    return MonthPassStats(
        n_windows=n,
        n_passed=n_pass,
        pass_rate=(n_pass / n) if n else 0.0,
        median_days=float(np.median(arr)) if len(arr) else float("nan"),
        p90_days=float(np.percentile(arr, 90)) if len(arr) else float("nan"),
        mean_days=float(arr.mean()) if len(arr) else float("nan"),
        n_blown=blown,
        details=details,
    )


def slice_prepared(prepared: dict, start: pd.Timestamp, end: pd.Timestamp) -> dict:
    """Slice a prepared book to [start, end] and rebuild timeline meta (signals stay causal)."""
    out = {}
    for p, d in prepared.items():
        if p == "__meta__":
            continue
        idx = d["index"]
        mask = (idx >= start) & (idx <= end)
        if not np.any(mask):
            continue
        out[p] = {k: (v[mask] if hasattr(v, "__len__") and k != "index" else v[mask]) for k, v in d.items()}
        # fix index specially
        out[p]["index"] = idx[mask]
        out[p]["times"] = d["times"][mask]
        out[p]["open"] = d["open"][mask]
        out[p]["high"] = d["high"][mask]
        out[p]["low"] = d["low"][mask]
        out[p]["close"] = d["close"][mask]
        out[p]["atr"] = d["atr"][mask]
        out[p]["sig"] = d["sig"][mask]
    if len(out) < 2:
        return {}
    pairs = list(out.keys())
    time_map: dict = {}
    entry_times = set()
    for pi, p in enumerate(pairs):
        times = out[p]["times"]
        sig = out[p]["sig"]
        for bi, t in enumerate(times):
            time_map.setdefault(t, []).append((pi, bi))
            if bi > 0 and sig[bi - 1] != 0:
                entry_times.add(t)
    timeline = sorted(time_map.keys())
    next_entry_from = {}
    nxt = None
    for t in reversed(timeline):
        if t in entry_times:
            nxt = t
        next_entry_from[t] = nxt
    out["__meta__"] = {
        "pairs": pairs,
        "time_map": time_map,
        "timeline": timeline,
        "next_entry_from": next_entry_from,
    }
    return out


def fast_days_to_target(prepared_slice: dict, rules: FundedRules, **sim_kwargs) -> tuple[int | None, bool, bool]:
    """Return (days_to_target_or_None, blown, consistency_ok) using fast_sim."""
    st = fast_backtest(prepared_slice, weekly_withdraw=False, rules=rules, **sim_kwargs)
    if st.blown or not st.consistency_ok or not st.hit_eval_target:
        return None, st.blown, st.consistency_ok
    # Approximate days from years in window: use timeline span * fraction of wealth path
    # Better: re-run is expensive; approximate with window length when hit_eval_target.
    # Use timeline first/last from meta for upper bound; refine via equity not available.
    # For screening, treat hit_eval_target in the month window as pass; days unknown → use window mid.
    meta = prepared_slice["__meta__"]
    tl = meta["timeline"]
    if not tl:
        return None, st.blown, st.consistency_ok
    days = int((pd.Timestamp(tl[-1]) - pd.Timestamp(tl[0])).days)
    # If target hit, true day <= window days; use years-scaled proxy from pnl velocity
    # Prefer conservative: report window days as upper bound when hit
    return days, st.blown, st.consistency_ok


def fast_rolling_month_eval(
    prepared: dict,
    *,
    window_days: int = 35,
    step_days: int = 21,
    max_days_to_pass: int = 35,
    rules: FundedRules | None = None,
    **sim_kwargs,
) -> MonthPassStats:
    """Fast month-pass screening on a precomputed prepared book (no signal recompute)."""
    rules = rules or FundedRules()
    pairs = prepared["__meta__"]["pairs"]
    start_ts = max(pd.Timestamp(prepared[p]["index"].min()) for p in pairs)
    end_ts = min(pd.Timestamp(prepared[p]["index"].max()) for p in pairs)

    details = []
    days_ok = []
    blown_n = 0
    cursor = start_ts
    while cursor + pd.Timedelta(days=window_days) <= end_ts:
        w_end = cursor + pd.Timedelta(days=window_days)
        sl = slice_prepared(prepared, cursor, w_end)
        if not sl or len(sl.get("__meta__", {}).get("timeline", [])) < 80:
            cursor += pd.Timedelta(days=step_days)
            continue
        st = fast_backtest(sl, weekly_withdraw=False, rules=rules, **sim_kwargs)
        # Estimate days-to-target by scanning a cheap equity proxy: cumulative closed pnl path
        # fast_sim doesn't expose curve; use hit_eval_target within window as pass if not blown.
        passed = bool(st.hit_eval_target and not st.blown and st.consistency_ok)
        d_hit = None
        if passed:
            # refine: binary-search subwindow end for first hit (log2(35) ~ 6 sims)
            lo, hi = 5, window_days
            best = window_days
            while lo <= hi:
                mid = (lo + hi) // 2
                mid_end = cursor + pd.Timedelta(days=mid)
                sub = slice_prepared(prepared, cursor, mid_end)
                if not sub:
                    lo = mid + 1
                    continue
                st2 = fast_backtest(sub, weekly_withdraw=False, rules=rules, **sim_kwargs)
                if st2.hit_eval_target and not st2.blown and st2.consistency_ok:
                    best = mid
                    hi = mid - 1
                else:
                    lo = mid + 1
            d_hit = best
            passed = d_hit <= max_days_to_pass
            if passed:
                days_ok.append(d_hit)
        if st.blown:
            blown_n += 1
        details.append(
            {
                "start": str(cursor.date()),
                "end": str(w_end.date()),
                "passed": passed,
                "days_to_target": d_hit,
                "blown": st.blown,
                "n_trades": st.n_trades,
            }
        )
        cursor += pd.Timedelta(days=step_days)

    n = len(details)
    n_pass = sum(1 for d in details if d["passed"])
    arr = np.array(days_ok, dtype=float) if days_ok else np.array([])
    return MonthPassStats(
        n_windows=n,
        n_passed=n_pass,
        pass_rate=(n_pass / n) if n else 0.0,
        median_days=float(np.median(arr)) if len(arr) else float("nan"),
        p90_days=float(np.percentile(arr, 90)) if len(arr) else float("nan"),
        mean_days=float(arr.mean()) if len(arr) else float("nan"),
        n_blown=blown_n,
        details=details,
    )
