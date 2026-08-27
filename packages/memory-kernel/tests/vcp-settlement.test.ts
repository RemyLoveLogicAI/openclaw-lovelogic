import { describe, it, expect } from "bun:test";
import {
  releaseSettlement,
  refundSettlement,
  disputeSettlement,
  verifyConsent,
  verifyConservation,
  checkConditions,
  type Settlement,
  type ConsentGrant,
} from "../src/VCP/Settlement";

function makeGrant(): ConsentGrant {
  const now = new Date();
  return {
    grantId: "test-grant",
    resourceId: "res-1",
    granteeId: "agent-1",
    scope: "settlement",
    issuedAt: now,
    expiresAt: new Date(now.getTime() + 3600_000),
  };
}

function makeSettlement(overrides?: Partial<Settlement>): Settlement {
  const now = new Date();
  return {
    id: "set-1",
    payerId: "payer",
    payeeId: "payee",
    asset: { kind: "native", amount: 1000n },
    status: "pending",
    createdAt: now.toISOString(),
    updatedAt: now.toISOString(),
    releasedAt: null,
    refundedAt: null,
    expiredAt: null,
    payerGrant: makeGrant(),
    payeeGrant: makeGrant(),
    conditions: [{ id: "c1", description: "Task completed", satisfied: true, evaluatedAt: now.toISOString() }],
    idempotencyKey: "idem-1",
    challengeWindowMs: 3600_000,
    auditLog: [],
    ...overrides,
  };
}

describe("VCP Settlement (Section 7)", () => {
  it("S1: conservation holds for mixed settlements", () => {
    const s1 = makeSettlement({ status: "released", asset: { kind: "native", amount: 500n } });
    const s2 = makeSettlement({ status: "refunded", asset: { kind: "native", amount: 500n } });
    const s3 = makeSettlement({ status: "pending", asset: { kind: "native", amount: 300n } });
    // 1300 escrowed = 500 released + 500 refunded + 300 still pending
    expect(verifyConservation([s1, s2, s3])).toBe(true);
  });

  it("S2: rejects release when payer consent is revoked", () => {
    const grant = makeGrant();
    grant.revokedAt = new Date();
    const s = makeSettlement({ payerGrant: grant });
    const result = releaseSettlement(s);
    expect(result.success).toBe(false);
    expect(result.error?.code).toBe("CONSENT_REVOKED");
  });

  it("S4: rejects release when conditions are not met", () => {
    const s = makeSettlement({
      conditions: [{ id: "c1", description: "Task done", satisfied: false, evaluatedAt: null }],
    });
    const result = releaseSettlement(s);
    expect(result.success).toBe(false);
    expect(result.error?.code).toBe("CONDITIONS_NOT_MET");
  });

  it("S3: rejects double-settlement", () => {
    const s = makeSettlement({ status: "released" });
    const result = releaseSettlement(s);
    expect(result.success).toBe(false);
    expect(result.error?.code).toBe("ALREADY_SETTLED");
  });

  it("successfully releases when all invariants pass", () => {
    const s = makeSettlement();
    const result = releaseSettlement(s);
    expect(result.success).toBe(true);
    expect(s.status).toBe("released");
    expect(s.releasedAt).not.toBeNull();
    expect(s.auditLog.length).toBe(1);
  });

  it("refunds a pending settlement", () => {
    const s = makeSettlement();
    const result = refundSettlement(s, new Date(), "Payer requested refund");
    expect(result.success).toBe(true);
    expect(s.status).toBe("refunded");
  });

  it("disputes a pending settlement", () => {
    const s = makeSettlement();
    disputeSettlement(s, "Quality dispute");
    expect(s.status).toBe("disputed");
  });
});
