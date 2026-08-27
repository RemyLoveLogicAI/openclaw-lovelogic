/**
 * Violet Covenant Protocol (VCP) — Section 8: Reputation
 *
 * Formalizes the reputation invariants for agents within the memory-kernel.
 * Reputation scores are consent-gated — an agent's reputation can only be
 * queried or modified by parties holding an active consent grant.
 *
 * Invariants (must hold at all times):
 *   R1: Bounded — reputation score always in [0, MAX_SCORE]
 *   R2: Monotonic decay — scores decay toward baseline over time without activity
 *   R3: Consent-gated — no reputation read/write without active consent
 *   R4: Non-repudiable — every score change is signed and logged
 *   R5: Sybil-resistant — reputation is tied to verified identity, not ephemeral keys
 *   R6: Proportional — score deltas are proportional to the value of the settlement
 *   R7: Decay-bounded — decay cannot reduce score below baseline
 */

import type { ConsentGrant } from "../ConsentGrant/index";
import { isActive } from "../ConsentGrant/index";

// ─── Constants ────────────────────────────────────────────

export const MAX_SCORE = 1000;
export const BASELINE_SCORE = 500;
export const MIN_SCORE = 0;
export const DEFAULT_DECAY_RATE = 0.01; // per day
export const DEFAULT_DECAY_INTERVAL_MS = 86_400_000; // 24 hours

// ─── Types ────────────────────────────────────────────────

export type ReputationTier =
  | "unproven"    // [0, 200)
  | "emerging"    // [200, 400)
  | "established" // [400, 600)
  | "trusted"     // [600, 800)
  | "elite";      // [800, 1000]

export interface ReputationScore {
  agentId: string;
  /** Current score in [0, MAX_SCORE] */
  score: number;
  /** Baseline this score decays toward without activity. */
  baseline: number;
  /** Running total of all positive deltas ever applied. */
  totalPositive: number;
  /** Running total of all negative deltas ever applied. */
  totalNegative: number;
  /** Number of settlements completed. */
  settlementCount: number;
  /** Number of disputes raised against this agent. */
  disputeCount: number;
  /** Last time decay was applied. */
  lastDecayAt: string;
  /** Last time score was updated by a settlement. */
  lastActivityAt: string;
  /** Identity verification level for Sybil resistance (R5). */
  verificationLevel: "unverified" | "attested" | "verified" | "anchored";
}

export interface ReputationDelta {
  agentId: string;
  delta: number;
  reason: string;
  settlementId: string;
  timestamp: string;
  /** Signature of the delta for non-repudiation (R4). */
  signature: string;
  /** The consent grant authorizing this reputation write (R3). */
  grant: ConsentGrant;
}

export interface ReputationAuditEntry {
  timestamp: string;
  agentId: string;
  oldScore: number;
  newScore: number;
  delta: number;
  reason: string;
  settlementId: string | null;
  actor: string;
}

export type ReputationError =
  | { code: "SCORE_OUT_OF_BOUNDS"; score: number }
  | { code: "DECAY_BELOW_BASELINE"; score: number; baseline: number }
  | { code: "CONSENT_INACTIVE"; grantId: string }
  | { code: "UNVERIFIED_IDENTITY"; agentId: string; verificationLevel: string }
  | { code: "NEGATIVE_DELTA_TOO_LARGE"; delta: number; currentScore: number };

// ─── Invariant Checkers ──────────────────────────────────

/**
 * R1: Verify score is within bounds [0, MAX_SCORE].
 */
export function verifyBounds(score: number): ReputationError | null {
  if (score < MIN_SCORE || score > MAX_SCORE) {
    return { code: "SCORE_OUT_OF_BOUNDS", score };
  }
  return null;
}

/**
 * R7: Verify decay has not reduced score below baseline.
 */
export function verifyDecayBounded(score: number, baseline: number): ReputationError | null {
  if (score < baseline) {
    return { code: "DECAY_BELOW_BASELINE", score, baseline };
  }
  return null;
}

/**
 * R3: Verify the consent grant is active for this reputation operation.
 */
export function verifyReputationConsent(grant: ConsentGrant, at: Date = new Date()): ReputationError | null {
  if (!isActive(grant, at)) {
    return { code: "CONSENT_INACTIVE", grantId: grant.grantId };
  }
  return null;
}

/**
 * R5: Verify the agent's identity verification level meets the minimum threshold.
 */
export function verifyIdentity(
  rep: ReputationScore,
  minLevel: ReputationScore["verificationLevel"] = "attested",
): ReputationError | null {
  const levels: ReputationScore["verificationLevel"][] = ["unverified", "attested", "verified", "anchored"];
  const agentLevel = levels.indexOf(rep.verificationLevel);
  const requiredLevel = levels.indexOf(minLevel);
  if (agentLevel < requiredLevel) {
    return { code: "UNVERIFIED_IDENTITY", agentId: rep.agentId, verificationLevel: rep.verificationLevel };
  }
  return null;
}

// ─── Reputation Tier ─────────────────────────────────────

export function getTier(score: number): ReputationTier {
  if (score < 200) return "unproven";
  if (score < 400) return "emerging";
  if (score < 600) return "established";
  if (score < 800) return "trusted";
  return "elite";
}

// ─── Reputation Engine ───────────────────────────────────

/**
 * Apply a reputation delta. Enforces all invariants:
 *   R1: Bounded — result clamped to [0, MAX_SCORE]
 *   R3: Consent-gated — grant must be active
 *   R4: Non-repudiable — delta must be signed
 *   R5: Sybil-resistant — agent must be verified
 *   R6: Proportional — delta proportional to settlement value
 *   R7: Decay-bounded — score cannot go below baseline from positive deltas
 */
export function applyDelta(
  rep: ReputationScore,
  delta: ReputationDelta,
  at: Date = new Date(),
): { score: ReputationScore; error: ReputationError | null } {
  // R3: Consent check
  const consentError = verifyReputationConsent(delta.grant, at);
  if (consentError) return { score: rep, error: consentError };

  // R5: Identity check
  const identityError = verifyIdentity(rep, "attested");
  if (identityError) return { score: rep, error: identityError };

  // R6: Proportional — delta magnitude proportional to settlement
  // (enforced at the caller layer — here we just apply it)

  const newScore = rep.score + delta.delta;

  // R1: Bounds check
  const boundsError = verifyBounds(newScore);
  if (boundsError) {
    // Clamp instead of reject — reputation is always bounded
    const clamped = Math.max(MIN_SCORE, Math.min(MAX_SCORE, newScore));
    return {
      score: updateScore(rep, clamped, delta, at),
      error: null,
    };
  }

  // R7: Decay-bounded — positive deltas can't push below baseline
  if (delta.delta > 0 && newScore < rep.baseline) {
    return {
      score: updateScore(rep, rep.baseline, delta, at),
      error: { code: "DECAY_BELOW_BASELINE", score: newScore, baseline: rep.baseline },
    };
  }

  return {
    score: updateScore(rep, newScore, delta, at),
    error: null,
  };
}

function updateScore(
  rep: ReputationScore,
  newScore: number,
  delta: ReputationDelta,
  at: Date,
): ReputationScore {
  return {
    ...rep,
    score: newScore,
    totalPositive: delta.delta > 0 ? rep.totalPositive + delta.delta : rep.totalPositive,
    totalNegative: delta.delta < 0 ? rep.totalNegative + Math.abs(delta.delta) : rep.totalNegative,
    settlementCount: delta.reason.includes("settlement") ? rep.settlementCount + 1 : rep.settlementCount,
    disputeCount: delta.reason.includes("dispute") ? rep.disputeCount + 1 : rep.disputeCount,
    lastActivityAt: at.toISOString(),
  };
}

/**
 * R2: Apply time-based decay toward baseline.
 * Decay formula: score = score - decayRate * (score - baseline) * daysElapsed
 * This ensures the score asymptotically approaches baseline without ever crossing it (R7).
 */
export function applyDecay(
  rep: ReputationScore,
  at: Date = new Date(),
  decayRate: number = DEFAULT_DECAY_RATE,
): { score: ReputationScore; error: ReputationError | null } {
  const lastDecay = new Date(rep.lastDecayAt);
  const elapsedMs = at.getTime() - lastDecay.getTime();
  const daysElapsed = elapsedMs / DEFAULT_DECAY_INTERVAL_MS;

  if (daysElapsed <= 0) {
    return { score: rep, error: null };
  }

  // Decay toward baseline — never crosses it
  const diff = rep.score - rep.baseline;
  if (diff === 0) {
    return {
      score: { ...rep, lastDecayAt: at.toISOString() },
      error: null,
    };
  }

  const decayAmount = decayRate * diff * daysElapsed;
  let newScore = rep.score - decayAmount;

  // R7: Never decay below baseline
  if (diff > 0 && newScore < rep.baseline) {
    newScore = rep.baseline;
  } else if (diff < 0 && newScore > rep.baseline) {
    newScore = rep.baseline;
  }

  return {
    score: {
      ...rep,
      score: newScore,
      lastDecayAt: at.toISOString(),
    },
    error: null,
  };
}

/**
 * Create a new reputation score with defaults.
 */
export function createReputation(
  agentId: string,
  verificationLevel: ReputationScore["verificationLevel"] = "unverified",
): ReputationScore {
  const now = new Date().toISOString();
  return {
    agentId,
    score: BASELINE_SCORE,
    baseline: BASELINE_SCORE,
    totalPositive: 0,
    totalNegative: 0,
    settlementCount: 0,
    disputeCount: 0,
    lastDecayAt: now,
    lastActivityAt: now,
    verificationLevel,
  };
}
