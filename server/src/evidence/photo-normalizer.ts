import { BadRequestException } from "@nestjs/common";
import sharp, { type Metadata } from "sharp";

const convertHEIC: (options: { buffer: Buffer; format: "JPEG"; quality: number }) => Promise<Buffer> = require("heic-convert");

const MAX_PHOTO_BYTES = 10 * 1024 * 1024;
const MAX_IMAGE_PIXELS = 40_000_000;

const acceptedMimes: Record<string, string[]> = {
  jpeg: ["image/jpeg"],
  png: ["image/png"],
  webp: ["image/webp"],
  avif: ["image/avif"],
  heic: ["image/heic", "image/heif"],
  gif: ["image/gif"],
  tiff: ["image/tiff"],
};

export type NormalizedPhoto = { buffer: Buffer; extension: "jpg" | "png" };

export async function normalizePhoto(file: { buffer: Buffer; size: number; mimetype: string } | undefined): Promise<NormalizedPhoto> {
  if (!file?.buffer?.length || file.size > MAX_PHOTO_BYTES || file.buffer.length > MAX_PHOTO_BYTES) {
    throw new BadRequestException("Upload one photo up to 10 MB");
  }

  let metadata: Metadata;
  try {
    metadata = await sharp(file.buffer, { limitInputPixels: MAX_IMAGE_PIXELS }).metadata();
  } catch {
    throw new BadRequestException("The uploaded file is not a readable image");
  }
  const format = metadata.format === "heif"
    ? metadata.compression === "hevc" ? "heic" : metadata.compression === "av1" ? "avif" : "unsupported"
    : metadata.format;
  if (!format || !acceptedMimes[format]) {
    throw new BadRequestException("Use a JPEG, PNG, HEIC, HEIF, WebP, AVIF, GIF, or TIFF photo");
  }
  if (!acceptedMimes[format].includes(file.mimetype)) {
    throw new BadRequestException("Photo content type does not match the file");
  }
  if (!metadata.width || !metadata.height || metadata.width * metadata.height > MAX_IMAGE_PIXELS) {
    throw new BadRequestException("Photo dimensions are too large");
  }

  // Existing JPEG/PNG evidence remains byte-for-byte stable for idempotent retries.
  if (format === "jpeg") return { buffer: file.buffer, extension: "jpg" };
  if (format === "png") return { buffer: file.buffer, extension: "png" };

  try {
    const source = format === "heic"
      ? Buffer.from(await convertHEIC({ buffer: file.buffer, format: "JPEG", quality: 0.9 }))
      : file.buffer;
    const buffer = await sharp(source, { limitInputPixels: MAX_IMAGE_PIXELS })
      .rotate()
      .resize({ width: 3072, height: 3072, fit: "inside", withoutEnlargement: true })
      .flatten({ background: "#ffffff" })
      .jpeg({ quality: 88 })
      .toBuffer();
    if (buffer.length > MAX_PHOTO_BYTES) throw new BadRequestException("Converted photo is too large to upload");
    return { buffer, extension: "jpg" };
  } catch (error) {
    if (error instanceof BadRequestException) throw error;
    throw new BadRequestException("The uploaded photo could not be converted");
  }
}
