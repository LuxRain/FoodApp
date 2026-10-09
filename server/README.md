# Food Donation API

Phase 1 NestJS/PostgreSQL vertical slice implementing intake sessions, items, automatic acceptance, the donation dashboard, and admin decisions.

## Local setup

```bash
npm install
docker compose up -d postgres
psql postgres://foodapp:foodapp@localhost:55432/foodapp -f migrations/001_initial_schema.sql
psql postgres://foodapp:foodapp@localhost:55432/foodapp -f migrations/002_development_seed.sql
psql postgres://foodapp:foodapp@localhost:55432/foodapp -f migrations/003_manual_intake_code.sql
psql postgres://foodapp:foodapp@localhost:55432/foodapp -f migrations/004_intake_category.sql
psql postgres://foodapp:foodapp@localhost:55432/foodapp -f migrations/005_trust_privacy_ledger.sql
psql postgres://foodapp:foodapp@localhost:55432/foodapp -f migrations/006_nutrition_dietary_claims.sql
psql postgres://foodapp:foodapp@localhost:55432/foodapp -f migrations/007_expanded_label_claims.sql
cp .env.example .env
npm run start:dev
```

The development seed creates the demo organization, main receiving location, regular/admin users, and barcode `012345678905` for the Low-Sodium Black Beans test product. Apply it once to a new local database.
Run each migration only once. On an existing database, apply only the migrations it is missing; do not rerun earlier scripts. This development database already has migrations 006–007 applied.

## Trust, auditability, privacy, and evaluation

On submission, the server stores `intake-trust-v1`, a 0–100 score and a factor breakdown in `intake_items`. It combines barcode identity, field confidence, photo/date evidence, and package/storage checks. The score is a triage aid, **not** a food-safety clearance; the existing acceptance policy still determines admin review. Scores are recalculated only on submission and are not retroactively populated for old items. Admin review responses include the score and factors.

Creation, submission, and admin decisions append minimal events to a per-organization SHA-256 hash chain in the same database transaction as the intake change. `GET /v1/admin/ledger/verify` checks sequence, links, and head. The chain covers **new events after migration 005**, not historical intake records. This is blockchain-style *tamper-evident logging*, not a decentralized blockchain or protection against a privileged database administrator who can rewrite the chain. For stronger evidence, periodically export and independently timestamp/anchor the head hash outside this database.

An admin can call `POST /v1/admin/privacy/monthly-releases/YYYY-MM` for a **closed UTC month**. The server releases a fixed histogram of submitted-item statuses with Laplace noise (epsilon 1, change-one-item L1 sensitivity 2). It saves and reuses the same release forever, so refreshing cannot average away fresh noise. Values can be zero or differ from exact inventory. The privacy unit is one intake item; this guarantee applies **only to that aggregate release**, not to the app's exact operational endpoints, photos, or donor records. Do not use noisy counts for inventory or safety decisions.

To evaluate the proposed 40% improvement, record matched manual-baseline and assisted-workflow durations including corrections and submission. Create a CSV with header `task_id,baseline_seconds,assisted_seconds` and at least ten unique task rows, then run `npm run evaluate:intake -- /absolute/path/paired-intake-times.csv`. The script reports aggregate time reduction and a paired bootstrap 95% interval; it marks the target met only if the interval's lower bound is at least 40%. No improvement is claimed until representative measurements exist.

## Manual product entry

Items entered without a catalog match retain any scanned code for admin review. They remain pending review and do not appear as available inventory. On acceptance or quarantine, the server creates an organization-local product and inventory lot in one transaction. An unverified scanned code is not added to the trusted product-code catalog automatically.

## Package-photo evidence

The API accepts a `photo` multipart field at `POST /v1/intake-items/:itemId/evidence` after the intake item is created and before submission. JPEG, PNG, HEIC/HEIF, WebP, AVIF, GIF, and TIFF files up to 10 MB are supported, with a maximum of eight distinct photos per item. The server checks the decoded format and MIME type, limits image dimensions, and converts non-JPEG/PNG uploads to orientation-corrected JPEG (the first frame of animated files). Set `evidenceType` to `date_label` or `package_photo` (`date_label` is the default for older clients); the optional `capturedAt` field is an ISO date. Uploading identical bytes again returns the existing asset, so retrying a saved draft does not duplicate photos. The response contains the evidence ID; `GET /v1/intake-items/:itemId/evidence` lists an item's assets, and `GET /v1/intake-items/:itemId/evidence/:evidenceId` returns the private image bytes.

To test one or more package photos with the locally installed Gemma 4 model in Ollama, run:

```bash
npm run analyze:photos -- /absolute/path/front.HEIC /absolute/path/ingredients.png
```

The command accepts one to eight images in the formats above, converts them before sending them to Ollama at `http://127.0.0.1:11434`, and prints suggested fields. Set `OLLAMA_MODEL` or `OLLAMA_URL` to override the defaults. This is a local diagnostic tool; it does not save or approve an intake item. Always verify printed dates and allergens against the physical package.

The iPhone app can also send one to eight JPEG package photos to `POST /v1/photo-analysis` (multipart field `photos`). The API calls the same local Ollama model and returns nullable suggestions for product name, brand, ingredients, explicit allergen text, weight, printed-date text and type, calories, calorie basis, serving size, and visible package claims. The claim catalog covers common free-from, dietary-style, nutrition, sourcing, and religious labels; unlisted claims can be stored verbatim as other printed claims. Analysis does not create an intake item or write photos to the database. The volunteer must confirm the actual printed date and type and all package claims against the package before submission. Claims route to admin review; they are not allergy-safe guarantees. No allergen statement visible means unknown, not allergen-free. Photo-identified items also go to admin review. Start Ollama on the **API Mac** before using this feature. No Ollama port needs to be exposed to the iPhone.

Files are stored under `server/var/evidence/` by default, outside the public web root, with metadata and a SHA-256 hash in PostgreSQL. Set `EVIDENCE_STORAGE_DIR` to an absolute directory for a persistent deployment. Back up that directory together with the database. This is local pilot storage; it does not yet provide object-store replication or malware scanning. The `malware_scan_state` value is recorded as `not_scanned` rather than implying a scan occurred.

Until managed OIDC is connected, requests use development-only actor headers:

- `x-user-id`
- `x-organization-id`
- `x-role: regular_user|admin`

Mutating submit/decision requests also require `Idempotency-Key`.
Creating an intake item also requires `Idempotency-Key`; replaying a request with the same key returns the original item. The iOS saved-draft flow persists that key before sending so a retry after an app restart does not create a duplicate item.

The server is authoritative for field-confidence routing, shelf-life policy, role enforcement, urgency, inventory creation, and idempotency.
The admin review queue includes the fields needed to inspect an intake item before deciding. A quarantined lot remains unavailable; later acceptance releases the same lot, while rejection disposes it and records the outgoing movement.
