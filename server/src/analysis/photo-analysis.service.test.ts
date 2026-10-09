import assert from "node:assert/strict";
import test from "node:test";
import { BadGatewayException, BadRequestException } from "@nestjs/common";
import sharp from "sharp";
import { parsePhotoAnalysis, PhotoAnalysisService } from "./photo-analysis.service";

test("accepts nutrition and explicit dietary claims from the vision model", () => {
  const result = parsePhotoAnalysis(JSON.stringify({
    productName: "  Soup  ", brand: null, ingredients: null,
    allergens: "Contains milk", packageWeight: "400 g", printedDate: "BEST BEFORE 2026-10-14", printedDateType: "best_before",
    calories: 90, calorieBasis: "per_serving", servingSize: "1 unit (56 g)",
    dietaryClaims: ["vegan", "gluten_free", "peanut_free", "low_sodium", "kosher", "non_gmo", "vegan"],
    otherLabelClaims: ["  No artificial colors  ", "No artificial colors"],
  }));
  assert.equal(result.productName, "Soup");
  assert.equal(result.brand, null);
  assert.equal(result.allergens, "Contains milk");
  assert.equal(result.calories, 90);
  assert.equal(result.calorieBasis, "per_serving");
  assert.equal(result.printedDateType, "best_before");
  assert.deepEqual(result.dietaryClaims, ["vegan", "gluten_free", "peanut_free", "low_sodium", "kosher", "non_gmo"]);
  assert.deepEqual(result.otherLabelClaims, ["No artificial colors"]);
  assert.throws(() => parsePhotoAnalysis('{"productName": 4}'), BadGatewayException);
  assert.throws(() => parsePhotoAnalysis(JSON.stringify({ ...result, calories: "90" })), BadGatewayException);
  assert.throws(() => parsePhotoAnalysis(JSON.stringify({ ...result, dietaryClaims: ["allergen_free"] })), BadGatewayException);
  assert.throws(() => parsePhotoAnalysis(JSON.stringify({ ...result, printedDateType: "manufactured_on" })), BadGatewayException);
  assert.equal(parsePhotoAnalysis(JSON.stringify({ ...result, printedDate: null })).printedDateType, null);
  assert.throws(() => parsePhotoAnalysis(JSON.stringify({ ...result, otherLabelClaims: [4] })), BadGatewayException);
  assert.throws(() => parsePhotoAnalysis("not JSON"), BadGatewayException);
});

test("requires one to eight photos before calling the vision model", async () => {
  const service = new PhotoAnalysisService();
  await assert.rejects(service.analyze([]), BadRequestException);
  const buffer = await sharp({ create: { width: 2, height: 2, channels: 3, background: "white" } }).jpeg().toBuffer();
  const photo = { buffer, size: buffer.length, mimetype: "image/jpeg" };
  await assert.rejects(service.analyze(Array(9).fill(photo)), BadRequestException);
});
