import { BadGatewayException, BadRequestException, Injectable } from "@nestjs/common";
import type { RequestActor } from "../auth/request-context";
import { DatabaseService } from "../database/database.service";

type OpenFoodFactsProduct = {
  code?: string;
  product_name?: string;
  brands?: string;
  categories?: string;
  serving_size?: string;
  allergens_tags?: string[];
  traces_tags?: string[];
  nutriments?: { "energy-kcal_serving"?: number; "energy-kcal_100g"?: number };
};
type OpenFoodFactsResponse = { status?: string; product?: OpenFoodFactsProduct };

export type ProductCandidate = {
  productId: string | null;
  normalizedCode: string;
  name: string;
  brand: string | null;
  category: string | null;
  calories: number | null;
  calorieBasis: "per_serving" | "per_100g" | null;
  servingSize: string | null;
  allergens: Array<{ code: string; declaration: "contains" | "cross_contact_advisory" }>;
  source: "internal_catalog" | "open_food_facts";
  confidence: number;
  requiresUserConfirmation: boolean;
};

@Injectable()
export class ProductLookupService {
  constructor(private readonly db: DatabaseService) {}

  async lookup(actor: RequestActor, rawCode: string, scheme: string): Promise<{ candidates: ProductCandidate[] }> {
    const normalizedCode = normalizeCode(rawCode);
    if (!normalizedCode) throw new BadRequestException("A checksum-valid UPC/EAN/GTIN is required");
    const local = await this.db.query(
      `SELECT p.id, p.canonical_name, p.brand, p.category FROM product_codes c JOIN products p ON p.id = c.product_id
       WHERE p.organization_id = $1 AND c.normalized_code IN ($2, $3) LIMIT 1`,
      [actor.organizationId, rawCode.replace(/\D/g, ""), normalizedCode],
    );
    if (local.rowCount) {
      const product = local.rows[0];
      return { candidates: [{ productId: product.id, normalizedCode, name: product.canonical_name, brand: product.brand, category: product.category, calories: null, calorieBasis: null, servingSize: null, allergens: [], source: "internal_catalog", confidence: 1, requiresUserConfirmation: false }] };
    }
    const candidate = await this.lookupOpenFoodFacts(normalizedCode, scheme);
    return { candidates: candidate ? [candidate] : [] };
  }

  private async lookupOpenFoodFacts(code: string, _scheme: string): Promise<ProductCandidate | null> {
    const userAgent = process.env.OPEN_FOOD_FACTS_USER_AGENT;
    if (!userAgent) throw new BadGatewayException("External product lookup is not configured");
    const fields = "code,product_name,brands,categories,serving_size,allergens_tags,traces_tags,nutriments";
    const url = new URL(`https://world.openfoodfacts.org/api/v3/product/${encodeURIComponent(code)}`);
    url.searchParams.set("product_type", "food"); url.searchParams.set("cc", "us"); url.searchParams.set("lc", "en"); url.searchParams.set("fields", fields);
    const response = await fetch(url, { headers: { "User-Agent": userAgent, Accept: "application/json" }, signal: AbortSignal.timeout(5_000) });
    if (response.status === 404) return null;
    if (!response.ok) throw new BadGatewayException(`Product provider returned ${response.status}`);
    const payload = await response.json() as OpenFoodFactsResponse;
    const product = payload.product;
    if (!product?.product_name) return null;
    const calories = product.nutriments?.["energy-kcal_serving"] ?? product.nutriments?.["energy-kcal_100g"] ?? null;
    return {
      productId: null, normalizedCode: code, name: product.product_name, brand: product.brands ?? null,
      category: product.categories?.split(",")[0]?.trim() || null, calories,
      calorieBasis: product.nutriments?.["energy-kcal_serving"] != null ? "per_serving" : calories != null ? "per_100g" : null,
      servingSize: product.serving_size ?? null,
      allergens: [
        ...(product.allergens_tags ?? []).map((tag) => ({ code: tag.replace(/^en:/, ""), declaration: "contains" as const })),
        ...(product.traces_tags ?? []).map((tag) => ({ code: tag.replace(/^en:/, ""), declaration: "cross_contact_advisory" as const })),
      ],
      source: "open_food_facts", confidence: 0.85, requiresUserConfirmation: true,
    };
  }
}

export function normalizeCode(raw: string): string | null {
  const digits = raw.replace(/\D/g, "");
  if (![8, 12, 13, 14].includes(digits.length)) return null;
  const expected = Number(digits.at(-1));
  const sum = [...digits.slice(0, -1)].reverse().reduce((total, digit, index) => total + Number(digit) * (index % 2 === 0 ? 3 : 1), 0);
  if ((10 - (sum % 10)) % 10 !== expected) return null;
  return digits.padStart(14, "0");
}
