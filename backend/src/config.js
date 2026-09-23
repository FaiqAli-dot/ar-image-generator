import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");

export const config = {
  port: Number(process.env.PORT || 3000),
  /** Public base URL used in permanent arUrl values. Falls back to request host. */
  publicBaseUrl: (process.env.PUBLIC_BASE_URL || "").replace(/\/$/, ""),
  dataDir: process.env.DATA_DIR || path.join(root, "data"),
  objectsDir: process.env.OBJECTS_DIR || path.join(root, "data", "objects"),
  /** Max bytes per uploaded image (default 8 MB). */
  maxImageBytes: Number(process.env.MAX_IMAGE_BYTES || 8 * 1024 * 1024),
  /** Max total views per object. */
  maxViews: Number(process.env.MAX_VIEWS || 120),
  /** Max request body / multipart field count. */
  maxFiles: Number(process.env.MAX_FILES || 130),
};
