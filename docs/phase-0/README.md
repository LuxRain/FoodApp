# Phase 0 - Domain and Policy Validation

Status: proposed for admin sign-off
Owner: Admin
Created: 2026-09-17

## Purpose

Phase 0 converts the product decisions into testable operating rules before implementation begins. It is complete when an admin approves the field dictionary, workflow states, acceptance rules, and exception matrix.

## Confirmed product decisions

- The application has two roles: `regular_user` and `admin`.
- A regular user scans an item and reviews an automatically filled form. Manual input is used only when data is missing or wrong.
- High-confidence, complete, policy-compliant records may be accepted automatically.
- Low-confidence, conflicting, duplicate, or safety-sensitive records go to the admin review queue.
- The admin can correct, accept, quarantine, or reject an exception.
- Donation intake is anonymous. No donor identity, contact, address, or receipt information is collected.
- PostgreSQL is the initial system of record. There is no existing inventory-system integration.
- Open Food Facts is the initial external product-data provider, behind an adapter and cache.
- The minimum deployment target is iOS 20.0.
- Calories are recorded when available, together with their serving basis.
- Default remaining shelf life is 14 days for shelf-stable/frozen food and 7 days for refrigerated/perishable food.

## Phase 0 artifacts

1. [Field dictionary](field-dictionary.md)
2. [Workflow states](workflow-states.md)
3. [Acceptance and routing rules](acceptance-rules.md)
4. [Admin exception matrix](admin-exception-matrix.md)
5. [Donation dashboard requirements](donation-dashboard.md)

## Admin sign-off checklist

- [ ] Required fields match actual receiving operations.
- [ ] Storage categories and the 7/14-day thresholds are approved.
- [ ] Date-label handling is approved, especially sell-by, packed-on, manufactured-on, and date-less fresh food.
- [ ] Package-condition and cold-chain choices match staff training.
- [ ] The FDA major-nine allergen model and declaration types are approved.
- [ ] Initial `0.90` OCR confidence threshold is approved for the pilot.
- [ ] Image-only identification always requiring admin review is approved.
- [ ] Automatic-acceptance and admin-review reason codes are understandable.
- [ ] Quarantine and rejection procedures match the organization's physical handling process.
- [ ] Image and audit-record retention periods have been chosen.
- [ ] The dashboard's 14-day yellow window, no-date behavior, and default visibility are approved.

## External policy references

- [NTFB Food & Nutrition Policy - archived copy](https://web.archive.org/web/20250320053319id_/https://ntfb.org/wp-content/uploads/2024/07/NTFB-Food-Nutrition-Policy-revised-8.17.2021-1.pdf)
- [USDA Food Product Dating](https://www.fsis.usda.gov/food-safety/safe-food-handling-and-preparation/food-safety-basics/food-product-dating)
- [FDA Food Allergies](https://www.fda.gov/food/nutrition-food-labeling-and-critical-foods/food-allergies)
- [Open Food Facts licensing](https://openfoodfacts.github.io/openfoodfacts-server/api/tutorials/license-be-on-the-legal-side/)
