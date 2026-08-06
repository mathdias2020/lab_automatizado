"""Worker server-side do Laboratório Automatizado.

O processo não monta o Docker socket. Ele consulta a fila via RPC protegido e
invoca apenas o wrapper root-owned autorizado pelo sudoers para executar o
benchmark DuckDB isolado.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class GatewayError(RuntimeError):
    pass


class Gateway:
    def __init__(self, base_url: str, service_role_key: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.service_role_key = service_role_key

    def rpc(self, function_name: str, payload: dict[str, Any]) -> Any:
        request = urllib.request.Request(
            f"{self.base_url}/rest/v1/rpc/{function_name}",
            data=json.dumps(payload).encode("utf-8"),
            method="POST",
            headers={
                "apikey": self.service_role_key,
                "Authorization": f"Bearer {self.service_role_key}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                raw = response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise GatewayError(f"RPC {function_name} retornou HTTP {exc.code}: {detail[:500]}") from exc
        except urllib.error.URLError as exc:
            raise GatewayError(f"Falha de rede no RPC {function_name}: {exc.reason}") from exc

        if not raw:
            return None
        return json.loads(raw)

    def heartbeat(self, worker_id: str, version: str, capabilities: list[str]) -> None:
        self.rpc(
            "lab_automatizado_heartbeat_worker",
            {
                "p_worker_id": worker_id,
                "p_version": version,
                "p_capabilities": capabilities,
            },
        )

    def claim(self, worker_id: str) -> list[dict[str, Any]]:
        result = self.rpc(
            "lab_automatizado_claim_next_command",
            {"p_worker_id": worker_id},
        )
        if result is None:
            return []
        if not isinstance(result, list):
            raise GatewayError(f"Resposta inesperada do claim: {type(result).__name__}")
        return result

    def finish(
        self,
        command_id: str,
        worker_id: str,
        command_status: str,
        run_status: str,
        message: str,
    ) -> None:
        self.rpc(
            "lab_automatizado_finish_command",
            {
                "p_command_id": command_id,
                "p_worker_id": worker_id,
                "p_command_status": command_status,
                "p_run_status": run_status,
                "p_message": message,
            },
        )

    def register_artifact(
        self,
        run_id: str,
        worker_id: str,
        artifact_type: str,
        uri: str,
        sha256: str,
        metadata: dict[str, Any],
    ) -> None:
        self.rpc(
            "lab_automatizado_register_artifact",
            {
                "p_run_id": run_id,
                "p_worker_id": worker_id,
                "p_artifact_type": artifact_type,
                "p_uri": uri,
                "p_sha256": sha256,
                "p_metadata": metadata,
            },
        )


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    service_role_key: str
    worker_id: str
    worker_version: str
    poll_seconds: float
    heartbeat_seconds: float
    run_timeout_seconds: int
    quality_runner: str
    research_runner: str
    strategy_runner: str

    @classmethod
    def from_env(cls) -> "Settings":
        required = {
            "SUPABASE_URL": os.environ.get("SUPABASE_URL", ""),
            "SUPABASE_SERVICE_ROLE_KEY": os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""),
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise SystemExit(f"Variáveis obrigatórias ausentes: {', '.join(missing)}")

        return cls(
            supabase_url=required["SUPABASE_URL"],
            service_role_key=required["SUPABASE_SERVICE_ROLE_KEY"],
            worker_id=os.environ.get("WORKER_ID", "lab-automatizado-vps-linux"),
            worker_version=os.environ.get("WORKER_VERSION", "0.1.0"),
            poll_seconds=float(os.environ.get("POLL_SECONDS", "5")),
            heartbeat_seconds=float(os.environ.get("HEARTBEAT_SECONDS", "15")),
            run_timeout_seconds=int(os.environ.get("RUN_TIMEOUT_SECONDS", "3600")),
            quality_runner=os.environ.get(
                "QUALITY_RUNNER", "/usr/local/sbin/lab-automatizado-quality-run"
            ),
            research_runner=os.environ.get(
                "RESEARCH_RUNNER", "/usr/local/sbin/lab-automatizado-research-run"
            ),
            strategy_runner=os.environ.get(
                "STRATEGY_RUNNER", "/usr/local/sbin/lab-automatizado-strategy-run"
            ),
        )


def register_run_artifacts(
    gateway: Gateway, settings: Settings, run_id: str, artifact_type: str
) -> int:
    run_root = Path(f"/srv/labs/projects/lab_automatizado/runs/control_plane/{run_id}")
    files = sorted(
        artifact
        for artifact in run_root.iterdir()
        if artifact.is_file() and artifact.suffix in {".csv", ".json", ".md"}
    )
    for artifact in files:
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        gateway.register_artifact(
            run_id=run_id,
            worker_id=settings.worker_id,
            artifact_type=artifact_type,
            uri=f"vps://{artifact}",
            sha256=digest,
            metadata={"bytes": artifact.stat().st_size, "name": artifact.name},
        )
    return len(files)


def run_command(gateway: Gateway, settings: Settings, command: dict[str, Any]) -> tuple[str, str]:
    command_id = str(command["command_id"])
    command_type = command.get("command_type")
    run_id = str(command.get("run_id"))

    if command_type != "start_run":
        return "failed", f"Comando não implementado nesta fase: {command_type}"

    payload = command.get("payload") or {}
    run_type = payload.get("run_type")
    config = payload.get("config") or {}
    runners = {
        "quality_benchmark": (settings.quality_runner, "quality_csv"),
        "research": (settings.research_runner, "research_artifact"),
        "strategy_backtest": (settings.strategy_runner, "strategy_backtest_artifact"),
    }
    runner_spec = runners.get(run_type)
    if runner_spec is None:
        return "failed", f"Tipo de run nao implementado nesta fase: {run_type}"

    runner, artifact_type = runner_spec
    if run_type == "research" and config.get("research_id") != "absorption_event_study_v1":
        return "failed", "Somente absorption_event_study_v1 esta permitido no worker inicial."
    if run_type in {"research", "strategy_backtest"} and config.get("asset") not in {"WDOFUT", "WINFUT"}:
        return "failed", "A pesquisa exige asset WDOFUT ou WINFUT."
    if run_type == "strategy_backtest":
        if config.get("executor_id") != "strategy_backtest_v1":
            return "failed", "Executor de estratégia não permitido."
        if config.get("phase") != "development":
            return "failed", "O worker inicial só aceita a fase development."
        if config.get("holdout_accessed") is not False:
            return "failed", "Holdout bloqueado no executor de desenvolvimento."
        if config.get("costs_applied") is not False or config.get("slippage_applied") is not False:
            return "failed", "Este laboratório executa somente retorno bruto."
        spec = config.get("execution_spec")
        if not isinstance(spec, dict):
            return "failed", "Hipótese sem execution_spec declarativa."
        if spec.get("version") != 1 or spec.get("feature", {}).get("kind") != "absorption_extreme":
            return "failed", "Feature declarativa ainda não suportada pelo executor V1."
        entry = spec.get("entry", {})
        exit_policy = spec.get("exit", {})
        if entry.get("timing") != "first_trade_after_signal_minute":
            return "failed", "Timing de entrada não suportado pelo executor V1."
        required_exit = {"stop_ticks", "target_ticks", "time_stop_minutes", "break_even", "trailing", "partial"}
        if not required_exit.issubset(exit_policy):
            return "failed", "Política de saída incompleta."
        if any(int(exit_policy.get(name, 0)) <= 0 for name in ("stop_ticks", "target_ticks", "time_stop_minutes")):
            return "failed", "Stop, alvo e time stop devem ser positivos."
        partial = exit_policy.get("partial")
        if not isinstance(partial, dict) or not (0 < float(partial.get("fraction", 0.5)) < 1):
            return "failed", "Fração de saída parcial inválida."

        try:
            run_root = Path(f"/srv/labs/projects/lab_automatizado/runs/control_plane/{run_id}")
            run_root.mkdir(parents=True, exist_ok=True)
            (run_root / "config.json").write_text(
                json.dumps(config, ensure_ascii=True, sort_keys=True) + "\n", encoding="utf-8"
            )
        except OSError as exc:
            return "failed", f"Não foi possível preparar a pasta do run: {exc}"

    try:
        completed = subprocess.run(
            ["sudo", "-n", runner, run_id]
            + ([str(config["asset"])] if run_type == "research" else []),
            check=False,
            capture_output=True,
            text=True,
            timeout=settings.run_timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        return "failed", f"Benchmark excedeu {settings.run_timeout_seconds}s."
    except OSError as exc:
        return "failed", f"Não foi possível iniciar o runner: {exc}"

    if completed.returncode != 0:
        stderr = (completed.stderr or "").strip().replace("\n", " ")
        return "failed", f"Runner retornou {completed.returncode}: {stderr[-500:]}"

    try:
        artifact_count = register_run_artifacts(gateway, settings, run_id, artifact_type)
    except (GatewayError, OSError) as exc:
        return "failed", f"Benchmark terminou, mas o registro de artefatos falhou: {exc}"

    return "completed", f"Benchmark concluído; {artifact_count} artefatos registrados."


def run_loop(settings: Settings, once: bool) -> None:
    gateway = Gateway(settings.supabase_url, settings.service_role_key)
    capabilities = ["quality_benchmark", "absorption_event_study_v1", "strategy_backtest_v1", "gross_only", "development_only"]
    last_heartbeat = 0.0

    while True:
        now = time.monotonic()
        if now - last_heartbeat >= settings.heartbeat_seconds:
            gateway.heartbeat(settings.worker_id, settings.worker_version, capabilities)
            last_heartbeat = now

        commands = gateway.claim(settings.worker_id)
        if commands:
            command = commands[0]
            command_status, message = run_command(gateway, settings, command)
            run_status = "succeeded" if command_status == "completed" else "failed"
            gateway.finish(
                str(command["command_id"]),
                settings.worker_id,
                command_status,
                run_status,
                message,
            )
            if once:
                return
        elif once:
            return
        else:
            time.sleep(settings.poll_seconds)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--once", action="store_true", help="Processa no máximo um comando e encerra.")
    args = parser.parse_args()
    run_loop(Settings.from_env(), once=args.once)


if __name__ == "__main__":
    main()
