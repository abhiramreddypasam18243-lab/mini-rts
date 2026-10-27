# Mini RTS relay (online play, D-60)

A small WebSocket server that pairs two players by a 4-character room code and passes their messages to each other. It knows nothing about the game: both players' machines run the same deterministic simulation and only exchange commands (see `scripts/net/lockstep.gd`). The protocol is described at the top of `server.js`.

## Run it locally

```
cd relay
npm ci
PORT=8090 npm start
```

Start the game with `-- --relay=ws://127.0.0.1:8090` (desktop), or open the web build with `?relay=ws://127.0.0.1:8090`.

## Tests

`npm test` runs `server.test.js` (AC-113). The end-to-end check with two game screens is `tools/net_smoke.gd` (AC-114); CI runs both.

## Deploy on Render (free)

1. On https://dashboard.render.com choose **New → Web Service** and connect the `mini-rts` repository.
2. Set **Name** `mini-rts-relay`, **Root Directory** `relay`, **Runtime** Node, **Build Command** `npm ci`, **Start Command** `node server.js`, **Instance type** Free.
3. Under **Advanced**, set **Health Check Path** to `/healthz`.

The game expects the relay at `wss://mini-rts-relay.onrender.com` (`NetClient.DEFAULT_URL`). If Render gives the service another address, change `DEFAULT_URL` and the `connect-src` address in `tools/csp_hash.gd`.

A free Render service sleeps after 15 minutes without traffic; the first player to connect then waits up to about a minute while it wakes.
