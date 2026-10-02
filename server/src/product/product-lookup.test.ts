import assert from "node:assert/strict";
import test from "node:test";
import { DatabaseService } from "../database/database.service";
import { ProductLookupService } from "./product-lookup.service";
import { normalizeCode } from "./product-lookup.service";

test("normalizes valid UPC to GTIN-14", () => assert.equal(normalizeCode("012345678905"), "00012345678905"));
test("rejects invalid check digits and arbitrary QR content", () => {
  assert.equal(normalizeCode("012345678904"), null);
  assert.equal(normalizeCode("https://example.invalid/123"), null);
});

test("keeps a product's original-language name without requesting English localization", async () => {
  const previousFetch = globalThis.fetch;
  const previousUserAgent = process.env.OPEN_FOOD_FACTS_USER_AGENT;
  process.env.OPEN_FOOD_FACTS_USER_AGENT = "FoodDonationTest/1.0";
  let requestedURL: URL | undefined;
  globalThis.fetch = async (input) => {
    requestedURL = new URL(String(input));
    return Response.json({ product: { product_name: "抹茶ビスケット", brands: "テスト" } });
  };
  try {
    const db = { query: async () => ({ rowCount: 0, rows: [] }) } as unknown as DatabaseService;
    const service = new ProductLookupService(db);
    const result = await service.lookup({ userId: "user", organizationId: "org", role: "regular_user" }, "012345678905", "upc");
    assert.equal(result.candidates[0]?.name, "抹茶ビスケット");
    assert.equal(requestedURL?.searchParams.has("lc"), false);
    assert.equal(requestedURL?.searchParams.has("cc"), false);
  } finally {
    globalThis.fetch = previousFetch;
    if (previousUserAgent === undefined) delete process.env.OPEN_FOOD_FACTS_USER_AGENT;
    else process.env.OPEN_FOOD_FACTS_USER_AGENT = previousUserAgent;
  }
});
