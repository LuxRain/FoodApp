import assert from "node:assert/strict";
import { test } from "node:test";
import { laplaceNoise } from "./monthly-release.service";

test("Laplace inverse CDF is symmetric", () => {
  assert.equal(laplaceNoise(2, () => 0.5), 0);
  assert.ok(Math.abs(laplaceNoise(2, () => 0.25) + laplaceNoise(2, () => 0.75)) < 1e-12);
});
