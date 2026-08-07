"""Scheduler persistente do ciclo autonomo de desenvolvimento."""

from __future__ import annotations

import json
import os
import signal
import time
from pathlib import Path
from typing import Any

from worker import Gateway, GatewayError


PROJECT_ROOT = Path("/srv/labs/projects/lab_automatizado")
CONTEXT_FILE = PROJECT_ROOT / "hermes" / "context" / "autonomous_results.md"
POLL_SECONDS = float(os.environ.get("ORCHESTRATOR_POLL_SECONDS", "30"))
WORKER_ID = os.environ.get("WORKER_ID", "lab-automatizado-research-orchestrator")
_running = True


def stop(_signum: int, _frame: object) -> None:
    global _running
    _running = False


def write_context(candidates: list[dict[str, Any]]) -> None:
    lines = [
        "# Resultados determinísticos do ciclo autônomo",
        "",
        "Este arquivo é um resumo gerado pelo orquestrador. Ele não é evidência",
        "por si só; os CSVs e hashes dos runs continuam sendo a fonte primária.",
        "",
    ]
    if not candidates:
        lines.append("Nenhum candidato bruto registrado ainda.")
    else:
        for candidate in candidates[:100]:
            metrics = candidate.get("metrics") if isinstance(candidate.get("metrics"), dict) else {}
            lines.extend(
                [
                    f"## {candidate.get('candidate_key', 'sem chave')}",
                    f"- ativo: {candidate.get('asset')}",
                    f"- status: {candidate.get('status')}",
                    f"- média mensal por contrato: {metrics.get('mean_monthly_pnl_per_contract')}",
                    f"- mediana mensal por contrato: {metrics.get('median_monthly_pnl_per_contract')}",
                    f"- meses positivos: {metrics.get('positive_months')} de {metrics.get('months')}",
                    f"- drawdown mensal por contrato: {metrics.get('monthly_equity_drawdown_per_contract')}",
                    "- promoção automática: proibida",
                    "",
                ]
            )
    temporary = CONTEXT_FILE.with_suffix(".tmp")
    CONTEXT_FILE.parent.mkdir(parents=True, exist_ok=True)
    temporary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.replace(temporary, CONTEXT_FILE)


def cycle(gateway: Gateway) -> None:
    control = gateway.rpc("lab_automatizado_get_lab_control", {})
    if not isinstance(control, dict) or not control.get("enabled"):
        return

    hypotheses = gateway.rpc("lab_automatizado_list_hypotheses", {"p_limit": 100}) or []
    for hypothesis in hypotheses:
        if hypothesis.get("status") not in {"proposed", "approved_for_test"}:
            continue
        gateway.rpc(
            "lab_automatizado_prepare_hypothesis_search",
            {
                "p_hypothesis_id": hypothesis["id"],
                "p_requested_by": WORKER_ID,
            },
        )

    gateway.rpc("lab_automatizado_queue_next_variant", {"p_requested_by": WORKER_ID})
    candidates = gateway.rpc("lab_automatizado_list_candidates", {"p_asset": None, "p_limit": 100}) or []
    write_context(candidates if isinstance(candidates, list) else [])
    gateway.rpc("lab_automatizado_record_lab_cycle", {"p_error": None})


def main() -> int:
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        raise SystemExit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    gateway = Gateway(url, key)
    while _running:
        try:
            cycle(gateway)
        except (GatewayError, OSError, ValueError, KeyError, TypeError) as exc:
            try:
                gateway.rpc("lab_automatizado_record_lab_cycle", {"p_error": str(exc)[:1000]})
            except GatewayError:
                pass
        time.sleep(max(5.0, POLL_SECONDS))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
