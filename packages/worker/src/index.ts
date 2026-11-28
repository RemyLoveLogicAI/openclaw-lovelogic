/**
 * Cloudflare Worker entry point for OpenClaw LoveLogic (wrangler.toml `main`).
 *
 * Exports the default `fetch` handler and the `MemoryStore` Durable Object
 * class bound as `MEMORY`. Routing lives in ./router.ts and the consent rules
 * in ./memory-store.ts; both mirror `MemoryKernel` from
 * @openclaw-lovelogic/memory-kernel: memories can only be stored or retrieved
 * while their consent lease is active, and a purge evicts the vector.
 */
import { DurableObject } from "cloudflare:workers";
import type { ConsentGrant } from "@openclaw-lovelogic/memory-kernel/ConsentGrant";
import type { Vector } from "@openclaw-lovelogic/memory-kernel/Kernel";
import {
  ConsentGatedMemory,
  DurableObjectStorageBackend,
  type MemoryStoreApi,
} from "./memory-store";
import { handleRequest } from "./router";

export { parseGrant, type SerializedGrant } from "./router";
export type { MemoryStoreApi, MemoryBackend } from "./memory-store";

export interface Env {
  MEMORY: DurableObjectNamespace<MemoryStore>;
  MEMORY_KERNEL_URL: string;
}

/**
 * Durable Object holding one namespace's memories, persisted in Durable Object
 * (SQLite-backed) storage so data survives restarts and evictions.
 */
export class MemoryStore extends DurableObject<Env> implements MemoryStoreApi {
  private readonly memory: ConsentGatedMemory;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.memory = new ConsentGatedMemory(new DurableObjectStorageBackend(ctx.storage));
  }

  storeMemory(grant: ConsentGrant, resourceId: string, vector: Vector): Promise<void> {
    return this.memory.storeMemory(grant, resourceId, vector);
  }

  retrieve(grant: ConsentGrant, resourceId: string): Promise<Vector | undefined> {
    return this.memory.retrieve(grant, resourceId);
  }

  purgeMemory(resourceId: string): Promise<boolean> {
    return this.memory.purgeMemory(resourceId);
  }

  size(): Promise<number> {
    return this.memory.size();
  }
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, {
      memoryKernelUrl: env.MEMORY_KERNEL_URL,
      // The stub exposes MemoryStore's RPC methods; their runtime shape matches MemoryStoreApi.
      getStore: (namespace) => env.MEMORY.get(env.MEMORY.idFromName(namespace)) as unknown as MemoryStoreApi,
    });
  },
} satisfies ExportedHandler<Env>;
