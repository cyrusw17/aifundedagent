/* MCPT Lab frontend */

const $ = (sel) => document.querySelector(sel);

function drawHeroCanvas() {
  const canvas = $("#hero-canvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;

  const real = [];
  const perm = [];
  let y1 = h * 0.55;
  let y2 = h * 0.55;
  for (let i = 0; i < 120; i++) {
    y1 += Math.sin(i / 9) * 6 + (Math.random() - 0.45) * 8;
    y2 += (Math.random() - 0.5) * 14;
    real.push(y1);
    perm.push(y2);
  }

  let t = 0;
  function frame() {
    t += 0.01;
    ctx.clearRect(0, 0, w, h);

    // baseline grid ticks
    ctx.strokeStyle = "rgba(232,226,212,0.06)";
    ctx.lineWidth = 1;
    for (let x = 40; x < w; x += 40) {
      ctx.beginPath();
      ctx.moveTo(x, 20);
      ctx.lineTo(x, h - 20);
      ctx.stroke();
    }

    const drawPath = (series, color, phase) => {
      ctx.beginPath();
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      series.forEach((y, i) => {
        const x = (i / (series.length - 1)) * (w - 48) + 24;
        const yy = y + Math.sin(t * 2 + i * 0.08 + phase) * 3;
        if (i === 0) ctx.moveTo(x, yy);
        else ctx.lineTo(x, yy);
      });
      ctx.stroke();
    };

    drawPath(perm, "rgba(157,163,150,0.55)", 1.2);
    drawPath(real, "rgba(212,161,90,0.95)", 0);

    // real marker
    ctx.fillStyle = "rgba(240,194,122,0.9)";
    ctx.font = "12px IBM Plex Mono, monospace";
    ctx.fillText("REAL PATH", 28, 36);
    ctx.fillStyle = "rgba(157,163,150,0.8)";
    ctx.fillText("PERMUTATIONS", 28, 54);

    requestAnimationFrame(frame);
  }
  frame();
}

function drawLineChart(canvas, series, color = "#d4a15a") {
  const ctx = canvas.getContext("2d");
  const dpr = window.devicePixelRatio || 1;
  const cssW = canvas.clientWidth || 400;
  const cssH = canvas.height;
  canvas.width = cssW * dpr;
  canvas.height = cssH * dpr;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  ctx.clearRect(0, 0, cssW, cssH);
  if (!series || series.length < 2) {
    ctx.fillStyle = "#9aa396";
    ctx.font = "13px Outfit, sans-serif";
    ctx.fillText("No series", 12, 24);
    return;
  }

  const vals = series.map((p) => p.v);
  const min = Math.min(...vals);
  const max = Math.max(...vals);
  const pad = 16;
  const span = max - min || 1;

  ctx.strokeStyle = "rgba(232,226,212,0.08)";
  ctx.beginPath();
  ctx.moveTo(pad, cssH / 2);
  ctx.lineTo(cssW - pad, cssH / 2);
  ctx.stroke();

  ctx.beginPath();
  ctx.strokeStyle = color;
  ctx.lineWidth = 2;
  series.forEach((p, i) => {
    const x = pad + (i / (series.length - 1)) * (cssW - pad * 2);
    const y = cssH - pad - ((p.v - min) / span) * (cssH - pad * 2);
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.stroke();
}

function drawHistogram(canvas, scores, realScore, color = "#3d8b7a") {
  const ctx = canvas.getContext("2d");
  const dpr = window.devicePixelRatio || 1;
  const cssW = canvas.clientWidth || 400;
  const cssH = canvas.height;
  canvas.width = cssW * dpr;
  canvas.height = cssH * dpr;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, cssW, cssH);

  if (!scores || !scores.length) {
    ctx.fillStyle = "#9aa396";
    ctx.font = "13px Outfit, sans-serif";
    ctx.fillText("No permutation scores", 12, 24);
    return;
  }

  const all = scores.concat([realScore]);
  const min = Math.min(...all);
  const max = Math.max(...all);
  const bins = 24;
  const width = (max - min) || 1;
  const counts = new Array(bins).fill(0);
  scores.forEach((s) => {
    let idx = Math.floor(((s - min) / width) * bins);
    if (idx >= bins) idx = bins - 1;
    if (idx < 0) idx = 0;
    counts[idx] += 1;
  });
  const maxC = Math.max(...counts, 1);
  const pad = 16;
  const barW = (cssW - pad * 2) / bins;

  counts.forEach((c, i) => {
    const bh = (c / maxC) * (cssH - pad * 2);
    const x = pad + i * barW;
    const y = cssH - pad - bh;
    ctx.fillStyle = color;
    ctx.globalAlpha = 0.75;
    ctx.fillRect(x + 1, y, Math.max(1, barW - 2), bh);
  });
  ctx.globalAlpha = 1;

  // real score line
  const rx = pad + ((realScore - min) / width) * (cssW - pad * 2);
  ctx.strokeStyle = "#f0c27a";
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(rx, pad);
  ctx.lineTo(rx, cssH - pad);
  ctx.stroke();

  ctx.fillStyle = "#f0c27a";
  ctx.font = "11px IBM Plex Mono, monospace";
  ctx.fillText(`REAL ${realScore.toFixed(3)}`, Math.min(rx + 6, cssW - 90), pad + 12);
}

function fmt(n, digits = 3) {
  if (n === null || n === undefined || Number.isNaN(n)) return "—";
  if (!Number.isFinite(n)) return "∞";
  return Number(n).toFixed(digits);
}

function renderResults(result) {
  const box = $("#results");
  box.classList.remove("hidden");

  const verdict = $("#verdict");
  verdict.textContent = result.verdict || "";
  const isFail =
    (result.insample_mcpt && !result.insample_mcpt.passed) ||
    (result.walkforward_mcpt && !result.walkforward_mcpt.passed);
  const isPass =
    result.insample_mcpt &&
    result.insample_mcpt.passed &&
    (!result.walkforward_mcpt || result.walkforward_mcpt.passed);
  verdict.classList.remove("pass", "fail");
  if (isPass) verdict.classList.add("pass");
  else if (isFail) verdict.classList.add("fail");

  const metrics = [];
  metrics.push({
    label: "In-sample PF",
    value: fmt(result.insample?.profit_factor),
  });
  if (result.insample_mcpt) {
    metrics.push({
      label: "In-sample p-value",
      value: fmt(result.insample_mcpt.p_value, 4),
      cls: result.insample_mcpt.passed ? "ok" : "bad",
    });
  }
  if (result.walkforward) {
    metrics.push({
      label: "Walk-forward PF",
      value: fmt(result.walkforward.profit_factor),
    });
  }
  if (result.walkforward_mcpt) {
    metrics.push({
      label: "WF p-value",
      value: fmt(result.walkforward_mcpt.p_value, 4),
      cls: result.walkforward_mcpt.passed ? "ok" : "bad",
    });
  }
  metrics.push({
    label: "Bars",
    value: String(result.n_bars),
  });
  metrics.push({
    label: "Param",
    value:
      typeof result.insample?.param === "object"
        ? JSON.stringify(result.insample.param)
        : String(result.insample?.param ?? "—"),
  });

  $("#metric-row").innerHTML = metrics
    .slice(0, 4)
    .map(
      (m) => `
      <div class="metric">
        <div class="label">${m.label}</div>
        <div class="value ${m.cls || ""}">${m.value}</div>
      </div>`
    )
    .join("");

  drawLineChart($("#equity-chart"), result.insample?.equity || [], "#d4a15a");
  drawHistogram(
    $("#hist-chart"),
    result.insample_mcpt?.perm_scores_sample || [],
    result.insample_mcpt?.real_score ?? 0,
    "#3d8b7a"
  );

  const hasWf = Boolean(result.walkforward);
  $("#wf-equity-panel").classList.toggle("hidden", !hasWf);
  $("#wf-hist-panel").classList.toggle("hidden", !result.walkforward_mcpt);
  if (hasWf) {
    drawLineChart($("#wf-equity-chart"), result.walkforward.equity || [], "#5cb8a2");
  }
  if (result.walkforward_mcpt) {
    drawHistogram(
      $("#wf-hist-chart"),
      result.walkforward_mcpt.perm_scores_sample || [],
      result.walkforward_mcpt.real_score ?? 0,
      "#c45c4a"
    );
  }
}

async function pollJob(jobId) {
  const status = $("#status-line");
  for (;;) {
    const res = await fetch(`/api/jobs/${jobId}`);
    if (!res.ok) throw new Error("Job lookup failed");
    const job = await res.json();
    status.textContent = `Status: ${job.status}…`;
    if (job.status === "done") return job.result;
    if (job.status === "error") throw new Error(job.error || "Run failed");
    await new Promise((r) => setTimeout(r, 800));
  }
}

async function onSubmit(e) {
  e.preventDefault();
  const btn = $("#run-btn");
  const status = $("#status-line");
  btn.disabled = true;
  status.textContent = "Queueing run…";

  const body = {
    strategy: $("#strategy").value,
    source: $("#source").value,
    symbol: $("#symbol").value.trim() || "BTC-USD",
    n_insample_perms: Number($("#n_insample_perms").value),
    n_walkforward_perms: Number($("#n_walkforward_perms").value),
    train_years: Number($("#train_years").value),
    run_walkforward: $("#run_walkforward").checked,
    lookback_min: 12,
    lookback_max: 60,
    seed: 42,
  };

  try {
    const res = await fetch("/api/run", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.detail || "Failed to start run");
    }
    const { job_id } = await res.json();
    status.textContent = `Running job ${job_id}…`;
    const result = await pollJob(job_id);
    status.textContent = "Done.";
    renderResults(result);
  } catch (err) {
    status.textContent = err.message || String(err);
  } finally {
    btn.disabled = false;
  }
}

document.addEventListener("DOMContentLoaded", () => {
  drawHeroCanvas();
  $("#run-form").addEventListener("submit", onSubmit);
});
