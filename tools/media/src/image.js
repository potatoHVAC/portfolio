import { mkdtemp, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";
import { sha256Buffer } from "./hash.js";
import { checkImageMetadata } from "./metadata.js";
import { deliveryKey } from "./paths.js";

const MAX_PIXELS = 100_000_000;
const TARGET_WIDTHS = [480, 768, 1200, 1600, 2400];
const FORMATS = {
  avif: { extension: "avif", contentType: "image/avif" },
  webp: { extension: "webp", contentType: "image/webp" },
  jpeg: { extension: "jpg", contentType: "image/jpeg" },
};

function orientedDimensions(metadata) {
  if ([5, 6, 7, 8].includes(metadata.orientation)) {
    return { width: metadata.height, height: metadata.width };
  }
  return { width: metadata.width, height: metadata.height };
}

function outputWidths(sourceWidth) {
  const widths = TARGET_WIDTHS.filter((width) => width <= sourceWidth);
  if (sourceWidth < TARGET_WIDTHS.at(-1) && !widths.includes(sourceWidth)) {
    widths.push(sourceWidth);
  }
  return widths.length > 0 ? widths.sort((a, b) => a - b) : [sourceWidth];
}

function pipelineFor(sourcePath, width) {
  return sharp(sourcePath, { animated: true, limitInputPixels: MAX_PIXELS })
    .rotate()
    .resize({ width, withoutEnlargement: true })
    .keepIccProfile();
}

async function encode(sourcePath, width, format) {
  let pipeline = pipelineFor(sourcePath, width);
  if (format === "avif") pipeline = pipeline.avif({ quality: 50 });
  if (format === "webp") pipeline = pipeline.webp({ quality: 80 });
  if (format === "jpeg") pipeline = pipeline.jpeg({ quality: 82, progressive: true });
  return pipeline.toBuffer({ resolveWithObject: true });
}

export async function inspectImage(source) {
  let metadata;
  try {
    metadata = await sharp(source.absolutePath, {
      animated: true,
      limitInputPixels: MAX_PIXELS,
    }).metadata();
  } catch (error) {
    throw new Error(`Unreadable image: ${error.message}`, { cause: error });
  }

  if (!metadata.width || !metadata.height) throw new Error("Image dimensions must be nonzero");
  if (metadata.width * metadata.height > MAX_PIXELS) {
    throw new Error("Image exceeds the 100-megapixel limit");
  }
  if ((metadata.pages ?? 1) !== 1) throw new Error("Animated images are unsupported");
  if (metadata.format !== source.expectedFormat) {
    throw new Error(
      `Image content is ${metadata.format ?? "unknown"}, not ${source.extension.slice(1)}`,
    );
  }

  const dimensions = orientedDimensions(metadata);
  return { ...metadata, ...dimensions };
}

export async function transformImage({
  source,
  temporaryRoot,
  metadataChecker = checkImageMetadata,
}) {
  const sourceMetadata = await inspectImage(source);
  const workDirectory = await mkdtemp(path.join(temporaryRoot, "image-"));
  const generated = [];

  try {
    const sources = { avif: [], webp: [], jpeg: [] };
    for (const format of Object.keys(FORMATS)) {
      const formatConfig = FORMATS[format];
      for (const requestedWidth of outputWidths(sourceMetadata.width)) {
        const { data, info } = await encode(source.absolutePath, requestedWidth, format);
        const checksum = sha256Buffer(data);
        const key = deliveryKey(
          source.assetId,
          checksum.hex,
          info.width,
          formatConfig.extension,
        );
        const localPath = path.join(workDirectory, path.basename(key));
        await writeFile(localPath, data);
        generated.push(localPath);
        sources[format].push({
          path: `/${key}`,
          contentType: formatConfig.contentType,
          bytes: data.byteLength,
          width: info.width,
          height: info.height,
          checksum,
          data,
        });
      }
    }

    const placeholder = await sharp(source.absolutePath, {
      animated: true,
      limitInputPixels: MAX_PIXELS,
    })
      .rotate()
      .resize({ width: 32, withoutEnlargement: true })
      .jpeg({ quality: 60, progressive: true })
      .toBuffer();

    await metadataChecker(generated);
    return {
      width: sourceMetadata.width,
      height: sourceMetadata.height,
      placeholder: `data:image/jpeg;base64,${placeholder.toString("base64")}`,
      sources,
      cleanup: () => rm(workDirectory, { recursive: true, force: true }),
    };
  } catch (error) {
    await rm(workDirectory, { recursive: true, force: true });
    throw error;
  }
}

export function publicImageEntry(transformed, sourceSha256, accessibility) {
  const sources = Object.fromEntries(
    Object.entries(transformed.sources).map(([format, descriptors]) => [
      format,
      descriptors.map((descriptor) =>
        Object.fromEntries(
          Object.entries(descriptor).filter(([key]) => !["checksum", "data"].includes(key)),
        ),
      ),
    ]),
  );
  return {
    kind: "image",
    sourceSha256,
    alt: accessibility.alt,
    ...(accessibility.decorative ? { decorative: true } : {}),
    width: transformed.width,
    height: transformed.height,
    placeholder: transformed.placeholder,
    sources,
  };
}
