import { type ConsentGrant, isActive } from "../ConsentGrant/index";

export type Vector = number[];

export interface MemoryRecord {
  resourceId: string;
  vector: Vector;
}

/**
 * Cosine distance in [0, 2]: 0 = identical direction, 1 = orthogonal, 2 = opposite.
 * Returns Infinity when either operand is missing (e.g. after a purge), which is
 * how a purged memory registers as maximally divergent.
 */
export function semanticDistance(a: Vector | undefined, b: Vector | undefined): number {
  if (!a || !b || a.length === 0 || b.length === 0 || a.length !== b.length) {
    return Infinity;
  }
  let dot = 0;
  let magA = 0;
  let magB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i]! * b[i]!;
    magA += a[i]! * a[i]!;
    magB += b[i]! * b[i]!;
  }
  if (magA === 0 || magB === 0) return Infinity;
  const cosine = dot / (Math.sqrt(magA) * Math.sqrt(magB));
  return 1 - cosine;
}

/**
 * In-memory vector store gated by consent. Memories can only be stored or
 * retrieved while their governing consent lease is active; purging removes the
 * vector entirely so subsequent retrieval and distance checks diverge.
 */
export class MemoryKernel {
  private store = new Map<string, MemoryRecord>();

  storeMemory(grant: ConsentGrant, resourceId: string, vector: Vector, at: Date = new Date()): void {
    if (!isActive(grant, at)) {
      throw new Error(`Consent lease ${grant.grantId} is not active — refusing to store`);
    }
    this.store.set(resourceId, { resourceId, vector: [...vector] });
  }

  retrieve(grant: ConsentGrant, resourceId: string, at: Date = new Date()): Vector | undefined {
    if (!isActive(grant, at)) return undefined;
    return this.store.get(resourceId)?.vector;
  }

  /** Vector purge: irreversibly evict the memory for a resource. */
  purgeMemory(resourceId: string): boolean {
    return this.store.delete(resourceId);
  }

  /** Raw presence check, independent of consent state (for assertions/inspection). */
  has(resourceId: string): boolean {
    return this.store.has(resourceId);
  }

  size(): number {
    return this.store.size;
  }
}

export async function processMemory(input: string): Promise<void> {
  // Skeleton implementation
  console.log("Kernel processing memory:", input);
}
