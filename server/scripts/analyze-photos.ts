import { readFile } from "node:fs/promises";
import { extname } from "node:path";
import { normalizePhoto } from "../src/evidence/photo-normalizer";

const mimeByExtension: Record<string, string> = {
  ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
  ".heic": "image/heic", ".heif": "image/heif", ".webp": "image/webp",
  ".avif": "image/avif", ".gif": "image/gif", ".tif": "image/tiff", ".tiff": "image/tiff",
};

async function main() {
  const paths = process.argv.slice(2);
  if (paths.length < 1 || paths.length > 8) {
    throw new Error("Pass one to eight image paths: npm run analyze:photos -- photo1.heic photo2.png");
  }
  const images: string[] = [];
  for (const path of paths) {
    const mimetype = mimeByExtension[extname(path).toLowerCase()];
    if (!mimetype) throw new Error(`Unsupported image filename: ${path}`);
    const buffer = await readFile(path);
    const normalized = await normalizePhoto({ buffer, size: buffer.length, mimetype });
    images.push(normalized.buffer.toString("base64"));
  }

  const model = process.env.OLLAMA_MODEL ?? "hf.co/google/gemma-4-12B-it-qat-q4_0-gguf:Q4_0";
  const endpoint = new URL("/api/chat", process.env.OLLAMA_URL ?? "http://127.0.0.1:11434");
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      messages: [{
        role: "user",
        content: "These photos show one food package. Read only visible information. Return productName, brand, ingredients, allergens, packageWeight, and printedDate. Use null for missing fields and do not guess. Keep original-language text when present.",
        images,
      }],
      format: {
        type: "object",
        properties: {
          productName: { type: ["string", "null"] },
          brand: { type: ["string", "null"] },
          ingredients: { type: ["string", "null"] },
          allergens: { type: ["string", "null"] },
          packageWeight: { type: ["string", "null"] },
          printedDate: { type: ["string", "null"] },
        },
        required: ["productName", "brand", "ingredients", "allergens", "packageWeight", "printedDate"],
      },
      think: false,
      stream: false,
      options: { temperature: 0, num_ctx: 8192, num_predict: 768 },
    }),
    signal: AbortSignal.timeout(180_000),
  });
  if (!response.ok) throw new Error(`Ollama returned HTTP ${response.status}: ${await response.text()}`);
  const result = await response.json() as { message?: { content?: string } };
  if (!result.message?.content) throw new Error("Ollama returned no product fields");
  console.log(JSON.stringify(JSON.parse(result.message.content), null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
