/**
 * HTTP routing for the Worker, independent of `cloudflare:workers` so it can
 * be unit-tested under Node with an in-memory store.
 *
 * Routes (each namespace maps to one MemoryStore instance):
 *   GET    /health
 *   PUT    /v1/:namespace/memories/:resourceId            body: { grant, vector }
 *   POST   /v1/:namespace/memories/:resourceId/retrieve   body: { grant }
 *   DELETE /v1/:namespace/memories/:resourceId            (purge)
 *   GET    /v1/:namespace/stats
 */
import type { ConsentGrant } from "@openclaw-lovelogic/memory-kernel/ConsentGrant";
import type { Vector } from "@openclaw-lovelogic/memory-kernel/Kernel";
import { CONSENT_ERROR_PATTERN, ConsentError, type MemoryStoreApi } from "./memory-store";

export interface RouterDeps {
  /** Returns the MemoryStore for a namespace (a Durable Object stub in production). */
  getStore(namespace: string): MemoryStoreApi;
  memoryKernelUrl: string;
}

/** ConsentGrant as it travels over JSON (dates as ISO strings or epoch ms). */
export interface SerializedGrant {
  grantId: string;
  resourceId: string;
  granteeId: string;
  scope: string;
  issuedAt: string | number;
  expiresAt?: string | number;
  revokedAt?: string | number;
}

export class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

export function parseGrant(input: unknown): ConsentGrant {
  if (!input || typeof input !== "object") throw new HttpError(400, "grant is required");
  const g = input as Partial<SerializedGrant>;
  for (const key of ["grantId", "resourceId", "granteeId", "scope"] as const) {
    if (typeof g[key] !== "string" || !g[key]) throw new HttpError(400, `grant.${key} is required`);
  }
  const toDate = (v: string | number | undefined, field: string): Date | undefined => {
    if (v === undefined || v === null) return undefined;
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) throw new HttpError(400, `grant.${field} is not a valid date`);
    return d;
  };
  const issuedAt = toDate(g.issuedAt, "issuedAt");
  if (!issuedAt) throw new HttpError(400, "grant.issuedAt is required");
  return {
    grantId: g.grantId!,
    resourceId: g.resourceId!,
    granteeId: g.granteeId!,
    scope: g.scope!,
    issuedAt,
    expiresAt: toDate(g.expiresAt, "expiresAt"),
    revokedAt: toDate(g.revokedAt, "revokedAt"),
  };
}

export function parseVector(input: unknown): Vector {
  if (!Array.isArray(input) || input.length === 0 || !input.every((n) => typeof n === "number" && Number.isFinite(n))) {
    throw new HttpError(400, "vector must be a non-empty array of finite numbers");
  }
  return input as Vector;
}

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const body = await request.json();
    if (!body || typeof body !== "object") throw new Error();
    return body as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "request body must be a JSON object");
  }
}

export async function handleRequest(request: Request, deps: RouterDeps): Promise<Response> {
  try {
    const url = new URL(request.url);
    let parts: string[];
    try {
      parts = url.pathname.split("/").filter(Boolean).map(decodeURIComponent);
    } catch {
      throw new HttpError(400, "malformed path");
    }

    if (parts.length === 0 || (parts[0] === "health" && parts.length === 1)) {
      return json({ ok: true, service: "openclaw-deploy", memoryKernelUrl: deps.memoryKernelUrl });
    }

    if (parts[0] !== "v1" || parts.length < 3) throw new HttpError(404, "not found");
    const namespace = parts[1]!;
    const store = deps.getStore(namespace);

    if (parts[2] === "stats" && parts.length === 3 && request.method === "GET") {
      return json({ namespace, size: await store.size() });
    }

    if (parts[2] === "memories" && parts[3]) {
      const resourceId = parts[3];
      const action = parts[4];

      if (!action && parts.length === 4 && request.method === "PUT") {
        const body = await readJson(request);
        await store.storeMemory(parseGrant(body.grant), resourceId, parseVector(body.vector));
        return json({ stored: true, resourceId }, 201);
      }
      if (action === "retrieve" && parts.length === 5 && request.method === "POST") {
        const body = await readJson(request);
        const vector = await store.retrieve(parseGrant(body.grant), resourceId);
        return vector ? json({ resourceId, vector }) : json({ error: "not found or consent inactive" }, 404);
      }
      if (!action && parts.length === 4 && request.method === "DELETE") {
        return json({ purged: await store.purgeMemory(resourceId), resourceId });
      }
    }

    throw new HttpError(404, "not found");
  } catch (err) {
    if (err instanceof HttpError) return json({ error: err.message }, err.status);
    // Errors thrown inside the Durable Object arrive over RPC as plain Errors (class lost, message kept).
    const message = err instanceof Error ? err.message : String(err);
    if (err instanceof ConsentError || CONSENT_ERROR_PATTERN.test(message)) return json({ error: message }, 403);
    return json({ error: "internal error", dbg: message, n: (err as any)?.name }, 500);
  }
}
