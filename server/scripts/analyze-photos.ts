import { readFile } from "node:fs/promises";
import { extname } from "node:path";
import { PhotoAnalysisService } from "../src/analysis/photo-analysis.service";

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
  const photos: Array<{ buffer: Buffer; size: number; mimetype: string }> = [];
  for (const path of paths) {
    const mimetype = mimeByExtension[extname(path).toLowerCase()];
    if (!mimetype) throw new Error(`Unsupported image filename: ${path}`);
    const buffer = await readFile(path);
    photos.push({ buffer, size: buffer.length, mimetype });
  }
  console.log(JSON.stringify(await new PhotoAnalysisService().analyze(photos), null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
