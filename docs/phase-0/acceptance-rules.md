# Acceptance and Routing Rules

Status: proposed for admin sign-off
Owner: Admin
Evaluation location: server

## Evaluation contract

Rules run against an immutable submission snapshot and active versioned ruleset. Each evaluation returns:

```json
{
  "result": "auto_accept",
  "rulesetVersion": "intake-us-1.0.0",
  "evaluatedAt": "2026-09-17T19:00:00Z",
  "reasonCodes": [],
  "inputSnapshotHash": "sha256:..."
}
```

Possible results are `auto_accept` and `admin_review`. Only an admin decision can produce `quarantined` or `rejected`.

## Automatic-acceptance rules

All rules below must pass.

| Rule ID | Requirement | Failure routing code |
|---|---|---|
| `AUTO-001` | Regular user reviewed and submitted the completed form. | `USER_REVIEW_MISSING` |
| `AUTO-002` | All required fields are present and valid. | `REQUIRED_FIELD_MISSING` |
| `AUTO-003` | Product identity is based on an exact checksum-valid code/catalog match. | `IDENTITY_REVIEW_REQUIRED` |
| `AUTO-004` | Each required OCR-derived field has confidence >= `0.90`, or was confirmed from visible evidence by the regular user. | `LOW_FIELD_CONFIDENCE` |
| `AUTO-005` | Product identity was not established only by image classification. | `IMAGE_ONLY_IDENTITY` |
| `AUTO-006` | Evidence sources do not conflict. | `EVIDENCE_CONFLICT` |
| `AUTO-007` | No likely duplicate is detected. | `POSSIBLE_DUPLICATE` |
| `AUTO-008` | Package condition is `acceptable` or an approved `not_applicable`. | `PACKAGE_CONDITION_EXCEPTION` |
| `AUTO-009` | Temperature/cold-chain rule passes for the category. | `COLD_CHAIN_EXCEPTION` |
| `AUTO-010` | Recall check is `clear` when a recall source is configured. | `RECALL_REVIEW_REQUIRED` |
| `AUTO-011` | Date is unambiguous and the date type is known, or an approved date-less category rule applies. | `DATE_REVIEW_REQUIRED` |
| `AUTO-012` | Remaining shelf life meets the applicable 7/14-day threshold. | `SHELF_LIFE_BELOW_MINIMUM` |
| `AUTO-013` | Infant formula is before its printed use-by date. | `INFANT_FORMULA_DATE_FAILURE` |
| `AUTO-014` | Allergen data has a matching label version or user-confirmed package evidence, with no conflict. | `ALLERGEN_REVIEW_REQUIRED` |
| `AUTO-015` | Storage location supports the selected storage type. | `STORAGE_MISMATCH` |
| `AUTO-016` | No admin-only policy exception or blocked category applies. | `POLICY_EXCEPTION` |

## Default shelf-life rules

| Storage/category | Minimum remaining days | Date handling |
|---|---:|---|
| Shelf-stable | 14 | Use applicable printed date. Packed/manufactured-only dates require a category rule or admin review. |
| Frozen | 14 | Requires acceptable frozen-condition/cold-chain result. |
| Refrigerated | 7 | Requires acceptable refrigerated-condition/cold-chain result. |
| Perishable prepared food | 7 | Proposed default; admin must verify this is realistic for operations. |
| Ambient fresh produce | N/A by default | `date_type=none` allowed with acceptable condition; admin decides whether to require `expected_distribution_by`. |
| Infant formula | 14 proposed | Never accept after printed use-by; admin must approve the pre-expiry minimum. |

The thresholds are organizational acceptance rules, not a claim that all food becomes unsafe on a label date. Store the printed date type so quality dates are not misrepresented as safety dates.

## Confidence rules

- Confidence is field-level, never one blended item score.
- An exact validated barcode match is deterministic identity evidence; provider freshness and matching label version remain separate checks.
- Default required OCR threshold is `0.90`.
- Manual correction creates a new user assertion linked to image evidence. It does not delete the OCR assertion.
- An image-only identity always routes to admin during the pilot, regardless of model score.
- The admin may change thresholds only by activating a new ruleset version.

## Nutrition classification

Nutrition classification does not decide safety:

- Green/yellow: nutritious for NTFB-aligned reporting.
- Red: non-nutritious for that reporting model, but not automatically rejected.
- Unclassified: insufficient verified inputs; may be accepted operationally if all safety and intake rules pass, unless admin policy requires nutrition review.

Every assessment stores the ruleset version and input snapshot.

## Admin decisions

For a record in `pending_admin_review`, the admin may:

- `accept_as_submitted`;
- `correct_and_accept`;
- `request_rescan`;
- `quarantine`;
- `reject`.

Every decision requires a reason code. Free-text notes are optional except for `OTHER`.
