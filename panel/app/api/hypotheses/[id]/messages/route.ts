import { NextRequest, NextResponse } from "next/server";
import { AuthFailure, authenticatedUser, rpc } from "@/lib/control-plane";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const humanMessageTypes = new Set(["counterargument", "question", "clarification"]);

async function hypothesisId(context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return uuidPattern.test(id) ? id : null;
}

export async function GET(
  request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  try {
    await authenticatedUser(request);
    const id = await hypothesisId(context);
    if (!id) return NextResponse.json({ error: "Identificador de hipótese inválido." }, { status: 400 });
    const messages = await rpc<unknown[]>("lab_automatizado_list_hypothesis_messages", {
      p_hypothesis_id: id,
      p_limit: 200,
    });
    return NextResponse.json({ messages });
  } catch (error) {
    if (error instanceof AuthFailure) return NextResponse.json({ error: error.message }, { status: error.status });
    const message = error instanceof Error ? error.message : "Falha desconhecida.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  try {
    const user = await authenticatedUser(request);
    const id = await hypothesisId(context);
    if (!id) return NextResponse.json({ error: "Identificador de hipótese inválido." }, { status: 400 });
    const body = (await request.json()) as {
      message?: unknown;
      message_type?: unknown;
      parent_message_id?: unknown;
    };
    const message = typeof body.message === "string" ? body.message.trim().slice(0, 8000) : "";
    const messageType = typeof body.message_type === "string" ? body.message_type : "";
    const parentMessageId = typeof body.parent_message_id === "string" ? body.parent_message_id : null;

    if (!message) return NextResponse.json({ error: "A mensagem não pode ficar vazia." }, { status: 400 });
    if (!humanMessageTypes.has(messageType)) return NextResponse.json({ error: "Tipo de mensagem inválido." }, { status: 400 });
    if (parentMessageId && !uuidPattern.test(parentMessageId)) return NextResponse.json({ error: "Mensagem pai inválida." }, { status: 400 });

    const created = await rpc<unknown>("lab_automatizado_post_hypothesis_message", {
      p_hypothesis_id: id,
      p_author_key: user.email ?? user.id ?? "panel",
      p_message_type: messageType,
      p_body: message,
      p_parent_message_id: parentMessageId,
    });
    return NextResponse.json({ message: created }, { status: 201 });
  } catch (error) {
    if (error instanceof AuthFailure) return NextResponse.json({ error: error.message }, { status: error.status });
    const message = error instanceof Error ? error.message : "Falha desconhecida.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
