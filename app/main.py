"""FastAPI server for the MCPT Trading Strategy Tester."""

from __future__ import annotations

import asyncio
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from mcpt.data import get_default_dataset, load_csv, slice_years
from mcpt.pipeline import run_full_pipeline
from mcpt.strategies import STRATEGY_REGISTRY

STATIC_DIR = Path(__file__).resolve().parent / "static"
UPLOAD_DIR = Path(__file__).resolve().parent.parent / "data" / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(
    title="MCPT Lab",
    description="Monte Carlo Permutation Test trading strategy tester",
    version="1.0.0",
)

executor = ThreadPoolExecutor(max_workers=2)
_jobs: dict[str, dict[str, Any]] = {}


class RunRequest(BaseModel):
    strategy: str = Field(default="donchian", description="donchian | ma_crossover | tree")
    source: str = Field(default="synthetic", description="synthetic | yfinance | cache")
    symbol: str = "BTC-USD"
    interval: str = "1h"
    start: str = "2018-01-01"
    end: str | None = None
    start_year: int | None = None
    end_year: int | None = None
    n_insample_perms: int = Field(default=80, ge=10, le=2000)
    n_walkforward_perms: int = Field(default=40, ge=10, le=500)
    train_years: int = Field(default=3, ge=1, le=8)
    lookback_min: int = Field(default=12, ge=5, le=100)
    lookback_max: int = Field(default=72, ge=20, le=200)
    run_walkforward: bool = True
    seed: int = 42
    upload_id: str | None = None


@app.get("/")
async def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/strategies")
async def list_strategies():
    return {
        key: {
            "id": key,
            "name": meta["name"],
            "description": meta["description"],
            "supports_walkforward": meta["walkforward"] is not None,
        }
        for key, meta in STRATEGY_REGISTRY.items()
    }


@app.get("/api/health")
async def health():
    return {"ok": True, "version": "1.0.0"}


@app.post("/api/upload")
async def upload_csv(file: UploadFile = File(...)):
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(400, "Upload a CSV with OHLC columns")
    upload_id = uuid.uuid4().hex[:12]
    path = UPLOAD_DIR / f"{upload_id}.csv"
    content = await file.read()
    path.write_bytes(content)
    try:
        df = load_csv(path)
    except Exception as exc:
        path.unlink(missing_ok=True)
        raise HTTPException(400, f"Invalid CSV: {exc}") from exc
    return {
        "upload_id": upload_id,
        "n_bars": len(df),
        "start": str(df.index[0]),
        "end": str(df.index[-1]),
    }


def _execute_run(job_id: str, req: RunRequest) -> None:
    _jobs[job_id]["status"] = "running"
    try:
        if req.upload_id:
            path = UPLOAD_DIR / f"{req.upload_id}.csv"
            if not path.exists():
                raise FileNotFoundError("Upload not found")
            df = load_csv(path)
            source_label = f"upload:{req.upload_id}"
        else:
            df, source_label = get_default_dataset(
                source=req.source,
                symbol=req.symbol,
                start=req.start,
                end=req.end,
                interval=req.interval,
            )

        if req.start_year is not None and req.end_year is not None:
            df = slice_years(df, req.start_year, req.end_year)

        if len(df) < 500:
            raise ValueError(f"Not enough bars after filtering ({len(df)})")

        # Infer bars/day from median spacing
        if len(df) > 2:
            deltas = df.index.to_series().diff().dropna().dt.total_seconds()
            median_sec = float(deltas.median())
            bars_per_day = max(1, int(round(86400 / median_sec))) if median_sec > 0 else 24
        else:
            bars_per_day = 24

        # Cap lookback_max for speed on large grids
        lookback_max = min(req.lookback_max, req.lookback_min + 60)

        result = run_full_pipeline(
            df,
            strategy=req.strategy,
            data_source=source_label,
            n_insample_perms=req.n_insample_perms,
            n_walkforward_perms=req.n_walkforward_perms,
            train_years=req.train_years,
            bars_per_day=bars_per_day,
            lookback_min=req.lookback_min,
            lookback_max=lookback_max,
            run_walkforward=req.run_walkforward and req.strategy == "donchian",
            seed=req.seed,
        )
        payload = result.to_dict()
        # Ensure nested Mcpt dicts are plain
        _jobs[job_id]["status"] = "done"
        _jobs[job_id]["result"] = payload
    except Exception as exc:
        _jobs[job_id]["status"] = "error"
        _jobs[job_id]["error"] = str(exc)


@app.post("/api/run")
async def start_run(req: RunRequest):
    if req.strategy not in STRATEGY_REGISTRY:
        raise HTTPException(400, f"Unknown strategy: {req.strategy}")
    if req.lookback_max <= req.lookback_min:
        raise HTTPException(400, "lookback_max must be > lookback_min")

    job_id = uuid.uuid4().hex[:12]
    _jobs[job_id] = {"status": "queued", "result": None, "error": None}
    loop = asyncio.get_event_loop()
    loop.run_in_executor(executor, _execute_run, job_id, req)
    return {"job_id": job_id}


@app.get("/api/jobs/{job_id}")
async def get_job(job_id: str):
    job = _jobs.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    return job


app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
