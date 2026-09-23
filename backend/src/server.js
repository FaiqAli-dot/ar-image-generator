import { createApp } from "./app.js";
import { config } from "./config.js";
import { ensureStorage } from "./storage.js";

await ensureStorage();
const app = createApp();

app.listen(config.port, () => {
  // eslint-disable-next-line no-console
  console.log(`AR Food object API listening on :${config.port}`);
  if (config.publicBaseUrl) {
    // eslint-disable-next-line no-console
    console.log(`Public base URL: ${config.publicBaseUrl}`);
  }
});
