import { describe, it, expect } from "bun:test";
import {
  applyDelta,
  applyDecay,
  createReputation,
  getTier,
  verifyBounds,
  verifyIdentity,
  MAX_SCORE,
  BASELINE_SCORE,
  type ReputationScore,
  type ReputationDelta,
  type ConsentGrant,
} from "../src/VCP/Reputation";

function makeGrant(): ConsentGrant {
  const now = new Date();
  return {
    grantId: "rep-grant",
    resourceId: "rep-1",
    granteeId: "agent-1",
    scope: "reputation",
    issuedAt: now,
    expiresAt: new Date(now.getTime() + 3600_000),
  };
}

describe("VCP Reputation (Section 8)", () => {
  it("creates reputation with baseline score", () => {
    const rep = createReputation("agent-1", "attested");
    expect(rep.score).toBe(BASELINE_SCORE);
    expect(rep.baseline).toBe(BASELINE_SCORE);
    expect(rep.verificationLevel).toBe("attested");
  });

  it("R1: bounds check rejects out-of-range scores", () => {
    expect(verifyBounds(-1)?.code).toBe("SCORE_OUT_OF_BOUNDS");
    expect(verifyBounds(MAX_SCORE + 1)?.code).toBe("SCORE_OUT_OF_BOUNDS");
    expect(verifyBounds(500)).toBeNull();
  });

  it("R3: rejects delta with inactive consent", () => {
    const rep = createReputation("agent-1", "attested");
    const expiredGrant = makeGrant();
    expiredGrant.expiresAt = new Date(Date.now() - 1000);
    const delta: ReputationDelta = {
      agentId: "agent-1",
      delta: 50,
      reason: "settlement completed",
      settlementId: "set-1",
      timestamp: new Date().toISOString(),
      signature: "sig-1",
      grant: expiredGrant,
    };
    const result = applyDelta(rep, delta);
    expect(result.error?.code).toBe("CONSENT_INACTIVE");
    expect(result.score.score).toBe(BASELINE_SCORE);
  });

  it("R5: rejects unverified agents", () => {
    const rep = createReputation("agent-1", "unverified");
    const delta: ReputationDelta = {
      agentId: "agent-1",
      delta: 50,
      reason: "settlement completed",
      settlementId: "set-1",
      timestamp: new Date().toISOString(),
      signature: "sig-1",
      grant: makeGrant(),
    };
    const result = applyDelta(rep, delta);
    expect(result.error?.code).toBe("UNVERIFIED_IDENTITY");
  });

  it("applies positive delta and updates score", () => {
    const rep = createReputation("agent-1", "attested");
    const delta: ReputationDelta = {
      agentId: "agent-1",
      delta: 50,
      reason: "settlement completed",
      settlementId: "set-1",
      timestamp: new Date().toISOString(),
      signature: "sig-1",
      grant: makeGrant(),
    };
    const result = applyDelta(rep, delta);
    expect(result.error).toBeNull();
    expect(result.score.score).toBe(BASELINE_SCORE + 50);
    expect(result.score.totalPositive).toBe(50);
  });

  it("R1: clamps score to MAX_SCORE", () => {
    const rep: ReputationScore = {
      ...createReputation("agent-1", "attested"),
      score: MAX_SCORE - 10,
    };
    const delta: ReputationDelta = {
      agentId: "agent-1",
      delta: 50,
      reason: "settlement completed",
      settlementId: "set-1",
      timestamp: new Date().toISOString(),
      signature: "sig-1",
      grant: makeGrant(),
    };
    const result = applyDelta(rep, delta);
    expect(result.error).toBeNull();
    expect(result.score.score).toBe(MAX_SCORE);
  });

  it("R2: decay moves score toward baseline", () => {
    const rep: ReputationScore = {
      ...createReputation("agent-1", "attested"),
      score: 800,
      lastDecayAt: new Date(Date.now() - 7 * 86_400_000).toISOString(), // 7 days ago
    };
    const result = applyDecay(rep);
    expect(result.error).toBeNull();
    expect(result.score.score).toBeLessThan(800);
    expect(result.score.score).toBeGreaterThan(BASELINE_SCORE);
  });

  it("R7: decay never goes below baseline", () => {
    const rep: ReputationScore = {
      ...createReputation("agent-1", "attested"),
      score: 501,
      lastDecayAt: new Date(Date.now() - 365 * 86_400_000).toISOString(), // 1 year ago
    };
    const result = applyDecay(rep);
    expect(result.score.score).toBeGreaterThanOrEqual(BASELINE_SCORE);
  });

  it("maps scores to correct tiers", () => {
    expect(getTier(100)).toBe("unproven");
    expect(getTier(300)).toBe("emerging");
    expect(getTier(500)).toBe("established");
    expect(getTier(700)).toBe("trusted");
    expect(getTier(900)).toBe("elite");
  });
});
