"""Avaliador deterministico de um backtest bruto concluido."""

from __future__ import annotations

import csv
import json
import statistics
from pathlib import Path
from typing import Any


EVALUATOR_VERSION = "candidate-evaluator-v2-monthly"


def _rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def _number(row: dict[str, str], name: str, default: float = 0.0) -> float:
    value = row.get(name)
    if value in (None, ""):
        return default
    return float(value)


def evaluate_strategy_run(gateway: Any, settings: Any, run_id: str, config: dict[str, Any]) -> None:
    run_root = Path(f"/srv/labs/projects/lab_automatizado/runs/control_plane/{run_id}")
    summary_rows = _rows(run_root / "run_summary.csv")
    monthly_rows = _rows(run_root / "monthly_metrics.csv")
    if len(summary_rows) != 1 or not monthly_rows:
        raise RuntimeError("Backtest sem run_summary.csv unico ou monthly_metrics.csv")

    monthly_series: dict[str, float] = {}
    for row in monthly_rows:
        month = (row.get("month") or "").strip()
        if not month:
            continue
        monthly_series[month[:10]] = _number(row, "gross_pnl_per_contract")
    if not monthly_series:
        raise RuntimeError("monthly_metrics.csv nao contem gross_pnl_per_contract")

    values = list(monthly_series.values())
    equity = 0.0
    peak = 0.0
    max_drawdown = 0.0
    for value in values:
        equity += value
        peak = max(peak, equity)
        max_drawdown = max(max_drawdown, peak - equity)

    summary = summary_rows[0]
    generation = int(config.get("generation", 0))
    variant_index = int(config.get("variant_index", 0))
    hypothesis_key = str(config.get("hypothesis_key") or "manual")
    candidate_key = f"{hypothesis_key}:g{generation}:v{variant_index:03d}:{run_id[:8]}"
    metrics: dict[str, Any] = {
        "asset": config.get("asset"),
        "search_stage": config.get("search_stage", "legacy"),
        "evaluation_start": config.get("evaluation_start"),
        "evaluation_end_exclusive": config.get("evaluation_end_exclusive"),
        "trades": int(_number(summary, "trades")),
        "gross_pnl_per_contract_total": _number(summary, "gross_pnl_per_contract_total"),
        "mean_monthly_pnl_per_contract": statistics.fmean(values),
        "median_monthly_pnl_per_contract": statistics.median(values),
        "positive_months": sum(1 for value in values if value > 0),
        "months": len(values),
        "monthly_equity_drawdown_per_contract": max_drawdown,
        "first_month": min(monthly_series),
        "last_month": max(monthly_series),
        "costs_applied": False,
        "slippage_applied": False,
        "holdout_accessed": False,
        "pricing_policy": "gross_only",
        "measurement_note": "drawdown computed on monthly per-contract equity; not an intraday risk gate",
    }
    candidate_artifact = run_root / "candidate_metrics.json"
    candidate_artifact.write_text(
        json.dumps(
            {
                "candidate_key": candidate_key,
                "evaluator_version": EVALUATOR_VERSION,
                "metrics": metrics,
                "monthly_series": monthly_series,
            },
            ensure_ascii=True,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    gateway.register_candidate(
        run_id=run_id,
        candidate_key=candidate_key,
        asset=str(config["asset"]),
        hypothesis_id=str(config["hypothesis_id"]) if config.get("hypothesis_id") else None,
        generation=generation,
        variant_index=variant_index,
        metrics=metrics,
        monthly_series=monthly_series,
        artifact_uri=f"vps://{candidate_artifact}",
        evaluator_version=EVALUATOR_VERSION,
    )
