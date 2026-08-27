/**
 * Violet Covenant Protocol (VCP) — Section 7: Settlement / Escrow
 *
 * Formalizes the settlement and escrow invariants for agent-to-agent
 * transactions within the memory-kernel. All settlements are governed
 * by consent-lease semantics — no settlement can execute without an
 * active consent grant from both parties.
 *
 * Invariants (must hold at all times):
 *   S1: Conservation — total escrowed = total released + total refunded
 *   S2: Consent-gated — no settlement without dual active consent grants
 *   S3: Idempotent — settlement(idempotencyKey) called twice = same result
 *   S4: Atomic — settlement either fully releases or fully refunds, never partial
 *   S5: Non-replayable — expired or revoked consent blocks settlement
 *   S6: Audit-trail — every state transition is logged with timestamp + actor
 */

import type { ConsentGrant } from "../ConsentGrant/index";
import { isActive } from "../ConsentGrant/index";

// ─── Types ────────────────────────────────────────────────

export type SettlementStatus =
  | "pending"      // escrow locked, awaiting conditions
  | "released"     // funds released to payee
  | "refunded"     // funds returned to payer
  | "disputed"     // challenge raised, awaiting resolution
  | "expired";     // escrow window closed without resolution

export type EscrowAsset =
  | { kind: "token"; contractAddress: string; amount: bigint }
  | { kind: "native"; amount: bigint }
  | { kind: "credit"; units: number };

export interface Settlement {
  id: string;
  payerId: string;
  payeeId: string;
  asset: EscrowAsset;
  status: SettlementStatus;
  createdAt: string;
  updatedAt: string;
  releasedAt: string | null;
  refundedAt: string | null;
  expiredAt: string | null;
  /** Both consent grants must be active for settlement to proceed. */
  payerGrant: ConsentGrant;
  payeeGrant: ConsentGrant;
  /** Settlement conditions that must ALL be true before release. */
  conditions: SettlementCondition[];
  /** Idempotency key to prevent double-settlement. */
  idempotencyKey: string;
  /** Challenge window in ms — if exceeded, auto-refund. */
  challengeWindowMs: number;
  /** Full audit trail of state transitions. */
  auditLog: SettlementAuditEntry[];
}

export interface SettlementCondition {
  id: string;
  description: string;
  satisfied: boolean;
  evaluatedAt: string | null;
}

export interface SettlementAuditEntry {
  timestamp: string;
  actor: string;
  fromStatus: SettlementStatus | null;
  toStatus: SettlementStatus;
  reason: string;
}

export interface SettlementResult {
  success: boolean;
  settlement: Settlement | null;
  error?: SettlementError;
}

export type SettlementError =
  | { code: "CONSENT_EXPIRED"; party: "payer" | "payee" }
  | { code: "CONSENT_REVOKED"; party: "payer" | "payee" }
  | { code: "CONDITIONS_NOT_MET"; unmet: string[] }
  | { code: "ALREADY_SETTLED"; status: SettlementStatus }
  | { code: "CHALLENGE_WINDOW_EXPIRED" }
  | { code: "DISPUTED"; reason: string }
  | { code: "IDEMPOTENCY_CONFLICT"; existingStatus: SettlementStatus };

// ─── Invariant Checkers ──────────────────────────────────

/**
 * S2 + S5: Verify both consent grants are active at the given time.
 * Returns the first error if either grant is inactive.
 */
export function verifyConsent(
  settlement: Settlement,
  at: Date = new Date(),
): SettlementError | null {
  if (!isActive(settlement.payerGrant, at)) {
    if (settlement.payerGrant.revokedAt) {
      return { code: "CONSENT_REVOKED", party: "payer" };
    }
    return { code: "CONSENT_EXPIRED", party: "payer" };
  }
  if (!isActive(settlement.payeeGrant, at)) {
    if (settlement.payeeGrant.revokedAt) {
      return { code: "CONSENT_REVOKED", party: "payee" };
    }
    return { code: "CONSENT_EXPIRED", party: "payee" };
  }
  return null;
}

/**
 * S4: Check that all settlement conditions are satisfied.
 * Returns the IDs of unsatisfied conditions.
 */
export function checkConditions(settlement: Settlement): string[] {
  return settlement.conditions
    .filter((c) => !c.satisfied)
    .map((c) => c.id);
}

/**
 * S1: Conservation check — for a collection of settlements, verify that
 * total escrowed = total released + total refunded.
 */
export function verifyConservation(settlements: Settlement[]): boolean {
  let escrowed = 0n;
  let released = 0n;
  let refunded = 0n;

  for (const s of settlements) {
    const amount = s.asset.kind === "credit" ? BigInt(s.asset.units) : s.asset.amount;
    escrowed += amount;
    if (s.status === "released") released += amount;
    if (s.status === "refunded") refunded += amount;
  }

  return escrowed === released + refunded;
}

/**
 * S3: Idempotency check — if a settlement with the same idempotency key
 * already exists, return the existing result rather than re-processing.
 */
export function checkIdempotency(
  existing: Settlement[],
  idempotencyKey: string,
): Settlement | null {
  return existing.find((s) => s.idempotencyKey === idempotencyKey) ?? null;
}

// ─── Settlement Engine ───────────────────────────────────

/**
 * Execute a settlement release. Enforces all invariants:
 *   - Dual consent active (S2, S5)
 *   - All conditions met (S4)
 *   - Not already settled (S3)
 *   - Challenge window not expired
 *   - Not disputed
 */
export function releaseSettlement(
  settlement: Settlement,
  at: Date = new Date(),
): SettlementResult {
  // S3: Idempotency — already settled
  if (settlement.status === "released") {
    return { success: false, settlement, error: { code: "ALREADY_SETTLED", status: "released" } };
  }
  if (settlement.status === "refunded") {
    return { success: false, settlement, error: { code: "ALREADY_SETTLED", status: "refunded" } };
  }

  // Check dispute
  if (settlement.status === "disputed") {
    return { success: false, settlement, error: { code: "DISPUTED", reason: "Settlement is under dispute" } };
  }

  // Check expiry
  if (settlement.status === "expired") {
    return { success: false, settlement, error: { code: "CHALLENGE_WINDOW_EXPIRED" } };
  }

  // S2 + S5: Verify consent
  const consentError = verifyConsent(settlement, at);
  if (consentError) {
    return { success: false, settlement, error: consentError };
  }

  // S4: Check conditions
  const unmet = checkConditions(settlement);
  if (unmet.length > 0) {
    return { success: false, settlement, error: { code: "CONDITIONS_NOT_MET", unmet } };
  }

  // Check challenge window
  const createdMs = new Date(settlement.createdAt).getTime();
  if (at.getTime() > createdMs + settlement.challengeWindowMs) {
    settlement.status = "expired";
    settlement.expiredAt = at.toISOString();
    settlement.auditLog.push({
      timestamp: at.toISOString(),
      actor: "system",
      fromStatus: "pending",
      toStatus: "expired",
      reason: "Challenge window expired",
    });
    return { success: false, settlement, error: { code: "CHALLENGE_WINDOW_EXPIRED" } };
  }

  // All invariants pass — release
  settlement.status = "released";
  settlement.releasedAt = at.toISOString();
  settlement.updatedAt = at.toISOString();
  settlement.auditLog.push({
    timestamp: at.toISOString(),
    actor: "system",
    fromStatus: "pending",
    toStatus: "released",
    reason: "All conditions met, dual consent active",
  });

  return { success: true, settlement };
}

/**
 * Execute a settlement refund. Can be triggered by:
 *   - Consent revocation by either party
 *   - Challenge window expiry
 *   - Dispute resolution in favor of payer
 */
export function refundSettlement(
  settlement: Settlement,
  at: Date = new Date(),
  reason: string = "Manual refund",
): SettlementResult {
  if (settlement.status === "released") {
    return { success: false, settlement, error: { code: "ALREADY_SETTLED", status: "released" } };
  }
  if (settlement.status === "refunded") {
    return { success: false, settlement, error: { code: "ALREADY_SETTLED", status: "refunded" } };
  }

  settlement.status = "refunded";
  settlement.refundedAt = at.toISOString();
  settlement.updatedAt = at.toISOString();
  settlement.auditLog.push({
    timestamp: at.toISOString(),
    actor: "system",
    fromStatus: settlement.auditLog.length > 0 ? settlement.auditLog[settlement.auditLog.length - 1]!.toStatus : "pending",
    toStatus: "refunded",
    reason,
  });

  return { success: true, settlement };
}

/**
 * Raise a dispute on a pending settlement.
 */
export function disputeSettlement(
  settlement: Settlement,
  reason: string,
  at: Date = new Date(),
): Settlement {
  settlement.status = "disputed";
  settlement.updatedAt = at.toISOString();
  settlement.auditLog.push({
    timestamp: at.toISOString(),
    actor: "system",
    fromStatus: "pending",
    toStatus: "disputed",
    reason,
  });
  return settlement;
}
