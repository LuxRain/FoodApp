import { createHash } from "node:crypto";
import { Injectable } from "@nestjs/common";
import type { PoolClient } from "pg";
import { DatabaseService } from "../database/database.service";

const GENESIS_HASH = "0".repeat(64);

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${canonical(record[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export type LedgerEvent = { organizationId: string; sequence: number; eventType: string; targetId: string; actorId: string; payload: Record<string, unknown>; previousHash: string };

export function hashEvent(event: LedgerEvent): string {
  return createHash("sha256").update(canonical(event), "utf8").digest("hex");
}

@Injectable()
export class IntakeLedgerService {
  constructor(private readonly db: DatabaseService) {}

  async append(client: PoolClient, organizationId: string, eventType: string, targetId: string, actorId: string, payload: Record<string, unknown>) {
    await client.query("INSERT INTO intake_ledger_heads (organization_id) VALUES ($1) ON CONFLICT DO NOTHING", [organizationId]);
    const head = await client.query<{ last_sequence: string; last_hash: string }>("SELECT last_sequence, last_hash FROM intake_ledger_heads WHERE organization_id = $1 FOR UPDATE", [organizationId]);
    const sequence = Number(head.rows[0].last_sequence) + 1;
    const previousHash = head.rows[0].last_hash;
    const eventHash = hashEvent({ organizationId, sequence, eventType, targetId, actorId, payload, previousHash });
    await client.query(
      `INSERT INTO intake_ledger_events (organization_id, sequence, event_type, target_id, actor_id, payload, previous_hash, event_hash)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8)`,
      [organizationId, sequence, eventType, targetId, actorId, JSON.stringify(payload), previousHash, eventHash],
    );
    await client.query("UPDATE intake_ledger_heads SET last_sequence = $2, last_hash = $3 WHERE organization_id = $1", [organizationId, sequence, eventHash]);
    return { sequence, eventHash };
  }

  async verify(organizationId: string) {
    return this.db.transaction(async (client) => {
      await client.query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY");
      const rows = await client.query<{ sequence: string; event_type: string; target_id: string; actor_id: string; payload: Record<string, unknown>; previous_hash: string; event_hash: string }>(
        "SELECT sequence, event_type, target_id, actor_id, payload, previous_hash, event_hash FROM intake_ledger_events WHERE organization_id = $1 ORDER BY sequence", [organizationId],
      );
      const head = await client.query<{ last_sequence: string; last_hash: string }>("SELECT last_sequence, last_hash FROM intake_ledger_heads WHERE organization_id = $1", [organizationId]);
      let previousHash = GENESIS_HASH;
      let sequence = 0;
      for (const row of rows.rows) {
        const expected = hashEvent({ organizationId, sequence: sequence + 1, eventType: row.event_type, targetId: row.target_id, actorId: row.actor_id, payload: row.payload, previousHash });
        if (Number(row.sequence) !== sequence + 1 || row.previous_hash !== previousHash || row.event_hash !== expected) return { valid: false, checkedEvents: sequence, brokenSequence: Number(row.sequence), coverage: "post_migration_events_only" };
        previousHash = row.event_hash;
        sequence++;
      }
      const valid = sequence === Number(head.rows[0]?.last_sequence ?? 0) && previousHash === (head.rows[0]?.last_hash ?? GENESIS_HASH);
      return { valid, checkedEvents: sequence, brokenSequence: valid ? null : sequence + 1, headHash: previousHash, coverage: "post_migration_events_only" };
    });
  }
}
