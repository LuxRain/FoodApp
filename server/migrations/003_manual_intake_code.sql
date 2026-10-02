BEGIN;

ALTER TABLE intake_items ADD COLUMN scanned_code text;

COMMIT;
