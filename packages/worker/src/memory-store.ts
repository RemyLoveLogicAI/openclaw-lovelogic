/**
 * MemoryStore contract and storage backends.
 *
 * `MemoryStoreApi` is the interface the Worker router talks to. Two backends
 * implement the key-value layer underneath it:
 *   - `InMemoryBackend`: a Map, for tests and local tooling.
 *   - `DurableObjectStorageBackend`: Durable Object storage (see index.ts,
 *     where the `MemoryStore` Durable Object wires it up for binding `MEMORY`).
 *
 * `ConsentGatedMemory` holds the consent rules, so both backends enforce
 * exactly the same checks as `MemoryKernel` in @openclaw-lovelogic/memory-kernel.
 *
 * This module must not import `cloudflare:workers`, so it can run under Node
 * (unit tests) as well as in workerd.
 */
import { isActive, type ConsentGrant } from "@openclaw-lovelogic/memory-kernel/ConsentGrant";
import type { MemoryRecord, Vector } from "@openclaw-lovelogic/memory-kernel/Kernel";

/** What the router needs from a memory store (one store per namespace). */
export interface MemoryStoreApi {
  storeMemory(grant: ConsentGrant, resourceId: string, vector: Vector): Promise<void>;
  retrieve(grant: ConsentGrant, resourceId: string): Promise<Vector | undefined>;
  /** Vector purge: irreversibly evict the memory for a resource. */
  purgeMemory(resourceId: string): Promise<boolean>;
  size(): Promise<number>;
}

/** Minimal async key-value layer a MemoryStore persists through. */
export interface MemoryBackend {
  get(key: string): Promise<MemoryRecord | undefined>;
  put(key: string, record: MemoryRecord): Promise<void>;
  delete(key: string): Promise<boolean>;
  count(prefix: string): Promise<number>;
}

/**
 * Thrown when a consent lease does not allow the operation. Across Durable
 * Object RPC the class is lost and the message arrives as
 * "ConsentError: Consent lease ...", so callers match CONSENT_ERROR_PATTERN.
 */
export class ConsentError extends Error {
  override readonly name = "ConsentError";
}

export const CONSENT_ERROR_PATTERN = /^(?:ConsentError: )?Consent lease .* (is not active|does not cover)/;

const PREFIX = "mem:";

export class ConsentGatedMemory implements MemoryStoreApi {
  constructor(
    private readonly backend: MemoryBackend,
    private readonly now: () => Date = () => new Date(),
  ) {}

  private key(resourceId: string): string {
    return `${PREFIX}${resourceId}`;
  }

  async storeMemory(grant: ConsentGrant, resourceId: string, vector: Vector): Promise<void> {
    if (grant.resourceId !== resourceId) {
      throw new ConsentError(`Consent lease ${grant.grantId} does not cover resource ${resourceId}`);
    }
    if (!isActive(grant, this.now())) {
      throw new ConsentError(`Consent lease ${grant.grantId} is not active — refusing to store`);
    }
    await this.backend.put(this.key(resourceId), { resourceId, vector: [...vector] });
  }

  async retrieve(grant: ConsentGrant, resourceId: string): Promise<Vector | undefined> {
    if (grant.resourceId !== resourceId || !isActive(grant, this.now())) return undefined;
    return (await this.backend.get(this.key(resourceId)))?.vector;
  }

  async purgeMemory(resourceId: string): Promise<boolean> {
    return this.backend.delete(this.key(resourceId));
  }

  async size(): Promise<number> {
    return this.backend.count(PREFIX);
  }
}

export class InMemoryBackend implements MemoryBackend {
  private readonly map = new Map<string, MemoryRecord>();

  async get(key: string): Promise<MemoryRecord | undefined> {
    const r = this.map.get(key);
    return r && { resourceId: r.resourceId, vector: [...r.vector] };
  }
  async put(key: string, record: MemoryRecord): Promise<void> {
    this.map.set(key, { resourceId: record.resourceId, vector: [...record.vector] });
  }
  async delete(key: string): Promise<boolean> {
    return this.map.delete(key);
  }
  async count(prefix: string): Promise<number> {
    let n = 0;
    for (const k of this.map.keys()) if (k.startsWith(prefix)) n++;
    return n;
  }
}

/** Structural subset of DurableObjectStorage used here (keeps this file free of workers types). */
export interface DurableObjectStorageLike {
  get<T>(key: string): Promise<T | undefined>;
  put<T>(key: string, value: T): Promise<void>;
  delete(key: string): Promise<boolean>;
  list<T>(options: { prefix: string }): Promise<Map<string, T>>;
}

export class DurableObjectStorageBackend implements MemoryBackend {
  constructor(private readonly storage: DurableObjectStorageLike) {}

  get(key: string): Promise<MemoryRecord | undefined> {
    return this.storage.get<MemoryRecord>(key);
  }
  put(key: string, record: MemoryRecord): Promise<void> {
    return this.storage.put(key, record);
  }
  delete(key: string): Promise<boolean> {
    return this.storage.delete(key);
  }
  async count(prefix: string): Promise<number> {
    return (await this.storage.list<MemoryRecord>({ prefix })).size;
  }
}
