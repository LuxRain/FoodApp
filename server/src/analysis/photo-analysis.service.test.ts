import assert from "node:assert/strict";
import test from "node:test";
import { BadGatewayException, BadRequestException } from "@nestjs/common";
import sharp from "sharp";
import { parsePhotoAnalysis, PhotoAnalysisService } from "./photo-analysis.service";

test("accepts only nullable text fields from the vision model", () => {
  const result = parsePhotoAnalysis(JSON.stringify({
    productName: "  Soup  ", brand: null, ingredients: null,
    allergens: "Contains milk", packageWeight: "400 g", printedDate: null,
  }));
  assert.equal(result.productName, "Soup");
  assert.equal(result.brand, null);
  assert.equal(result.allergens, "Contains milk");
  assert.throws(() => parsePhotoAnalysis('{"productName": 4}'), BadGatewayException);
  assert.throws(() => parsePhotoAnalysis("not JSON"), BadGatewayException);
});

test("requires one to eight photos before calling the vision model", async () => {
  const service = new PhotoAnalysisService();
  await assert.rejects(service.analyze([]), BadRequestException);
  const buffer = await sharp({ create: { width: 2, height: 2, channels: 3, background: "white" } }).jpeg().toBuffer();
  const photo = { buffer, size: buffer.length, mimetype: "image/jpeg" };
  await assert.rejects(service.analyze(Array(9).fill(photo)), BadRequestException);
});
