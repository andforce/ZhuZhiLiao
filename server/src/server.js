import { createHash, randomBytes, randomUUID } from "node:crypto";
import http from "node:http";
import { WebSocket, WebSocketServer } from "ws";
import { openCounterDatabase } from "./database.js";

const MAX_MESSAGE_BYTES = 1_024;
const MAX_WAHS_PER_MESSAGE = 30;
const RATE_WINDOW_MS = 10_000;
const MAX_WAHS_PER_WINDOW = 300;
const HEARTBEAT_INTERVAL_MS = 30_000;
const BROADCAST_DELAY_MS = 40;
const MAX_LEADERBOARD_ENTRIES = 100;
const PUBLIC_CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

function json(response, statusCode, body) {
  response.writeHead(statusCode, {
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
    "x-content-type-options": "nosniff"
  });
  response.end(body === undefined ? undefined : JSON.stringify(body));
}

function tokenHash(token) {
  return createHash("sha256").update(token).digest("hex");
}

function bearerToken(request) {
  const authorization = request.headers.authorization;
  if (typeof authorization !== "string" || !authorization.startsWith("Bearer ")) {
    return undefined;
  }
  const token = authorization.slice(7).trim();
  return token.length > 0 ? token : undefined;
}

function publicCode() {
  const bytes = randomBytes(6);
  return Array.from(bytes, (byte) => PUBLIC_CODE_ALPHABET[byte & 31]).join("");
}

function publicPlayer(player) {
  return {
    code: player.publicCode,
    score: Number(player.score),
    rank: Number(player.rank)
  };
}

export function createCounterServer({ databasePath, initialWahs = 0 }) {
  const counterDatabase = openCounterDatabase(databasePath, initialWahs);
  const webSockets = new WebSocketServer({
    noServer: true,
    maxPayload: MAX_MESSAGE_BYTES
  });

  let broadcastTimer;
  let heartbeatTimer;
  let isClosed = false;
  const playerRateWindows = new Map();

  function currentOnline() {
    let online = 0;
    for (const socket of webSockets.clients) {
      if (socket.readyState === WebSocket.OPEN) {
        online += 1;
      }
    }
    return online;
  }

  function currentStats() {
    return {
      online: currentOnline(),
      wahs: counterDatabase.getWahs()
    };
  }

  function statsMessage() {
    return JSON.stringify({ t: "stats", ...currentStats() });
  }

  function broadcastStats() {
    broadcastTimer = undefined;
    const message = statsMessage();
    for (const socket of webSockets.clients) {
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(message);
      }
    }
  }

  function scheduleBroadcast() {
    if (broadcastTimer === undefined) {
      broadcastTimer = setTimeout(broadcastStats, BROADCAST_DELAY_MS);
      broadcastTimer.unref();
    }
  }

  function acceptsWahs(key, count) {
    const now = Date.now();
    let window = playerRateWindows.get(key);
    if (!window || now - window.startedAt >= RATE_WINDOW_MS) {
      window = { startedAt: now, wahs: 0 };
      playerRateWindows.set(key, window);
    }
    if (window.wahs + count > MAX_WAHS_PER_WINDOW) {
      return false;
    }
    window.wahs += count;
    return true;
  }

  function authenticate(request) {
    const token = bearerToken(request);
    return token ? counterDatabase.getPlayerByTokenHash(tokenHash(token)) : undefined;
  }

  function createPlayerRecord() {
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const token = randomBytes(32).toString("base64url");
      try {
        const player = counterDatabase.createPlayer({
          id: randomUUID(),
          publicCode: publicCode(),
          tokenHash: tokenHash(token)
        });
        return { id: player.id, code: player.publicCode, token };
      } catch (error) {
        if (error?.code !== "SQLITE_CONSTRAINT_UNIQUE") {
          throw error;
        }
      }
    }
    throw new Error("Unable to allocate a unique public player code");
  }

  function handleAuthenticatedMessage(socket, message) {
    const playerID = socket.player.id;
    if (message?.t === "migrate") {
      if (socket.player.hasMigrated === 1) {
        socket.send(JSON.stringify({
          t: "migration",
          score: Number(socket.player.score),
          migrated: true
        }));
        return;
      }
      if (!Number.isSafeInteger(message.personal)
        || !Number.isSafeInteger(message.pendingGlobal)
        || message.personal < 0
        || message.pendingGlobal < 0
        || message.pendingGlobal > message.personal
        || message.personal > counterDatabase.getWahs() + message.pendingGlobal) {
        socket.close(1008, "invalid migration");
        return;
      }
      const player = counterDatabase.migratePlayer(
        playerID,
        message.personal,
        message.pendingGlobal
      );
      if (!player) {
        socket.close(1008, "unknown player");
        return;
      }
      socket.player = player;
      socket.send(JSON.stringify({
        t: "migration",
        score: Number(player.score),
        migrated: true
      }));
      if (player.didMigrate && message.pendingGlobal > 0) {
        scheduleBroadcast();
      }
      return;
    }

    if (message?.t === "score") {
      if (!Number.isSafeInteger(message.value) || message.value < 0) {
        socket.close(1008, "invalid score");
        return;
      }
      const delta = Math.max(message.value - socket.player.score, 0);
      if (delta > MAX_WAHS_PER_MESSAGE) {
        socket.close(1008, "score advanced too far");
        return;
      }
      if (!acceptsWahs(`player:${playerID}`, delta)) {
        socket.close(1008, "rate limit exceeded");
        return;
      }
      const result = counterDatabase.submitScore(playerID, message.value);
      if (!result) {
        socket.close(1008, "migration required");
        return;
      }
      socket.player = { ...socket.player, score: result.score, hasMigrated: 1 };
      socket.send(JSON.stringify({ t: "score", score: result.score }));
      if (result.delta > 0) {
        scheduleBroadcast();
      }
    }
  }

  webSockets.on("connection", (socket, request, player) => {
    socket.isAlive = true;
    socket.player = player;
    socket.rateKey = `legacy:${request.socket.remoteAddress ?? "unknown"}:${randomUUID()}`;

    scheduleBroadcast();
    if (player) {
      socket.send(JSON.stringify({
        t: "player",
        id: player.id,
        code: player.publicCode,
        score: Number(player.score),
        migrated: player.hasMigrated === 1
      }));
    }

    socket.on("pong", () => {
      socket.isAlive = true;
    });

    socket.on("error", () => {
      socket.terminate();
    });

    socket.on("message", (data, isBinary) => {
      if (isBinary) {
        socket.close(1003, "text messages only");
        return;
      }

      const text = data.toString("utf8");
      if (text === "ping") {
        socket.send("pong");
        return;
      }

      let message;
      try {
        message = JSON.parse(text);
      } catch {
        socket.close(1007, "invalid JSON");
        return;
      }

      if (socket.player) {
        handleAuthenticatedMessage(socket, message);
        return;
      }

      // Keep old App Store builds contributing to the aggregate during rollout.
      if (message?.t !== "wah") {
        return;
      }
      if (!Number.isInteger(message.n)
        || message.n < 1
        || message.n > MAX_WAHS_PER_MESSAGE) {
        socket.close(1008, "invalid wah count");
        return;
      }
      if (!acceptsWahs(socket.rateKey, message.n)) {
        socket.close(1008, "rate limit exceeded");
        return;
      }
      counterDatabase.incrementWahs(message.n);
      scheduleBroadcast();
    });

    socket.on("close", () => {
      playerRateWindows.delete(socket.rateKey);
      scheduleBroadcast();
    });
  });

  const httpServer = http.createServer((request, response) => {
    const url = new URL(request.url ?? "/", "http://localhost");

    if (request.method === "POST" && url.pathname === "/api/players") {
      json(response, 201, createPlayerRecord());
      return;
    }

    if (url.pathname === "/api/leaderboard") {
      const player = authenticate(request);
      if (!player) {
        json(response, 401, { error: "Unauthorized" });
        return;
      }
      if (request.method !== "GET") {
        json(response, 405, { error: "Method not allowed" });
        return;
      }
      const requestedLimit = Number.parseInt(url.searchParams.get("limit") ?? "100", 10);
      const limit = Number.isInteger(requestedLimit)
        ? Math.min(Math.max(requestedLimit, 1), MAX_LEADERBOARD_ENTRIES)
        : MAX_LEADERBOARD_ENTRIES;
      const leaderboard = counterDatabase.leaderboard(player.id, limit);
      json(response, 200, {
        totalPlayers: leaderboard.totalPlayers,
        entries: leaderboard.entries.map(publicPlayer),
        me: leaderboard.me ? publicPlayer(leaderboard.me) : null
      });
      return;
    }

    if (request.method === "DELETE" && url.pathname === "/api/players/me") {
      const player = authenticate(request);
      if (!player) {
        json(response, 401, { error: "Unauthorized" });
        return;
      }
      counterDatabase.deletePlayer(player.id);
      json(response, 204);
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/stats") {
      json(response, 200, currentStats());
      return;
    }

    if (request.method === "GET" && url.pathname === "/healthz") {
      json(response, 200, { status: "ok" });
      return;
    }

    if (url.pathname === "/api/ws") {
      json(response, 426, { error: "WebSocket upgrade required" });
      return;
    }

    json(response, 404, { error: "Not found" });
  });

  httpServer.on("upgrade", (request, socket, head) => {
    const url = new URL(request.url ?? "/", "http://localhost");
    if (url.pathname !== "/api/ws") {
      socket.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n");
      socket.destroy();
      return;
    }

    const player = authenticate(request);
    webSockets.handleUpgrade(request, socket, head, (webSocket) => {
      webSockets.emit("connection", webSocket, request, player);
    });
  });

  heartbeatTimer = setInterval(() => {
    for (const socket of webSockets.clients) {
      if (!socket.isAlive) {
        socket.terminate();
        continue;
      }
      socket.isAlive = false;
      socket.ping();
    }
  }, HEARTBEAT_INTERVAL_MS);
  heartbeatTimer.unref();

  return {
    async listen({ host, port }) {
      await new Promise((resolve, reject) => {
        const onError = (error) => {
          httpServer.off("listening", onListening);
          reject(error);
        };
        const onListening = () => {
          httpServer.off("error", onError);
          resolve();
        };
        httpServer.once("error", onError);
        httpServer.once("listening", onListening);
        httpServer.listen(port, host);
      });
      return httpServer.address();
    },

    getStats: currentStats,

    async close() {
      if (isClosed) {
        return;
      }
      isClosed = true;
      clearInterval(heartbeatTimer);
      clearTimeout(broadcastTimer);
      for (const socket of webSockets.clients) {
        socket.terminate();
      }
      await new Promise((resolve, reject) => {
        httpServer.close((error) => error ? reject(error) : resolve());
      });
      counterDatabase.close();
    }
  };
}
