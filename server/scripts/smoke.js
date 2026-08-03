import assert from "node:assert/strict";
import { WebSocket } from "ws";

const origin = (process.argv[2] ?? "https://zhuzhiliao.aimfor.top").replace(/\/$/, "");
const websocketURL = origin.replace(/^http/, "ws") + "/api/ws";

const healthResponse = await fetch(`${origin}/healthz`);
assert.equal(healthResponse.status, 200);
assert.deepEqual(await healthResponse.json(), { status: "ok" });

const statsResponse = await fetch(`${origin}/api/stats`);
assert.equal(statsResponse.status, 200);
const stats = await statsResponse.json();
assert.equal(Number.isInteger(stats.online), true);
assert.equal(Number.isInteger(stats.wahs), true);

const webSocketStats = await new Promise((resolve, reject) => {
  const socket = new WebSocket(websocketURL);
  const timer = setTimeout(() => {
    socket.terminate();
    reject(new Error("WebSocket smoke test timed out"));
  }, 5_000);

  socket.once("error", reject);
  socket.once("message", (data) => {
    clearTimeout(timer);
    const message = JSON.parse(data.toString("utf8"));
    socket.close();
    resolve(message);
  });
});

assert.equal(webSocketStats.t, "stats");
assert.equal(Number.isInteger(webSocketStats.online), true);
assert.equal(Number.isInteger(webSocketStats.wahs), true);
console.log(JSON.stringify({ health: "ok", stats, webSocket: webSocketStats }, null, 2));
