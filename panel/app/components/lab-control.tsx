"use client";

import { useCallback, useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";

type Control = {
  enabled: boolean;
  mode: string;
  max_variants_per_hypothesis: number;
  max_generations: number;
  max_strategies_per_asset: number;
  target_monthly_pnl_per_contract: number;
  diagnostic_band_low: number;
  diagnostic_band_high: number;
  max_drawdown_per_contract: number;
  last_cycle_at: string | null;
  last_error: string | null;
};

type Candidate = {
  asset: string;
  status: string;
  metrics: {
    mean_monthly_pnl_per_contract?: number;
    median_monthly_pnl_per_contract?: number;
    positive_months?: number;
    months?: number;
    monthly_equity_drawdown_per_contract?: number;
  };
};

type PortfolioMember = { asset: string; slot: number; candidate_status: string };

function money(value: number | undefined) {
  const numeric = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(numeric)) return "—";
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 }).format(numeric);
}

export default function LabControl({ session }: { session: Session }) {
  const [control, setControl] = useState<Control | null>(null);
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [portfolio, setPortfolio] = useState<PortfolioMember[]>([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    try {
      const response = await fetch("/api/lab", {
        cache: "no-store",
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      const body = (await response.json()) as { control?: Control; candidates?: Candidate[]; portfolio?: PortfolioMember[]; error?: string };
      if (!response.ok) throw new Error(body.error ?? "Não foi possível consultar o ciclo.");
      setControl(body.control ?? null);
      setCandidates(body.candidates ?? []);
      setPortfolio(body.portfolio ?? []);
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Falha ao consultar o ciclo.");
    } finally {
      setLoading(false);
    }
  }, [session.access_token]);

  useEffect(() => {
    void load();
    const timer = window.setInterval(() => void load(), 15000);
    return () => window.clearInterval(timer);
  }, [load]);

  async function toggle() {
    if (!control) return;
    setSubmitting(true);
    setError("");
    try {
      const response = await fetch("/api/lab", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({ enabled: !control.enabled }),
      });
      const body = (await response.json()) as { control?: Control; error?: string };
      if (!response.ok) throw new Error(body.error ?? "Não foi possível alterar o laboratório.");
      setControl(body.control ?? control);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Falha ao alterar o laboratório.");
    } finally {
      setSubmitting(false);
    }
  }

  const wdo = candidates.filter((candidate) => candidate.asset === "WDOFUT");
  const win = candidates.filter((candidate) => candidate.asset === "WINFUT");

  return (
    <section className="lab-control-card" id="lab-control" aria-label="Controle do laboratório">
      <div className="section-heading compact-heading">
        <div><p className="eyebrow">AUTONOMOUS RESEARCH LOOP</p><h2>Laboratório</h2></div>
        <span className={`status ${control?.enabled ? "status-success" : "status-warning"}`}>{loading ? "Consultando…" : control?.enabled ? "Rodando" : "Pausado"}</span>
      </div>
      <p className="lab-control-copy">O play libera Hermes para preparar variantes e o worker para executar um backtest por vez. A promoção ao portfólio continua humana.</p>
      <div className="lab-control-actions">
        <button className="primary-button" onClick={() => void toggle()} disabled={loading || submitting || !control}>
          {submitting ? "Atualizando…" : control?.enabled ? "Pausar laboratório" : "Iniciar laboratório"}
          <span aria-hidden="true">{control?.enabled ? "Ⅱ" : "▶"}</span>
        </button>
        <span className="lab-control-hint">{control ? `${control.max_variants_per_hypothesis} variantes · ${control.max_generations} gerações · máximo ${control.max_strategies_per_asset}/ativo` : ""}</span>
      </div>
      {error ? <p className="auth-error" role="alert">{error}</p> : null}
      <div className="lab-control-grid">
        {[{ label: "WDO", list: wdo }, { label: "WIN", list: win }].map(({ label, list }) => {
          const latest = list[0];
          return <div className="lab-control-stat" key={label}><span className="metric-label">CANDIDATOS {label}</span><strong>{list.length}</strong><small>{latest ? `${money(latest.metrics.mean_monthly_pnl_per_contract)} / contrato / mês` : "aguardando primeiro resultado"}</small></div>;
        })}
        <div className="lab-control-stat"><span className="metric-label">PORTFÓLIO</span><strong>{portfolio.length} / 10</strong><small>slots preenchidos com aprovação humana</small></div>
      </div>
      <p className="lab-control-foot">Alvo: {money(control?.target_monthly_pnl_per_contract)} por contrato/mês · faixa diagnóstica {money(control?.diagnostic_band_low)}–{money(control?.diagnostic_band_high)} · DD mensal informativo até {money(control?.max_drawdown_per_contract)}.</p>
    </section>
  );
}
