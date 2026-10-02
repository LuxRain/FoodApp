BEGIN;

ALTER TABLE intake_items
  ADD COLUMN category text NOT NULL DEFAULT 'other'
  CHECK (category IN (
    'produce', 'canned_jarred', 'dry_goods_grains', 'dairy_eggs',
    'meat_seafood', 'prepared_meals', 'bakery_snacks', 'beverages',
    'infant_food', 'other'
  ));

UPDATE intake_items AS i
SET category = CASE
  WHEN p.category ILIKE '%infant%' OR p.category ILIKE '%baby%' OR p.category ILIKE '%formula%' THEN 'infant_food'
  WHEN p.category ILIKE '%canned%' OR p.category ILIKE '%jarred%' OR p.category ILIKE '%tinned%' THEN 'canned_jarred'
  WHEN p.category ILIKE '%produce%' OR p.category ILIKE '%fruit%' OR p.category ILIKE '%vegetable%' THEN 'produce'
  WHEN p.category ILIKE '%grain%' OR p.category ILIKE '%rice%' OR p.category ILIKE '%pasta%' OR p.category ILIKE '%cereal%' THEN 'dry_goods_grains'
  WHEN p.category ILIKE '%dairy%' OR p.category ILIKE '%cheese%' OR p.category ILIKE '%yogurt%' OR p.category ILIKE '%egg%' THEN 'dairy_eggs'
  WHEN p.category ILIKE '%meat%' OR p.category ILIKE '%poultry%' OR p.category ILIKE '%seafood%' OR p.category ILIKE '%fish%' THEN 'meat_seafood'
  WHEN p.category ILIKE '%meal%' OR p.category ILIKE '%entree%' OR p.category ILIKE '%soup%' THEN 'prepared_meals'
  WHEN p.category ILIKE '%bakery%' OR p.category ILIKE '%bread%' OR p.category ILIKE '%snack%' THEN 'bakery_snacks'
  WHEN p.category ILIKE '%beverage%' OR p.category ILIKE '%drink%' OR p.category ILIKE '%juice%' THEN 'beverages'
  ELSE 'other'
END
FROM products AS p
WHERE i.product_id = p.id;

COMMIT;
