import assert from "node:assert/strict";
import { test } from "node:test";
import { hashEvent } from "./intake-ledger.service";

test("hash is stable across object key order and changes with history", () => {
  const event = { organizationId: "o", sequence: 1, eventType: "submitted", targetId: "t", actorId: "a", payload: { status: "pending", score: 75 }, previousHash: "0".repeat(64) };
  assert.equal(hashEvent(event), hashEvent({ ...event, payload: { score: 75, status: "pending" } }));
  assert.notEqual(hashEvent(event), hashEvent({ ...event, previousHash: "1".repeat(64) }));
});
