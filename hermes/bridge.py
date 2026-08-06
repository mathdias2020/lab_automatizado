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
    }:
        raise ValueError("unsupported agent status/mode")
    if payload.get("version") != "0.1.0-bootstrap":
        raise ValueError("unsupported bootstrap version")
    capabilities = payload.get("capabilities")
    if not isinstance(capabilities, list) or not set(capabilities).issubset(
        {"read_development_data", "heartbeat_only", "propose_hypotheses"}
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
        except (OSError, ValueError, json.JSONDecodeError, RuntimeError) as exc:
            print(f"Hermes bridge warning: {exc}", flush=True)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    raise SystemExit(main())
