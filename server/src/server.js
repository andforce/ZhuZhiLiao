import http from "node:http";
import { WebSocket, WebSocketServer } from "ws";
import { openCounterDatabase } from "./database.js";

const MAX_MESSAGE_BYTES = 1_024;
const MAX_WAHS_PER_MESSAGE = 30;
const RATE_WINDOW_MS = 10_000;
const MAX_WAHS_PER_WINDOW = 300;
const HEARTBEAT_INTERVAL_MS = 30_000;
const BROADCAST_DELAY_MS = 40;

function json(response, statusCode, body) {
  response.writeHead(statusCode, {
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
    "x-content-type-options": "nosniff"
  });
  response.end(JSON.stringify(body));
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

  function acceptsWahs(socket, count) {
    const now = Date.now();
    if (now - socket.wahWindowStartedAt >= RATE_WINDOW_MS) {
      socket.wahWindowStartedAt = now;
      socket.wahsInWindow = 0;
    }

    if (socket.wahsInWindow + count > MAX_WAHS_PER_WINDOW) {
      return false;
    }

    socket.wahsInWindow += count;
    return true;
  }

  webSockets.on("connection", (socket) => {
    socket.isAlive = true;
    socket.wahWindowStartedAt = Date.now();
    socket.wahsInWindow = 0;

    scheduleBroadcast();

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

      if (message?.t !== "wah") {
        return;
      }

      if (!Number.isInteger(message.n)
        || message.n < 1
        || message.n > MAX_WAHS_PER_MESSAGE) {
        socket.close(1008, "invalid wah count");
        return;
      }

      if (!acceptsWahs(socket, message.n)) {
        socket.close(1008, "rate limit exceeded");
        return;
      }

      counterDatabase.incrementWahs(message.n);
      scheduleBroadcast();
    });

    socket.on("close", scheduleBroadcast);
  });

  const httpServer = http.createServer((request, response) => {
    const url = new URL(request.url ?? "/", "http://localhost");

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

    webSockets.handleUpgrade(request, socket, head, (webSocket) => {
      webSockets.emit("connection", webSocket, request);
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
        httpServer.close((error) => {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        });
      });
      counterDatabase.close();
    }
  };
}
