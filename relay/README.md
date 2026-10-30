# Tube Timer relay + phone app

A tiny Node server (no dependencies) that connects the Tube Timer Mac app with the parents' phone app.

- **Mac:** `POST /api/sync` every 3 seconds sends status and receives the parents' commands. It also starts pairing (`/api/pair/start`) and can unpair every phone (`/api/phones/reset`).
- **Phone app:** `/app/` (`public/index.html`). It pairs with a 6-digit code (`/api/pair/claim`), polls `/api/status` every 3 seconds, and sends commands with `/api/command`.
- **Storage:** none needed. Everything is kept in memory. The Mac re-sends its status and its list of paired phones on every sync, so a restart or redeploy loses nothing important. Only SHA-256 hashes of keys are kept.

## Run locally

```bash
PORT=8787 node relay/server.js
defaults write com.tubetimer.app relayURL -string http://127.0.0.1:8787   # point the Mac app at it
```

## Deploy on Railway

1. `railway login`, then from `relay/`: `railway link` (project **tube-timer**), then `railway add --service tube-timer-parents` and `railway up --service tube-timer-parents`.
2. The service builds `relay/Dockerfile` and listens on `$PORT`. Health check: `/healthz`.
3. Generate a domain (`railway domain`). If it isn't `tube-timer-parents.up.railway.app`, update `kDefaultRelayURL` in `app/relay.swift` and rebuild the Mac app.
