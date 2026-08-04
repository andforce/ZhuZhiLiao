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
const EARTH_BROADCAST_DELAY_MS = 120;
const EARTH_ACTIVITY_DURATION_MS = 120_000;
const MAX_LEADERBOARD_ENTRIES = 100;
const PUBLIC_CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const EARTH_CELL_SIZE_KM = 20;
const EARTH_LATITUDE_STEP = EARTH_CELL_SIZE_KM / 111.32;
const EARTH_DETAIL_DEGREES = [30, 12, 4, 1];

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

function parseEarthCell(cell) {
  const match = /^v1:(\d{1,4}):(\d{1,5})$/.exec(cell ?? "");
  if (!match) {
    return undefined;
  }
  const latitudeIndex = Number(match[1]);
  const longitudeIndex = Number(match[2]);
  const latitudeBandCount = Math.ceil(180 / EARTH_LATITUDE_STEP);
  if (latitudeIndex < 0 || latitudeIndex >= latitudeBandCount) {
    return undefined;
  }
  const latitude = Math.min(
    90 - EARTH_LATITUDE_STEP / 2,
    -90 + (latitudeIndex + 0.5) * EARTH_LATITUDE_STEP
  );
  const circumference = 40_075 * Math.max(Math.cos(latitude * Math.PI / 180), 0);
  const longitudeBandCount = Math.max(1, Math.round(circumference / EARTH_CELL_SIZE_KM));
  if (longitudeIndex < 0 || longitudeIndex >= longitudeBandCount) {
    return undefined;
  }
  const longitude = -180 + (longitudeIndex + 0.5) * 360 / longitudeBandCount;
  return { cell, latitude, longitude };
}

function isInBounds(player, bounds) {
  if (!Array.isArray(bounds) || bounds.length === 0) {
    return true;
  }
  return bounds.some((box) => Number.isFinite(box?.minLatitude)
    && Number.isFinite(box?.maxLatitude)
    && Number.isFinite(box?.minLongitude)
    && Number.isFinite(box?.maxLongitude)
    && player.locationLat >= box.minLatitude
    && player.locationLat <= box.maxLatitude
    && player.locationLon >= box.minLongitude
    && player.locationLon <= box.maxLongitude);
}

function earthSnapshot(database, request, playerID) {
  const detail = Number.isInteger(request?.detail)
    ? Math.min(Math.max(request.detail, 0), 4)
    : 0;
  const now = Date.now();
  const players = database.earthPlayers().filter((player) => isInBounds(player, request?.bounds));

  if (detail === 4) {
    return players.map((player) => ({
      kind: "player",
      id: player.publicCode,
      code: player.publicCode,
      score: Number(player.score),
      latitude: Number(player.locationLat),
      longitude: Number(player.locationLon),
      activeUntil: player.lastWahAt === null ? null : Number(player.lastWahAt) + EARTH_ACTIVITY_DURATION_MS,
      isMe: player.id === playerID
    }));
  }

  const size = EARTH_DETAIL_DEGREES[detail];
  const clusters = new Map();
  for (const player of players) {
    const latitudeBucket = Math.floor((player.locationLat + 90) / size);
    const longitudeBucket = Math.floor((player.locationLon + 180) / size);
    const id = `d${detail}:${latitudeBucket}:${longitudeBucket}`;
    let cluster = clusters.get(id);
    if (!cluster) {
      cluster = {
        kind: "cluster",
        id,
        latitudeSum: 0,
        longitudeX: 0,
        longitudeY: 0,
        userCount: 0,
        totalWahs: 0,
        activeCount: 0,
        activeUntil: null,
        containsMe: false
      };
      clusters.set(id, cluster);
    }
    const activeUntil = player.lastWahAt === null
      ? null
      : Number(player.lastWahAt) + EARTH_ACTIVITY_DURATION_MS;
    const longitudeRadians = Number(player.locationLon) * Math.PI / 180;
    cluster.latitudeSum += Number(player.locationLat);
    cluster.longitudeX += Math.cos(longitudeRadians);
    cluster.longitudeY += Math.sin(longitudeRadians);
    cluster.userCount += 1;
    cluster.totalWahs += Number(player.score);
    cluster.containsMe ||= player.id === playerID;
    if (activeUntil !== null && activeUntil > now) {
      cluster.activeCount += 1;
      cluster.activeUntil = Math.max(cluster.activeUntil ?? 0, activeUntil);
    }
  }
  return Array.from(clusters.values(), (cluster) => ({
    kind: cluster.kind,
    id: cluster.id,
    latitude: cluster.latitudeSum / cluster.userCount,
    longitude: Math.atan2(cluster.longitudeY, cluster.longitudeX) * 180 / Math.PI,
    userCount: cluster.userCount,
    totalWahs: cluster.totalWahs,
    activeCount: cluster.activeCount,
    activeUntil: cluster.activeUntil,
    containsMe: cluster.containsMe
  }));
}

async function requestJSON(request) {
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > MAX_MESSAGE_BYTES) {
      throw new Error("payload too large");
    }
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

export function createCounterServer({ databasePath, initialWahs = 0 }) {
  const counterDatabase = openCounterDatabase(databasePath, initialWahs);
  const webSockets = new WebSocketServer({
    noServer: true,
    maxPayload: MAX_MESSAGE_BYTES
  });

  let broadcastTimer;
  let earthBroadcastTimer;
  let earthRevision = 0;
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

  function scheduleEarthRevision() {
    if (earthBroadcastTimer !== undefined) {
      return;
    }
    earthBroadcastTimer = setTimeout(() => {
      earthBroadcastTimer = undefined;
      earthRevision += 1;
      const message = JSON.stringify({ t: "earth_revision", revision: earthRevision });
      for (const socket of webSockets.clients) {
        if (socket.readyState === WebSocket.OPEN && socket.earthSubscribed) {
          socket.send(message);
        }
      }
    }, EARTH_BROADCAST_DELAY_MS);
    earthBroadcastTimer.unref();
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
    if (message?.t === "earth_view") {
      socket.earthSubscribed = true;
      const nodes = earthSnapshot(counterDatabase, message, playerID);
      socket.send(JSON.stringify({
        t: "earth_snapshot",
        requestID: typeof message.requestID === "string" ? message.requestID : "",
        serverTime: Date.now(),
        revision: earthRevision,
        nodes
      }));
      return;
    }
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
      socket.send(JSON.stringify({
        t: "score",
        score: result.score,
        lastWahAt: result.lastWahAt ?? null
      }));
      if (result.delta > 0) {
        scheduleBroadcast();
        scheduleEarthRevision();
      }
    }
  }

  webSockets.on("connection", (socket, request, player) => {
    socket.isAlive = true;
    socket.player = player;
    socket.earthSubscribed = false;
    socket.rateKey = `legacy:${request.socket.remoteAddress ?? "unknown"}:${randomUUID()}`;

    scheduleBroadcast();
    if (player) {
      socket.send(JSON.stringify({
        t: "player",
        id: player.id,
        code: player.publicCode,
        score: Number(player.score),
        migrated: player.hasMigrated === 1,
        earthEnabled: player.earthEnabled === 1,
        locationCell: player.locationCell ?? null
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

  const httpServer = http.createServer(async (request, response) => {
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
      scheduleEarthRevision();
      json(response, 204);
      return;
    }

    if (url.pathname === "/api/players/me/earth") {
      const player = authenticate(request);
      if (!player) {
        json(response, 401, { error: "Unauthorized" });
        return;
      }
      if (request.method === "PUT") {
        try {
          const body = await requestJSON(request);
          const location = body?.enabled === true ? parseEarthCell(body.cellID) : undefined;
          if (!location) {
            json(response, 400, { error: "Invalid earth location" });
            return;
          }
          const updated = counterDatabase.setEarthLocation(player.id, location);
          scheduleEarthRevision();
          json(response, 200, {
            enabled: true,
            cellID: updated.locationCell,
            latitude: updated.locationLat,
            longitude: updated.locationLon
          });
        } catch {
          json(response, 400, { error: "Invalid JSON" });
        }
        return;
      }
      if (request.method === "DELETE") {
        counterDatabase.disableEarth(player.id);
        scheduleEarthRevision();
        json(response, 204);
        return;
      }
      json(response, 405, { error: "Method not allowed" });
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
      clearTimeout(earthBroadcastTimer);
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
