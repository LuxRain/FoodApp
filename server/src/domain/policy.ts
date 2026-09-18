import type { AcceptanceInput, AcceptanceResult, DateUrgency, StorageType } from "./types";

export const DEFAULT_CONFIDENCE_THRESHOLD = 0.9;

export function minimumRemainingDays(storageType: StorageType): number {
  return storageType === "refrigerated" || storageType === "ambient_fresh" ? 7 : 14;
}

export function calculateUrgency(daysRemaining: number | null): DateUrgency {
  if (daysRemaining === null) return "no_date";
  if (daysRemaining < 0) return "expired_or_past";
  if (daysRemaining <= 14) return "due_soon";
  return "good";
}

export function evaluateAcceptance(input: AcceptanceInput): AcceptanceResult {
  const reasons = new Set<string>();
  const minimum = minimumRemainingDays(input.storageType);

  if (!input.productId) reasons.add("PRODUCT_UNRESOLVED");
  if (input.identitySource === "image") reasons.add("IMAGE_ONLY_IDENTITY");
  if (!input.userReviewedAt) reasons.add("USER_REVIEW_REQUIRED");
  if (input.requiredFieldConfidence.some((confidence) => confidence < DEFAULT_CONFIDENCE_THRESHOLD)) reasons.add("LOW_FIELD_CONFIDENCE");
  if (input.dateType === "unknown") reasons.add("AMBIGUOUS_DATE_TYPE");
  if (input.dateType !== "none" && !input.dateValue) reasons.add("DATE_REQUIRED");
  if (input.remainingDays !== null && input.remainingDays < minimum) reasons.add("SHELF_LIFE_EXCEPTION");
  if (input.storageType === "unknown") reasons.add("STORAGE_UNKNOWN");
  if (!["acceptable", "not_applicable"].includes(input.packageCondition)) reasons.add("PACKAGE_CONDITION_EXCEPTION");
  if (["out_of_range", "unknown"].includes(input.temperatureStatus)) reasons.add("TEMPERATURE_EXCEPTION");
  if (input.allergenConflict) reasons.add("ALLERGEN_CONFLICT");
  if (input.evidenceConflict) reasons.add("EVIDENCE_CONFLICT");
  if (input.duplicateSuspected) reasons.add("DUPLICATE_SUSPECTED");

  return { route: reasons.size === 0 ? "auto_accept" : "admin_review", reasonCodes: [...reasons], minimumRemainingDays: minimum };
}
