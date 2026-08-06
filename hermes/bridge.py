"""Ponte allowlisted entre o heartbeat local e o registry privado do Supabase."""

from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


AGENT_KEY = "hermes-supervisor"
HEARTBEAT_FILE = Path(
    os.environ.get(
        "HERMES_HEARTBEAT_FILE",
        "/srv/labs/projects/lab_automatizado/hermes/outbox/heartbeat.json",
    )
)
PROPOSALS_DIR = Path(
    os.environ.get(
        "HERMES_PROPOSALS_DIR",
        "/srv/labs/projects/lab_automatizado/hermes/proposals",
    )
)
REVIEW_INBOX_DIR = Path(
    os.environ.get(
        "HERMES_REVIEW_INBOX_DIR",
        "/srv/labs/projects/lab_automatizado/hermes/reviews/inbox",
    )
)
REVIEW_RESPONSES_DIR = Path(
    os.environ.get(
        "HERMES_REVIEW_RESPONSES_DIR",
        "/srv/labs/projects/lab_automatizado/hermes/reviews/responses",
    )
)
POLL_SECONDS = float(os.environ.get("HERMES_BRIDGE_POLL_SECONDS", "3"))
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")


def rpc(function_name: str, payload: dict[str, Any]) -> Any:
    request = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/rpc/{function_name}",
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "apikey": SERVICE_ROLE_KEY,
            "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"RPC HTTP {exc.code}: {detail[:300]}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"RPC network error: {exc.reason}") from exc
    return json.loads(raw) if raw else None


def read_validated_heartbeat() -> tuple[dict[str, Any], int]:
    payload = json.loads(HEARTBEAT_FILE.read_text(encoding="utf-8"))
    if payload.get("kind") != "hermes_heartbeat":
        raise ValueError("invalid heartbeat kind")
    if payload.get("agent_key") != AGENT_KEY:
        raise ValueError("invalid agent key")
    if (payload.get("status"), payload.get("mode")) not in {
        ("observing", "observation"),
        ("proposing", "proposal"),
        ("reviewing", "proposal"),
    }:
        raise ValueError("unsupported agent status/mode")
    if payload.get("version") != "0.1.0-bootstrap":
        raise ValueError("unsupported bootstrap version")
    capabilities = payload.get("capabilities")
    if not isinstance(capabilities, list) or not set(capabilities).issubset(
        {"read_development_data", "heartbeat_only", "propose_hypotheses", "adversarial_review"}
    ):
        raise ValueError("unsupported capabilities")
    metadata = payload.get("metadata")
    if not isinstance(metadata, dict) or metadata.get("service_role_access") is not False:
        raise ValueError("unsafe metadata")
    return payload, HEARTBEAT_FILE.stat().st_mtime_ns


def send_heartbeat(payload: dict[str, Any]) -> None:
    rpc(
        "lab_automatizado_heartbeat_agent",
        {
            "p_agent_key": AGENT_KEY,
            "p_status": payload["status"],
            "p_mode": payload["mode"],
            "p_version": payload["version"],
            "p_capabilities": payload["capabilities"],
            "p_metadata": payload["metadata"],
        },
    )


def read_validated_proposal(path: Path) -> tuple[dict[str, Any], int]:
    proposal = json.loads(path.read_text(encoding="utf-8"))
    if proposal.get("kind") != "hermes_hypothesis_proposal":
        raise ValueError("invalid proposal kind")
    if proposal.get("agent_key") != AGENT_KEY:
        raise ValueError("invalid proposal agent")
    if proposal.get("schema_version") != 1:
        raise ValueError("unsupported proposal schema")
    key = proposal.get("hypothesis_key")
    if not isinstance(key, str) or not re.fullmatch(r"hermes-[a-f0-9]{12}-(wdofut|winfut)", key):
        raise ValueError("invalid hypothesis key")
    if proposal.get("asset") not in {"WDOFUT", "WINFUT"}:
        raise ValueError("invalid asset")
    if proposal.get("family") not in {"entry", "exit", "portfolio", "market_structure"}:
        raise ValueError("invalid family")
    for field in ("title", "summary", "observation", "mechanism"):
        value = proposal.get(field)
        if not isinstance(value, str) or not value.strip() or len(value) > 4000:
            raise ValueError(f"invalid {field}")
    payload = proposal.get("payload")
    if not isinstance(payload, dict) or len(json.dumps(payload)) > 20000:
        raise ValueError("invalid proposal payload")
    if payload.get("contract_version") != "hermes_execution_v2":
        raise ValueError("proposal is missing hermes_execution_v2 contract")
    execution_spec = payload.get("execution_spec")
    if not isinstance(execution_spec, dict) or execution_spec.get("version") != 1:
        raise ValueError("proposal is missing executable execution_spec")
    if execution_spec.get("feature", {}).get("kind") != "absorption_extreme":
        raise ValueError("proposal feature is not supported by executor V1")
    if payload.get("primary_metric") != "gross_pnl_per_contract_month":
        raise ValueError("proposal must use gross_pnl_per_contract_month")
    return proposal, path.stat().st_mtime_ns


def send_proposal(proposal: dict[str, Any]) -> Any:
    return rpc(
        "lab_automatizado_record_hypothesis",
        {
            "p_hypothesis_key": proposal["hypothesis_key"],
            "p_agent_key": AGENT_KEY,
            "p_asset": proposal["asset"],
            "p_family": proposal["family"],
            "p_title": proposal["title"],
            "p_summary": proposal["summary"],
            "p_observation": proposal["observation"],
            "p_mechanism": proposal["mechanism"],
            "p_payload": proposal["payload"],
            "p_source_run_id": proposal.get("source_run_id"),
        },
    )


def atomic_json_write(target: Path, payload: dict[str, Any]) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(f".{target.name}.tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=True, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, target)


def claim_review_request() -> None:
    REVIEW_INBOX_DIR.mkdir(parents=True, exist_ok=True)
    if any(REVIEW_INBOX_DIR.glob("*.json")):
        return
    claimed = rpc("lab_automatizado_claim_hypothesis_message", {"p_agent_key": AGENT_KEY})
    if not claimed:
        return
    if not isinstance(claimed, dict) or not isinstance(claimed.get("message"), dict):
        raise ValueError("invalid claimed review response")
    message = claimed["message"]
    message_id = message.get("id")
    hypothesis_id = message.get("hypothesis_id")
    if not isinstance(message_id, str) or not isinstance(hypothesis_id, str):
        raise ValueError("invalid claimed review identifiers")
    payload = {
        "kind": "hermes_hypothesis_review_request",
        "schema_version": 1,
        "agent_key": AGENT_KEY,
        "message_id": message_id,
        "hypothesis_id": hypothesis_id,
        "parent_message_id": message_id,
        "message": message,
        "thread": claimed.get("thread") if isinstance(claimed.get("thread"), list) else [],
    }
    try:
        atomic_json_write(REVIEW_INBOX_DIR / f"{message_id}.json", payload)
    except (OSError, TypeError, ValueError) as exc:
        rpc(
            "lab_automatizado_requeue_hypothesis_message",
            {
                "p_message_id": message_id,
                "p_agent_key": AGENT_KEY,
                "p_reason": f"review inbox delivery failed: {exc}",
            },
        )
        raise
    print(f"Hermes review request claimed: message={message_id}", flush=True)


def read_validated_review_response(path: Path) -> dict[str, Any]:
    response = json.loads(path.read_text(encoding="utf-8"))
    if response.get("schema_version") != 1 or response.get("agent_key") != AGENT_KEY:
        raise ValueError("unsupported Hermes review response")
    if response.get("kind") == "hermes_hypothesis_review_failure":
        if not isinstance(response.get("message_id"), str) or not isinstance(response.get("error"), str):
            raise ValueError("invalid Hermes review failure")
        return response
    if response.get("kind") != "hermes_hypothesis_review_response":
        raise ValueError("invalid Hermes review response kind")
    for field in ("message_id", "hypothesis_id", "parent_message_id"):
        if not isinstance(response.get(field), str) or not response[field].strip():
            raise ValueError(f"invalid Hermes review response {field}")
    if response.get("message_type") not in {"response", "revision_proposal", "abandonment"}:
        raise ValueError("invalid Hermes review response type")
    message = response.get("message")
    if not isinstance(message, str) or not message.strip() or len(message) > 8000:
        raise ValueError("invalid Hermes review response message")
    payload = response.get("payload")
    if payload is not None and not isinstance(payload, dict):
        raise ValueError("invalid Hermes review response payload")
    return response


def publish_review_response(path: Path) -> None:
    response = read_validated_review_response(path)
    parent_message_id = response.get("parent_message_id") or response["message_id"]
    if response.get("kind") == "hermes_hypothesis_review_failure":
        rpc(
            "lab_automatizado_fail_hypothesis_message",
            {
                "p_message_id": response["message_id"],
                "p_agent_key": AGENT_KEY,
                "p_error_message": response["error"],
            },
        )
    else:
        rpc(
            "lab_automatizado_publish_hermes_message",
            {
                "p_hypothesis_id": response["hypothesis_id"],
                "p_parent_message_id": parent_message_id,
                "p_message_type": response["message_type"],
                "p_body": response["message"],
                "p_payload": response.get("payload") or {},
                "p_agent_key": AGENT_KEY,
            },
        )
    (REVIEW_INBOX_DIR / f"{parent_message_id}.json").unlink(missing_ok=True)
    path.unlink(missing_ok=True)
    print(f"Hermes review response registered: parent={parent_message_id}", flush=True)


def main() -> int:
    if not SUPABASE_URL or not SERVICE_ROLE_KEY:
        raise SystemExit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    print(f"Hermes bridge listening on {HEARTBEAT_FILE}", flush=True)
    last_mtime = 0
    proposal_mtimes: dict[Path, int] = {}
    while True:
        try:
            if HEARTBEAT_FILE.is_file():
                payload, mtime = read_validated_heartbeat()
                if mtime != last_mtime:
                    send_heartbeat(payload)
                    last_mtime = mtime
                    print("Hermes heartbeat registered", flush=True)
            if PROPOSALS_DIR.is_dir():
                for path in sorted(PROPOSALS_DIR.glob("*.json"))[:20]:
                    proposal, mtime = read_validated_proposal(path)
                    if proposal_mtimes.get(path) == mtime:
                        continue
                    try:
                        hypothesis_id = send_proposal(proposal)
                    except RuntimeError as exc:
                        if "duplicate key" not in str(exc).lower() and "unique constraint" not in str(exc).lower():
                            raise
                        hypothesis_id = "already-registered"
                    proposal_mtimes[path] = mtime
                    print(
                        f"Hermes hypothesis registered: {proposal['hypothesis_key']} id={hypothesis_id}",
                        flush=True,
                    )
            if REVIEW_RESPONSES_DIR.is_dir():
                for path in sorted(REVIEW_RESPONSES_DIR.glob("*.json"))[:10]:
                    publish_review_response(path)
            claim_review_request()
        except (OSError, ValueError, json.JSONDecodeError, RuntimeError) as exc:
            print(f"Hermes bridge warning: {exc}", flush=True)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    raise SystemExit(main())
