import { NextRequest } from "next/server";

function serverConfig() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error("SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY não estão configurados.");
  }
  return { url: url.replace(/\/$/, ""), key };
}

export class AuthFailure extends Error {
  constructor(public readonly status: 401 | 403, message: string) {
    super(message);
  }
}

export async function authenticatedUser(request: NextRequest) {
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

export async function rpc<T>(name: string, payload: Record<string, unknown>): Promise<T> {
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
