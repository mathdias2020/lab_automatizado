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
  const [session, setSession] = useState<Session | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [authSubmitting, setAuthSubmitting] = useState(false);
  const [authError, setAuthError] = useState("");
  const [runs, setRuns] = useState<Run[]>([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
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
    } else if (!authLoading) {
      setRuns([]);
      setLoading(false);
    }
  }, [authLoading, loadRuns, session]);

  const counts = useMemo(() => ({
    total: runs.length,
    active: runs.filter((run) => ["queued", "claimed", "running"].includes(run.status)).length,
    succeeded: runs.filter((run) => run.status === "succeeded").length,
  }), [runs]);
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
        <nav className="nav" aria-label="Navegação principal"><a className="nav-item nav-item-active" href="#overview"><span>◉</span> Overview</a><a className="nav-item" href="#runs"><span>↗</span> Execuções</a><a className="nav-item" href="#workers"><span>⌁</span> Workers</a><a className="nav-item" href="#artifacts"><span>▱</span> Artefatos</a></nav>
        <div className="sidebar-note"><span className="pulse-dot" aria-hidden="true" /><div><strong>Modo laboratório</strong><p>Sem ordens · sem ProfitDLL</p></div></div>
        <div className="sidebar-footer"><span>LAB_AUTOMATIZADO</span><span>v0.1</span></div>
      </aside>

      <section className="content" id="overview">
        <header className="topbar"><div><p className="breadcrumb">LABORATÓRIO / CONTROL PLANE</p><h1>Pesquisas que deixam rastro.</h1></div><div className="topbar-actions"><div className="connection-state"><span className={`pulse-dot ${controlPlaneReady ? "" : "pulse-dot-warning"}`} /> {message}</div><button className="quiet-button" onClick={() => void handleLogout()}>Sair</button></div></header>
        <section className="hero-grid"><div className="hero-card"><div className="eyebrow">PRÓXIMA AÇÃO SEGURA</div><h2>Coloque um benchmark na fila.</h2><p>O worker reivindica uma execução por vez e grava estado, eventos, hashes e artefatos.</p><button className="primary-button" onClick={enqueueBenchmark} disabled={submitting}><span>{submitting ? "Enfileirando…" : "Iniciar quality benchmark"}</span><span aria-hidden="true">↗</span></button></div><div className="signal-card" id="workers"><div className="eyebrow">SINAL DO SISTEMA</div><div className="signal-line"><span className="signal-bar signal-bar-bright" /><span className="signal-bar signal-bar-medium" /><span className="signal-bar signal-bar-low" /></div><div className="signal-value">2 vCPU <span>/</span> KVM2</div><p>Fila serializada para preservar a qualidade do experimento.</p></div></section>
        <section className="metrics" aria-label="Resumo das execuções"><div className="metric metric-featured"><span className="metric-label">EXECUÇÕES VISÍVEIS</span><strong>{counts.total}</strong><span className="metric-foot">últimas 50</span></div><div className="metric"><span className="metric-label">ATIVAS</span><strong>{counts.active}</strong><span className="metric-foot">aguardando ou rodando</span></div><div className="metric"><span className="metric-label">CONCLUÍDAS</span><strong>{counts.succeeded}</strong><span className="metric-foot">com resultado</span></div><div className="metric metric-text"><span className="metric-label">DATASET</span><strong>expanded_v1</strong><span className="metric-foot">Parquet somente leitura</span></div></section>
        <section className="runs-section" id="runs"><div className="section-heading"><div><p className="eyebrow">AUDIT LOG</p><h2>Execuções recentes</h2></div><button className="quiet-button" onClick={() => session && void loadRuns(session.access_token)} disabled={loading}>{loading ? "Atualizando…" : "Atualizar"}</button></div><div className="run-table" role="table" aria-label="Execuções recentes"><div className="run-row run-row-heading" role="row"><span>Execução</span><span>Estado</span><span>Worker</span><span>Criada em</span><span>Finalizada</span></div>{runs.length === 0 && !loading ? <div className="empty-state"><span>∅</span><div><strong>Nenhuma execução ainda</strong><p>O primeiro benchmark aparecerá aqui com seu estado auditável.</p></div></div> : null}{loading ? <div className="empty-state"><span className="loading-mark">◌</span><div><strong>Consultando o control plane</strong><p>Buscando o estado mais recente da fila.</p></div></div> : null}{runs.map((run) => <div className="run-row" role="row" key={run.id}><span className="run-name"><strong>{run.run_key}</strong><small>{run.run_type}</small></span><span><span className={statusClass(run.status)}>{statusLabel[run.status] ?? run.status}</span></span><span className="mono">{run.worker_id ?? "—"}</span><span>{formatDate(run.created_at)}</span><span>{formatDate(run.finished_at)}</span></div>)}</div></section>
        <footer className="page-footer"><span>Supabase · schema privado lab_automatizado</span><span>RLS ativo · service role server-side</span></footer>
      </section>
    </main>
  );
}
