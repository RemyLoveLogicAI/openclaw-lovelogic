/**
 * Cloudflare Worker entry point for OpenClaw LoveLogic.
 *
 * Exposes a small consent-gated memory API backed by the `MemoryStore`
 * Durable Object (binding `MEMORY`, see wrangler.toml). Semantics mirror
 * `MemoryKernel` from @openclaw-lovelogic/memory-kernel: memories can only be
 * stored or retrieved while their consent lease is active, and a purge evicts
 * the vector irreversibly.
 *
 * Routes (each namespace maps to one MemoryStore instance):
 *   GET    /health
 *   PUT    /v1/:namespace/memories/:resourceId   body: { grant, vector }
 *   POST   /v1/:namespace/memories/:resourceId/retrieve   body: { grant }
 *   DELETE /v1/:namespace/memories/:resourceId   (purge)
 *   GET    /v1/:namespace/stats
 */
import { DurableObject } from "cloudflare:workers";
import { isActive, type ConsentGrant } from "@openclaw-lovelogic/memory-kernel/ConsentGrant";
import type { MemoryRecord, Vector } from "@openclaw-lovelogic/memory-kernel/Kernel";

export interface Env {
  MEMORY: DurableObjectNamespace<MemoryStore>;
  MEMORY_KERNEL_URL: string;
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

function parseVector(input: unknown): Vector {
  if (!Array.isArray(input) || input.length === 0 || !input.every((n) => typeof n === "number" && Number.isFinite(n))) {
    throw new HttpError(400, "vector must be a non-empty array of finite numbers");
  }
  return input as Vector;
}

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

/**
 * Durable Object holding one namespace's memories. Persisted with the DO
 * storage API so data survives restarts; the consent checks are the same
 * ones MemoryKernel applies in-process.
 */
export class MemoryStore extends DurableObject<Env> {
  private key(resourceId: string): string {
    return `mem:${resourceId}`;
  }

  async storeMemory(grant: ConsentGrant, resourceId: string, vector: Vector): Promise<void> {
    if (grant.resourceId !== resourceId) {
      throw new HttpError(403, `Consent lease ${grant.grantId} does not cover resource ${resourceId}`);
    }
    if (!isActive(grant)) {
      throw new HttpError(403, `Consent lease ${grant.grantId} is not active — refusing to store`);
    }
    const record: MemoryRecord = { resourceId, vector: [...vector] };
    await this.ctx.storage.put(this.key(resourceId), record);
  }

  async retrieve(grant: ConsentGrant, resourceId: string): Promise<Vector | undefined> {
    if (grant.resourceId !== resourceId || !isActive(grant)) return undefined;
    const record = await this.ctx.storage.get<MemoryRecord>(this.key(resourceId));
    return record?.vector;
  }

  /** Vector purge: irreversibly evict the memory for a resource. */
  async purgeMemory(resourceId: string): Promise<boolean> {
    return this.ctx.storage.delete(this.key(resourceId));
  }

  async size(): Promise<number> {
    const all = await this.ctx.storage.list({ prefix: "mem:" });
    return all.size;
  }
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const body = await request.json();
    if (!body || typeof body !== "object") throw new Error();
    return body as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "request body must be a JSON object");
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      const parts = url.pathname.split("/").filter(Boolean).map(decodeURIComponent);

      if (parts.length === 0 || (parts[0] === "health" && parts.length === 1)) {
        return json({ ok: true, service: "openclaw-deploy", memoryKernelUrl: env.MEMORY_KERNEL_URL });
      }

      if (parts[0] !== "v1" || parts.length < 3) throw new HttpError(404, "not found");
      const namespace = parts[1]!;
      const store = env.MEMORY.get(env.MEMORY.idFromName(namespace));

      if (parts[2] === "stats" && parts.length === 3 && request.method === "GET") {
        return json({ namespace, size: await store.size() });
      }

      if (parts[2] === "memories" && parts[3]) {
        const resourceId = parts[3];
        const action = parts[4];

        if (!action && request.method === "PUT") {
          const body = await readJson(request);
          await store.storeMemory(parseGrant(body.grant), resourceId, parseVector(body.vector));
          return json({ stored: true, resourceId }, 201);
        }
        if (action === "retrieve" && parts.length === 5 && request.method === "POST") {
          const body = await readJson(request);
          const vector = await store.retrieve(parseGrant(body.grant), resourceId);
          return vector ? json({ resourceId, vector }) : json({ error: "not found or consent inactive" }, 404);
        }
        if (!action && request.method === "DELETE") {
          return json({ purged: await store.purgeMemory(resourceId), resourceId });
        }
      }

      throw new HttpError(404, "not found");
    } catch (err) {
      if (err instanceof HttpError) return json({ error: err.message }, err.status);
      // Errors thrown inside the Durable Object arrive as plain Errors over RPC.
      const message = err instanceof Error ? err.message : String(err);
      if (/Consent lease .* (is not active|does not cover)/.test(message)) return json({ error: message }, 403);
      return json({ error: "internal error" }, 500);
    }
  },
} satisfies ExportedHandler<Env>;
