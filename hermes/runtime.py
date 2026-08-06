"""Bootstrap observacional do Hermes, sem acesso de rede ou a credenciais."""

from __future__ import annotations

import json
import os
import signal
import time
from datetime import datetime, timezone
from pathlib import Path


AGENT_KEY = "hermes-supervisor"
VERSION = os.environ.get("HERMES_VERSION", "0.1.0-bootstrap")
OUTBOX = Path(os.environ.get("HERMES_OUTBOX", "/srv/labs/projects/lab_automatizado/hermes/outbox"))
DATASET = Path(
    os.environ.get(
        "HERMES_DATASET",
        "/srv/labs/datasets/canonical/normalized_sample_v1",
    )
)
HEARTBEAT_SECONDS = float(os.environ.get("HERMES_HEARTBEAT_SECONDS", "15"))
ENGINE_STATUS_FILE = Path(
    os.environ.get(
        "HERMES_ENGINE_STATUS_FILE",
        "/srv/labs/projects/lab_automatizado/hermes/work/engine-status.json",
    )
)

_running = True


def stop(_signum: int, _frame: object) -> None:
    global _running
    _running = False


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def dataset_metadata() -> dict[str, object]:
    available = DATASET.is_dir()
    parquet_count = 0
    if available:
        parquet_count = sum(1 for path in DATASET.rglob("*.parquet") if path.is_file())
    return {
        "dataset_path": str(DATASET),
        "dataset_available": available,
        "dataset_parquet_count": parquet_count,
        "data_scope": "development-only",
        "holdout_access": False,
    }


def engine_status() -> tuple[str, str, list[str], dict[str, object]]:
    default = ("observing", "observation", ["read_development_data", "heartbeat_only"], {})
    try:
        if not ENGINE_STATUS_FILE.is_file() or time.time() - ENGINE_STATUS_FILE.stat().st_mtime > 120:
            return default
        payload = json.loads(ENGINE_STATUS_FILE.read_text(encoding="utf-8"))
        status = payload.get("status")
        mode = payload.get("mode")
        capabilities = payload.get("capabilities")
        metadata = payload.get("metadata")
        if status not in {"observing", "proposing", "reviewing"} or mode not in {"observation", "proposal"}:
            return default
        if not isinstance(capabilities, list) or not isinstance(metadata, dict):
            return default
        return status, mode, [str(item) for item in capabilities], metadata
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return default


def heartbeat_payload() -> dict[str, object]:
    status, mode, capabilities, engine_metadata = engine_status()
    return {
        "kind": "hermes_heartbeat",
        "agent_key": AGENT_KEY,
        "status": status,
        "mode": mode,
        "version": VERSION,
        "capabilities": capabilities,
        "metadata": {
            "runtime": "hermes-runtime",
            "execution_enabled": False,
            "hypothesis_generation_enabled": status == "proposing",
            "service_role_access": False,
            "docker_socket_access": False,
            "network_access": False,
            "pid": os.getpid(),
            "observed_at": utc_now(),
            **engine_metadata,
            **dataset_metadata(),
        },
    }


def write_heartbeat(payload: dict[str, object]) -> None:
    OUTBOX.mkdir(parents=True, exist_ok=True)
    target = OUTBOX / "heartbeat.json"
    temporary = OUTBOX / ".heartbeat.json.tmp"
    temporary.write_text(json.dumps(payload, ensure_ascii=True, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, target)


def main() -> int:
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print(
        f"Hermes bootstrap iniciado: agent={AGENT_KEY} mode=observation "
        f"dataset={DATASET}",
        flush=True,
    )
    while _running:
        write_heartbeat(heartbeat_payload())
        time.sleep(HEARTBEAT_SECONDS)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
