import type { AcceptanceInput } from "../domain/types";

export const TRUST_ALGORITHM_VERSION = "intake-trust-v1";

export type TrustInput = Pick<AcceptanceInput, "productId" | "identitySource" | "requiredFieldConfidence" | "dateType" | "dateValue" | "storageType" | "packageCondition" | "temperatureStatus" | "allergenConflict" | "evidenceConflict" | "duplicateSuspected"> & {
  photoCount: number;
  hasDateLabelPhoto: boolean;
};

export function scoreIntake(input: TrustInput) {
  const confidence = input.requiredFieldConfidence.filter((value) => Number.isFinite(value) && value >= 0 && value <= 1);
  const meanConfidence = confidence.length ? confidence.reduce((sum, value) => sum + value, 0) / confidence.length : 0;
  const factors = {
    resolvedBarcode: Boolean(input.productId && ["barcode", "qr", "gs1"].includes(input.identitySource)) ? 20 : 0,
    fieldConfidence: Math.round(meanConfidence * 20),
    photoEvidence: Math.min(Math.max(input.photoCount, 0), 2) * 5,
    dateLabelPhoto: input.hasDateLabelPhoto ? 5 : 0,
    dateClarity: input.dateType !== "unknown" && (input.dateType === "none" || Boolean(input.dateValue)) ? 15 : 0,
    storageKnown: input.storageType !== "unknown" ? 10 : 0,
    packageSafe: ["acceptable", "not_applicable"].includes(input.packageCondition) ? 10 : 0,
    temperatureSafe: !["out_of_range", "unknown"].includes(input.temperatureStatus) ? 10 : 0,
    conflicts: [input.allergenConflict, input.evidenceConflict, input.duplicateSuspected].filter(Boolean).length * -15,
  };
  const score = Math.max(0, Math.min(100, Object.values(factors).reduce((sum, value) => sum + value, 0)));
  return { score, factors, version: TRUST_ALGORITHM_VERSION };
}
