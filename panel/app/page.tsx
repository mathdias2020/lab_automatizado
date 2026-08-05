"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

type Run = {
  id: string;
  run_key: string;
  run_type: string;
  status: string;
  dataset_manifest: string | null;
  created_at: string;
  finished_at: string | null;
  worker_id: string | null;
};

const statusLabel: Record<string, string> = {
  queued: "Na fila",
  claimed: "Reivindicado",
  running: "Executando",
  succeeded: "Concluído",
  failed: "Falhou",
  cancelled: "Cancelado",
};

function formatDate(value: string | null) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

function statusClass(status: string) {
  if (status === "succeeded") return "status status-success";
  if (status === "failed") return "status status-danger";
  if (status === "queued") return "status status-warning";
  return "status status-active";
}

export default function Home() {
  const [runs, setRuns] = useState<Run[]>([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState("Verificando o control plane…");

  const loadRuns = useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch("/api/runs", { cache: "no-store" });
      const body = (await response.json()) as { runs?: Run[]; error?: string };
      if (!response.ok) throw new Error(body.error ?? "Não foi possível consultar as execuções.");
      setRuns(body.runs ?? []);
      setMessage("Control plane conectado");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Falha ao consultar o control plane.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadRuns();
  }, [loadRuns]);

  const counts = useMemo(() => ({
    total: runs.length,
    active: runs.filter((run) => ["queued", "claimed", "running"].includes(run.status)).length,
    succeeded: runs.filter((run) => run.status === "succeeded").length,
  }), [runs]);
  const controlPlaneReady = message === "Control plane conectado" || message.includes("colocado na fila");

  async function enqueueBenchmark() {
    setSubmitting(true);
    const suffix = new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
    try {
      const response = await fetch("/api/runs", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ run_key: `quality-panel-${suffix}` }),
      });
      const body = (await response.json()) as { run_id?: string; error?: string };
      if (!response.ok) throw new Error(body.error ?? "Não foi possível colocar o benchmark na fila.");
      setMessage(`Benchmark ${body.run_id?.slice(0, 8) ?? ""} colocado na fila`);
      await loadRuns();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Falha ao criar a execução.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="shell">
      <aside className="sidebar">
        <div className="brand-lockup">
          <span className="brand-mark" aria-hidden="true">∿</span>
          <div>
            <p className="brand-name">fluxo lab</p>
            <p className="brand-subtitle">automated research</p>
          </div>
        </div>

        <nav className="nav" aria-label="Navegação principal">
          <a className="nav-item nav-item-active" href="#overview"><span>◉</span> Overview</a>
          <a className="nav-item" href="#runs"><span>↗</span> Execuções</a>
          <a className="nav-item" href="#workers"><span>⌁</span> Workers</a>
          <a className="nav-item" href="#artifacts"><span>▱</span> Artefatos</a>
        </nav>

        <div className="sidebar-note">
          <span className="pulse-dot" aria-hidden="true" />
          <div>
            <strong>Modo laboratório</strong>
            <p>Sem ordens · sem ProfitDLL</p>
          </div>
        </div>

        <div className="sidebar-footer">
          <span>LAB_AUTOMATIZADO</span>
          <span>v0.1</span>
        </div>
      </aside>

      <section className="content" id="overview">
        <header className="topbar">
          <div>
            <p className="breadcrumb">LABORATÓRIO / CONTROL PLANE</p>
            <h1>Pesquisas que deixam rastro.</h1>
          </div>
          <div className="connection-state"><span className={`pulse-dot ${controlPlaneReady ? "" : "pulse-dot-warning"}`} /> {message}</div>
        </header>

        <section className="hero-grid">
          <div className="hero-card">
            <div className="eyebrow">PRÓXIMA AÇÃO SEGURA</div>
            <h2>Coloque um benchmark na fila.</h2>
            <p>O worker reivindica uma execução por vez e grava estado, eventos, hashes e artefatos.</p>
            <button className="primary-button" onClick={enqueueBenchmark} disabled={submitting}>
              <span>{submitting ? "Enfileirando…" : "Iniciar quality benchmark"}</span>
              <span aria-hidden="true">↗</span>
            </button>
          </div>

          <div className="signal-card" id="workers">
            <div className="eyebrow">SINAL DO SISTEMA</div>
            <div className="signal-line"><span className="signal-bar signal-bar-bright" /><span className="signal-bar signal-bar-medium" /><span className="signal-bar signal-bar-low" /></div>
            <div className="signal-value">2 vCPU <span>/</span> KVM2</div>
            <p>Fila serializada para preservar a qualidade do experimento.</p>
          </div>
        </section>

        <section className="metrics" aria-label="Resumo das execuções">
          <div className="metric metric-featured"><span className="metric-label">EXECUÇÕES VISÍVEIS</span><strong>{counts.total}</strong><span className="metric-foot">últimas 50</span></div>
          <div className="metric"><span className="metric-label">ATIVAS</span><strong>{counts.active}</strong><span className="metric-foot">aguardando ou rodando</span></div>
          <div className="metric"><span className="metric-label">CONCLUÍDAS</span><strong>{counts.succeeded}</strong><span className="metric-foot">com resultado</span></div>
          <div className="metric metric-text"><span className="metric-label">DATASET</span><strong>expanded_v1</strong><span className="metric-foot">Parquet somente leitura</span></div>
        </section>

        <section className="runs-section" id="runs">
          <div className="section-heading">
            <div><p className="eyebrow">AUDIT LOG</p><h2>Execuções recentes</h2></div>
            <button className="quiet-button" onClick={() => void loadRuns()} disabled={loading}>{loading ? "Atualizando…" : "Atualizar"}</button>
          </div>

          <div className="run-table" role="table" aria-label="Execuções recentes">
            <div className="run-row run-row-heading" role="row"><span>Execução</span><span>Estado</span><span>Worker</span><span>Criada em</span><span>Finalizada</span></div>
            {runs.length === 0 && !loading ? <div className="empty-state"><span>∅</span><div><strong>Nenhuma execução ainda</strong><p>O primeiro benchmark aparecerá aqui com seu estado auditável.</p></div></div> : null}
            {loading ? <div className="empty-state"><span className="loading-mark">◌</span><div><strong>Consultando o control plane</strong><p>Buscando o estado mais recente da fila.</p></div></div> : null}
            {runs.map((run) => <div className="run-row" role="row" key={run.id}><span className="run-name"><strong>{run.run_key}</strong><small>{run.run_type}</small></span><span><span className={statusClass(run.status)}>{statusLabel[run.status] ?? run.status}</span></span><span className="mono">{run.worker_id ?? "—"}</span><span>{formatDate(run.created_at)}</span><span>{formatDate(run.finished_at)}</span></div>)}
          </div>
        </section>

        <footer className="page-footer"><span>Supabase · schema privado lab_automatizado</span><span>RLS ativo · service role server-side</span></footer>
      </section>
    </main>
  );
}
