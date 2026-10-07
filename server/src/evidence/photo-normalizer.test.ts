import assert from "node:assert/strict";
import test from "node:test";
import { BadRequestException } from "@nestjs/common";
import sharp from "sharp";
import { normalizePhoto } from "./photo-normalizer";

const image = () => sharp({ create: { width: 4, height: 4, channels: 4, background: "#ffffff" } });
const upload = (buffer: Buffer, mimetype: string) => ({ buffer, size: buffer.length, mimetype });

test("keeps JPEG and PNG evidence unchanged", async () => {
  for (const [buffer, mimetype, extension] of [
    [await image().jpeg().toBuffer(), "image/jpeg", "jpg"],
    [await image().png().toBuffer(), "image/png", "png"],
  ] as const) {
    const result = await normalizePhoto(upload(buffer, mimetype));
    assert.equal(result.extension, extension);
    assert.deepEqual(result.buffer, buffer);
  }
});

test("converts WebP, AVIF, GIF and TIFF to JPEG", async () => {
  for (const [buffer, mimetype] of [
    [await image().webp().toBuffer(), "image/webp"],
    [await image().avif().toBuffer(), "image/avif"],
    [await image().gif().toBuffer(), "image/gif"],
    [await image().tiff().toBuffer(), "image/tiff"],
  ] as const) {
    const result = await normalizePhoto(upload(buffer, mimetype));
    assert.equal(result.extension, "jpg");
    assert.equal((await sharp(result.buffer).metadata()).format, "jpeg");
  }
});

test("rejects mismatched content type and unreadable bytes", async () => {
  const png = await image().png().toBuffer();
  await assert.rejects(normalizePhoto(upload(png, "image/jpeg")), BadRequestException);
  await assert.rejects(normalizePhoto(upload(Buffer.from("not a photo"), "image/jpeg")), BadRequestException);
});
