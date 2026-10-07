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
cp .env.example .env
npm run start:dev
```

The development seed creates the demo organization, main receiving location, regular/admin users, and barcode `012345678905` for the Low-Sodium Black Beans test product. Apply it once to a new local database.
Run each migration only once. If your database already has migrations 001–003, apply only `004_intake_category.sql`; do not rerun the earlier scripts.

## Manual product entry

Items entered without a catalog match retain any scanned code for admin review. They remain pending review and do not appear as available inventory. On acceptance or quarantine, the server creates an organization-local product and inventory lot in one transaction. An unverified scanned code is not added to the trusted product-code catalog automatically.

## Package-photo evidence

The API accepts a `photo` multipart field at `POST /v1/intake-items/:itemId/evidence` after the intake item is created and before submission. JPEG, PNG, HEIC/HEIF, WebP, AVIF, GIF, and TIFF files up to 10 MB are supported, with a maximum of eight distinct photos per item. The server checks the decoded format and MIME type, limits image dimensions, and converts non-JPEG/PNG uploads to orientation-corrected JPEG (the first frame of animated files). Set `evidenceType` to `date_label` or `package_photo` (`date_label` is the default for older clients); the optional `capturedAt` field is an ISO date. Uploading identical bytes again returns the existing asset, so retrying a saved draft does not duplicate photos. The response contains the evidence ID; `GET /v1/intake-items/:itemId/evidence` lists an item's assets, and `GET /v1/intake-items/:itemId/evidence/:evidenceId` returns the private image bytes.

To test one or more package photos with the locally installed Gemma 4 model in Ollama, run:

```bash
npm run analyze:photos -- /absolute/path/front.HEIC /absolute/path/ingredients.png
```

The command accepts one to eight images in the formats above, converts them before sending them to Ollama at `http://127.0.0.1:11434`, and prints suggested fields. Set `OLLAMA_MODEL` or `OLLAMA_URL` to override the defaults. This is a local diagnostic tool; it does not save or approve an intake item. Always verify printed dates and allergens against the physical package.

The iPhone app can also send one to eight JPEG package photos to `POST /v1/photo-analysis` (multipart field `photos`). The API calls the same local Ollama model and returns nullable suggestions for product name, brand, ingredients, allergens, weight, and printed-date text. Analysis does not create an intake item or write photos to the database. The volunteer must explicitly apply the product/brand suggestion and confirm the printed date; photo-identified items go to admin review rather than automatic acceptance. Start Ollama on the **API Mac** before using this feature. No Ollama port needs to be exposed to the iPhone.

Files are stored under `server/var/evidence/` by default, outside the public web root, with metadata and a SHA-256 hash in PostgreSQL. Set `EVIDENCE_STORAGE_DIR` to an absolute directory for a persistent deployment. Back up that directory together with the database. This is local pilot storage; it does not yet provide object-store replication or malware scanning. The `malware_scan_state` value is recorded as `not_scanned` rather than implying a scan occurred.

Until managed OIDC is connected, requests use development-only actor headers:

- `x-user-id`
- `x-organization-id`
- `x-role: regular_user|admin`

Mutating submit/decision requests also require `Idempotency-Key`.
Creating an intake item also requires `Idempotency-Key`; replaying a request with the same key returns the original item. The iOS saved-draft flow persists that key before sending so a retry after an app restart does not create a duplicate item.

The server is authoritative for field-confidence routing, shelf-life policy, role enforcement, urgency, inventory creation, and idempotency.
The admin review queue includes the fields needed to inspect an intake item before deciding. A quarantined lot remains unavailable; later acceptance releases the same lot, while rejection disposes it and records the outgoing movement.
