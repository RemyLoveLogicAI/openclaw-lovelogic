import { describe, expect, test } from "bun:test";
import { issueGrant, revokeGrant, isActive } from "../modules/ConsentGrant/index";
import { verify } from "../modules/Verifier/index";
import { MemoryKernel, semanticDistance, type Vector } from "../modules/Kernel/index";

const RESOURCE = "persona:alice/memory:childhood-home";

// Two near-identical embeddings — a stored memory and a later re-derivation of
// "the same thought". While consent holds, they should be semantically close.
const stored: Vector = [0.9, 0.1, 0.42, 0.05];
const requery: Vector = [0.89, 0.12, 0.41, 0.06];

describe("consent-lease revocation → vector purge → semantic divergence", () => {
  test("similar embeddings are close while the lease is active", () => {
    const d = semanticDistance(stored, requery);
    expect(d).toBeLessThan(0.01);
  });

  test("a purged memory diverges to Infinity once the lease is revoked", async () => {
    const kernel = new MemoryKernel();
    const grant = await issueGrant(RESOURCE, "grantee:kernel", "read");

    // Precondition: active lease admits storage and retrieval.
    expect(isActive(grant)).toBe(true);
    expect(await verify(grant)).toBe(true);
    kernel.storeMemory(grant, RESOURCE, stored);
    expect(kernel.has(RESOURCE)).toBe(true);

    const before = kernel.retrieve(grant, RESOURCE);
    expect(before).toBeDefined();
    expect(semanticDistance(before, requery)).toBeLessThan(0.01);

    // Mathematically revoke the consent lease.
    revokeGrant(grant);
    expect(isActive(grant)).toBe(false);
    expect(await verify(grant)).toBe(false);

    // Retrieval is denied by consent even before the physical purge.
    expect(kernel.retrieve(grant, RESOURCE)).toBeUndefined();

    // Simulate the vector purge triggered by revocation.
    expect(kernel.purgeMemory(RESOURCE)).toBe(true);
    expect(kernel.has(RESOURCE)).toBe(false);
    expect(kernel.size()).toBe(0);

    // Semantic distance now diverges maximally: the purged vector is gone, so
    // there is nothing left that resembles the original memory.
    const after = kernel.retrieve(grant, RESOURCE);
    expect(after).toBeUndefined();
    expect(semanticDistance(after, requery)).toBe(Infinity);
  });

  test("an expired lease behaves like a revoked one", async () => {
    const kernel = new MemoryKernel();
    const grant = await issueGrant(RESOURCE, "grantee:kernel", "read", 50);
    const future = new Date(grant.issuedAt.getTime() + 1000);

    expect(isActive(grant, future)).toBe(false);
    expect(() => kernel.storeMemory(grant, RESOURCE, stored, future)).toThrow();
  });
});
