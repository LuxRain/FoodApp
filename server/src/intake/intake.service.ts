import { BadRequestException, ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import type { PoolClient } from "pg";
import { DatabaseService } from "../database/database.service";
import { evaluateAcceptance } from "../domain/policy";
import type { AcceptanceInput, DateType, StorageType } from "../domain/types";
import type { RequestActor } from "../auth/request-context";
import type { AdminDecisionDto, CreateItemDto, CreateSessionDto, SubmitItemDto } from "./dto";

type ItemRow = {
  id: string; organization_id: string; product_id: string | null; product_name: string; identity_source: AcceptanceInput["identitySource"];
  quantity: string; quantity_unit: string; date_type: DateType; date_value: string | null; storage_type: StorageType; storage_location_id: string;
  package_condition: string; temperature_status: string; required_field_confidence: number[]; nutrition_tier: string; status: string;
};

@Injectable()
export class IntakeService {
  constructor(private readonly db: DatabaseService) {}

  async createSession(actor: RequestActor, dto: CreateSessionDto) {
    const existing = await this.db.query("SELECT id, status FROM intake_sessions WHERE organization_id = $1 AND client_mutation_id = $2", [actor.organizationId, dto.clientMutationId]);
    if (existing.rowCount) return existing.rows[0];
    const result = await this.db.query(
      `INSERT INTO intake_sessions (organization_id, receiving_location_id, received_at, source_channel, created_by, client_mutation_id)
       SELECT $1, id, $3, $4, $5, $6 FROM locations WHERE id = $2 AND organization_id = $1
       RETURNING id, status, received_at`,
      [actor.organizationId, dto.receivingLocationId, dto.receivedAt, dto.sourceChannel ?? null, actor.userId, dto.clientMutationId],
    );
    if (!result.rowCount) throw new BadRequestException("Receiving location is outside the organization");
    return result.rows[0];
  }

  async createItem(actor: RequestActor, sessionId: string, dto: CreateItemDto, idempotencyKey: string) {
    if (!idempotencyKey) throw new BadRequestException("Idempotency-Key header is required");
    return this.db.transaction(async (client) => {
      const replay = await client.query("SELECT result FROM sync_mutations WHERE organization_id = $1 AND client_mutation_id = $2", [actor.organizationId, idempotencyKey]);
      if (replay.rowCount) return replay.rows[0].result;
      const result = await client.query(
        `INSERT INTO intake_items (
          organization_id, session_id, product_id, product_name, brand, category, identity_source, scanned_code, quantity, quantity_unit,
          date_type, date_value, date_label_raw, storage_type, storage_location_id, package_condition,
          temperature_status, calorie_status, calories, calorie_basis, allergen_summary, required_field_confidence, status
        )
        SELECT $1, s.id, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, l.id, $16, $17, $18, $19, $20, $21::jsonb, $22::jsonb, 'ready_for_user_review'
        FROM intake_sessions s JOIN locations l ON l.id = $15 AND l.organization_id = s.organization_id
        WHERE s.id = $2 AND s.organization_id = $1
        RETURNING id, status, version`,
        [actor.organizationId, sessionId, dto.productId ?? null, dto.productName, dto.brand ?? null, dto.category ?? "other", dto.identitySource, dto.scannedCode ?? null,
          dto.quantity, dto.quantityUnit, dto.dateType, dto.dateValue ?? null, dto.dateLabelRaw ?? null, dto.storageType,
          dto.storageLocationId, dto.packageCondition, dto.temperatureStatus, dto.calorieStatus, dto.calories ?? null,
          dto.calorieBasis ?? null, JSON.stringify(dto.allergens), JSON.stringify(dto.requiredFieldConfidence)],
      );
      if (!result.rowCount) throw new BadRequestException("Session or storage location is invalid");
      const response = result.rows[0];
      await client.query("INSERT INTO sync_mutations (organization_id, client_mutation_id, result) VALUES ($1, $2, $3::jsonb)", [actor.organizationId, idempotencyKey, JSON.stringify(response)]);
      return response;
    });
  }

  async submitItem(actor: RequestActor, itemId: string, dto: SubmitItemDto, idempotencyKey: string) {
    if (!idempotencyKey) throw new BadRequestException("Idempotency-Key header is required");
    return this.db.transaction(async (client) => {
      const replay = await client.query("SELECT result FROM sync_mutations WHERE organization_id = $1 AND client_mutation_id = $2", [actor.organizationId, idempotencyKey]);
      if (replay.rowCount) return replay.rows[0].result;
      const itemResult = await client.query<ItemRow>("SELECT * FROM intake_items WHERE id = $1 AND organization_id = $2 FOR UPDATE", [itemId, actor.organizationId]);
      const item = itemResult.rows[0];
      if (!item) throw new NotFoundException("Intake item not found");
      if (!['ready_for_user_review', 'processing'].includes(item.status)) throw new ConflictException(`Item cannot be submitted from ${item.status}`);

      const days = item.date_value ? await this.daysRemaining(client, item.date_value, item.storage_location_id) : null;
      const outcome = evaluateAcceptance({
        productId: item.product_id, identitySource: item.identity_source, requiredFieldConfidence: item.required_field_confidence,
        userReviewedAt: dto.userReviewedAt, dateType: item.date_type, dateValue: item.date_value, remainingDays: days,
        storageType: item.storage_type, packageCondition: item.package_condition, temperatureStatus: item.temperature_status,
        allergenConflict: dto.allergenConflict, evidenceConflict: dto.evidenceConflict, duplicateSuspected: dto.duplicateSuspected,
      });
      const status = outcome.route === "auto_accept" ? "auto_accepted" : "pending_admin_review";
      await client.query(
        `UPDATE intake_items SET status = $3::intake_status, user_reviewed_at = $4, submitted_at = now(), decided_at = CASE WHEN $3::text = 'auto_accepted' THEN now() ELSE NULL END,
          decision_by = CASE WHEN $3::text = 'auto_accepted' THEN 'system' ELSE NULL END, routing_reason_codes = $5, version = version + 1, updated_at = now()
         WHERE id = $1 AND organization_id = $2`, [itemId, actor.organizationId, status, dto.userReviewedAt, outcome.reasonCodes],
      );
      let inventoryLotId: string | null = null;
      if (status === "auto_accepted") inventoryLotId = await this.createInventory(client, actor, item, idempotencyKey, "Automatic acceptance");
      const response = { intakeItemId: itemId, status, routingReasonCodes: outcome.reasonCodes, inventoryLotId };
      await client.query("INSERT INTO sync_mutations (organization_id, client_mutation_id, result) VALUES ($1, $2, $3::jsonb)", [actor.organizationId, idempotencyKey, JSON.stringify(response)]);
      return response;
    });
  }

  async reviewQueue(actor: RequestActor) {
    const result = await this.db.query(
      `SELECT i.id, i.product_name AS "productName", i.brand, i.category, i.scanned_code AS "scannedCode", i.identity_source AS "identitySource",
        i.quantity::float8, i.quantity_unit AS "quantityUnit", i.date_type AS "dateType", i.date_value AS "dateValue",
        i.date_label_raw AS "dateLabelRaw", i.storage_type AS "storageType", loc.name AS "storageLocationName",
        i.package_condition AS "packageCondition", i.temperature_status AS "temperatureStatus",
        i.calorie_status AS "calorieStatus", i.calories::float8, i.calorie_basis AS "calorieBasis",
        i.allergen_summary AS allergens, i.routing_reason_codes AS "routingReasonCodes", i.status, i.created_at AS "createdAt"
       FROM intake_items i JOIN locations loc ON loc.id = i.storage_location_id
       WHERE i.organization_id = $1 AND i.status IN ('pending_admin_review', 'quarantined') ORDER BY i.created_at`, [actor.organizationId],
    );
    return { items: result.rows };
  }

  async decide(actor: RequestActor, itemId: string, dto: AdminDecisionDto, idempotencyKey: string) {
    if (!idempotencyKey) throw new BadRequestException("Idempotency-Key header is required");
    return this.db.transaction(async (client) => {
      const replay = await client.query("SELECT result FROM sync_mutations WHERE organization_id = $1 AND client_mutation_id = $2", [actor.organizationId, idempotencyKey]);
      if (replay.rowCount) return replay.rows[0].result;
      const result = await client.query<ItemRow>("SELECT * FROM intake_items WHERE id = $1 AND organization_id = $2 FOR UPDATE", [itemId, actor.organizationId]);
      const item = result.rows[0];
      if (!item) throw new NotFoundException("Intake item not found");
      if (!['pending_admin_review', 'quarantined'].includes(item.status)) throw new ConflictException(`Item cannot be decided from ${item.status}`);
      const status = dto.decision === "accept" ? "admin_accepted" : dto.decision === "quarantine" ? "quarantined" : "rejected";
      if ((status === "admin_accepted" || status === "quarantined") && !item.product_id) {
        const product = await client.query<{ id: string }>(
          `INSERT INTO products (organization_id, canonical_name, brand, category, default_unit)
          SELECT organization_id, product_name, brand, category, quantity_unit
           FROM intake_items WHERE id = $1 AND organization_id = $2 RETURNING id`,
          [itemId, actor.organizationId],
        );
        item.product_id = product.rows[0].id;
        await client.query("UPDATE intake_items SET product_id = $3 WHERE id = $1 AND organization_id = $2", [itemId, actor.organizationId, item.product_id]);
      }
      await client.query("UPDATE intake_items SET status = $3::intake_status, decision_by = $4, decision_reason = $5, decided_at = now(), version = version + 1, updated_at = now() WHERE id = $1 AND organization_id = $2", [itemId, actor.organizationId, status, actor.userId, dto.reason]);
      let inventoryLotId: string | null = null;
      if (status === "admin_accepted" || status === "quarantined") inventoryLotId = await this.createInventory(client, actor, item, idempotencyKey, dto.reason, status === "quarantined");
      if (status === "rejected" && item.status === "quarantined") await this.disposeInventory(client, actor, item, idempotencyKey, dto.reason);
      const response = { intakeItemId: itemId, status, inventoryLotId };
      await client.query("INSERT INTO audit_events (organization_id, actor_id, action, target_type, target_id, after_value) VALUES ($1, $2, $3, 'intake_item', $4, $5::jsonb)", [actor.organizationId, actor.userId, `admin_${dto.decision}`, itemId, JSON.stringify(response)]);
      await client.query("INSERT INTO sync_mutations (organization_id, client_mutation_id, result) VALUES ($1, $2, $3::jsonb)", [actor.organizationId, idempotencyKey, JSON.stringify(response)]);
      return response;
    });
  }

  private async daysRemaining(client: PoolClient, dateValue: string, locationId: string): Promise<number | null> {
    const result = await client.query<{ days: number }>(`SELECT ($1::date - (CURRENT_TIMESTAMP AT TIME ZONE timezone)::date)::int AS days FROM locations WHERE id = $2`, [dateValue, locationId]);
    return result.rows[0]?.days ?? null;
  }

  private async createInventory(client: PoolClient, actor: RequestActor, item: ItemRow, key: string, reason: string, quarantined = false): Promise<string> {
    if (!item.product_id) throw new ConflictException("Accepted inventory requires a resolved product");
    const existing = await client.query<{ id: string }>("SELECT id FROM inventory_lots WHERE intake_item_id = $1 AND organization_id = $2 FOR UPDATE", [item.id, actor.organizationId]);
    if (existing.rowCount) {
      await client.query(
        "UPDATE inventory_lots SET status = $3::inventory_status, row_version = row_version + 1, updated_at = now() WHERE id = $1 AND organization_id = $2",
        [existing.rows[0].id, actor.organizationId, quarantined ? "quarantined" : "available"],
      );
      return existing.rows[0].id;
    }
    const lot = await client.query<{ id: string }>(
      `INSERT INTO inventory_lots (organization_id, intake_item_id, product_id, location_id, on_hand_quantity, unit, date_type, date_value, storage_type, status, nutrition_tier)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,
      [actor.organizationId, item.id, item.product_id, item.storage_location_id, item.quantity, item.quantity_unit, item.date_type, item.date_value, item.storage_type, quarantined ? "quarantined" : "available", item.nutrition_tier],
    );
    await client.query(
      `INSERT INTO inventory_movements (organization_id, lot_id, movement_type, quantity_delta, actor_id, reason, idempotency_key)
       VALUES ($1,$2,'RECEIVE',$3,$4,$5,$6) ON CONFLICT (organization_id, idempotency_key) DO NOTHING`,
      [actor.organizationId, lot.rows[0].id, item.quantity, actor.userId, reason, `${key}:receive`],
    );
    return lot.rows[0].id;
  }

  private async disposeInventory(client: PoolClient, actor: RequestActor, item: ItemRow, key: string, reason: string): Promise<void> {
    const lot = await client.query<{ id: string; on_hand_quantity: string }>(
      "SELECT id, on_hand_quantity FROM inventory_lots WHERE intake_item_id = $1 AND organization_id = $2 FOR UPDATE",
      [item.id, actor.organizationId],
    );
    if (!lot.rowCount) return;
    await client.query(
      "UPDATE inventory_lots SET status = 'disposed', on_hand_quantity = 0, row_version = row_version + 1, updated_at = now() WHERE id = $1 AND organization_id = $2",
      [lot.rows[0].id, actor.organizationId],
    );
    await client.query(
      `INSERT INTO inventory_movements (organization_id, lot_id, movement_type, quantity_delta, actor_id, reason, idempotency_key)
       VALUES ($1, $2, 'DISPOSE', $3, $4, $5, $6) ON CONFLICT (organization_id, idempotency_key) DO NOTHING`,
      [actor.organizationId, lot.rows[0].id, -Number(lot.rows[0].on_hand_quantity), actor.userId, reason, `${key}:dispose`],
    );
  }
}
