import assert from "node:assert/strict";
import test from "node:test";
import { calculateUrgency, evaluateAcceptance, minimumRemainingDays } from "./policy";
import type { AcceptanceInput } from "./types";

const validInput: AcceptanceInput = {
  productId: "product-1", identitySource: "barcode", requiredFieldConfidence: [0.99, 0.95],
  userReviewedAt: "2026-09-17T18:00:00Z", dateType: "best_if_used_by", dateValue: "2026-10-14",
  remainingDays: 27, storageType: "shelf_stable", packageCondition: "acceptable",
  temperatureStatus: "not_applicable", allergenConflict: false, evidenceConflict: false, duplicateSuspected: false,
};

test("urgency implements the dashboard boundaries", () => {
  assert.equal(calculateUrgency(-1), "expired_or_past");
  assert.equal(calculateUrgency(0), "due_soon");
  assert.equal(calculateUrgency(14), "due_soon");
  assert.equal(calculateUrgency(15), "good");
  assert.equal(calculateUrgency(null), "no_date");
});

test("storage-specific shelf-life defaults are preserved", () => {
  assert.equal(minimumRemainingDays("shelf_stable"), 14);
  assert.equal(minimumRemainingDays("frozen"), 14);
  assert.equal(minimumRemainingDays("refrigerated"), 7);
});

test("a complete high-confidence barcode intake auto accepts", () => {
  assert.deepEqual(evaluateAcceptance(validInput), { route: "auto_accept", reasonCodes: [], minimumRemainingDays: 14 });
});

test("image-only and shelf-life exceptions route to admin with explicit reasons", () => {
  const result = evaluateAcceptance({ ...validInput, identitySource: "image", remainingDays: 6 });
  assert.equal(result.route, "admin_review");
  assert.deepEqual(result.reasonCodes, ["IMAGE_ONLY_IDENTITY", "SHELF_LIFE_EXCEPTION"]);
});
