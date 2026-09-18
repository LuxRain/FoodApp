BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE user_role AS ENUM ('regular_user', 'admin');
CREATE TYPE intake_status AS ENUM ('draft', 'ready_for_user_review', 'submitted', 'processing', 'auto_accepted', 'pending_admin_review', 'admin_accepted', 'quarantined', 'rejected');
CREATE TYPE inventory_status AS ENUM ('available', 'quarantined', 'reserved', 'distributed', 'disposed');
CREATE TYPE nutrition_tier AS ENUM ('green', 'yellow', 'red', 'unclassified');

CREATE TABLE organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  timezone text NOT NULL DEFAULT 'America/Chicago',
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  name text NOT NULL,
  timezone text NOT NULL,
  storage_capabilities text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_memberships (
  user_id text NOT NULL,
  organization_id uuid NOT NULL REFERENCES organizations(id),
  role user_role NOT NULL,
  location_scope uuid[] NOT NULL DEFAULT '{}',
  PRIMARY KEY (user_id, organization_id)
);

CREATE TABLE products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  canonical_name text NOT NULL,
  brand text,
  category text NOT NULL,
  food_group text NOT NULL DEFAULT 'unknown',
  default_unit text NOT NULL DEFAULT 'each',
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE product_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products(id),
  scheme text NOT NULL,
  normalized_code text NOT NULL,
  raw_code text NOT NULL,
  provider text NOT NULL,
  UNIQUE (scheme, normalized_code)
);

CREATE TABLE intake_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  receiving_location_id uuid NOT NULL REFERENCES locations(id),
  received_at timestamptz NOT NULL,
  source_channel text,
  status text NOT NULL DEFAULT 'draft',
  created_by text NOT NULL,
  client_mutation_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, client_mutation_id)
);

CREATE TABLE intake_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  session_id uuid NOT NULL REFERENCES intake_sessions(id),
  product_id uuid REFERENCES products(id),
  product_name text NOT NULL,
  brand text,
  identity_source text NOT NULL,
  quantity numeric(14,3) NOT NULL CHECK (quantity > 0),
  quantity_unit text NOT NULL,
  date_type text NOT NULL,
  date_value date,
  date_label_raw text,
  storage_type text NOT NULL,
  storage_location_id uuid NOT NULL REFERENCES locations(id),
  package_condition text NOT NULL,
  temperature_status text NOT NULL,
  calorie_status text NOT NULL DEFAULT 'unknown',
  calories numeric(10,2),
  calorie_basis text,
  allergen_summary jsonb NOT NULL DEFAULT '[]',
  nutrition_tier nutrition_tier NOT NULL DEFAULT 'unclassified',
  required_field_confidence jsonb NOT NULL DEFAULT '[]',
  user_reviewed_at timestamptz,
  status intake_status NOT NULL DEFAULT 'draft',
  routing_reason_codes text[] NOT NULL DEFAULT '{}',
  version integer NOT NULL DEFAULT 1,
  submitted_at timestamptz,
  decided_at timestamptz,
  decision_by text,
  decision_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE field_assertions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intake_item_id uuid NOT NULL REFERENCES intake_items(id),
  field_name text NOT NULL,
  value jsonb NOT NULL,
  source_type text NOT NULL,
  source_ref text,
  confidence numeric(5,4),
  provider_version text,
  review_status text NOT NULL DEFAULT 'proposed',
  confirmed_by text,
  confirmed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE evidence_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intake_item_id uuid NOT NULL REFERENCES intake_items(id),
  object_key text NOT NULL,
  content_hash text NOT NULL,
  evidence_type text NOT NULL,
  captured_at timestamptz NOT NULL,
  malware_scan_state text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory_lots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  intake_item_id uuid NOT NULL UNIQUE REFERENCES intake_items(id),
  product_id uuid NOT NULL REFERENCES products(id),
  location_id uuid NOT NULL REFERENCES locations(id),
  on_hand_quantity numeric(14,3) NOT NULL,
  unit text NOT NULL,
  date_type text NOT NULL,
  date_value date,
  storage_type text NOT NULL,
  status inventory_status NOT NULL,
  nutrition_tier nutrition_tier NOT NULL,
  row_version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  lot_id uuid NOT NULL REFERENCES inventory_lots(id),
  movement_type text NOT NULL,
  quantity_delta numeric(14,3) NOT NULL,
  actor_id text NOT NULL,
  reason text NOT NULL,
  idempotency_key text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, idempotency_key)
);

CREATE TABLE audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  actor_id text NOT NULL,
  action text NOT NULL,
  target_type text NOT NULL,
  target_id uuid NOT NULL,
  before_value jsonb,
  after_value jsonb,
  request_id text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sync_mutations (
  organization_id uuid NOT NULL REFERENCES organizations(id),
  client_mutation_id text NOT NULL,
  result jsonb NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, client_mutation_id)
);

CREATE INDEX intake_items_dashboard_idx ON intake_items (organization_id, date_value NULLS LAST, created_at, id);
CREATE INDEX intake_items_review_idx ON intake_items (organization_id, status, created_at) WHERE status IN ('pending_admin_review', 'quarantined');
CREATE INDEX inventory_lots_location_idx ON inventory_lots (organization_id, location_id, status, date_value NULLS LAST);

COMMIT;
