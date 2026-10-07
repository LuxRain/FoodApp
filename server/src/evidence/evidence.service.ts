import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { dirname, resolve, sep } from "node:path";
import { DatabaseService } from "../database/database.service";
import type { RequestActor } from "../auth/request-context";
import { normalizePhoto } from "./photo-normalizer";

type EvidenceRow = {
  id: string;
  intake_item_id: string;
  evidence_type: string;
  captured_at: Date;
  created_at: Date;
  content_hash: string;
  object_key: string;
};

const MAX_PHOTOS_PER_ITEM = 8;

@Injectable()
export class EvidenceService {
  private readonly storageRoot = resolve(process.env.EVIDENCE_STORAGE_DIR ?? "var/evidence");

  constructor(private readonly db: DatabaseService) {}

  async upload(actor: RequestActor, itemId: string, file: { buffer: Buffer; size: number; mimetype: string } | undefined, capturedAtRaw: string | undefined, evidenceTypeRaw?: string) {
    this.assertUUID(itemId);
    const { buffer, extension } = await normalizePhoto(file);
    const capturedAt = capturedAtRaw ? new Date(capturedAtRaw) : new Date();
    if (Number.isNaN(capturedAt.getTime())) throw new BadRequestException("capturedAt must be a valid date");
    const evidenceType = evidenceTypeRaw ?? "date_label";
    if (!['date_label', 'package_photo'].includes(evidenceType)) throw new BadRequestException("Invalid evidence type");

    const hash = createHash("sha256").update(buffer).digest("hex");
    return this.db.transaction(async (client) => {
      const item = await client.query("SELECT id FROM intake_items WHERE id = $1 AND organization_id = $2 FOR UPDATE", [itemId, actor.organizationId]);
      if (!item.rowCount) throw new NotFoundException("Intake item not found");
      const existing = await client.query<EvidenceRow>(
        "SELECT * FROM evidence_assets WHERE intake_item_id = $1 AND content_hash = $2 LIMIT 1",
        [itemId, hash],
      );
      if (existing.rows[0]) return this.publicAsset(existing.rows[0]);
      const count = await client.query<{ count: number }>("SELECT COUNT(*)::int AS count FROM evidence_assets WHERE intake_item_id = $1", [itemId]);
      if (count.rows[0].count >= MAX_PHOTOS_PER_ITEM) throw new BadRequestException("An intake item can have at most eight photos");

      const objectKey = `${actor.organizationId}/${itemId}/${randomUUID()}.${extension}`;
      const filePath = this.filePath(objectKey);
      await mkdir(dirname(filePath), { recursive: true, mode: 0o700 });
      await writeFile(filePath, buffer, { flag: "wx", mode: 0o600 });
      try {
        const result = await client.query<EvidenceRow>(
          `INSERT INTO evidence_assets (intake_item_id, object_key, content_hash, evidence_type, captured_at, malware_scan_state)
           VALUES ($1, $2, $3, $4, $5, 'not_scanned') RETURNING *`,
          [itemId, objectKey, hash, evidenceType, capturedAt],
        );
        return this.publicAsset(result.rows[0]);
      } catch (error) {
        await unlink(filePath).catch(() => {});
        throw error;
      }
    });
  }

  async list(actor: RequestActor, itemId: string) {
    this.assertUUID(itemId);
    await this.requireItem(actor, itemId);
    const result = await this.db.query<EvidenceRow>(
      "SELECT * FROM evidence_assets WHERE intake_item_id = $1 ORDER BY captured_at DESC, created_at DESC",
      [itemId],
    );
    return { items: result.rows.map((row) => this.publicAsset(row)) };
  }

  async read(actor: RequestActor, itemId: string, evidenceId: string) {
    this.assertUUID(itemId);
    this.assertUUID(evidenceId);
    await this.requireItem(actor, itemId);
    const result = await this.db.query<EvidenceRow>(
      "SELECT * FROM evidence_assets WHERE id = $1 AND intake_item_id = $2",
      [evidenceId, itemId],
    );
    const asset = result.rows[0];
    if (!asset) throw new NotFoundException("Evidence not found");
    const data = await readFile(this.filePath(asset.object_key)).catch(() => { throw new NotFoundException("Evidence file is unavailable"); });
    return { data, contentType: asset.object_key.endsWith(".png") ? "image/png" : "image/jpeg" };
  }

  private async requireItem(actor: RequestActor, itemId: string) {
    const result = await this.db.query("SELECT id FROM intake_items WHERE id = $1 AND organization_id = $2", [itemId, actor.organizationId]);
    if (!result.rowCount) throw new NotFoundException("Intake item not found");
  }

  private assertUUID(value: string) {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
      throw new BadRequestException("Invalid identifier");
    }
  }

  private filePath(objectKey: string) {
    const path = resolve(this.storageRoot, objectKey);
    if (!path.startsWith(this.storageRoot + sep)) throw new BadRequestException("Invalid evidence path");
    return path;
  }

  private publicAsset(row: EvidenceRow) {
    return {
      id: row.id,
      intakeItemId: row.intake_item_id,
      evidenceType: row.evidence_type,
      capturedAt: row.captured_at,
      createdAt: row.created_at,
      contentHash: row.content_hash,
    };
  }
}
