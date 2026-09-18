BEGIN;

INSERT INTO organizations (id, name, timezone)
VALUES ('00000000-0000-4000-8000-000000000001', 'Food Donation Pilot', 'America/New_York');

INSERT INTO locations (id, organization_id, name, timezone, storage_capabilities)
VALUES (
  '00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-000000000001',
  'Main Pantry · A3',
  'America/New_York',
  ARRAY['shelf_stable', 'refrigerated', 'frozen']
);

INSERT INTO user_memberships (user_id, organization_id, role, location_scope)
VALUES
  ('regular-demo', '00000000-0000-4000-8000-000000000001', 'regular_user', ARRAY['00000000-0000-4000-8000-000000000101']::uuid[]),
  ('admin-demo', '00000000-0000-4000-8000-000000000001', 'admin', ARRAY['00000000-0000-4000-8000-000000000101']::uuid[]);

INSERT INTO products (id, organization_id, canonical_name, brand, category, food_group, default_unit)
VALUES (
  '00000000-0000-4000-8000-000000000201',
  '00000000-0000-4000-8000-000000000001',
  'Low-Sodium Black Beans',
  'Community Pantry',
  'canned_beans',
  'protein',
  'can'
);

INSERT INTO product_codes (product_id, scheme, normalized_code, raw_code, provider)
VALUES ('00000000-0000-4000-8000-000000000201', 'upc_a', '012345678905', '012345678905', 'development_seed');

COMMIT;
