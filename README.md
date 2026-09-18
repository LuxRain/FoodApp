# Food Donation Intake

An iOS-first food-donation intake system for barcode, QR, and package-image capture, with automatic field suggestions, server-side acceptance rules, an expiration-prioritized dashboard, and admin review.

## Repository

- `SYSTEM_DESIGN.md` — architecture and security decisions.
- `docs/phase-0/` — signed-off field, workflow, dashboard, and policy requirements.
- `prototype/` — approved interactive Liquid Glass UI prototype.
- `server/` — NestJS/PostgreSQL Phase 1 API vertical slice.
- `ios/` — Swift domain, API client, code parsing, and offline outbox foundation.

## Verified Phase 1 slice

The implemented vertical slice can:

1. resolve a checksum-valid UPC/GTIN against the internal catalog, with an Open Food Facts v3 adapter as the external fallback;
2. create an anonymous intake session and item;
3. route the reviewed item using per-field confidence and shelf-life rules;
4. atomically create a lot and receive movement for accepted inventory;
5. replay idempotent submissions without double counting;
6. return an expiration-sorted donation dashboard;
7. enforce admin-only access to the exception queue and decision endpoint;
8. encode the matching contract in a Swift client with a durable offline outbox.

See each component's README for local commands and known environment requirements.
