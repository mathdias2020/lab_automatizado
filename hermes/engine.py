"""Motor Hermes em modo proposal: lê contexto, chama o modelo e grava JSON."""

from __future__ import annotations

import hashlib
import json
import os
import signal
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


AGENT_KEY = "hermes-supervisor"
ENGINE_VERSION = "0.3.0-executable-research"
MODEL_PROVIDER = os.environ.get("HERMES_MODEL_PROVIDER", "openai")
MODEL_NAME = os.environ.get("HERMES_MODEL_NAME", "gpt-5.1")
MODEL_BASE_URL = os.environ.get("HERMES_MODEL_BASE_URL", "https://api.openai.com/v1").rstrip("/")
MODEL_API_KEY = os.environ.get("HERMES_MODEL_API_KEY", "")
CONFIGURED_REASONING_EFFORT = os.environ.get("HERMES_MODEL_REASONING_EFFORT", "medium")
# Proposal cycles are bounded; high reasoning is reserved for the later
# adversarial-review stage so the model cannot exhaust the response budget.
REASONING_EFFORT = (
    CONFIGURED_REASONING_EFFORT
    if CONFIGURED_REASONING_EFFORT in {"none", "low", "medium"}
    else "medium"
)
CONTEXT_DIR = Path(os.environ.get("HERMES_CONTEXT_DIR", "/srv/labs/projects/lab_automatizado/hermes/context"))
PROPOSALS_DIR = Path(os.environ.get("HERMES_PROPOSALS_DIR", "/srv/labs/projects/lab_automatizado/hermes/proposals"))
WORK_DIR = Path(os.environ.get("HERMES_WORK_DIR", "/srv/labs/projects/lab_automatizado/hermes/work"))
REVIEW_INBOX_DIR = Path(os.environ.get("HERMES_REVIEW_INBOX_DIR", "/srv/labs/projects/lab_automatizado/hermes/reviews/inbox"))
REVIEW_RESPONSES_DIR = Path(os.environ.get("HERMES_REVIEW_RESPONSES_DIR", "/srv/labs/projects/lab_automatizado/hermes/reviews/responses"))
REVIEW_STATE_DIR = WORK_DIR / "review-state"
DATASET = Path(os.environ.get("HERMES_DATASET", "/srv/labs/datasets/canonical/normalized_sample_v1"))
INTERVAL_SECONDS = float(os.environ.get("HERMES_PROPOSAL_INTERVAL_SECONDS", "21600"))
REVIEW_POLL_SECONDS = float(os.environ.get("HERMES_REVIEW_POLL_SECONDS", "3"))
MAX_CONTEXT_BYTES = int(os.environ.get("HERMES_MAX_CONTEXT_BYTES", "180000"))

_running = True


def stop(_signum: int, _frame: object) -> None:
    global _running
    _running = False


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_engine_status(status: str, mode: str, capabilities: list[str], metadata: dict[str, object]) -> None:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    target = WORK_DIR / "engine-status.json"
    temporary = WORK_DIR / ".engine-status.json.tmp"
    temporary.write_text(
        json.dumps(
            {
                "status": status,
                "mode": mode,
                "capabilities": capabilities,
                "metadata": metadata,
                "updated_at": utc_now(),
            },
            ensure_ascii=True,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, target)


def collect_context() -> tuple[str, str]:
    pieces: list[str] = []
    total = 0
    for path in sorted(CONTEXT_DIR.glob("*.md")):
        content = path.read_text(encoding="utf-8", errors="replace")
        remaining = MAX_CONTEXT_BYTES - total
        if remaining <= 0:
            break
        content = content[:remaining]
        pieces.append(f"\n===== {path.name} =====\n{content}")
        total += len(content.encode("utf-8"))

    parquet_paths = sorted(DATASET.rglob("*.parquet")) if DATASET.is_dir() else []
    dataset_note = {
        "path": str(DATASET),
        "available": DATASET.is_dir(),
        "parquet_count": len(parquet_paths),
        "sample_paths": [str(path) for path in parquet_paths[:8]],
        "holdout_access": False,
    }
    pieces.append("\n===== DATASET_RUNTIME_FACTS =====\n" + json.dumps(dataset_note, ensure_ascii=True, sort_keys=True))
    context = "".join(pieces)
    return context, hashlib.sha256(context.encode("utf-8")).hexdigest()


def model_request(context: str) -> dict[str, Any]:
    if MODEL_PROVIDER != "openai":
        raise RuntimeError(f"Unsupported model provider: {MODEL_PROVIDER}")
    if not MODEL_API_KEY:
        raise RuntimeError("HERMES_MODEL_API_KEY is empty")

    system_prompt = """
Você é Hermes, pesquisador adaptativo de um laboratório quantitativo intraday.
Você está em modo PROPOSAL: pode explorar o contexto de desenvolvimento e
propor hipóteses, mas não pode acessar holdout, enviar ordens, promover
estratégias ou alegar lucratividade sem evidência determinística.

Use somente o contexto fornecido. Não invente contagens, métricas ou resultados.
Toda proposta precisa sair pronta para o executor: condição mensurável de
entrada, lado, preenchimento no próximo negócio, stop, alvo, time stop,
break-even, trailing, saída parcial, sessão e quantidade. Se uma ideia exigir
uma feature que ainda não está no DSL, declare isso e não a apresente como
executável.

O executor V1 aceita a feature `absorption_extreme`, distâncias em ticks,
uma posição por estratégia/ativo/sessão, retorno bruto e fase development.
Use exatamente `max_variants=500`, `max_seconds=7200` e `max_generations=5`.
O alvo de pesquisa é R$ 1.000 brutos por contrato/mês no portfólio do ativo;
R$ 700–R$ 1.300 é apenas faixa diagnóstica; drawdown acima de R$ 5.000 por
contrato é rejeição do candidato. Gere exatamente duas propostas: uma para
WDOFUT e uma para WINFUT.

Responda SOMENTE com JSON válido neste formato:
{
  "proposals": [
    {
      "asset": "WDOFUT|WINFUT",
      "family": "entry|exit|portfolio|market_structure",
      "title": "...",
      "summary": "...",
      "observation": "...",
      "mechanism": "...",
      "payload": {
        "contract_version": "hermes_execution_v2",
        "primary_metric": "gross_pnl_per_contract_month",
        "execution_spec": {
          "version": 1,
          "feature": {
            "kind": "absorption_extreme",
            "aggression_quantile": 0.95,
            "absorption_move_quantile": 0.25,
            "trade_types": ["AggressorBuyer", "AggressorSeller"]
          },
          "entry": {
            "timing": "first_trade_after_signal_minute",
            "side": "same_as_signed_aggression"
          },
          "exit": {
            "stop_ticks": 20,
            "target_ticks": 40,
            "time_stop_minutes": 15,
            "break_even": {"enabled": true, "activate_ticks": 20, "offset_ticks": 0},
            "trailing": {"enabled": false, "activate_ticks": 30, "distance_ticks": 20, "step_ticks": 5},
            "partial": {"enabled": false, "fraction": 0.5, "target_ticks": 20},
            "session_close": true
          },
          "position": {
            "contracts_by_asset": {"WDOFUT": 10, "WINFUT": 50},
            "one_open_position_per_strategy_asset": true
          }
        },
        "baselines": [],
        "falsifiers": [],
        "search_budget": {"max_variants": 500, "max_seconds": 7200, "max_generations": 5}
      }
    }
  ]
}
""".strip()
    user_prompt = (
        "Contexto do laboratório:\n"
        + context
        + "\n\nLembre: o objetivo econômico é R$ 1.000 por contrato/mês em média por ativo; "
        "a faixa R$ 700–R$ 1.300 é diagnóstica, e a base futura é 10 WDO / 50 WIN."
    )
    body = {
        "model": MODEL_NAME,
        "store": False,
        "reasoning": {"effort": REASONING_EFFORT},
        "max_output_tokens": 8000,
        "input": [
            {"role": "system", "content": [{"type": "input_text", "text": system_prompt}]},
            {"role": "user", "content": [{"type": "input_text", "text": user_prompt}]},
        ],
    }
    request = urllib.request.Request(
        f"{MODEL_BASE_URL}/responses",
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {MODEL_API_KEY}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        exc.read()
        raise RuntimeError(f"Model API HTTP {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Model API network error: {exc.reason}") from exc


def output_text(response: dict[str, Any]) -> str:
    direct = response.get("output_text")
    if isinstance(direct, str) and direct.strip():
        return direct.strip()
    chunks: list[str] = []
    for item in response.get("output", []):
        if not isinstance(item, dict):
            continue
        if item.get("type") == "output_text" and isinstance(item.get("text"), str):
            chunks.append(item["text"])
        content_items = item.get("content", [])
        if isinstance(content_items, str):
            chunks.append(content_items)
        for content in content_items if isinstance(content_items, list) else []:
            if isinstance(content, dict) and isinstance(content.get("text"), str):
                chunks.append(content["text"])
    if not chunks:
        output_types = [
            item.get("type") for item in response.get("output", []) if isinstance(item, dict)
        ]
        raise RuntimeError(
            "Model response did not contain output text "
            f"(status={response.get('status')}, output_types={output_types}, "
            f"incomplete={response.get('incomplete_details')})"
        )
    return "\n".join(chunks).strip()


def parse_json(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`").replace("json\n", "", 1).strip()
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start < 0 or end <= start:
        raise ValueError("model output is not JSON")
    parsed = json.loads(cleaned[start : end + 1])
    if not isinstance(parsed, dict) or not isinstance(parsed.get("proposals"), list):
        raise ValueError("model output has invalid proposal envelope")
    return parsed


def parse_json_object(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`").replace("json\n", "", 1).strip()
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start < 0 or end <= start:
        raise ValueError("model output is not JSON")
    parsed = json.loads(cleaned[start : end + 1])
    if not isinstance(parsed, dict):
        raise ValueError("model output is not a JSON object")
    return parsed


def clip(value: object, limit: int = 4000) -> str:
    return str(value).strip()[:limit]


def existing_keys() -> set[str]:
    keys: set[str] = set()
    if not PROPOSALS_DIR.is_dir():
        return keys
    for path in PROPOSALS_DIR.glob("*.json"):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(payload.get("hypothesis_key"), str):
                keys.add(payload["hypothesis_key"])
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            continue
    return keys


def write_proposals(parsed: dict[str, Any], context_hash: str) -> int:
    PROPOSALS_DIR.mkdir(parents=True, exist_ok=True)
    existing = existing_keys()
    count = 0
    assets_seen: set[str] = set()
    for item in parsed["proposals"]:
        if not isinstance(item, dict):
            raise ValueError("proposal is not an object")
        asset = item.get("asset")
        if asset not in {"WDOFUT", "WINFUT"} or asset in assets_seen:
            raise ValueError("proposals must contain one WDOFUT and one WINFUT")
        assets_seen.add(asset)
        suffix = "wdofut" if asset == "WDOFUT" else "winfut"
        hypothesis_key = f"hermes-{context_hash[:12]}-{suffix}"
        if hypothesis_key in existing:
            continue
        payload = item.get("payload") if isinstance(item.get("payload"), dict) else {}
        execution_spec = payload.get("execution_spec")
        if not isinstance(execution_spec, dict):
            raise ValueError(f"proposal {asset} has no executable execution_spec")
        if execution_spec.get("version") != 1:
            raise ValueError(f"proposal {asset} has unsupported execution_spec version")
        if execution_spec.get("feature", {}).get("kind") != "absorption_extreme":
            raise ValueError(f"proposal {asset} uses an unsupported feature kind")
        if execution_spec.get("entry", {}).get("timing") != "first_trade_after_signal_minute":
            raise ValueError(f"proposal {asset} uses unsupported entry timing")
        payload = {
            **payload,
            "contract_version": "hermes_execution_v2",
            "primary_metric": "gross_pnl_per_contract_month",
            "target_monthly_pnl_per_contract": 1000,
            "diagnostic_monthly_band": [700, 1300],
            "max_drawdown_per_contract": 5000,
            "base_contracts": {"WDOFUT": 10, "WINFUT": 50},
            "search_budget": {"max_variants": 500, "max_seconds": 7200, "max_generations": 5},
            "data_scope": "development-only",
            "pricing_policy": "gross_only",
            "costs_applied": False,
            "slippage_applied": False,
            "holdout_accessed": False,
            "source_context_sha256": context_hash,
            "llm_model": MODEL_NAME,
            "generated_at": utc_now(),
        }
        proposal = {
            "kind": "hermes_hypothesis_proposal",
            "schema_version": 1,
            "agent_key": AGENT_KEY,
            "hypothesis_key": hypothesis_key,
            "asset": asset,
            "family": item.get("family"),
            "title": clip(item.get("title")),
            "summary": clip(item.get("summary")),
            "observation": clip(item.get("observation")),
            "mechanism": clip(item.get("mechanism")),
            "payload": payload,
            "source_run_id": None,
        }
        target = PROPOSALS_DIR / f"{hypothesis_key}.json"
        temporary = PROPOSALS_DIR / f".{hypothesis_key}.tmp"
        temporary.write_text(json.dumps(proposal, ensure_ascii=True, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(temporary, target)
        count += 1
    if assets_seen != {"WDOFUT", "WINFUT"}:
        raise ValueError("model did not return exactly one proposal per asset")
    return count


def generate_once() -> int:
    context, context_hash = collect_context()
    write_engine_status(
        "proposing",
        "proposal",
        ["read_development_data", "propose_hypotheses"],
        {"model": MODEL_NAME, "context_sha256": context_hash, "execution_enabled": False},
    )
    try:
        result = write_proposals(parse_json(output_text(model_request(context))), context_hash)
    finally:
        write_engine_status(
            "observing",
            "observation",
            ["read_development_data", "propose_hypotheses"],
            {"model": MODEL_NAME, "execution_enabled": False},
        )
    return result


def review_model_request(review_request: dict[str, Any]) -> dict[str, Any]:
    if MODEL_PROVIDER != "openai":
        raise RuntimeError(f"Unsupported model provider: {MODEL_PROVIDER}")
    if not MODEL_API_KEY:
        raise RuntimeError("HERMES_MODEL_API_KEY is empty")

    context, context_hash = collect_context()
    thread = review_request.get("thread")
    if not isinstance(thread, list):
        raise ValueError("review request thread is invalid")

    system_prompt = """
Você é Hermes, pesquisador adaptativo de um laboratório quantitativo intraday.
Você está respondendo a uma objeção humana sobre uma hipótese já registrada.

Você pode defender a hipótese, reconhecer uma falha, propor uma reformulação ou
recomendar abandono. Não pode inventar contagens, métricas, resultados, custos ou
evidências. Não trate memória textual como prova de lucratividade. Diferencie o
que está documentado no contexto, o que é inferência e o que ainda precisa de
teste determinístico.

Não altere o protocolo, não acesse holdout, não execute pesquisa e não promova a
estratégia. Se propuser uma revisão executável, inclua uma `execution_spec` V1
completa no payload; se a objeção exigir dados que não estão no contexto, diga
exatamente qual consulta, baseline, placebo ou teste deve ser executado.

Responda SOMENTE com JSON válido neste formato:
{
  "message_type": "response|revision_proposal|abandonment",
  "message": "resposta clara e auditável",
  "payload": {
    "stance": "defend|revise|abandon",
    "evidence_basis": [],
    "remaining_uncertainty": [],
    "proposed_test_changes": []
  }
}
""".strip()
    user_prompt = (
        "Contexto do laboratório:\n"
        + context
        + "\n\nThread da hipótese:\n"
        + json.dumps(thread, ensure_ascii=False, sort_keys=True)
        + "\n\nMensagem que exige resposta:\n"
        + json.dumps(review_request.get("message"), ensure_ascii=False, sort_keys=True)
        + "\n\nA origem do contexto é o hash SHA-256 "
        + context_hash
        + ". Não alegue que esse hash é uma evidência de desempenho."
    )
    body = {
        "model": MODEL_NAME,
        "store": False,
        "reasoning": {"effort": REASONING_EFFORT},
        "max_output_tokens": 6000,
        "input": [
            {"role": "system", "content": [{"type": "input_text", "text": system_prompt}]},
            {"role": "user", "content": [{"type": "input_text", "text": user_prompt}]},
        ],
    }
    request = urllib.request.Request(
        f"{MODEL_BASE_URL}/responses",
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {MODEL_API_KEY}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        exc.read()
        raise RuntimeError(f"Model API HTTP {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Model API network error: {exc.reason}") from exc


def validate_review_request(path: Path) -> dict[str, Any]:
    request = json.loads(path.read_text(encoding="utf-8"))
    if request.get("kind") != "hermes_hypothesis_review_request":
        raise ValueError("invalid review request kind")
    if request.get("schema_version") != 1 or request.get("agent_key") != AGENT_KEY:
        raise ValueError("unsupported review request")
    for field in ("message_id", "hypothesis_id", "parent_message_id"):
        value = request.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"invalid review request {field}")
    if not isinstance(request.get("message"), dict) or not isinstance(request.get("thread"), list):
        raise ValueError("invalid review request envelope")
    return request


def atomic_json_write(target: Path, payload: dict[str, Any]) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(f".{target.name}.tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=True, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, target)


def process_review_request(path: Path) -> None:
    request = validate_review_request(path)
    parent_message_id = request["parent_message_id"]
    state_marker = REVIEW_STATE_DIR / f"{parent_message_id}.done"
    response_path = REVIEW_RESPONSES_DIR / f"{parent_message_id}.json"
    if state_marker.exists() or response_path.exists():
        return

    write_engine_status(
        "reviewing",
        "proposal",
        ["read_development_data", "adversarial_review"],
        {"model": MODEL_NAME, "hypothesis_id": request["hypothesis_id"], "execution_enabled": False},
    )
    try:
        parsed = parse_json_object(output_text(review_model_request(request)))
        message_type = parsed.get("message_type")
        message = parsed.get("message")
        payload = parsed.get("payload") if isinstance(parsed.get("payload"), dict) else {}
        if message_type not in {"response", "revision_proposal", "abandonment"}:
            raise ValueError("invalid Hermes review message type")
        if not isinstance(message, str) or not message.strip() or len(message) > 8000:
            raise ValueError("invalid Hermes review message")
        response = {
            "kind": "hermes_hypothesis_review_response",
            "schema_version": 1,
            "agent_key": AGENT_KEY,
            "message_id": request["message_id"],
            "hypothesis_id": request["hypothesis_id"],
            "parent_message_id": parent_message_id,
            "message_type": message_type,
            "message": message.strip(),
            "payload": payload,
        }
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        response = {
            "kind": "hermes_hypothesis_review_failure",
            "schema_version": 1,
            "agent_key": AGENT_KEY,
            "message_id": request["message_id"],
            "parent_message_id": parent_message_id,
            "error": str(exc)[:1000],
        }
    finally:
        write_engine_status(
            "observing",
            "observation",
            ["read_development_data", "propose_hypotheses", "adversarial_review"],
            {"model": MODEL_NAME, "execution_enabled": False},
        )

    atomic_json_write(response_path, response)
    state_marker.parent.mkdir(parents=True, exist_ok=True)
    state_marker.write_text(utc_now() + "\n", encoding="utf-8")


def process_review_requests() -> int:
    if not REVIEW_INBOX_DIR.is_dir():
        return 0
    processed = 0
    for path in sorted(REVIEW_INBOX_DIR.glob("*.json"))[:3]:
        process_review_request(path)
        processed += 1
    return processed


def main() -> int:
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    if MODEL_PROVIDER != "openai" or not MODEL_API_KEY:
        raise SystemExit("OpenAI provider and HERMES_MODEL_API_KEY are required")
    print(
        f"Hermes engine started in proposal mode with {MODEL_NAME} "
        f"(reasoning={REASONING_EFFORT})",
        flush=True,
    )
    next_proposal_at = 0.0
    while _running:
        try:
            reviewed = process_review_requests()
            if reviewed:
                print(f"Hermes review cycle complete: {reviewed} request(s)", flush=True)
            elif time.monotonic() >= next_proposal_at:
                created = generate_once()
                print(f"Hermes proposal cycle complete: {created} new proposal(s)", flush=True)
                next_proposal_at = time.monotonic() + max(1, INTERVAL_SECONDS)
        except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
            print(f"Hermes engine warning: {exc}", flush=True)
        time.sleep(max(0.5, REVIEW_POLL_SECONDS))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
