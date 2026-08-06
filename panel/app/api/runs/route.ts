import { NextRequest, NextResponse } from "next/server";
import { AuthFailure, authenticatedUser, rpc } from "@/lib/control-plane";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

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
    const body = (await request.json()) as {
      run_key?: unknown;
      run_type?: unknown;
      asset?: unknown;
    };
    const runKey = typeof body.run_key === "string" ? body.run_key.trim() : "";
    if (!/^[a-z0-9][a-z0-9-]{2,100}$/.test(runKey)) {
      return NextResponse.json({ error: "run_key inválido." }, { status: 400 });
    }

    const requestedType = typeof body.run_type === "string" ? body.run_type : "quality_benchmark";
    if (!["quality_benchmark", "absorption_event_study_v1"].includes(requestedType)) {
      return NextResponse.json({ error: "Tipo de pesquisa não permitido nesta fase." }, { status: 400 });
    }

    const asset = typeof body.asset === "string" ? body.asset : "";
    if (requestedType === "absorption_event_study_v1" && !["WDOFUT", "WINFUT"].includes(asset)) {
      return NextResponse.json({ error: "A pesquisa exige WDOFUT ou WINFUT." }, { status: 400 });
    }

    const runType = requestedType === "quality_benchmark" ? "quality_benchmark" : "research";
    const config = requestedType === "quality_benchmark"
      ? {
          source: "panel",
          dataset_root: "/srv/labs/datasets/canonical/expanded_sample_v1/normalized",
        }
      : {
          source: "panel",
          research_id: "absorption_event_study_v1",
          asset,
          evidence_level: "predictive_event_study_pilot",
          holdout_accessed: false,
          costs_applied: false,
          trading_simulation: false,
          dataset_root: "/srv/labs/datasets/canonical/expanded_sample_v1/normalized",
        };

    const runId = await rpc<string>("lab_automatizado_enqueue_run", {
      p_run_key: runKey,
      p_run_type: runType,
      p_dataset_manifest: "expanded-sample-v1-manifest.json",
      p_config: config,
      p_requested_by: user.email ?? user.id ?? "panel",
    });

    return NextResponse.json({ run_id: runId }, { status: 201 });
  } catch (error) {
    if (error instanceof AuthFailure) return NextResponse.json({ error: error.message }, { status: error.status });
    const message = error instanceof Error ? error.message : "Falha desconhecida.";
    return NextResponse.json({ error: message }, { status: 503 });
  }
}
