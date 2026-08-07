#!/usr/bin/env python3
"""Run one strategy backtest month at a time and merge its artifacts."""

from __future__ import annotations

import csv
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable


PROJECT_ROOT = Path("/srv/labs/projects/lab_automatizado")
EXECUTOR_ROOT = PROJECT_ROOT / "executor"
RUNS_ROOT = PROJECT_ROOT / "runs" / "control_plane"


def parse_timestamp(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed


def format_timestamp(value: datetime) -> str:
    return value.strftime("%Y-%m-%dT%H:%M:%S")


def next_month(value: datetime) -> datetime:
    if value.month == 12:
        return value.replace(year=value.year + 1, month=1, day=1)
    return value.replace(month=value.month + 1, day=1)


def month_chunks(start: datetime, end: datetime) -> Iterable[tuple[str, datetime, datetime]]:
    cursor = start.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    while cursor < end:
        boundary = next_month(cursor)
        chunk_start = max(start, cursor)
        chunk_end = min(end, boundary)
        if chunk_start < chunk_end:
            yield cursor.strftime("%Y-%m"), chunk_start, chunk_end
        cursor = boundary


def read_single_csv(path: Path) -> dict[str, str]:
    with path.open("r", newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise RuntimeError(f"Esperava uma linha em {path}, encontrei {len(rows)}.")
    return rows[0]


def merge_csv(paths: list[Path], destination: Path) -> None:
    header: list[str] | None = None
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("w", newline="", encoding="utf-8") as output:
        writer = csv.writer(output)
        for path in paths:
            with path.open("r", newline="", encoding="utf-8") as source:
                reader = csv.reader(source)
                current_header = next(reader, None)
                if current_header is None:
                    continue
                if header is None:
                    header = current_header
                    writer.writerow(header)
                elif current_header != header:
                    raise RuntimeError(f"Cabecalhos divergentes entre artefatos: {path}")
                for row in reader:
                    writer.writerow(row)
        if header is None:
            raise RuntimeError(f"Nenhum CSV disponivel para consolidar em {destination}.")


def merge_summary(paths: list[Path], destination: Path, config: dict) -> None:
    rows: list[dict[str, str]] = []
    fieldnames: list[str] | None = None
    for path in paths:
        with path.open("r", newline="", encoding="utf-8") as source:
            reader = csv.DictReader(source)
            if fieldnames is None:
                fieldnames = reader.fieldnames
            elif reader.fieldnames != fieldnames:
                raise RuntimeError(f"Cabecalhos divergentes no resumo: {path}")
            rows.extend(reader)

    if not fieldnames:
        raise RuntimeError("Os resumos mensais nao possuem cabecalho.")

    def number(name: str) -> float:
        return sum(float(row[name]) for row in rows if row.get(name) not in (None, ""))

    trades = int(number("trades"))
    gross_total = number("gross_pnl_per_contract_total")
    trading_days = int(number("trading_days"))
    first_sessions = [row["first_session"] for row in rows if row.get("first_session")]
    last_sessions = [row["last_session"] for row in rows if row.get("last_session")]
    summary = {name: "" for name in fieldnames}
    for name in ("executor_id", "executor_version", "asset", "phase", "operational_scope"):
        summary[name] = str(config.get("executor_id", "")) if name == "executor_id" else summary[name]
    if rows:
        for name in ("executor_version", "asset", "phase", "operational_scope"):
            summary[name] = rows[0].get(name, "")
    summary.update(
        {
            "trades": str(trades),
            "gross_pnl_per_contract_total": str(gross_total),
            "mean_trade_gross_pnl_per_contract": str(gross_total / trades) if trades else "",
            "trading_days": str(trading_days),
            "first_session": min(first_sessions) if first_sessions else "",
            "last_session": max(last_sessions) if last_sessions else "",
            "holdout_accessed": "False",
            "costs_applied": "False",
            "slippage_applied": "False",
        }
    )
    with destination.open("w", newline="", encoding="utf-8") as output:
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerow(summary)


def run_compose(
    service: str,
    run_root: Path,
    tmp_root: Path,
    config_file: Path,
    thresholds_file: Path | None,
    data_root: Path,
) -> None:
    run_root.mkdir(parents=True, exist_ok=True)
    tmp_root.mkdir(parents=True, exist_ok=True)
    env = {
        "DATA_ROOT": str(data_root),
        "RUN_ROOT": str(run_root),
        "TMP_ROOT": str(tmp_root),
        "CONFIG_FILE": str(config_file),
    }
    if thresholds_file is not None:
        env["THRESHOLDS_FILE"] = str(thresholds_file)
    command = [
        "/usr/bin/docker",
        "compose",
        "-f",
        str(EXECUTOR_ROOT / "compose.yaml"),
        "run",
        "--rm",
        service,
    ]
    completed = subprocess.run(command, cwd=EXECUTOR_ROOT, env={**__import__("os").environ, **env}, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"Servico {service} retornou {completed.returncode}.")


def stage_chunk_input(asset_root: Path, chunk_root: Path, data_start: datetime, data_end: datetime) -> Path:
    """Expose only the current and overlapping next month through hard links."""
    input_root = chunk_root / "input"
    if input_root.exists():
        shutil.rmtree(input_root)
    input_root.mkdir(parents=True)

    cursor = data_start.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    while cursor < data_end:
        source_month = asset_root / f"ano={cursor.year}" / f"mes={cursor.month:02d}"
        if source_month.is_dir():
            target_month = input_root / f"ano={cursor.year}_mes={cursor.month:02d}"
            target_month.mkdir(parents=True)
            for source_file in source_month.rglob("*.parquet"):
                os.link(source_file, target_month / source_file.name)
        cursor = next_month(cursor)
    return input_root


def main() -> int:
    if len(sys.argv) != 2:
        print("Uso: strategy_monthly_runner.py RUN_ID", file=sys.stderr)
        return 2

    run_id = sys.argv[1]
    if not run_id or any(char not in "0123456789abcdef-" for char in run_id):
        print("run_id invalido", file=sys.stderr)
        return 2

    run_root = RUNS_ROOT / run_id
    config_path = run_root / "config.json"
    if not config_path.is_file():
        print("config.json ausente", file=sys.stderr)
        return 2
    config = json.loads(config_path.read_text(encoding="utf-8"))
    global_start = parse_timestamp(config["evaluation_start"])
    global_end = parse_timestamp(config["evaluation_end_exclusive"])
    time_stop_minutes = int(config["execution_spec"]["exit"]["time_stop_minutes"])
    asset_data_root = Path("/srv/labs/datasets/raw/full") / Path(
        f"ticker={str(config['asset']).lower()}"
    )
    if not asset_data_root.is_dir():
        raise RuntimeError(f"Dataset particionado do ativo ausente: {asset_data_root}")

    for name in ("trades.csv", "monthly_metrics.csv", "run_summary.csv", "thresholds.csv", "chunks_manifest.json"):
        target = run_root / name
        if target.exists():
            target.unlink()

    preparation_root = run_root / "preparation"
    preparation_tmp = preparation_root / "tmp"
    thresholds_source = preparation_root / "thresholds.csv"
    thresholds: dict[str, str] | None = None
    if thresholds_source.is_file():
        try:
            cached = read_single_csv(thresholds_source)
            numeric_fields = ("aggression_abs_threshold", "absorption_move_abs_threshold")
            if cached.get("asset") == config.get("asset") and all(float(cached[field]) >= 0 for field in numeric_fields):
                thresholds = cached
                print("Reutilizando thresholds do preparo anterior.")
        except (OSError, RuntimeError, ValueError, KeyError):
            thresholds = None

    if thresholds is None:
        if preparation_root.exists():
            shutil.rmtree(preparation_root)
        preparation_root.mkdir(parents=True)
        preparation_config = preparation_root / "config.json"
        preparation_config.write_text(json.dumps(config, ensure_ascii=True, sort_keys=True) + "\n", encoding="utf-8")
        run_compose(
            "strategy-prepare",
            preparation_root,
            preparation_tmp,
            preparation_config,
            None,
            asset_data_root,
        )
        thresholds = read_single_csv(thresholds_source)
    shutil.copy2(thresholds_source, run_root / "thresholds.csv")

    chunks_root = run_root / "chunks"
    if chunks_root.exists():
        shutil.rmtree(chunks_root)
    chunks_root.mkdir(parents=True)

    trade_files: list[Path] = []
    metric_files: list[Path] = []
    summary_files: list[Path] = []
    manifest: list[dict[str, str]] = []
    for label, chunk_start, chunk_end in month_chunks(global_start, global_end):
        chunk_root = chunks_root / label
        chunk_tmp = chunk_root / "tmp"
        chunk_root.mkdir(parents=True)
        chunk_config = dict(config)
        chunk_config.update(
            {
                "signal_start_exclusive": format_timestamp(chunk_start),
                "signal_end_exclusive": format_timestamp(chunk_end),
                "data_start_exclusive": format_timestamp(chunk_start),
                "data_end_exclusive": format_timestamp(min(global_end, chunk_end + timedelta(minutes=time_stop_minutes))),
                "thresholds_file": "/runner/thresholds.csv",
            }
        )
        chunk_config_path = chunk_root / "config.json"
        chunk_config_path.write_text(json.dumps(chunk_config, ensure_ascii=True, sort_keys=True) + "\n", encoding="utf-8")
        data_start = parse_timestamp(chunk_config["data_start_exclusive"])
        data_end = parse_timestamp(chunk_config["data_end_exclusive"])
        staged_input = stage_chunk_input(asset_data_root, chunk_root, data_start, data_end)
        staged_files = list(staged_input.rglob("*.parquet"))
        if not staged_files:
            shutil.rmtree(staged_input, ignore_errors=True)
            manifest.append(
                {
                    "month": label,
                    "signal_start": format_timestamp(chunk_start),
                    "signal_end": format_timestamp(chunk_end),
                    "data_end": chunk_config["data_end_exclusive"],
                    "status": "no_data",
                }
            )
            continue
        try:
            run_compose(
                "strategy-backtest",
                chunk_root,
                chunk_tmp,
                chunk_config_path,
                thresholds_source,
                staged_input,
            )
        finally:
            shutil.rmtree(staged_input, ignore_errors=True)
        trade_files.append(chunk_root / "trades.csv")
        metric_files.append(chunk_root / "monthly_metrics.csv")
        summary_files.append(chunk_root / "run_summary.csv")
        manifest.append(
            {
                "month": label,
                "signal_start": format_timestamp(chunk_start),
                "signal_end": format_timestamp(chunk_end),
                "data_end": chunk_config["data_end_exclusive"],
                "status": "completed",
            }
        )
        if chunk_tmp.exists():
            shutil.rmtree(chunk_tmp)

    merge_csv(trade_files, run_root / "trades.csv")
    merge_csv(metric_files, run_root / "monthly_metrics.csv")
    merge_summary(summary_files, run_root / "run_summary.csv", config)
    (run_root / "chunks_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    shutil.rmtree(preparation_tmp, ignore_errors=True)
    print(f"Backtest mensal concluido: {len(manifest)} chunks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
