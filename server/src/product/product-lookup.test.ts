import assert from "node:assert/strict";
import test from "node:test";
import { normalizeCode } from "./product-lookup.service";

test("normalizes valid UPC to GTIN-14", () => assert.equal(normalizeCode("012345678905"), "00012345678905"));
test("rejects invalid check digits and arbitrary QR content", () => {
  assert.equal(normalizeCode("012345678904"), null);
  assert.equal(normalizeCode("https://example.invalid/123"), null);
});
