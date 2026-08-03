import { resolve } from "node:path";
import { createCounterServer } from "./server.js";

const host = process.env.HOST ?? "127.0.0.1";
const port = Number.parseInt(process.env.PORT ?? "3210", 10);
const databasePath = resolve(
  process.env.SQLITE_PATH ?? "./data/counter.sqlite"
);
const initialWahs = Number.parseInt(process.env.INITIAL_WAHS ?? "0", 10);

if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error("PORT must be an integer between 1 and 65535");
}

if (!Number.isSafeInteger(initialWahs) || initialWahs < 0) {
  throw new Error("INITIAL_WAHS must be a non-negative safe integer");
}

const app = createCounterServer({ databasePath, initialWahs });
const address = await app.listen({ host, port });
console.log(`ZhuZhiLiao counter server listening on ${address.address}:${address.port}`);

let isShuttingDown = false;
async function shutdown(signal) {
  if (isShuttingDown) {
    return;
  }
  isShuttingDown = true;
  console.log(`Received ${signal}; shutting down`);
  await app.close();
}

process.once("SIGTERM", () => {
  shutdown("SIGTERM").catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
});

process.once("SIGINT", () => {
  shutdown("SIGINT").catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
});
