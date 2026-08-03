import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { WebSocket } from "ws";
import { createCounterServer } from "../src/server.js";

const cleanups = [];

afterEach(async () => {
  while (cleanups.length > 0) {
    await cleanups.pop()();
  }
});

async function startServer(databasePath) {
  const app = createCounterServer({ databasePath });
  const address = await app.listen({ host: "127.0.0.1", port: 0 });
  cleanups.push(() => app.close());
  return {
    app,
    httpURL: `http://127.0.0.1:${address.port}`,
    wsURL: `ws://127.0.0.1:${address.port}/api/ws`
  };
}

function connect(url) {
  const socket = new WebSocket(url);
  const queued = [];
  const waiters = [];

  socket.on("message", (data) => {
    const text = data.toString("utf8");
    const matchingIndex = waiters.findIndex(({ predicate }) => predicate(text));
    if (matchingIndex >= 0) {
      const [{ resolve, timer }] = waiters.splice(matchingIndex, 1);
      clearTimeout(timer);
      resolve(text);
    } else {
      queued.push(text);
    }
  });

  return {
    socket,
    next(predicate = () => true) {
      const matchingIndex = queued.findIndex(predicate);
      if (matchingIndex >= 0) {
        return Promise.resolve(queued.splice(matchingIndex, 1)[0]);
      }

      return new Promise((resolve, reject) => {
        const waiter = { predicate, resolve };
        waiter.timer = setTimeout(() => {
          const index = waiters.indexOf(waiter);
          if (index >= 0) {
            waiters.splice(index, 1);
          }
          reject(new Error("Timed out waiting for WebSocket message"));
        }, 2_000);
        waiters.push(waiter);
      });
    }
  };
}

async function jsonResponse(url) {
  const response = await fetch(url);
  return { status: response.status, body: await response.json() };
}

test("reports live connections and persists only global wahs", async () => {
  const directory = await mkdtemp(join(tmpdir(), "zhuzhiliao-server-"));
  cleanups.push(() => rm(directory, { recursive: true, force: true }));
  const databasePath = join(directory, "counter.sqlite");
  const server = await startServer(databasePath);
  const client = connect(server.wsURL);
  cleanups.push(() => client.socket.terminate());

  const connected = JSON.parse(await client.next((text) => text.includes('"online":1')));
  assert.deepEqual(connected, { t: "stats", online: 1, wahs: 0 });

  client.socket.send(JSON.stringify({ t: "wah", n: 7 }));
  const incremented = JSON.parse(await client.next((text) => text.includes('"wahs":7')));
  assert.deepEqual(incremented, { t: "stats", online: 1, wahs: 7 });

  const stats = await jsonResponse(`${server.httpURL}/api/stats`);
  assert.deepEqual(stats, { status: 200, body: { online: 1, wahs: 7 } });

  await new Promise((resolve) => {
    client.socket.once("close", resolve);
    client.socket.close();
  });
  assert.deepEqual(server.app.getStats(), { online: 0, wahs: 7 });

  await cleanups.pop()();
  const restarted = await startServer(databasePath);
  const persisted = await jsonResponse(`${restarted.httpURL}/api/stats`);
  assert.deepEqual(persisted.body, { online: 0, wahs: 7 });
});

test("rejects invalid increments without changing the counter", async () => {
  const server = await startServer(":memory:");
  const client = connect(server.wsURL);
  cleanups.push(() => client.socket.terminate());
  await client.next((text) => text.includes('"online":1'));

  client.socket.send(JSON.stringify({ t: "wah", n: 31 }));
  await new Promise((resolve) => client.socket.once("close", resolve));

  const stats = await jsonResponse(`${server.httpURL}/api/stats`);
  assert.deepEqual(stats.body, { online: 0, wahs: 0 });
});

test("exposes health and rejects plain HTTP on the WebSocket path", async () => {
  const server = await startServer(":memory:");

  const health = await jsonResponse(`${server.httpURL}/healthz`);
  assert.deepEqual(health, { status: 200, body: { status: "ok" } });

  const websocket = await jsonResponse(`${server.httpURL}/api/ws`);
  assert.deepEqual(websocket, {
    status: 426,
    body: { error: "WebSocket upgrade required" }
  });
});
