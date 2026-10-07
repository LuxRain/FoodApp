import { BadGatewayException, BadRequestException, Injectable, ServiceUnavailableException } from "@nestjs/common";
import sharp from "sharp";
import { normalizePhoto } from "../evidence/photo-normalizer";

type Upload = { buffer: Buffer; size: number; mimetype: string };
export type PhotoAnalysis = {
  productName: string | null;
  brand: string | null;
  ingredients: string | null;
  allergens: string | null;
  packageWeight: string | null;
  printedDate: string | null;
};

const fields = ["productName", "brand", "ingredients", "allergens", "packageWeight", "printedDate"] as const;
const schema = {
  type: "object",
  properties: Object.fromEntries(fields.map((field) => [field, { type: ["string", "null"] }])),
  required: fields,
};

export function parsePhotoAnalysis(content: string): PhotoAnalysis {
  let value: unknown;
  try { value = JSON.parse(content); } catch { throw new BadGatewayException("The vision model returned invalid JSON"); }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new BadGatewayException("The vision model returned invalid fields");
  const record = value as Record<string, unknown>;
  const result = {} as PhotoAnalysis;
  for (const field of fields) {
    const candidate = record[field];
    if (candidate !== null && typeof candidate !== "string") throw new BadGatewayException("The vision model returned invalid fields");
    result[field] = typeof candidate === "string" ? candidate.trim().slice(0, 4000) || null : null;
  }
  return result;
}

@Injectable()
export class PhotoAnalysisService {
  async analyze(files: Upload[] | undefined): Promise<PhotoAnalysis> {
    if (!files?.length || files.length > 8) throw new BadRequestException("Send one to eight package photos");
    if (files.reduce((sum, file) => sum + file.size, 0) > 40 * 1024 * 1024) {
      throw new BadRequestException("Package photos exceed the 40 MB request limit");
    }
    const images: string[] = [];
    for (const file of files) {
      const normalized = await normalizePhoto(file);
      const compact = await sharp(normalized.buffer)
        .rotate().resize({ width: 2048, height: 2048, fit: "inside", withoutEnlargement: true })
        .flatten({ background: "#ffffff" }).jpeg({ quality: 82 }).toBuffer();
      images.push(compact.toString("base64"));
    }

    const model = process.env.OLLAMA_MODEL ?? "hf.co/google/gemma-4-12B-it-qat-q4_0-gguf:Q4_0";
    let response: Response;
    try {
      response = await fetch(new URL("/api/chat", process.env.OLLAMA_URL ?? "http://127.0.0.1:11434"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model,
          messages: [{ role: "user", content: "These photos show ONE food package. Read only visible text and visual product identity. Return productName, brand, ingredients, allergens, packageWeight and printedDate. Preserve the original language. Use null when absent or unreadable; never infer allergens, dates or ingredients from appearance. Do not treat a barcode number as a product name.", images }],
          format: schema,
          think: false,
          stream: false,
          options: { temperature: 0, num_ctx: 8192, num_predict: 768 },
        }),
        signal: AbortSignal.timeout(180_000),
      });
    } catch {
      throw new ServiceUnavailableException("The local vision model is unavailable. Check that Ollama is running on the API Mac");
    }
    if (!response.ok) throw new BadGatewayException(`The vision model failed (HTTP ${response.status})`);
    let payload: { message?: { content?: string } };
    try { payload = await response.json() as typeof payload; }
    catch { throw new BadGatewayException("The vision model returned an invalid response"); }
    if (!payload.message?.content) throw new BadGatewayException("The vision model returned no product fields");
    return parsePhotoAnalysis(payload.message.content);
  }
}
