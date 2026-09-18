export type UserRole = "regular_user" | "admin";
export type StorageType = "shelf_stable" | "refrigerated" | "frozen" | "ambient_fresh" | "unknown";
export type DateType = "use_by" | "expiration" | "best_if_used_by" | "best_before" | "sell_by" | "freeze_by" | "packed_on" | "manufactured_on" | "unknown" | "none";
export type DateUrgency = "expired_or_past" | "due_soon" | "good" | "no_date";
export type IntakeStatus = "draft" | "ready_for_user_review" | "submitted" | "processing" | "auto_accepted" | "pending_admin_review" | "admin_accepted" | "quarantined" | "rejected";

export type AcceptanceInput = {
  productId: string | null;
  identitySource: "barcode" | "qr" | "gs1" | "image" | "manual";
  requiredFieldConfidence: number[];
  userReviewedAt: string | null;
  dateType: DateType;
  dateValue: string | null;
  remainingDays: number | null;
  storageType: StorageType;
  packageCondition: string;
  temperatureStatus: string;
  allergenConflict: boolean;
  evidenceConflict: boolean;
  duplicateSuspected: boolean;
};

export type AcceptanceResult = {
  route: "auto_accept" | "admin_review";
  reasonCodes: string[];
  minimumRemainingDays: number;
};
