BEGIN;

ALTER TABLE intake_items DROP CONSTRAINT intake_items_dietary_claims_allowed;

ALTER TABLE intake_items
  ADD CONSTRAINT intake_items_dietary_claims_allowed
  CHECK (dietary_claims <@ ARRAY[
    'dairy_free', 'lactose_free', 'gluten_free', 'wheat_free', 'egg_free', 'soy_free',
    'peanut_free', 'tree_nut_free', 'sesame_free', 'fish_free', 'shellfish_free',
    'vegan', 'vegetarian', 'plant_based', 'keto', 'paleo',
    'kosher', 'halal', 'organic', 'non_gmo',
    'no_added_sugar', 'sugar_free', 'low_sugar', 'low_sodium', 'no_salt_added',
    'low_fat', 'fat_free', 'low_calorie', 'high_protein', 'high_fiber'
  ]::text[]);

ALTER TABLE intake_items
  ADD COLUMN other_label_claims text[] NOT NULL DEFAULT '{}',
  ADD CONSTRAINT intake_items_other_label_claims_count CHECK (cardinality(other_label_claims) <= 8);

COMMIT;
