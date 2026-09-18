import { Injectable } from "@nestjs/common";
import type { RequestActor } from "../auth/request-context";
import { DatabaseService } from "../database/database.service";

@Injectable()
export class DashboardService {
  constructor(private readonly db: DatabaseService) {}

  async list(actor: RequestActor, search?: string, limit = 50) {
    const safeLimit = Math.min(Math.max(limit, 1), 100);
    const result = await this.db.query(
      `SELECT i.id AS "intakeItemId", lot.id AS "inventoryLotId",
        jsonb_build_object('name', i.product_name, 'brand', i.brand) AS product,
        jsonb_build_object('quantity', COALESCE(lot.on_hand_quantity, i.quantity)::float8, 'unit', COALESCE(lot.unit, i.quantity_unit)) AS "onHand",
        jsonb_build_object(
          'type', i.date_type,
          'value', i.date_value,
          'daysRemaining', CASE WHEN i.date_value IS NULL THEN NULL ELSE (i.date_value - (CURRENT_TIMESTAMP AT TIME ZONE loc.timezone)::date)::int END,
          'urgency', CASE
            WHEN i.date_value IS NULL THEN 'no_date'
            WHEN i.date_value < (CURRENT_TIMESTAMP AT TIME ZONE loc.timezone)::date THEN 'expired_or_past'
            WHEN i.date_value <= (CURRENT_TIMESTAMP AT TIME ZONE loc.timezone)::date + 14 THEN 'due_soon'
            ELSE 'good' END
        ) AS date,
        i.nutrition_tier AS "nutritionTier",
        jsonb_build_object('id', loc.id, 'name', loc.name) AS location,
        lot.status AS "inventoryState", i.status AS "intakeStatus",
        CASE WHEN i.status = 'auto_accepted' THEN 'auto_accepted' WHEN i.status = 'admin_accepted' THEN 'admin_accepted' ELSE NULL END AS "acceptancePath",
        s.received_at AS "receivedAt"
      FROM intake_items i
      JOIN intake_sessions s ON s.id = i.session_id
      JOIN locations loc ON loc.id = i.storage_location_id
      LEFT JOIN inventory_lots lot ON lot.intake_item_id = i.id
      WHERE i.organization_id = $1 AND ($2::text IS NULL OR i.product_name ILIKE '%' || $2 || '%' OR COALESCE(i.brand, '') ILIKE '%' || $2 || '%')
      ORDER BY i.date_value ASC NULLS LAST, s.received_at ASC, i.id ASC
      LIMIT $3`,
      [actor.organizationId, search?.trim() || null, safeLimit],
    );
    return { items: result.rows, nextCursor: null };
  }
}
