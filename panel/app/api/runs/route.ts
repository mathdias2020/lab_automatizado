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

function authorized(request: NextRequest) {
  if (process.env.NODE_ENV !== "production" && !process.env.PANEL_INTERNAL_TOKEN) return true;
  const expected = process.env.PANEL_INTERNAL_TOKEN;
  return Boolean(expected && request.headers.get("x-panel-token") === expected);
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
  if (!authorized(request)) return NextResponse.json({ error: "Não autorizado." }, { status: 401 });

  try {
    const runs = await rpc<unknown[]>("lab_automatizado_list_runs", { p_limit: 50 });
    return NextResponse.json({ runs });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Falha desconhecida.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}

export async function POST(request: NextRequest) {
  if (!authorized(request)) return NextResponse.json({ error: "Não autorizado." }, { status: 401 });

  try {
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
      p_requested_by: "panel",
    });

    return NextResponse.json({ run_id: runId }, { status: 201 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Falha desconhecida.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
