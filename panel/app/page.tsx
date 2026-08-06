"use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase-browser";

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

type Agent = {
  agent_key: string;
  display_name: string;
  agent_type: string;
  status: string;
  mode: string;
  version: string | null;
  capabilities: string[];
  last_heartbeat_at: string | null;
  last_activity_at: string | null;
};

type Hypothesis = {
  id: string;
  hypothesis_key: string;
  agent_key: string;
  asset: string | null;
  family: string;
  title: string;
  summary: string;
  observation: string | null;
  mechanism: string | null;
  status: string;
  review_notes: string | null;
  created_at: string;
  reviewed_at: string | null;
};

const statusLabel: Record<string, string> = {
  queued: "Na fila",
  claimed: "Reivindicado",
  running: "Executando",
  succeeded: "Concluído",
  failed: "Falhou",
  cancelled: "Cancelado",
};

const agentStatusLabel: Record<string, string> = {
  offline: "Offline",
  starting: "Iniciando",
  idle: "Ocioso",
  observing: "Observando",
  proposing: "Propondo",
  reviewing: "Revisando",
  degraded: "Degradado",
  error: "Erro",
};

const agentModeLabel: Record<string, string> = {
  disabled: "Desligado",
  observation: "Somente observação",
  proposal: "Proposta de hipóteses",
  controlled_execution: "Execução controlada",
};

const hypothesisStatusLabel: Record<string, string> = {
  proposed: "Proposta",
  under_review: "Em revisão",
  approved_for_test: "Aprovada para teste",
  rejected: "Rejeitada",
  archived: "Arquivada",
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

function agentStatusClass(status: string) {
  if (status === "error") return "status status-danger";
  if (status === "offline" || status === "degraded") return "status status-warning";
  return "status status-active";
}

export default function Home() {
  const [session, setSession] = useState<Session | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [authSubmitting, setAuthSubmitting] = useState(false);
  const [authError, setAuthError] = useState("");
  const [runs, setRuns] = useState<Run[]>([]);
  const [agents, setAgents] = useState<Agent[]>([]);
  const [hypotheses, setHypotheses] = useState<Hypothesis[]>([]);
  const [loading, setLoading] = useState(true);
  const [researchLoading, setResearchLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [reviewingHypothesis, setReviewingHypothesis] = useState<string | null>(null);
  const [hypothesisNotes, setHypothesisNotes] = useState<Record<string, string>>({});
  const [message, setMessage] = useState("Verificando a sessão…");

  useEffect(() => {
    if (!supabase) {
      setAuthLoading(false);
      setAuthError("As variáveis públicas do Supabase ainda não foram configuradas.");
      return;
    }

    let active = true;
    void supabase.auth.getSession().then(({ data: { session: currentSession } }) => {
      if (active) {
        setSession(currentSession);
        setAuthLoading(false);
      }
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      if (active) setSession(nextSession);
    });

    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, []);

  const loadResearchStatus = useCallback(async (accessToken: string) => {
    setResearchLoading(true);
    try {
      const response = await fetch("/api/agents", {
        cache: "no-store",
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      const body = (await response.json()) as { agents?: Agent[]; hypotheses?: Hypothesis[]; error?: string };
      if (!response.ok) throw new Error(body.error ?? "Não foi possível consultar o Hermes.");
      setAgents(body.agents ?? []);
      setHypotheses(body.hypotheses ?? []);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Falha ao consultar o Hermes.");
    } finally {
      setResearchLoading(false);
    }
  }, []);

  const loadRuns = useCallback(async (accessToken: string) => {
    setLoading(true);
    try {
      const response = await fetch("/api/runs", {
        cache: "no-store",
        headers: { Authorization: `Bearer ${accessToken}` },
      });
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
    if (session) {
      void loadRuns(session.access_token);
      void loadResearchStatus(session.access_token);
    } else if (!authLoading) {
      setRuns([]);
      setAgents([]);
      setHypotheses([]);
      setLoading(false);
      setResearchLoading(false);
    }
  }, [authLoading, loadResearchStatus, loadRuns, session]);

  const counts = useMemo(() => ({
    total: runs.length,
    active: runs.filter((run) => ["queued", "claimed", "running"].includes(run.status)).length,
    succeeded: runs.filter((run) => run.status === "succeeded").length,
  }), [runs]);
  const currentAgent = agents[0] ?? null;
  const pendingHypotheses = hypotheses.filter((hypothesis) => ["proposed", "under_review"].includes(hypothesis.status));
  const controlPlaneReady = message === "Control plane conectado" || message.includes("colocado na fila");

  async function handleLogin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supabase) return;
    setAuthSubmitting(true);
    setAuthError("");
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) setAuthError(error.message === "Invalid login credentials" ? "E-mail ou senha inválidos." : error.message);
    setAuthSubmitting(false);
  }

  async function handleLogout() {
    if (supabase) await supabase.auth.signOut();
    setSession(null);
    setMessage("Sessão encerrada");
  }

  async function enqueueBenchmark() {
    if (!session) return;
    setSubmitting(true);
    const suffix = new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
    try {
      const response = await fetch("/api/runs", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ run_key: `quality-panel-${suffix}` }),
      });
      const body = (await response.json()) as { run_id?: string; error?: string };
      if (!response.ok) throw new Error(body.error ?? "Não foi possível colocar o benchmark na fila.");
      setMessage(`Benchmark ${body.run_id?.slice(0, 8) ?? ""} colocado na fila`);
      await loadRuns(session.access_token);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Falha ao criar a execução.");
    } finally {
      setSubmitting(false);
    }
  }

  async function enqueueResearch(asset: "WDOFUT" | "WINFUT") {
    if (!session) return;
    setSubmitting(true);
    const suffix = new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
    const assetSlug = asset === "WDOFUT" ? "wdo" : "win";
    try {
      const response = await fetch("/api/runs", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({
          run_key: `absorption-${assetSlug}-${suffix}`,
          run_type: "absorption_event_study_v1",
          asset,
        }),
      });
      const body = (await response.json()) as { run_id?: string; error?: string };
      if (!response.ok) throw new Error(body.error ?? "Não foi possível colocar a pesquisa na fila.");
      setMessage(`${assetSlug.toUpperCase()} absorption ${body.run_id?.slice(0, 8) ?? ""} colocado na fila`);
      await loadRuns(session.access_token);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Falha ao criar a pesquisa.");
    } finally {
      setSubmitting(false);
    }
  }

  async function reviewHypothesis(id: string, status: "under_review" | "approved_for_test" | "rejected") {
    if (!session) return;
    setReviewingHypothesis(id);
    try {
      const response = await fetch(`/api/hypotheses/${id}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ status, notes: hypothesisNotes[id] ?? "" }),
      });
      const body = (await response.json()) as { error?: string };
      if (!response.ok) throw new Error(body.error ?? "Não foi possível revisar a hipótese.");
      setMessage(`Hipótese ${status === "approved_for_test" ? "aprovada para teste" : status === "rejected" ? "rejeitada" : "marcada para revisão"}.`);
      await loadResearchStatus(session.access_token);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Falha ao revisar a hipótese.");
    } finally {
      setReviewingHypothesis(null);
    }
  }

  if (authLoading) {
    return <main className="auth-shell"><div className="auth-card"><span className="loading-mark">◌</span><p>Verificando a sessão…</p></div></main>;
  }

  if (!session) {
    return (
      <main className="auth-shell">
        <section className="auth-card" aria-labelledby="login-title">
          <div className="brand-lockup auth-brand"><span className="brand-mark" aria-hidden="true">∿</span><div><p className="brand-name">fluxo lab</p><p className="brand-subtitle">automated research</p></div></div>
          <p className="eyebrow auth-eyebrow">LAB_AUTOMATIZADO / ACESSO</p>
          <h1 id="login-title">Entre no control plane.</h1>
          <p className="auth-copy">Acompanhe workers, filas e resultados do laboratório com uma sessão autenticada.</p>
          <form className="auth-form" onSubmit={handleLogin}>
            <label htmlFor="email">E-mail</label>
            <input id="email" type="email" value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" required />
            <label htmlFor="password">Senha</label>
            <input id="password" type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="current-password" required />
            {authError ? <p className="auth-error" role="alert">{authError}</p> : null}
            <button className="primary-button auth-button" type="submit" disabled={authSubmitting}>{authSubmitting ? "Autenticando…" : "Entrar"}<span aria-hidden="true">↗</span></button>
          </form>
          <p className="auth-footnote">Usuários são gerenciados em Authentication → Users no Supabase.</p>
        </section>
      </main>
    );
  }

  return (
    <main className="shell">
      <aside className="sidebar">
        <div className="brand-lockup"><span className="brand-mark" aria-hidden="true">∿</span><div><p className="brand-name">fluxo lab</p><p className="brand-subtitle">automated research</p></div></div>
        <nav className="nav" aria-label="Navegação principal"><a className="nav-item nav-item-active" href="#overview"><span>◉</span> Overview</a><a className="nav-item" href="#runs"><span>↗</span> Execuções</a><a className="nav-item" href="#workers"><span>⌁</span> Workers</a><a className="nav-item" href="#hypotheses"><span>◇</span> Hipóteses</a><a className="nav-item" href="#artifacts"><span>▱</span> Artefatos</a></nav>
        <div className="sidebar-note"><span className="pulse-dot pulse-dot-warning" aria-hidden="true" /><div><strong>Modo laboratório</strong><p>Sem ordens · Hermes controlado</p></div></div>
        <div className="sidebar-footer"><span>LAB_AUTOMATIZADO</span><span>v0.1</span></div>
      </aside>

      <section className="content" id="overview">
        <header className="topbar"><div><p className="breadcrumb">LABORATÓRIO / CONTROL PLANE</p><h1>Pesquisas que deixam rastro.</h1></div><div className="topbar-actions"><div className="connection-state"><span className={`pulse-dot ${controlPlaneReady ? "" : "pulse-dot-warning"}`} /> {message}</div><button className="quiet-button" onClick={() => void handleLogout()}>Sair</button></div></header>
        <section className="hero-grid"><div className="hero-card"><div className="eyebrow">PRÓXIMA AÇÃO SEGURA</div><h2>Coloque uma pesquisa na fila.</h2><p>O worker reivindica uma execução por vez e grava estado, eventos, hashes e artefatos.</p><button className="primary-button" onClick={enqueueBenchmark} disabled={submitting}><span>{submitting ? "Enfileirando…" : "Iniciar quality benchmark"}</span><span aria-hidden="true">↗</span></button><div className="research-actions"><button className="quiet-button" onClick={() => void enqueueResearch("WDOFUT")} disabled={submitting}>Absorção WDO</button><button className="quiet-button" onClick={() => void enqueueResearch("WINFUT")} disabled={submitting}>Absorção WIN</button></div><p className="research-note">Estudo de evento; sem ordens, PnL ou promoção.</p></div><div className="signal-card" id="workers"><div className="eyebrow">HERMES SUPERVISOR</div><div className="signal-line"><span className="signal-bar signal-bar-bright" /><span className="signal-bar signal-bar-medium" /><span className="signal-bar signal-bar-low" /></div><div className="signal-value">{currentAgent ? (agentStatusLabel[currentAgent.status] ?? currentAgent.status) : "Indisponível"} <span>/</span> Hermes</div><p>{currentAgent ? `${agentModeLabel[currentAgent.mode] ?? currentAgent.mode} · ${currentAgent.version ?? "versão não informada"}` : "Registry ainda não respondeu."}</p></div></section>
        <section className="metrics" aria-label="Resumo das execuções"><div className="metric metric-featured"><span className="metric-label">EXECUÇÕES VISÍVEIS</span><strong>{counts.total}</strong><span className="metric-foot">últimas 50</span></div><div className="metric"><span className="metric-label">ATIVAS</span><strong>{counts.active}</strong><span className="metric-foot">aguardando ou rodando</span></div><div className="metric"><span className="metric-label">CONCLUÍDAS</span><strong>{counts.succeeded}</strong><span className="metric-foot">com resultado</span></div><div className="metric metric-text"><span className="metric-label">HERMES</span><strong>{currentAgent ? (agentStatusLabel[currentAgent.status] ?? currentAgent.status) : "—"}</strong><span className="metric-foot">{pendingHypotheses.length} hipótese(s) pendente(s)</span></div></section>
        <section className="hypotheses-section" id="hypotheses"><div className="section-heading"><div><p className="eyebrow">RESEARCH REGISTRY</p><h2>Hipóteses para revisão</h2></div><button className="quiet-button" onClick={() => session && void loadResearchStatus(session.access_token)} disabled={researchLoading}>{researchLoading ? "Atualizando…" : "Atualizar"}</button></div>{researchLoading ? <div className="empty-state"><span className="loading-mark">◌</span><div><strong>Consultando o Hermes</strong><p>Buscando estado do agente e hipóteses registradas.</p></div></div> : null}{!researchLoading && hypotheses.length === 0 ? <div className="empty-state"><span>◇</span><div><strong>Nenhuma hipótese registrada</strong><p>O Hermes ainda está desligado. Quando estiver em modo de proposta, suas hipóteses aparecerão aqui.</p></div></div> : null}{!researchLoading && hypotheses.length > 0 ? <div className="hypothesis-list">{hypotheses.map((hypothesis) => <article className="hypothesis-card" key={hypothesis.id}><div className="hypothesis-card-header"><div><p className="eyebrow">{hypothesis.family} · {hypothesis.asset ?? "ambos"}</p><h3>{hypothesis.title}</h3></div><span className={statusClass(hypothesis.status === "approved_for_test" ? "queued" : hypothesis.status === "rejected" ? "failed" : hypothesis.status === "proposed" ? "queued" : "running")}>{hypothesisStatusLabel[hypothesis.status] ?? hypothesis.status}</span></div><p className="hypothesis-summary">{hypothesis.summary}</p><div className="hypothesis-meta"><span>{hypothesis.hypothesis_key}</span><span>{formatDate(hypothesis.created_at)}</span><span>{hypothesis.agent_key}</span></div>{["proposed", "under_review"].includes(hypothesis.status) ? <div className="hypothesis-review"><input className="hypothesis-note" value={hypothesisNotes[hypothesis.id] ?? ""} onChange={(event) => setHypothesisNotes((current) => ({ ...current, [hypothesis.id]: event.target.value }))} placeholder="Nota da revisão (opcional)" aria-label={`Nota para ${hypothesis.title}`} /><div className="hypothesis-actions"><button className="quiet-button" onClick={() => void reviewHypothesis(hypothesis.id, "under_review")} disabled={reviewingHypothesis === hypothesis.id}>Revisar</button><button className="quiet-button hypothesis-approve" onClick={() => void reviewHypothesis(hypothesis.id, "approved_for_test")} disabled={reviewingHypothesis === hypothesis.id}>Aprovar para teste</button><button className="quiet-button hypothesis-reject" onClick={() => void reviewHypothesis(hypothesis.id, "rejected")} disabled={reviewingHypothesis === hypothesis.id}>Rejeitar</button></div></div> : hypothesis.review_notes ? <p className="hypothesis-review-note">Revisão: {hypothesis.review_notes}</p> : null}</article>)}</div> : null}</section>
        <section className="runs-section" id="runs"><div className="section-heading"><div><p className="eyebrow">AUDIT LOG</p><h2>Execuções recentes</h2></div><button className="quiet-button" onClick={() => session && void loadRuns(session.access_token)} disabled={loading}>{loading ? "Atualizando…" : "Atualizar"}</button></div><div className="run-table" role="table" aria-label="Execuções recentes"><div className="run-row run-row-heading" role="row"><span>Execução</span><span>Estado</span><span>Worker</span><span>Criada em</span><span>Finalizada</span></div>{runs.length === 0 && !loading ? <div className="empty-state"><span>∅</span><div><strong>Nenhuma execução ainda</strong><p>O primeiro benchmark aparecerá aqui com seu estado auditável.</p></div></div> : null}{loading ? <div className="empty-state"><span className="loading-mark">◌</span><div><strong>Consultando o control plane</strong><p>Buscando o estado mais recente da fila.</p></div></div> : null}{runs.map((run) => <div className="run-row" role="row" key={run.id}><span className="run-name"><strong>{run.run_key}</strong><small>{run.run_type}</small></span><span><span className={statusClass(run.status)}>{statusLabel[run.status] ?? run.status}</span></span><span className="mono">{run.worker_id ?? "—"}</span><span>{formatDate(run.created_at)}</span><span>{formatDate(run.finished_at)}</span></div>)}</div></section>
        <footer className="page-footer"><span>Supabase · schema privado lab_automatizado</span><span>RLS ativo · service role server-side</span></footer>
      </section>
    </main>
  );
}
