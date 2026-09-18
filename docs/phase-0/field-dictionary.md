# Intake Field Dictionary

Status: proposed for admin sign-off
Principle: retain the final value and its evidence, source, confidence, and review history.

Legend:

- **Required:** needed before the item may be accepted automatically.
- **Auto-fill:** preferred source used to populate the form.
- **Regular edit:** whether a regular user may enter or correct the field.
- **Admin control:** behavior reserved for an admin.

## Intake context

| Field | Type | Required | Auto-fill | Regular edit | Validation and notes |
|---|---|:---:|---|:---:|---|
| `organization_id` | ID | Yes | Signed-in account | No | Server derives from authenticated membership. |
| `receiving_location_id` | ID | Yes | User's last/default location | Yes | Must be inside the user's authorized location scope. |
| `received_at` | timestamp | Yes | Device/server time | Yes | Store UTC; display in location timezone. Edits are audited. |
| `source_channel` | enum | No | Last selection | Yes | Non-identifying values only, such as `walk_in`, `food_drive`, `retail_rescue`, `other`, `unknown`. |
| `created_by` | user ID | Yes | Authenticated user | No | Never supplied as trusted client input. |
| `client_mutation_id` | UUID/ULID | Yes | Device | No | Unique per organization/device operation for idempotency. |

## Product identity

| Field | Type | Required | Auto-fill | Regular edit | Validation and notes |
|---|---|:---:|---|:---:|---|
| `code_scheme` | enum | Conditional | Scanner | No | `upc_a`, `upc_e`, `ean_8`, `ean_13`, `gtin_14`, `gs1`, `qr`, `code_128`, `none`, `unknown`. |
| `raw_code` | string | Conditional | Scanner | No | Preserve exactly as scanned; never execute arbitrary QR payloads. |
| `normalized_code` | string | Conditional | Parser | No | Validate check digit where the scheme supports it. |
| `product_id` | ID | Yes | Internal catalog/provider match | Yes | Manual product choice is audited. New-product creation may require admin review. |
| `product_name` | string | Yes | Catalog, OCR, or image candidate | Yes | 1-160 characters; image-only identity routes to admin. |
| `brand` | string | No | Catalog/OCR | Yes | Preserve source and label version. |
| `category` | controlled code | Yes | Catalog/model | Yes | Must map to approved taxonomy; manual/custom category routes to admin. |
| `food_group` | enum | No | Policy engine | No | `fruit`, `vegetable`, `grain`, `protein`, `dairy`, `mixed`, `other`, `unknown`. Admin may override with reason. |
| `label_version_id` | ID | Conditional | Catalog match | No | Required to auto-accept catalog allergens/nutrition. |

## Quantity and lot

| Field | Type | Required | Auto-fill | Regular edit | Validation and notes |
|---|---|:---:|---|:---:|---|
| `quantity` | decimal | Yes | Scan/count assistance when available | Yes | Greater than zero; maximum configured by admin. |
| `quantity_unit` | enum | Yes | Product default | Yes | `each`, `case`, `can`, `box`, `bag`, `bottle`, `lb`, `oz`, `kg`, `g`, `l`, `ml`, `other`. |
| `units_per_case` | decimal | Conditional | Catalog or package OCR | Yes | Required when `quantity_unit=case` and inventory is tracked as individual units. |
| `lot_code` | string | No/Policy | GS1/OCR | Yes | Required only for categories selected by admin. Retain exact raw text. |
| `storage_type` | enum | Yes | Catalog/category rule | Yes | `shelf_stable`, `refrigerated`, `frozen`, `ambient_fresh`, `unknown`. `unknown` routes to admin. |
| `storage_location_id` | ID | Yes | Receiving-location default | Yes | Must be compatible with `storage_type`. |

## Date information

| Field | Type | Required | Auto-fill | Regular edit | Validation and notes |
|---|---|:---:|---|:---:|---|
| `date_type` | enum | Yes | OCR + nearby label phrase | Yes | `use_by`, `expiration`, `best_if_used_by`, `best_before`, `sell_by`, `freeze_by`, `packed_on`, `manufactured_on`, `unknown`, `none`. |
| `date_value` | date | Conditional | OCR/GS1 | Yes | Required unless `date_type=none`; ambiguous numeric dates route to admin. |
| `date_precision` | enum | Yes | Parser | No | `day`, `month`, `year`, `unknown`. Non-day precision routes to admin when shelf-life cannot be established. |
| `date_label_raw` | string | Conditional | OCR | Yes | Preserve wording such as “BEST IF USED BY”. |
| `remaining_days` | integer | Derived | Server | No | `date_value - received_at` in receiving-location calendar days. |
| `minimum_remaining_days` | integer | Derived | Active rule set | No | Default 14 for shelf-stable/frozen; 7 for refrigerated/perishable. |
| `action_date` | date | Derived | Server rules | No | Date used for inventory ordering; normally equals `date_value`, but remains null when the printed date cannot support rotation. |
| `date_urgency` | enum | Derived | Server at read time | No | `expired_or_past`, `due_soon`, `good`, `no_date`; never persisted as the source of truth. |

## Condition and safety observations

| Field | Type | Required | Auto-fill | Regular edit | Validation and notes |
|---|---|:---:|---|:---:|---|
| `package_condition` | enum | Yes | None | Yes | `acceptable`, `dented_minor`, `leaking`, `swollen`, `open`, `broken_seal`, `rusted`, `damaged`, `not_applicable`, `unknown`. Anything except `acceptable`/approved `not_applicable` routes to admin. |
| `temperature_status` | enum | Conditional | Optional sensor/manual | Yes | `acceptable`, `out_of_range`, `not_measured`, `not_applicable`, `unknown`. Required for admin-configured refrigerated/frozen categories. |
| `temperature_value_c` | decimal | Conditional | Sensor/manual | Yes | Store Celsius canonically; display local preference. |
| `recall_status` | enum | Yes | Server recall check when configured | No | `clear`, `possible_match`, `unknown`, `not_checked`. Possible/unknown policy states route to admin. |
| `safety_notes` | text | No | None | Yes | Plain text; never used alone to clear a safety exception. |

## Allergens

| Field | Type | Required | Auto-fill | Regular edit | Validation and notes |
|---|---|:---:|---|:---:|---|
| `allergen_code` | enum[] | Conditional | Matching label version/OCR | Yes | FDA major nine: milk, egg, fish, crustacean shellfish, tree nuts, peanuts, wheat, soybeans, sesame. |
| `allergen_specific_name` | string[] | No | Label OCR/catalog | Yes | Preserve fish, shellfish, and tree-nut types where printed. |
| `allergen_declaration` | enum | Yes | Catalog/OCR | Yes | `contains`, `cross_contact_advisory`, `not_declared_on_label`, `unknown`. Never translate `not_declared_on_label` into “allergen-free.” |
| `allergen_label_text` | text | Conditional | OCR | Yes | Exact relevant label text; image evidence required for regular-user correction. |

## Nutrition and calories

| Field | Type | Required | Auto-fill | Regular edit | Validation and notes |
|---|---|:---:|---|:---:|---|
| `calorie_status` | enum | Yes | Catalog/OCR | Yes | `recorded`, `not_labeled`, `not_applicable`, `unknown`. Missing is never stored as zero. |
| `calories` | decimal | Conditional | Label version/OCR | Yes | Required when `calorie_status=recorded`; non-negative. |
| `calorie_basis` | enum | Conditional | Label version/OCR | Yes | `per_serving`, `per_100g`, `per_100ml`, `per_package`, `other`. |
| `serving_size` | decimal | Conditional | Label version/OCR | Yes | Required for `per_serving` when printed. |
| `serving_size_unit` | unit code | Conditional | Label version/OCR | Yes | Canonical unit plus raw label text. |
| `servings_per_container` | decimal | No | Label version/OCR | Yes | Needed before package/lot calories can be derived. |
| `derived_calories_per_package` | decimal | No | Server calculation | No | Store formula/input versions; label as calculated. |
| `nutrition_facts` | JSON/domain rows | No | Label version/OCR | Yes | Saturated fat, sodium, added/total sugar, and other values retain unit and basis. |
| `nutrition_tier` | enum | Yes | Policy engine | No | `green`, `yellow`, `red`, `unclassified`; admin override requires a reason. |
| `nutrition_descriptors` | code[] | No | Policy engine | No | NTFB-aligned descriptors such as LSU, LSA, GF, LF, WG, and packing-medium codes. |

## Evidence, confidence, and decision

| Field | Type | Required | Auto-fill | Regular edit | Validation and notes |
|---|---|:---:|---|:---:|---|
| `evidence_assets` | image refs[] | Yes | Camera | Add only | At minimum retain identity/date evidence used for a decision; use private object storage. |
| `field_assertions` | assertions[] | Yes | System | No | Value, source, confidence, model/provider version, evidence reference, reviewer, timestamp. |
| `user_reviewed_at` | timestamp | Yes | Submit action | No | Required for automatic acceptance. |
| `routing_status` | enum | Yes | Server rules | No | `auto_accept` or `admin_review`. |
| `routing_reason_codes` | code[] | Yes | Server rules | No | Empty only for auto-accepted records. |
| `disposition_status` | enum | Yes | Server/admin | No | `accepted`, `pending_admin_review`, `quarantined`, `rejected`. |
| `decision_by` | enum/ID | Yes | Server/admin | No | `system` for auto-acceptance or admin user ID. |
| `decision_reason` | code/text | Conditional | Rule/admin | No | Required for admin correction, quarantine, rejection, or override. |
