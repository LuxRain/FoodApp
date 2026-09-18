# Admin Exception Matrix

Status: proposed for admin sign-off

This matrix defines what the admin sees and the permitted resolution. The interface should present the evidence beside the disputed field rather than forcing the admin to reconstruct the submission.

| Trigger | Severity | Default queue priority | Evidence shown | Permitted admin actions | Suggested default |
|---|---|---:|---|---|---|
| Required OCR confidence below `0.90` | Review | Normal | Image crop, raw OCR, candidates, user value | Correct/accept, request rescan, reject | Correct from image or request rescan |
| Image-only product identity | Review | Normal | Front image, top candidates, category | Select/create product and accept, request rescan, reject | Confirm identity before accepting |
| Barcode/catalog/package conflict | Review | High | Scanned code, catalog record, package image | Choose correct version, correct/accept, quarantine | Do not accept catalog data blindly |
| Ambiguous date such as `03/04/26` | Review | High | Date crop, raw text, locale, candidate interpretations | Set date/type and accept, request rescan, quarantine/reject | Require explicit interpretation |
| Unknown date type | Review | High | Printed phrase/crop and product category | Set type and accept, request rescan, quarantine | Never silently treat as expiration |
| Shelf-life below 7/14-day threshold | Policy exception | High | Date evidence, remaining-days calculation, applicable rule | Accept with override, quarantine, reject | Follow local distribution capacity |
| Date-less approved fresh item | Review until policy approved | Normal | Product/category and condition photos | Accept, quarantine, reject | Admin decides whether this may later auto-accept |
| Infant formula on/after use-by | Safety | Urgent | Package identity and use-by evidence | Reject; quarantine pending disposal if physically held | Reject |
| Allergen sources conflict | Safety | Urgent | Label image/text, catalog declaration, versions | Correct from current label, quarantine, reject | Current visible label governs; preserve conflict |
| Allergen unknown/unreadable where label is expected | Safety | High | Ingredient/allergen-panel images | Request rescan, quarantine, reject | Do not infer absence |
| Package leaking, swollen, open, broken seal, rusted, or damaged | Safety | Urgent | Condition selections and photos | Quarantine or reject | Quarantine/reject per physical policy |
| Refrigerated/frozen cold-chain exception | Safety | Urgent | Temperature, capture time, storage/category | Quarantine or reject | Quarantine |
| Possible recall match | Safety | Urgent | Recall source, GTIN/product, lot/date match | Clear false match, quarantine, reject | Quarantine until resolved |
| Possible duplicate | Inventory | Normal | Both records, images, time/device, quantity/date/lot | Mark not duplicate and accept, merge/cancel duplicate | Never silently drop quantity |
| Storage-location mismatch | Operations | High | Required storage and selected location capabilities | Change location and accept, quarantine | Move to compatible location |
| New product/category created manually | Data quality | Normal | Submitted fields and package images | Approve/correct product and accept, request more evidence | Approve canonical product first |
| Nutrition data incomplete | Nutrition | Low | Nutrition image, catalog values, missing fields | Accept unclassified, correct, request rescan | Does not block safety unless admin rule says so |
| Red SWAP/HER tier | Nutrition | Low | Rule explanation and nutrition inputs | Accept, accept with note, reject only for separate policy reason | Do not reject solely because it is red |
| System/provider unavailable | Technical | Normal | Retry history and cached result | Retry, accept using verified manual evidence, leave pending | Prefer retry; prevent duplicate movement |

## Queue ordering

1. Urgent safety exceptions.
2. High-priority safety/operational exceptions.
3. Normal confidence, duplicate, and data-quality exceptions.
4. Low-priority nutrition completeness exceptions.

## Required audit data

Every admin decision records:

- admin user ID;
- decision and reason code;
- original submitted snapshot;
- corrected values, if any;
- evidence viewed/used;
- ruleset and model/provider versions;
- timestamp and request ID;
- resulting lot, movement, quarantine, or rejection reference.

## Admin-owned open validations

These do not block document completion, but they must be approved before production:

1. Whether prepared perishable food can realistically meet the proposed seven-day remaining-life rule.
2. Whether date-less fresh produce can auto-accept after a regular-user condition check.
3. Which categories require a measured temperature and the acceptable ranges.
4. What physical quarantine location and labeling process will be used.
5. Which recall data source will be used, if any.
6. How long package images and rejected-item evidence will be retained.
