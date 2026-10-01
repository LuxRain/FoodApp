import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { dirname, resolve, sep } from "node:path";
import { DatabaseService } from "../database/database.service";
import type { RequestActor } from "../auth/request-context";

type EvidenceRow = {
  id: string;
  intake_item_id: string;
  evidence_type: string;
  captured_at: Date;
  created_at: Date;
  content_hash: string;
  object_key: string;
};

const MAX_PHOTO_BYTES = 10 * 1024 * 1024;

@Injectable()
export class EvidenceService {
  private readonly storageRoot = resolve(process.env.EVIDENCE_STORAGE_DIR ?? "var/evidence");

  constructor(private readonly db: DatabaseService) {}

  async upload(actor: RequestActor, itemId: string, file: { buffer: Buffer; size: number; mimetype: string } | undefined, capturedAtRaw: string | undefined) {
    this.assertUUID(itemId);
    if (!file?.buffer?.length || file.size > MAX_PHOTO_BYTES) throw new BadRequestException("Upload one photo up to 10 MB");
    const extension = this.detectImage(file.buffer);
    if (!extension) throw new BadRequestException("Only JPEG and PNG package photos are supported");
    if ((extension === "jpg" && file.mimetype !== "image/jpeg") || (extension === "png" && file.mimetype !== "image/png")) {
      throw new BadRequestException("Photo content type does not match the file");
    }
    const capturedAt = capturedAtRaw ? new Date(capturedAtRaw) : new Date();
    if (Number.isNaN(capturedAt.getTime())) throw new BadRequestException("capturedAt must be a valid date");
    await this.requireItem(actor, itemId);

    const hash = createHash("sha256").update(file.buffer).digest("hex");
    const existing = await this.db.query<EvidenceRow>(
      "SELECT * FROM evidence_assets WHERE intake_item_id = $1 AND content_hash = $2 AND evidence_type = 'date_label' LIMIT 1",
      [itemId, hash],
    );
    if (existing.rows[0]) return this.publicAsset(existing.rows[0]);

    const objectKey = `${actor.organizationId}/${itemId}/${randomUUID()}.${extension}`;
    const filePath = this.filePath(objectKey);
    await mkdir(dirname(filePath), { recursive: true, mode: 0o700 });
    await writeFile(filePath, file.buffer, { flag: "wx", mode: 0o600 });
    try {
      const result = await this.db.query<EvidenceRow>(
        `INSERT INTO evidence_assets (intake_item_id, object_key, content_hash, evidence_type, captured_at, malware_scan_state)
         VALUES ($1, $2, $3, 'date_label', $4, 'not_scanned') RETURNING *`,
        [itemId, objectKey, hash, capturedAt],
      );
      return this.publicAsset(result.rows[0]);
    } catch (error) {
      await unlink(filePath).catch(() => {});
      throw error;
    }
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

  private detectImage(bytes: Buffer): "jpg" | "png" | null {
    if (bytes.length >= 3 && bytes.subarray(0, 3).equals(Buffer.from([0xff, 0xd8, 0xff]))) return "jpg";
    if (bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return "png";
    return null;
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
