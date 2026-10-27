// AC-113: the relay pairs players by code and passes messages (D-60).
// Run with `npm test` in relay/.
"use strict";

const test = require("node:test");
const assert = require("node:assert");
const WebSocket = require("ws");
const { start, ALPHABET, CODE_LENGTH } = require("./server");

// A client that collects every message, with a helper to await the next one.
function client(port) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket("ws://127.0.0.1:" + port);
    const inbox = [];
    const waiters = [];
    ws.on("message", (d) => {
      const m = JSON.parse(d);
      if (waiters.length) waiters.shift()(m);
      else inbox.push(m);
    });
    ws.next = () => (inbox.length ? Promise.resolve(inbox.shift()) : new Promise((r) => waiters.push(r)));
    ws.put = (m) => ws.send(JSON.stringify(m));
    ws.on("open", () => resolve(ws));
    ws.on("error", reject);
  });
}

async function withServer(fn) {
  const server = await start(0);
  const port = server.address().port;
  try {
    await fn(port);
  } finally {
    server.closeAllConnections?.();
    await new Promise((r) => server.close(r));
  }
}

test("AC-113 host gets a code, a guest joins, both start with the host's setup", () =>
  withServer(async (port) => {
    const host = await client(port);
    host.put({ op: "host", setup: { v: 1, seed: 42, map: "river" } });
    const hosted = await host.next();
    assert.strictEqual(hosted.op, "hosted");
    assert.strictEqual(hosted.code.length, CODE_LENGTH);
    for (const ch of hosted.code) assert.ok(ALPHABET.includes(ch));
    const guest = await client(port);
    guest.put({ op: "join", code: hosted.code.toLowerCase(), v: 1 });
    const a = await host.next();
    const b = await guest.next();
    assert.deepStrictEqual(a, { op: "start", you: "player", setup: { v: 1, seed: 42, map: "river" } });
    assert.deepStrictEqual(b, { op: "start", you: "ai", setup: { v: 1, seed: 42, map: "river" } });
    // Messages go to the other player only, in order.
    host.put({ op: "relay", d: { t: 2 } });
    host.put({ op: "relay", d: { t: 3 } });
    guest.put({ op: "relay", d: { t: 2, c: ["x"] } });
    assert.deepStrictEqual(await guest.next(), { op: "relay", d: { t: 2 } });
    assert.deepStrictEqual(await guest.next(), { op: "relay", d: { t: 3 } });
    assert.deepStrictEqual(await host.next(), { op: "relay", d: { t: 2, c: ["x"] } });
    // When one leaves, the other is told.
    guest.close();
    assert.deepStrictEqual(await host.next(), { op: "left" });
    host.close();
  }));

test("AC-113 a wrong code, a full room or another version is refused", () =>
  withServer(async (port) => {
    const nobody = await client(port);
    nobody.put({ op: "join", code: "ZZZZ", v: 1 });
    assert.strictEqual((await nobody.next()).op, "error");
    const host = await client(port);
    host.put({ op: "host", setup: { v: 2 } });
    const { code } = await host.next();
    const old = await client(port);
    old.put({ op: "join", code, v: 1 });
    assert.match((await old.next()).msg, /different version/);
    const guest = await client(port);
    guest.put({ op: "join", code, v: 2 });
    assert.strictEqual((await guest.next()).op, "start");
    const third = await client(port);
    third.put({ op: "join", code, v: 2 });
    assert.strictEqual((await third.next()).op, "error", "a room holds two players");
    for (const ws of [nobody, host, old, guest, third]) ws.close();
  }));

test("AC-113 the health check answers ok", () =>
  withServer(async (port) => {
    const res = await fetch("http://127.0.0.1:" + port + "/healthz");
    assert.strictEqual(res.status, 200);
    assert.strictEqual(await res.text(), "ok");
  }));
