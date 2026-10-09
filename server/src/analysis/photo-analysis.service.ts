import { BadGatewayException, BadRequestException, Injectable, ServiceUnavailableException } from "@nestjs/common";
import sharp from "sharp";
import { normalizePhoto } from "../evidence/photo-normalizer";
import { labelClaimCodes, type LabelClaimCode } from "./label-claims";

type Upload = { buffer: Buffer; size: number; mimetype: string };
export type PhotoAnalysis = {
  productName: string | null;
  brand: string | null;
  ingredients: string | null;
  allergens: string | null;
  packageWeight: string | null;
  printedDate: string | null;
  printedDateType: "best_if_used_by" | "best_before" | "use_by" | "expiration" | "sell_by" | null;
  calories: number | null;
  calorieBasis: "per_serving" | "per_100g" | "per_package" | null;
  servingSize: string | null;
  dietaryClaims: LabelClaimCode[];
  otherLabelClaims: string[];
};

const fields = ["productName", "brand", "ingredients", "allergens", "packageWeight", "printedDate"] as const;
const schema = {
  type: "object",
  properties: {
    ...Object.fromEntries(fields.map((field) => [field, { type: ["string", "null"] }])),
    calories: { type: ["number", "null"] },
    printedDateType: { type: ["string", "null"], enum: ["best_if_used_by", "best_before", "use_by", "expiration", "sell_by", null] },
    calorieBasis: { type: ["string", "null"], enum: ["per_serving", "per_100g", "per_package", null] },
    servingSize: { type: ["string", "null"] },
    dietaryClaims: { type: "array", items: { type: "string", enum: labelClaimCodes } },
    otherLabelClaims: { type: "array", maxItems: 8, items: { type: "string", maxLength: 120 } },
  },
  required: [...fields, "printedDateType", "calories", "calorieBasis", "servingSize", "dietaryClaims", "otherLabelClaims"],
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
  const calories = record.calories;
  const printedDateType = record.printedDateType;
  const basis = record.calorieBasis;
  const servingSize = record.servingSize;
  const claims = record.dietaryClaims;
  if (calories !== null && (typeof calories !== "number" || !Number.isFinite(calories) || calories < 0)) throw new BadGatewayException("The vision model returned invalid calories");
  if (printedDateType !== null && !["best_if_used_by", "best_before", "use_by", "expiration", "sell_by"].includes(printedDateType as string)) throw new BadGatewayException("The vision model returned invalid printed date type");
  if (basis !== null && !["per_serving", "per_100g", "per_package"].includes(basis as string)) throw new BadGatewayException("The vision model returned invalid calorie basis");
  if (servingSize !== null && typeof servingSize !== "string") throw new BadGatewayException("The vision model returned invalid serving size");
  if (!Array.isArray(claims) || !claims.every((claim) => labelClaimCodes.includes(claim))) throw new BadGatewayException("The vision model returned invalid dietary claims");
  const otherClaims = record.otherLabelClaims;
  if (!Array.isArray(otherClaims) || otherClaims.length > 8 || !otherClaims.every((claim) => typeof claim === "string" && claim.length <= 120)) throw new BadGatewayException("The vision model returned invalid other label claims");
  result.calories = calories as number | null;
  result.printedDateType = printedDateType as PhotoAnalysis["printedDateType"];
  result.calorieBasis = basis as PhotoAnalysis["calorieBasis"];
  result.servingSize = typeof servingSize === "string" ? servingSize.trim().slice(0, 200) || null : null;
  result.dietaryClaims = [...new Set(claims)] as PhotoAnalysis["dietaryClaims"];
  result.otherLabelClaims = [...new Set(otherClaims.map((claim: string) => claim.trim()).filter(Boolean))];
  if (result.calories === null) result.calorieBasis = null;
  if (result.printedDate === null) result.printedDateType = null;
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
          messages: [{ role: "user", content: `These photos show ONE food package. Read only visible text and visual product identity. Return productName, brand, ingredients, allergens, packageWeight, printedDate, printedDateType, calories, calorieBasis, servingSize, dietaryClaims, otherLabelClaims. For printedDate, transcribe the complete date-bearing label phrase when visible, including words such as BEST BEFORE, BEST IF USED BY, USE BY, EXP, or SELL BY; not just its digits. printedDateType must be best_if_used_by, best_before, use_by, expiration, or sell_by ONLY if those words or an unambiguous abbreviation are visibly printed near that date. If only digits are visible, use null for printedDateType; do not infer it from the product or date. calories is the numeric Calories value from the Nutrition Facts label; calorieBasis must be per_serving, per_100g, or per_package only when printed. servingSize is the printed serving-size text. dietaryClaims may contain only these codes: ${labelClaimCodes.join(", ")}. Add a code ONLY when an equivalent claim for the whole product is explicitly printed on the package; never infer it from ingredients, nutrition numbers, symbols without readable text, or product appearance. Organic certification text can support organic, but organic ingredients alone cannot. Put other explicit dietary, nutrient, ingredient-restriction, sourcing, or religious claims not in that list into otherLabelClaims as short verbatim text; do not duplicate catalog claims. Exclude generic slogans such as 'real ingredients', storage instructions such as 'keep refrigerated' or 'perishable', product origin, distributor details, and ordinary Nutrition Facts values from otherLabelClaims. allergens is only an explicit Contains or May contain statement, never an inferred absence. Preserve original language for text. Use null when absent or unreadable and [] when no claim is visible. Never infer allergens, dates, calories, or ingredients from appearance. Do not treat a barcode number as a product name.`, images }],
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
