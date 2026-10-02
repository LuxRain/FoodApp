import assert from "node:assert/strict";
import test from "node:test";
import { BadRequestException } from "@nestjs/common";
import type { DatabaseService } from "../database/database.service";
import { EvidenceService } from "./evidence.service";

const actor = { userId: "user", organizationId: "org", role: "regular_user" as const };
const itemId = "00000000-0000-4000-8000-000000000001";
const photo = { buffer: Buffer.from([0xff, 0xd8, 0xff]), size: 3, mimetype: "image/jpeg" };

test("rejects a ninth photo before writing an evidence file", async () => {
  const queries: string[] = [];
  const db = {
    transaction: async (work: (client: { query: (sql: string) => Promise<unknown> }) => Promise<unknown>) => work({
      query: async (sql: string) => {
        queries.push(sql);
        if (sql.includes("FOR UPDATE")) return { rowCount: 1, rows: [{ id: itemId }] };
        if (sql.includes("content_hash")) return { rowCount: 0, rows: [] };
        if (sql.includes("COUNT(*)")) return { rowCount: 1, rows: [{ count: 8 }] };
        throw new Error(`Unexpected query: ${sql}`);
      },
    }),
  } as unknown as DatabaseService;

  await assert.rejects(new EvidenceService(db).upload(actor, itemId, photo, undefined, "package_photo"), BadRequestException);
  assert.equal(queries.some((sql) => sql.includes("INSERT INTO evidence_assets")), false);
});
