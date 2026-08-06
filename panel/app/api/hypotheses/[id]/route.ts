import { NextRequest, NextResponse } from "next/server";
import { AuthFailure, authenticatedUser, rpc } from "@/lib/control-plane";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const reviewStatuses = new Set(["under_review", "approved_for_test", "rejected", "archived"]);

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  try {
    const user = await authenticatedUser(request);
    const { id } = await context.params;
    if (!uuidPattern.test(id)) {
      return NextResponse.json({ error: "Identificador de hipótese inválido." }, { status: 400 });
    }

    const body = (await request.json()) as { status?: unknown; notes?: unknown };
    const status = typeof body.status === "string" ? body.status : "";
    const notes = typeof body.notes === "string" ? body.notes.trim().slice(0, 2000) : "";
    if (!reviewStatuses.has(status)) {
      return NextResponse.json({ error: "Status de revisão não permitido." }, { status: 400 });
    }

    const hypothesis = await rpc<unknown>("lab_automatizado_review_hypothesis", {
      p_hypothesis_id: id,
      p_status: status,
      p_review_notes: notes,
      p_reviewed_by: user.email ?? user.id ?? "panel",
    });

    return NextResponse.json({ hypothesis });
  } catch (error) {
    if (error instanceof AuthFailure) return NextResponse.json({ error: error.message }, { status: error.status });
    const message = error instanceof Error ? error.message : "Falha desconhecida.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
