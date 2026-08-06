"""Ponte allowlisted entre o heartbeat local e o registry privado do Supabase."""

from __future__ import annotations

import json
import os
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
    if payload.get("status") != "observing" or payload.get("mode") != "observation":
        raise ValueError("bootstrap only accepts observing/observation")
    if payload.get("version") != "0.1.0-bootstrap":
        raise ValueError("unsupported bootstrap version")
    capabilities = payload.get("capabilities")
    if capabilities != ["read_development_data", "heartbeat_only"]:
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
            "p_status": "observing",
            "p_mode": "observation",
            "p_version": payload["version"],
            "p_capabilities": payload["capabilities"],
            "p_metadata": payload["metadata"],
        },
    )


def main() -> int:
    if not SUPABASE_URL or not SERVICE_ROLE_KEY:
        raise SystemExit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    print(f"Hermes bridge listening on {HEARTBEAT_FILE}", flush=True)
    last_mtime = 0
    while True:
        try:
            if HEARTBEAT_FILE.is_file():
                payload, mtime = read_validated_heartbeat()
                if mtime != last_mtime:
                    send_heartbeat(payload)
                    last_mtime = mtime
                    print("Hermes heartbeat registered", flush=True)
        except (OSError, ValueError, json.JSONDecodeError, RuntimeError) as exc:
            print(f"Hermes bridge warning: {exc}", flush=True)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    raise SystemExit(main())
