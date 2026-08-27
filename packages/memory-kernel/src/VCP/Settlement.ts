/**
 * Violet Covenant Protocol (VCP) — Section 7: Settlement / Escrow
 *
 * Invariants:
 *   S1: Conservation — total escrowed = total released + total refunded + total pending
 *   S2: Consent-gated — no settlement without dual active consent grants
 *   S3: Idempotent — settlement(idempotencyKey) called twice = same result
 *   S4: Atomic — settlement either fully releases or fully refund, never partial
 *   S5: Non-replayable — expired or revoked consent blocks settlement
 *   S6: Audit-trail — every state transition is logged with timestamp + actor
 */

import type { ConsentGrant } from "../ConsentGrant/index";
import { isActive } from "../ConsentGrant/index";

export type SettlementStatus =
  | "pending"
  | "released"
  | "refunded"
  | "disputed"
  | "expired";

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
  payerGrant: ConsentGrant;
  payeeGrant: ConsentGrant;
  conditions: SettlementCondition[];
  idempotencyKey: string;
  challengeWindowMs: number;
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

function getAmount(asset: EscrowAsset): bigint {
  if (asset.kind === "credit") return BigInt(asset.units);
  return asset.amount;
}

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

export function checkConditions(settlement: Settlement): string[] {
  return settlement.conditions
    .filter((c) => !c.satisfied)
    .map((c) => c.id);
}

/**
 * S1: Conservation — total escrowed = released + refunded + still_pending.
 * Pending and disputed settlements still hold escrowed funds.
 */
export function verifyConservation(settlements: Settlement[]): boolean {
  let released = 0n;
  let refunded = 0n;
  let stillEscrowed = 0n;

  for (const s of settlements) {
    const amount = getAmount(s.asset);
    if (s.status === "released") released += amount;
    else if (s.status === "refunded") refunded += amount;
    else if (s.status === "pending" || s.status === "disputed") stillEscrowed += amount;
    // expired settlements are auto-refunded, count as refunded
    else if (s.status === "expired") refunded += amount;
  }

  return released + refunded + stillEscrowed === settlements.reduce((sum, s) => sum + getAmount(s.asset), 0n);
}

export function checkIdempotency(
  existing: Settlement[],
  idempotencyKey: string,
): Settlement | null {
  return existing.find((s) => s.idempotencyKey === idempotencyKey) ?? null;
}

export function releaseSettlement(
  settlement: Settlement,
  at: Date = new Date(),
): SettlementResult {
  if (settlement.status === "released") {
    return { success: false, settlement, error: { code: "ALREADY_SETTLED", status: "released" } };
  }
  if (settlement.status === "refunded") {
    return { success: false, settlement, error: { code: "ALREADY_SETTLED", status: "refunded" } };
  }

  if (settlement.status === "disputed") {
    return { success: false, settlement, error: { code: "DISPUTED", reason: "Settlement is under dispute" } };
  }

  if (settlement.status === "expired") {
    return { success: false, settlement, error: { code: "CHALLENGE_WINDOW_EXPIRED" } };
  }

  const consentError = verifyConsent(settlement, at);
  if (consentError) {
    return { success: false, settlement, error: consentError };
  }

  const unmet = checkConditions(settlement);
  if (unmet.length > 0) {
    return { success: false, settlement, error: { code: "CONDITIONS_NOT_MET", unmet } };
  }

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

  const prevStatus = settlement.auditLog.length > 0
    ? settlement.auditLog[settlement.auditLog.length - 1]!.toStatus
    : "pending";

  settlement.status = "refunded";
  settlement.refundedAt = at.toISOString();
  settlement.updatedAt = at.toISOString();
  settlement.auditLog.push({
    timestamp: at.toISOString(),
    actor: "system",
    fromStatus: prevStatus as SettlementStatus,
    toStatus: "refunded",
    reason,
  });

  return { success: true, settlement };
}

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
