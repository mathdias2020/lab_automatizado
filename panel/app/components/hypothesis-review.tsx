"use client";

import { useCallback, useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";

type Hypothesis = {
  id: string;
  title: string;
  status: string;
};

type ReviewMessage = {
  id: string;
  author_type: "human" | "hermes" | "system";
  author_key: string;
  message_type: string;
  body: string;
  delivery_status: string;
  created_at: string;
};

type Props = {
  hypothesis: Hypothesis;
  session: Session;
  onChanged: () => Promise<void>;
  onNotify: (message: string) => void;
};

const messageTypeLabels: Record<string, string> = {
  counterargument: "Objeção",
  question: "Pergunta",
  clarification: "Esclarecimento",
  response: "Resposta do Hermes",
  revision_proposal: "Reformulação proposta",
  abandonment: "Abandono proposto",
  decision: "Decisão humana",
  system: "Sistema",
};

function formatDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

export default function HypothesisReview({ hypothesis, session, onChanged, onNotify }: Props) {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<ReviewMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [messageType, setMessageType] = useState<"counterargument" | "question" | "clarification">("counterargument");
  const [loading, setLoading] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [decisionNote, setDecisionNote] = useState("");

  const loadMessages = useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch(`/api/hypotheses/${hypothesis.id}/messages`, {
        cache: "no-store",
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      const body = (await response.json()) as { messages?: ReviewMessage[]; error?: string };
      if (!response.ok) throw new Error(body.error ?? "Não foi possível consultar a conversa.");
      setMessages(body.messages ?? []);
    } catch (error) {
      onNotify(error instanceof Error ? error.message : "Falha ao consultar a conversa.");
    } finally {
      setLoading(false);
    }
  }, [hypothesis.id, onNotify, session.access_token]);

  useEffect(() => {
    if (open) void loadMessages();
  }, [loadMessages, open]);

  async function sendMessage() {
    const message = draft.trim();
    if (!message) return;
    setSubmitting(true);
    try {
      const response = await fetch(`/api/hypotheses/${hypothesis.id}/messages`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ message, message_type: messageType }),
      });
      const body = (await response.json()) as { message?: ReviewMessage; error?: string };
      if (!response.ok) throw new Error(body.error ?? "Não foi possível enviar a mensagem.");
      setDraft("");
      setOpen(true);
      onNotify("Questionamento enviado ao Hermes.");
      await Promise.all([loadMessages(), onChanged()]);
    } catch (error) {
      onNotify(error instanceof Error ? error.message : "Falha ao enviar o questionamento.");
    } finally {
      setSubmitting(false);
    }
  }

  async function decide(status: "approved_for_test" | "rejected") {
    setSubmitting(true);
    try {
      const response = await fetch(`/api/hypotheses/${hypothesis.id}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ status, notes: decisionNote.trim() }),
      });
      const body = (await response.json()) as { error?: string };
      if (!response.ok) throw new Error(body.error ?? "Não foi possível registrar a decisão.");
      setDecisionNote("");
      onNotify(status === "approved_for_test" ? "Hipótese aprovada; teste bruto enfileirado." : "Hipótese rejeitada.");
      await Promise.all([loadMessages(), onChanged()]);
    } catch (error) {
      onNotify(error instanceof Error ? error.message : "Falha ao registrar a decisão.");
    } finally {
      setSubmitting(false);
    }
  }

  const reviewable = ["proposed", "under_review"].includes(hypothesis.status);

  return (
    <div className="hypothesis-review-panel">
      <div className="hypothesis-review-toolbar">
        <div>
          <strong>{messages.length ? `${messages.length} registro(s) na conversa` : "Ainda sem conversa"}</strong>
          <p>{reviewable ? "Questione o Hermes antes de autorizar o teste." : "Histórico preservado para auditoria."}</p>
        </div>
        <button className="quiet-button" type="button" onClick={() => setOpen((current) => !current)}>
          {open ? "Fechar conversa" : "Abrir conversa"}
        </button>
      </div>

      {open ? (
        <div className="hypothesis-review-thread">
          <div className="thread-heading">
            <span className="eyebrow">REVIEW THREAD</span>
            <button className="thread-refresh" type="button" onClick={() => void loadMessages()} disabled={loading}>
              {loading ? "Atualizando…" : "Atualizar"}
            </button>
          </div>

          <div className="thread-messages" aria-live="polite">
            {loading && messages.length === 0 ? <p className="thread-empty">Consultando o histórico…</p> : null}
            {!loading && messages.length === 0 ? <p className="thread-empty">Escreva a primeira objeção ou pergunta para o Hermes.</p> : null}
            {messages.map((message) => (
              <article className={`thread-message thread-message-${message.author_type}`} key={message.id}>
                <div className="thread-message-meta">
                  <span>{message.author_type === "hermes" ? "Hermes" : message.author_type === "human" ? "Você" : "Sistema"}</span>
                  <span>{messageTypeLabels[message.message_type] ?? message.message_type}</span>
                  <time dateTime={message.created_at}>{formatDate(message.created_at)}</time>
                </div>
                <p>{message.body}</p>
                {message.delivery_status === "pending" ? <small className="thread-pending">Aguardando resposta do Hermes</small> : null}
                {message.delivery_status === "failed" ? <small className="thread-failed">Falha na entrega — tente novamente</small> : null}
              </article>
            ))}
          </div>

          {reviewable ? (
            <div className="thread-composer">
              <div className="thread-composer-heading">
                <label htmlFor={`message-type-${hypothesis.id}`}>Tipo</label>
                <select id={`message-type-${hypothesis.id}`} value={messageType} onChange={(event) => setMessageType(event.target.value as typeof messageType)}>
                  <option value="counterargument">Objeção</option>
                  <option value="question">Pergunta</option>
                  <option value="clarification">Pedido de esclarecimento</option>
                </select>
              </div>
              <textarea value={draft} onChange={(event) => setDraft(event.target.value)} maxLength={8000} placeholder="Ex.: esse efeito pode ser apenas concentração em um horário; qual placebo ou baseline elimina essa explicação?" aria-label={`Mensagem para Hermes sobre ${hypothesis.title}`} />
              <div className="thread-composer-footer">
                <span>{draft.length}/8000</span>
                <button className="quiet-button hypothesis-approve" type="button" onClick={() => void sendMessage()} disabled={submitting || !draft.trim()}>
                  {submitting ? "Enviando…" : "Enviar ao Hermes"}
                </button>
              </div>
              <div className="decision-gate">
                <label htmlFor={`decision-note-${hypothesis.id}`}>Justificativa da decisão (opcional)</label>
                <input id={`decision-note-${hypothesis.id}`} value={decisionNote} onChange={(event) => setDecisionNote(event.target.value)} maxLength={2000} placeholder="A aprovação autoriza apenas o teste determinístico." />
                <div className="hypothesis-actions">
                  <button className="quiet-button hypothesis-approve" type="button" onClick={() => void decide("approved_for_test")} disabled={submitting}>Aprovar para teste</button>
                  <button className="quiet-button hypothesis-reject" type="button" onClick={() => void decide("rejected")} disabled={submitting}>Rejeitar</button>
                </div>
              </div>
            </div>
          ) : (
            <p className="thread-locked">Esta hipótese não aceita novas decisões neste estado.</p>
          )}
        </div>
      ) : null}
    </div>
  );
}
