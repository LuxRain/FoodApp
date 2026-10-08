BEGIN;

ALTER TABLE intake_items
  ADD COLUMN trust_score smallint CHECK (trust_score BETWEEN 0 AND 100),
  ADD COLUMN trust_factors jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN trust_algorithm_version text;

CREATE TABLE intake_ledger_heads (
  organization_id uuid PRIMARY KEY REFERENCES organizations(id),
  last_sequence bigint NOT NULL DEFAULT 0,
  last_hash text NOT NULL DEFAULT repeat('0', 64)
);

CREATE TABLE intake_ledger_events (
  organization_id uuid NOT NULL REFERENCES organizations(id),
  sequence bigint NOT NULL CHECK (sequence > 0),
  event_type text NOT NULL,
  target_id uuid NOT NULL,
  actor_id text NOT NULL,
  payload jsonb NOT NULL,
  previous_hash text NOT NULL,
  event_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, sequence),
  UNIQUE (organization_id, event_hash)
);

CREATE FUNCTION prevent_intake_ledger_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Audit and privacy releases are immutable';
END;
$$;
CREATE TRIGGER intake_ledger_append_only BEFORE UPDATE OR DELETE ON intake_ledger_events
  FOR EACH ROW EXECUTE FUNCTION prevent_intake_ledger_mutation();

CREATE TABLE dp_monthly_releases (
  organization_id uuid NOT NULL REFERENCES organizations(id),
  month_start date NOT NULL,
  epsilon numeric(6,3) NOT NULL CHECK (epsilon > 0),
  mechanism text NOT NULL,
  noisy_counts jsonb NOT NULL,
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, month_start)
);

CREATE TRIGGER dp_monthly_release_immutable BEFORE UPDATE OR DELETE ON dp_monthly_releases
  FOR EACH ROW EXECUTE FUNCTION prevent_intake_ledger_mutation();

COMMIT;
