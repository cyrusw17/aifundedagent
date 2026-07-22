#!/usr/bin/env python3
"""Download HistData M1 bars for the strategy universe."""

from __future__ import annotations

import os
from pathlib import Path

from histdata import download_hist_data as dl
from histdata.api import Platform as P, TimeFrame as TF

PAIRS = [
    "eurusd",
    "gbpusd",
    "audusd",
    "usdjpy",
    "xauusd",
    "usdcad",
    "eurjpy",
    "gbpjpy",
]
YEARS = ["2023", "2024", "2025"]


def main() -> None:
    root = Path(__file__).resolve().parents[1] / "data" / "raw"
    root.mkdir(parents=True, exist_ok=True)
    os.chdir(root)
    for pair in PAIRS:
        for year in YEARS:
            try:
                path = dl(
                    year=year,
                    month=None,
                    pair=pair,
                    platform=P.META_TRADER,
                    time_frame=TF.ONE_MINUTE,
                )
                print("OK", pair, year, path)
            except Exception as exc:  # noqa: BLE001
                print("FAIL", pair, year, exc)


if __name__ == "__main__":
    main()
