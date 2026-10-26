import { createApp } from "./app.js";
import { config } from "./config.js";
import { ensureStorage } from "./storage.js";
import { ensureGlbDirs } from "./glb/pipeline.js";

await ensureStorage();
await ensureGlbDirs();
const app = createApp();

app.listen(config.port, () => {
  // eslint-disable-next-line no-console
  console.log(`AR Food object API listening on :${config.port}`);
  // eslint-disable-next-line no-console
  console.log(`Owner GLB import: http://localhost:${config.port}/owner`);
  if (config.publicBaseUrl) {
    // eslint-disable-next-line no-console
    console.log(`Public base URL: ${config.publicBaseUrl}`);
  }
});
