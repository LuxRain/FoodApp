import assert from "node:assert/strict";
import { test } from "node:test";
import { scoreIntake, type TrustInput } from "./trust-score";

const base: TrustInput = { productId: "product", identitySource: "barcode", requiredFieldConfidence: [0.95, 0.9], dateType: "best_before", dateValue: "2027-01-01", storageType: "shelf_stable", packageCondition: "acceptable", temperatureStatus: "not_applicable", allergenConflict: false, evidenceConflict: false, duplicateSuspected: false, photoCount: 0, hasDateLabelPhoto: false };

test("trust score is versioned, bounded, and explained", () => {
  const result = scoreIntake(base);
  assert.equal(result.version, "intake-trust-v1");
  assert.ok(result.score >= 0 && result.score <= 100);
  assert.equal(result.factors.resolvedBarcode, 20);
});

test("evidence raises score, conflicts lower score", () => {
  const baseline = scoreIntake(base).score;
  assert.ok(scoreIntake({ ...base, photoCount: 2, hasDateLabelPhoto: true }).score > baseline);
  assert.ok(scoreIntake({ ...base, evidenceConflict: true }).score < baseline);
});

test("invalid confidence cannot inflate score", () => {
  assert.equal(scoreIntake({ ...base, requiredFieldConfidence: [2, -1] }).factors.fieldConfidence, 0);
});
