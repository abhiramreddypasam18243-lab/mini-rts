// Relay for Mini RTS online matches (decision D-60).
//
// It knows nothing about the game. It pairs two players by a room code and
// passes their messages from one to the other:
//   client -> server  {"op": "host", "setup": {...}}       make a room
//                     {"op": "join", "code": "K7QM", "v": 1} join a room
//                     {"op": "relay", "d": {...}}           pass to the other player
//   server -> client  {"op": "hosted", "code": "K7QM"}
//                     {"op": "start", "you": "player" | "ai", "setup": {...}}
//                     {"op": "relay", "d": {...}}
//                     {"op": "left"}                        the other player is gone
//                     {"op": "error", "msg": "..."}
// The host plays the "player" side (blue), the guest the "ai" side (red).
// GET / and GET /healthz answer "ok" (the host's health check).
"use strict";

const http = require("http");
const { WebSocketServer } = require("ws");

// No 0/O or 1/I/L, so a code read aloud cannot be mistyped.
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 4;
// A room nobody joins is dropped after this long.
const ROOM_TTL_MS = 15 * 60 * 1000;
const PING_MS = 25 * 1000;

function makeCode(rooms) {
  for (;;) {
    let c = "";
    for (let i = 0; i < CODE_LENGTH; i++) {
      c += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
    }
    if (!rooms.has(c)) return c;
  }
}

function send(ws, msg) {
  if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
}

// Starts the relay on `port` (0 = any free port); resolves to the server.
function start(port) {
  const rooms = new Map(); // code -> {host, guest, setup, created}

  const server = http.createServer((req, res) => {
    if (req.url === "/" || req.url === "/healthz") {
      res.writeHead(200, { "Content-Type": "text/plain" });
      res.end("ok");
    } else {
      res.writeHead(404);
      res.end();
    }
  });
  const wss = new WebSocketServer({ server, maxPayload: 64 * 1024 });

  function leave(ws) {
    const code = ws.room;
    if (!code) return;
    ws.room = null;
    const r = rooms.get(code);
    if (!r) return;
    rooms.delete(code);
    const peer = ws === r.host ? r.guest : r.host;
    if (peer) {
      peer.room = null;
      send(peer, { op: "left" });
    }
  }

  wss.on("connection", (ws) => {
    ws.room = null;
    ws.alive = true;
    ws.on("pong", () => { ws.alive = true; });
    ws.on("message", (data) => {
      let m;
      try {
        m = JSON.parse(data);
      } catch {
        return send(ws, { op: "error", msg: "Bad message" });
      }
      if (m === null || typeof m !== "object") return;
      if (m.op === "host") {
        if (ws.room) return send(ws, { op: "error", msg: "Already in a game" });
        const code = makeCode(rooms);
        rooms.set(code, { host: ws, guest: null, setup: m.setup || {}, created: Date.now() });
        ws.room = code;
        send(ws, { op: "hosted", code });
      } else if (m.op === "join") {
        if (ws.room) return send(ws, { op: "error", msg: "Already in a game" });
        const code = String(m.code || "").trim().toUpperCase();
        const r = rooms.get(code);
        if (!r || r.guest) return send(ws, { op: "error", msg: "No game is waiting with code " + code });
        if (r.setup.v !== m.v) {
          return send(ws, { op: "error", msg: "The host has a different version of the game. Both players need the same version." });
        }
        r.guest = ws;
        ws.room = code;
        send(r.host, { op: "start", you: "player", setup: r.setup });
        send(ws, { op: "start", you: "ai", setup: r.setup });
      } else if (m.op === "relay") {
        const r = rooms.get(ws.room);
        if (!r || !r.guest) return;
        send(ws === r.host ? r.guest : r.host, { op: "relay", d: m.d });
      } else if (m.op === "leave") {
        leave(ws);
      }
    });
    ws.on("close", () => leave(ws));
  });

  // Ping every client (keeps idle connections open through proxies) and drop
  // dead ones and rooms nobody joined.
  const timer = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.alive) {
        ws.terminate();
        continue;
      }
      ws.alive = false;
      ws.ping();
    }
    const now = Date.now();
    for (const [code, r] of rooms) {
      if (!r.guest && now - r.created > ROOM_TTL_MS) {
        rooms.delete(code);
        r.host.room = null;
        send(r.host, { op: "error", msg: "Nobody joined in time" });
      }
    }
  }, PING_MS);
  server.on("close", () => clearInterval(timer));

  return new Promise((resolve) => {
    server.listen(port, () => resolve(server));
  });
}

module.exports = { start, ALPHABET, CODE_LENGTH };

if (require.main === module) {
  const port = Number(process.env.PORT) || 8080;
  start(port).then(() => console.log("Mini RTS relay listening on port " + port));
}
