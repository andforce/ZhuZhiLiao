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

function connect(url, options) {
  const socket = new WebSocket(url, options);
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

async function createPlayer(httpURL) {
  const response = await fetch(`${httpURL}/api/players`, { method: "POST" });
  assert.equal(response.status, 201);
  return response.json();
}

function authorization(player) {
  return { headers: { authorization: `Bearer ${player.token}` } };
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

test("creates an anonymous player and idempotently advances their score", async () => {
  const server = await startServer(":memory:");
  const player = await createPlayer(server.httpURL);
  assert.match(player.id, /^[0-9a-f-]{36}$/);
  assert.match(player.code, /^[0-9A-HJKMNP-TV-Z]{6}$/);
  assert.ok(player.token.length >= 40);

  const client = connect(server.wsURL, authorization(player));
  cleanups.push(() => client.socket.terminate());
  const identity = JSON.parse(await client.next((text) => text.includes('"t":"player"')));
  assert.deepEqual(identity, {
    t: "player",
    id: player.id,
    code: player.code,
    score: 0,
    migrated: false,
    earthEnabled: false,
    locationCell: null
  });

  client.socket.send(JSON.stringify({ t: "migrate", personal: 0, pendingGlobal: 0 }));
  assert.deepEqual(
    JSON.parse(await client.next((text) => text.includes('"t":"migration"'))),
    { t: "migration", score: 0, migrated: true }
  );

  client.socket.send(JSON.stringify({ t: "score", value: 7 }));
  const scoreMessage = JSON.parse(await client.next((text) => text.includes('"t":"score"')));
  assert.equal(scoreMessage.t, "score");
  assert.equal(scoreMessage.score, 7);
  assert.ok(Number.isSafeInteger(scoreMessage.lastWahAt));
  client.socket.send(JSON.stringify({ t: "score", value: 7 }));
  await client.next((text) => text.includes('"t":"score"'));

  const leaderboard = await fetch(`${server.httpURL}/api/leaderboard`, {
    headers: authorization(player).headers
  });
  assert.equal(leaderboard.status, 200);
  assert.deepEqual(await leaderboard.json(), {
    totalPlayers: 1,
    entries: [{ code: player.code, score: 7, rank: 1 }],
    me: { code: player.code, score: 7, rank: 1 }
  });
  assert.equal(server.app.getStats().wahs, 7);
});

test("migrates legacy personal and pending totals exactly once", async () => {
  const server = await startServer(":memory:");
  const legacy = connect(server.wsURL);
  cleanups.push(() => legacy.socket.terminate());
  await legacy.next((text) => text.includes('"online":1'));
  legacy.socket.send(JSON.stringify({ t: "wah", n: 5 }));
  await legacy.next((text) => text.includes('"wahs":5'));

  const player = await createPlayer(server.httpURL);
  const client = connect(server.wsURL, authorization(player));
  cleanups.push(() => client.socket.terminate());
  await client.next((text) => text.includes('"t":"player"'));

  client.socket.send(JSON.stringify({ t: "migrate", personal: 7, pendingGlobal: 2 }));
  assert.equal(
    JSON.parse(await client.next((text) => text.includes('"t":"migration"'))).score,
    7
  );
  client.socket.send(JSON.stringify({ t: "migrate", personal: 99, pendingGlobal: 0 }));
  assert.equal(
    JSON.parse(await client.next((text) => text.includes('"t":"migration"'))).score,
    7
  );
  assert.equal(server.app.getStats().wahs, 7);
});

test("shares ranks for tied scores and always returns the current player", async () => {
  const server = await startServer(":memory:");
  const players = await Promise.all([
    createPlayer(server.httpURL),
    createPlayer(server.httpURL),
    createPlayer(server.httpURL)
  ]);

  for (const [index, player] of players.entries()) {
    const client = connect(server.wsURL, authorization(player));
    cleanups.push(() => client.socket.terminate());
    await client.next((text) => text.includes('"t":"player"'));
    client.socket.send(JSON.stringify({ t: "migrate", personal: 0, pendingGlobal: 0 }));
    await client.next((text) => text.includes('"t":"migration"'));
    client.socket.send(JSON.stringify({ t: "score", value: index < 2 ? 10 : 1 }));
    await client.next((text) => text.includes('"t":"score"'));
  }

  const response = await fetch(`${server.httpURL}/api/leaderboard?limit=1`, {
    headers: authorization(players[2]).headers
  });
  const leaderboard = await response.json();
  assert.equal(leaderboard.totalPlayers, 3);
  assert.equal(leaderboard.entries.length, 1);
  assert.equal(leaderboard.entries[0].rank, 1);
  assert.deepEqual(leaderboard.me, { code: players[2].code, score: 1, rank: 3 });
});

test("requires a valid token and deletes a leaderboard identity", async () => {
  const server = await startServer(":memory:");
  const unauthorized = await fetch(`${server.httpURL}/api/leaderboard`);
  assert.equal(unauthorized.status, 401);

  const player = await createPlayer(server.httpURL);
  const deleted = await fetch(`${server.httpURL}/api/players/me`, {
    method: "DELETE",
    headers: authorization(player).headers
  });
  assert.equal(deleted.status, 204);

  const afterDelete = await fetch(`${server.httpURL}/api/leaderboard`, {
    headers: authorization(player).headers
  });
  assert.equal(afterDelete.status, 401);
});

test("publishes opt-in earth points, activity, clusters, and removal", async () => {
  const server = await startServer(":memory:");
  const player = await createPlayer(server.httpURL);
  const client = connect(server.wsURL, authorization(player));
  cleanups.push(() => client.socket.terminate());
  await client.next((text) => text.includes('"t":"player"'));
  client.socket.send(JSON.stringify({ t: "migrate", personal: 0, pendingGlobal: 0 }));
  await client.next((text) => text.includes('"t":"migration"'));

  const enabled = await fetch(`${server.httpURL}/api/players/me/earth`, {
    method: "PUT",
    headers: {
      ...authorization(player).headers,
      "content-type": "application/json"
    },
    body: JSON.stringify({ enabled: true, cellID: "v1:500:1002" })
  });
  assert.equal(enabled.status, 200);
  assert.equal((await enabled.json()).cellID, "v1:500:1002");

  client.socket.send(JSON.stringify({
    t: "earth_view",
    requestID: "individual",
    detail: 4,
    bounds: []
  }));
  const initial = JSON.parse(await client.next((text) => text.includes('"requestID":"individual"')));
  assert.equal(initial.nodes.length, 1);
  assert.equal(initial.nodes[0].kind, "player");
  assert.equal(initial.nodes[0].isMe, true);
  assert.equal(initial.nodes[0].activeUntil, null);

  client.socket.send(JSON.stringify({ t: "score", value: 3 }));
  const score = JSON.parse(await client.next((text) => text.includes('"t":"score"')));
  client.socket.send(JSON.stringify({
    t: "earth_view",
    requestID: "cluster",
    detail: 0,
    bounds: []
  }));
  const clustered = JSON.parse(await client.next((text) => text.includes('"requestID":"cluster"')));
  assert.equal(clustered.nodes.length, 1);
  assert.deepEqual(
    {
      kind: clustered.nodes[0].kind,
      userCount: clustered.nodes[0].userCount,
      totalWahs: clustered.nodes[0].totalWahs,
      activeCount: clustered.nodes[0].activeCount,
      containsMe: clustered.nodes[0].containsMe
    },
    { kind: "cluster", userCount: 1, totalWahs: 3, activeCount: 1, containsMe: true }
  );
  assert.equal(clustered.nodes[0].activeUntil, score.lastWahAt + 600_000);

  const removed = await fetch(`${server.httpURL}/api/players/me/earth`, {
    method: "DELETE",
    headers: authorization(player).headers
  });
  assert.equal(removed.status, 204);
  client.socket.send(JSON.stringify({
    t: "earth_view",
    requestID: "removed",
    detail: 4,
    bounds: []
  }));
  const empty = JSON.parse(await client.next((text) => text.includes('"requestID":"removed"')));
  assert.deepEqual(empty.nodes, []);
});

test("rejects malformed earth cells without storing a location", async () => {
  const server = await startServer(":memory:");
  const player = await createPlayer(server.httpURL);
  const response = await fetch(`${server.httpURL}/api/players/me/earth`, {
    method: "PUT",
    headers: {
      ...authorization(player).headers,
      "content-type": "application/json"
    },
    body: JSON.stringify({ enabled: true, cellID: "v1:9999:0" })
  });
  assert.equal(response.status, 400);
});
