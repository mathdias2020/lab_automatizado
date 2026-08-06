import { NextRequest, NextResponse } from "next/server";
import { AuthFailure, authenticatedUser, rpc } from "@/lib/control-plane";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    await authenticatedUser(request);
    const [agents, hypotheses] = await Promise.all([
      rpc<unknown[]>("lab_automatizado_list_agents", {}),
      rpc<unknown[]>("lab_automatizado_list_hypotheses", { p_limit: 50 }),
    ]);
    return NextResponse.json({ agents, hypotheses });
  } catch (error) {
    if (error instanceof AuthFailure) return NextResponse.json({ error: error.message }, { status: error.status });
    const message = error instanceof Error ? error.message : "Falha desconhecida.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
