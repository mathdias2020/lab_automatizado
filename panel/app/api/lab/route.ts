import { NextRequest, NextResponse } from "next/server";
import { AuthFailure, authenticatedUser, rpc } from "@/lib/control-plane";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    await authenticatedUser(request);
    const [control, candidates, portfolio, health] = await Promise.all([
      rpc<unknown>("lab_automatizado_get_lab_control", {}),
      rpc<unknown[]>("lab_automatizado_list_candidates", { p_asset: null, p_limit: 100 }),
      rpc<unknown[]>("lab_automatizado_list_portfolio", { p_asset: null }),
      rpc<unknown>("lab_automatizado_get_lab_health", {}),
    ]);
    return NextResponse.json({ control, candidates, portfolio, health });
  } catch (error) {
    if (error instanceof AuthFailure) return NextResponse.json({ error: error.message }, { status: error.status });
    const message = error instanceof Error ? error.message : "Falha desconhecida.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const user = await authenticatedUser(request);
    const body = (await request.json()) as { enabled?: unknown };
    if (typeof body.enabled !== "boolean") {
      return NextResponse.json({ error: "enabled deve ser booleano." }, { status: 400 });
    }
    const control = await rpc<unknown>("lab_automatizado_set_lab_control", {
      p_enabled: body.enabled,
      p_requested_by: user.email ?? user.id ?? "panel",
    });
    return NextResponse.json({ control });
  } catch (error) {
    if (error instanceof AuthFailure) return NextResponse.json({ error: error.message }, { status: error.status });
    const message = error instanceof Error ? error.message : "Falha desconhecida.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
