export interface ConsentGrant {
  grantId: string;
  resourceId: string;
  granteeId: string;
  scope: string;
  issuedAt: Date;
  /** Optional lease expiry. When set and in the past, the grant is expired. */
  expiresAt?: Date;
  /** Timestamp at which the lease was explicitly revoked, if any. */
  revokedAt?: Date;
}

let grantCounter = 0;

export async function issueGrant(
  resourceId: string,
  granteeId: string,
  scope: string = "read",
  leaseMs?: number,
): Promise<ConsentGrant> {
  const now = new Date();
  return {
    grantId: `grant-${++grantCounter}-${now.getTime()}`,
    resourceId,
    granteeId,
    scope,
    issuedAt: now,
    expiresAt: leaseMs !== undefined ? new Date(now.getTime() + leaseMs) : undefined,
  };
}

/**
 * Mathematically revoke a consent lease. Mutates the grant in place by stamping
 * `revokedAt` and collapsing any remaining lease window to now.
 */
export function revokeGrant(grant: ConsentGrant, at: Date = new Date()): ConsentGrant {
  grant.revokedAt = at;
  grant.expiresAt = at;
  return grant;
}

/** A grant is active only if it has not been revoked and its lease has not expired. */
export function isActive(grant: ConsentGrant, at: Date = new Date()): boolean {
  if (grant.revokedAt && at >= grant.revokedAt) return false;
  if (grant.expiresAt && at >= grant.expiresAt) return false;
  return true;
}
