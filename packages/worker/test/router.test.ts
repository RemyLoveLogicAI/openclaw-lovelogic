import { describe, expect, test } from "vitest";
import { ConsentGatedMemory, InMemoryBackend, type MemoryStoreApi } from "../src/memory-store";
import { handleRequest, type RouterDeps } from "../src/router";

function deps(): RouterDeps {
  const stores = new Map<string, MemoryStoreApi>();
  return {
    memoryKernelUrl: "https://example.invalid",
    getStore: (ns) => {
      if (!stores.has(ns)) stores.set(ns, new ConsentGatedMemory(new InMemoryBackend()));
      return stores.get(ns)!;
    },
  };
}

const base = "https://worker.test";
const grant = (over: Record<string, unknown> = {}) => ({
  grantId: "g1", resourceId: "r1", granteeId: "agent", scope: "read", issuedAt: "2026-01-01T00:00:00Z", ...over,
});
const call = (d: RouterDeps, method: string, path: string, body?: unknown) =>
  handleRequest(new Request(base + path, { method, body: body === undefined ? undefined : JSON.stringify(body) }), d);

describe("Worker router", () => {
  test("GET /health", async () => {
    const res = await call(deps(), "GET", "/health");
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true, service: "openclaw-deploy" });
  });

  test("store -> retrieve -> stats -> purge", async () => {
    const d = deps();
    expect((await call(d, "PUT", "/v1/ns/memories/r1", { grant: grant(), vector: [1, 2] })).status).toBe(201);
    const got = await call(d, "POST", "/v1/ns/memories/r1/retrieve", { grant: grant() });
    expect(await got.json()).toEqual({ resourceId: "r1", vector: [1, 2] });
    expect(await (await call(d, "GET", "/v1/ns/stats")).json()).toEqual({ namespace: "ns", size: 1 });
    expect(await (await call(d, "DELETE", "/v1/ns/memories/r1")).json()).toEqual({ purged: true, resourceId: "r1" });
    expect((await call(d, "POST", "/v1/ns/memories/r1/retrieve", { grant: grant() })).status).toBe(404);
  });

  test("revoked grant is refused with 403", async () => {
    const res = await call(deps(), "PUT", "/v1/ns/memories/r1", {
      grant: grant({ revokedAt: "2026-01-02T00:00:00Z" }), vector: [1],
    });
    expect(res.status).toBe(403);
  });

  test("bad input is 400, unknown route is 404", async () => {
    const d = deps();
    expect((await call(d, "PUT", "/v1/ns/memories/r1", { grant: grant(), vector: [] })).status).toBe(400);
    expect((await call(d, "PUT", "/v1/ns/memories/r1", { vector: [1] })).status).toBe(400);
    expect((await call(d, "GET", "/v1/ns/nope")).status).toBe(404);
    expect((await call(d, "GET", "/v1/ns/memories/%E0%A4%A")).status).toBe(400);
  });

  test("consent errors that crossed Durable Object RPC still map to 403", async () => {
    const rpcLike: RouterDeps = {
      memoryKernelUrl: "x",
      getStore: () => ({
        storeMemory: async () => { throw new Error("ConsentError: Consent lease g9 is not active — refusing to store"); },
        retrieve: async () => undefined,
        purgeMemory: async () => false,
        size: async () => 0,
      }),
    };
    const res = await call(rpcLike, "PUT", "/v1/ns/memories/r1", { grant: grant(), vector: [1] });
    expect(res.status).toBe(403);
  });
});
