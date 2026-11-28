import { describe, expect, test } from "vitest";
import type { ConsentGrant } from "@openclaw-lovelogic/memory-kernel/ConsentGrant";
import {
  ConsentError,
  ConsentGatedMemory,
  DurableObjectStorageBackend,
  InMemoryBackend,
  type DurableObjectStorageLike,
} from "../src/memory-store";

const NOW = new Date("2026-06-01T00:00:00Z");
const grant = (over: Partial<ConsentGrant> = {}): ConsentGrant => ({
  grantId: "g1",
  resourceId: "persona:alice/memory:home",
  granteeId: "agent:openclaw",
  scope: "read",
  issuedAt: new Date("2026-01-01T00:00:00Z"),
  ...over,
});

/** Fake of the Durable Object storage API, to exercise the DO backend's mapping. */
class FakeDoStorage implements DurableObjectStorageLike {
  readonly data = new Map<string, unknown>();
  async get<T>(key: string) { return this.data.get(key) as T | undefined; }
  async put<T>(key: string, value: T) { this.data.set(key, structuredClone(value)); }
  async delete(key: string) { return this.data.delete(key); }
  async list<T>({ prefix }: { prefix: string }) {
    return new Map([...this.data].filter(([k]) => k.startsWith(prefix))) as Map<string, T>;
  }
}

const backends = {
  InMemoryBackend: () => new InMemoryBackend(),
  DurableObjectStorageBackend: () => new DurableObjectStorageBackend(new FakeDoStorage()),
};

for (const [name, make] of Object.entries(backends)) {
  describe(`ConsentGatedMemory on ${name}`, () => {
    test("stores and retrieves while the lease is active", async () => {
      const m = new ConsentGatedMemory(make(), () => NOW);
      const g = grant();
      await m.storeMemory(g, g.resourceId, [0.1, 0.2, 0.3]);
      expect(await m.retrieve(g, g.resourceId)).toEqual([0.1, 0.2, 0.3]);
      expect(await m.size()).toBe(1);
    });

    test("refuses to store under a revoked lease", async () => {
      const m = new ConsentGatedMemory(make(), () => NOW);
      const g = grant({ revokedAt: new Date("2026-05-01T00:00:00Z") });
      await expect(m.storeMemory(g, g.resourceId, [1])).rejects.toBeInstanceOf(ConsentError);
      expect(await m.size()).toBe(0);
    });

    test("refuses a lease for a different resource", async () => {
      const m = new ConsentGatedMemory(make(), () => NOW);
      await expect(m.storeMemory(grant(), "other", [1])).rejects.toThrow(/does not cover/);
    });

    test("hides memories once the lease expires, and purge evicts them", async () => {
      let now = NOW;
      const m = new ConsentGatedMemory(make(), () => now);
      const g = grant({ expiresAt: new Date("2026-07-01T00:00:00Z") });
      await m.storeMemory(g, g.resourceId, [1, 2]);
      now = new Date("2026-08-01T00:00:00Z");
      expect(await m.retrieve(g, g.resourceId)).toBeUndefined();
      expect(await m.purgeMemory(g.resourceId)).toBe(true);
      expect(await m.purgeMemory(g.resourceId)).toBe(false);
      expect(await m.size()).toBe(0);
    });
  });
}
