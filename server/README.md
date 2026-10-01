# Food Donation API

Phase 1 NestJS/PostgreSQL vertical slice implementing intake sessions, items, automatic acceptance, the donation dashboard, and admin decisions.

## Local setup

```bash
npm install
docker compose up -d postgres
psql postgres://foodapp:foodapp@localhost:55432/foodapp -f migrations/001_initial_schema.sql
psql postgres://foodapp:foodapp@localhost:55432/foodapp -f migrations/002_development_seed.sql
cp .env.example .env
npm run start:dev
```

The development seed creates the demo organization, main receiving location, regular/admin users, and barcode `012345678905` for the Low-Sodium Black Beans test product. Apply it once to a new local database.

## Package-photo evidence

The API accepts a `photo` multipart field at `POST /v1/intake-items/:itemId/evidence` after the intake item is created and before submission. JPEG and PNG files up to 10 MB are supported. The optional `capturedAt` field is an ISO date. The response contains the evidence ID; `GET /v1/intake-items/:itemId/evidence` lists an item's assets, and `GET /v1/intake-items/:itemId/evidence/:evidenceId` returns the private image bytes.

Files are stored under `server/var/evidence/` by default, outside the public web root, with metadata and a SHA-256 hash in PostgreSQL. Set `EVIDENCE_STORAGE_DIR` to an absolute directory for a persistent deployment. Back up that directory together with the database. This is local pilot storage; it does not yet provide object-store replication or malware scanning. The `malware_scan_state` value is recorded as `not_scanned` rather than implying a scan occurred.

Until managed OIDC is connected, requests use development-only actor headers:

- `x-user-id`
- `x-organization-id`
- `x-role: regular_user|admin`

Mutating submit/decision requests also require `Idempotency-Key`.

The server is authoritative for field-confidence routing, shelf-life policy, role enforcement, urgency, inventory creation, and idempotency.
