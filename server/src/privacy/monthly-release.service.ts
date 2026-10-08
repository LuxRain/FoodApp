import { randomInt } from "node:crypto";
import { BadRequestException, Injectable } from "@nestjs/common";
import { DatabaseService } from "../database/database.service";
import type { RequestActor } from "../auth/request-context";

const EPSILON = 1;
const SENSITIVITY = 2; // One item's status can change from one bucket to another.
const STATUSES = ["auto_accepted", "pending_admin_review", "admin_accepted", "quarantined", "rejected"] as const;

export function laplaceNoise(scale: number, uniform: () => number = () => (randomInt(2 ** 48 - 1) + 0.5) / (2 ** 48)) {
  const u = uniform() - 0.5;
  if (!(scale > 0) || !(u > -0.5 && u < 0.5)) throw new Error("Invalid Laplace parameters");
  if (u === 0) return 0;
  return -scale * Math.sign(u) * Math.log(1 - 2 * Math.abs(u));
}

@Injectable()
export class MonthlyReleaseService {
  constructor(private readonly db: DatabaseService) {}

  async release(actor: RequestActor, month: string) {
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) throw new BadRequestException("Month must be YYYY-MM");
    const monthStart = `${month}-01`;
    const nextMonth = new Date(`${monthStart}T00:00:00.000Z`);
    nextMonth.setUTCMonth(nextMonth.getUTCMonth() + 1);
    if (Number.isNaN(nextMonth.getTime()) || nextMonth > new Date()) throw new BadRequestException("Only closed UTC months can be released");
    return this.db.transaction(async (client) => {
      // Serialize releases per organization, including the first release for a month.
      await client.query("SELECT id FROM organizations WHERE id = $1 FOR UPDATE", [actor.organizationId]);
      const existing = await client.query<{ month_start: string; epsilon: string; mechanism: string; noisy_counts: Record<string, number>; created_at: string }>(
        "SELECT month_start, epsilon, mechanism, noisy_counts, created_at FROM dp_monthly_releases WHERE organization_id = $1 AND month_start = $2", [actor.organizationId, monthStart],
      );
      if (existing.rowCount) return this.format(month, existing.rows[0]);
      const counts = await client.query<{ status: string; count: string }>(
        `SELECT status::text, count(*)::text FROM intake_items
         WHERE organization_id = $1 AND submitted_at >= $2::timestamptz AND submitted_at < $3::timestamptz
         GROUP BY status`, [actor.organizationId, `${monthStart}T00:00:00.000Z`, nextMonth.toISOString()],
      );
      const raw = new Map(counts.rows.map((row) => [row.status, Number(row.count)]));
      const noisyCounts = Object.fromEntries(STATUSES.map((status) => [status, Math.max(0, Math.round((raw.get(status) ?? 0) + laplaceNoise(SENSITIVITY / EPSILON)))]));
      const inserted = await client.query<{ month_start: string; epsilon: string; mechanism: string; noisy_counts: Record<string, number>; created_at: string }>(
        `INSERT INTO dp_monthly_releases (organization_id, month_start, epsilon, mechanism, noisy_counts, created_by)
         VALUES ($1, $2, $3, 'fixed-status-histogram-laplace-v1', $4::jsonb, $5)
         RETURNING month_start, epsilon, mechanism, noisy_counts, created_at`,
        [actor.organizationId, monthStart, EPSILON, JSON.stringify(noisyCounts), actor.userId],
      );
      return this.format(month, inserted.rows[0]);
    });
  }

  private format(month: string, row: { epsilon: string; mechanism: string; noisy_counts: Record<string, number>; created_at: string }) {
    return { month, epsilon: Number(row.epsilon), mechanism: row.mechanism, noisyCounts: row.noisy_counts, releasedAt: row.created_at,
      privacyUnit: "one intake item", warning: "Noisy aggregate only; counts may differ from exact inventory and must not drive food-safety decisions." };
  }
}
