// These codes describe words printed on a package, not independently verified properties.
export const labelClaimCodes = [
  "dairy_free", "lactose_free", "gluten_free", "wheat_free", "egg_free", "soy_free",
  "peanut_free", "tree_nut_free", "sesame_free", "fish_free", "shellfish_free",
  "vegan", "vegetarian", "plant_based", "keto", "paleo",
  "kosher", "halal", "organic", "non_gmo",
  "no_added_sugar", "sugar_free", "low_sugar", "low_sodium", "no_salt_added",
  "low_fat", "fat_free", "low_calorie", "high_protein", "high_fiber",
] as const;

export type LabelClaimCode = typeof labelClaimCodes[number];
