import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function serverConfig() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error("SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY não estão configurados.");
  }
  return { url: url.replace(/\/$/, ""), key };
}

class AuthFailure extends Error {
  constructor(public readonly status: 401 | 403, message: string) {
    super(message);
  }
}

async function authenticatedUser(request: NextRequest) {
  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new AuthFailure(401, "Sessão ausente ou expirada.");

  const { url, key } = serverConfig();
  const response = await fetch(`${url}/auth/v1/user`, {
    cache: "no-store",
    headers: {
      apikey: key,
      Authorization: `Bearer ${match[1]}`,
    },
  });

  if (!response.ok) throw new AuthFailure(401, "Sessão ausente ou expirada.");

  const user = (await response.json()) as { id?: string; email?: string | null };
  const allowedEmails = (process.env.PANEL_ALLOWED_EMAILS ?? "")
    .split(",")
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean);

  if (allowedEmails.length > 0 && (!user.email || !allowedEmails.includes(user.email.toLowerCase()))) {
    throw new AuthFailure(403, "Este usuário não está autorizado para este laboratório.");
  }

  return user;
}

async function rpc<T>(name: string, payload: Record<string, unknown>): Promise<T> {
  const { url, key } = serverConfig();
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    cache: "no-store",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Supabase RPC ${name} falhou (${response.status}): ${detail.slice(0, 300)}`);
  }
  return (await response.json()) as T;
}

export async function GET(request: NextRequest) {
  try {
    await authenticatedUser(request);
    const runs = await rpc<unknown[]>("lab_automatizado_list_runs", { p_limit: 50 });
    return NextResponse.json({ runs });
  } catch (error) {
    if (error instanceof AuthFailure) return NextResponse.json({ error: error.message }, { status: error.status });
    const message = error instanceof Error ? error.message : "Falha desconhecida.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const user = await authenticatedUser(request);
    const body = (await request.json()) as { run_key?: unknown };
    const runKey = typeof body.run_key === "string" ? body.run_key.trim() : "";
    if (!/^[a-z0-9][a-z0-9-]{2,100}$/.test(runKey)) {
      return NextResponse.json({ error: "run_key inválido." }, { status: 400 });
    }

    const runId = await rpc<string>("lab_automatizado_enqueue_run", {
      p_run_key: runKey,
      p_run_type: "quality_benchmark",
      p_dataset_manifest: "expanded-sample-v1-manifest.json",
      p_config: {
        source: "panel",
        dataset_root: "/srv/labs/datasets/canonical/expanded_sample_v1/normalized",
      },
      p_requested_by: user.email ?? user.id ?? "panel",
    });

    return NextResponse.json({ run_id: runId }, { status: 201 });
  } catch (error) {
    if (error instanceof AuthFailure) return NextResponse.json({ error: error.message }, { status: error.status });
    const message = error instanceof Error ? error.message : "Falha desconhecida.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
