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

Until managed OIDC is connected, requests use development-only actor headers:

- `x-user-id`
- `x-organization-id`
- `x-role: regular_user|admin`

Mutating submit/decision requests also require `Idempotency-Key`.

The server is authoritative for field-confidence routing, shelf-life policy, role enforcement, urgency, inventory creation, and idempotency.
