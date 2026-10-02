import assert from "node:assert/strict";
import test from "node:test";
import { BadRequestException } from "@nestjs/common";
import type { RequestActor } from "../auth/request-context";
import { DatabaseService } from "../database/database.service";
import { DashboardService } from "./dashboard.service";

const actor: RequestActor = { userId: "demo", organizationId: "organization", role: "regular_user" };

test("dashboard sorts before limiting and returns product category", async () => {
  const queries: string[] = [];
  const db = {
    query: async (sql: string) => {
      queries.push(sql);
      return { rows: [] };
    },
  } as unknown as DatabaseService;
  const service = new DashboardService(db);

  for (const sort of ["received", "expiration", "category", "name"]) {
    await service.list(actor, undefined, 50, sort);
  }

  assert.match(queries[0], /ORDER BY s\.received_at DESC, i\.date_value ASC NULLS LAST/);
  assert.match(queries[1], /ORDER BY i\.date_value ASC NULLS LAST, s\.received_at DESC/);
  assert.match(queries[2], /ORDER BY i\.category ASC/);
  assert.match(queries[3], /ORDER BY i\.product_name ASC/);
  for (const sql of queries) {
    assert.match(sql, /'category', i\.category/);
    assert.ok(sql.indexOf("ORDER BY") < sql.indexOf("LIMIT $3"));
  }
});

test("dashboard rejects an unknown sort value", async () => {
  const db = { query: async () => ({ rows: [] }) } as unknown as DatabaseService;
  await assert.rejects(new DashboardService(db).list(actor, undefined, 50, "drop_table"), BadRequestException);
});
