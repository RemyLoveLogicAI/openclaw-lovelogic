import { type ConsentGrant, isActive } from "../ConsentGrant/index";

/**
 * Validate a consent grant's current state. A grant verifies only while its
 * lease is active (not expired and not revoked).
 */
export async function verify(grant: ConsentGrant, at: Date = new Date()): Promise<boolean> {
  return isActive(grant, at);
}
