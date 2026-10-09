BEGIN;

ALTER TABLE intake_items
  ADD COLUMN serving_size text,
  ADD COLUMN dietary_claims text[] NOT NULL DEFAULT '{}';

ALTER TABLE intake_items
  ADD CONSTRAINT intake_items_dietary_claims_allowed
  CHECK (dietary_claims <@ ARRAY['dairy_free', 'gluten_free', 'vegan']::text[]);

COMMIT;
