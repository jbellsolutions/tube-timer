// Tube Timer relay: carries status from the kid's Mac to the parents' phones, and the parents' commands back.
//
// The Mac is the source of truth. It syncs every few seconds (status up, commands down) and re-sends its list of
// paired phones, so this server keeps everything in memory and a restart loses nothing important.
// Keys are never stored, only their SHA-256 hashes.
const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const PORT = process.env.PORT || 8080;
const PUBLIC = path.join(__dirname, "public");
const ONLINE_SEC = 20;            // the Mac counts as online if it synced this recently
const PAIR_CODE_MIN = 10;         // pairing codes last 10 minutes
const COMMANDS = new Set(["add10", "endBreak", "lockNow", "resetToday", "setEnabled", "approve", "deny",
  "allowChannel", "funChannel", "blockChannel", "removeChannel", "setLimits", "setBedtime"]);

const sha = (s) => crypto.createHash("sha256").update(String(s)).digest("hex");
const token = (n = 24) => crypto.randomBytes(n).toString("base64url");
const now = () => Date.now();

/** hid -> { macHash, parents: [{hash, name, added}], ready, status, seen, commands: [], results: [], pair } */
const homes = new Map();

// ---------- tiny helpers ----------
function send(res, code, body, headers = {}) {
  const data = typeof body === "string" ? body : JSON.stringify(body);
  res.writeHead(code, { "content-type": typeof body === "string" ? "text/plain" : "application/json",
    "cache-control": "no-store", ...headers });
  res.end(data);
}
function readJSON(req) {
  return new Promise((resolve) => {
    let raw = "";
    req.on("data", (c) => { raw += c; if (raw.length > 256 * 1024) req.destroy(); });
    req.on("end", () => { try { resolve(JSON.parse(raw || "{}")); } catch { resolve(null); } });
  });
}
const bearer = (req) => (req.headers.authorization || "").replace(/^Bearer\s+/i, "").trim();

// Pairing-claim rate limit: 10 tries per IP per 10 minutes.
const tries = new Map();
function tooManyTries(ip) {
  const t = (tries.get(ip) || []).filter((x) => now() - x < 10 * 60 * 1000);
  t.push(now()); tries.set(ip, t);
  return t.length > 10;
}

function macAuth(body, req) {
  const home = homes.get(body && body.hid);
  return home && home.macHash === sha(bearer(req)) ? home : null;
}
function parentAuth(hid, req) {
  const home = homes.get(hid), h = sha(bearer(req));
  if (!home) return null;
  const parent = home.parents.find((p) => p.hash === h);
  return parent ? { home, parent } : null;
}

// ---------- API ----------
async function api(req, res, url) {
  const route = `${req.method} ${url.pathname}`;

  // Mac: status up, commands down. Creates the household on first contact (or after a server restart).
  if (route === "POST /api/sync") {
    const b = await readJSON(req);
    if (!b || typeof b.hid !== "string" || b.hid.length < 16) return send(res, 400, { error: "bad request" });
    let home = homes.get(b.hid);
    if (!home) {
      home = { macHash: sha(bearer(req)), parents: [], ready: false, commands: [], results: [], seen: 0 };
      homes.set(b.hid, home);
    }
    if (home.macHash !== sha(bearer(req))) return send(res, 403, { error: "wrong key" });
    if (!home.ready) {                      // first sync since start: adopt the Mac's list of phones
      home.parents = Array.isArray(b.parents) ? b.parents.filter((p) => p && typeof p.hash === "string").slice(0, 20) : [];
      home.ready = true;
    }
    home.status = b.status || {};
    home.seen = now();
    for (const r of Array.isArray(b.results) ? b.results.slice(0, 50) : []) home.results.push({ ...r, at: now() });
    home.results = home.results.slice(-30);
    const commands = home.commands.filter((c) => !c.sent);
    commands.forEach((c) => (c.sent = now()));
    home.commands = home.commands.filter((c) => now() - c.at < 10 * 60 * 1000).slice(-50);
    return send(res, 200, { commands: commands.map(({ id, type, args, from }) => ({ id, type, args, from })),
      parents: home.parents.map(({ hash, name, added }) => ({ hash, name, added })) });
  }

  // Mac: start pairing a phone.
  if (route === "POST /api/pair/start") {
    const b = await readJSON(req), home = macAuth(b, req);
    if (!home) return send(res, 403, { error: "wrong key" });
    const code = String(crypto.randomInt(100000, 1000000));
    home.pair = { hash: sha(code), expires: now() + PAIR_CODE_MIN * 60 * 1000 };
    return send(res, 200, { code, minutes: PAIR_CODE_MIN });
  }

  // Mac: unpair every phone.
  if (route === "POST /api/phones/reset") {
    const b = await readJSON(req), home = macAuth(b, req);
    if (!home) return send(res, 403, { error: "wrong key" });
    home.parents = [];
    return send(res, 200, { ok: true });
  }

  // Phone: trade a pairing code for this household's id and a phone key.
  if (route === "POST /api/pair/claim") {
    const ip = req.headers["x-forwarded-for"] || req.socket.remoteAddress;
    if (tooManyTries(ip)) return send(res, 429, { error: "Too many tries. Wait a few minutes." });
    const b = await readJSON(req);
    const code = String((b && b.code) || "").replace(/\D/g, "");
    for (const [hid, home] of homes) {
      if (home.pair && home.pair.expires > now() && home.pair.hash === sha(code)) {
        const key = token();
        const name = String((b && b.name) || "Parent").slice(0, 40);
        home.parents.push({ hash: sha(key), name, added: new Date().toISOString() });
        home.parents = home.parents.slice(-20);
        home.pair = null;
        return send(res, 200, { hid, key, name });
      }
    }
    return send(res, 404, { error: "That code didn't work. Make a new one on the Mac." });
  }

  // Phone: latest status.
  if (route === "GET /api/status") {
    const a = parentAuth(url.searchParams.get("hid"), req);
    if (!a) return send(res, 403, { error: "This phone isn't paired (anymore). Pair it again from the Mac." });
    const { home } = a;
    return send(res, 200, { status: home.status || null, seen: home.seen,
      online: now() - home.seen < ONLINE_SEC * 1000, results: home.results.slice(-15),
      pending: home.commands.filter((c) => !c.sent).map((c) => c.id),
      phones: home.parents.map((p) => p.name) });
  }

  // Phone: send a command to the Mac.
  if (route === "POST /api/command") {
    const b = await readJSON(req);
    const a = b && parentAuth(b.hid, req);
    if (!a) return send(res, 403, { error: "This phone isn't paired (anymore)." });
    if (!COMMANDS.has(b.type)) return send(res, 400, { error: "unknown command" });
    const cmd = { id: token(8), type: b.type, args: b.args || {}, from: a.parent.name, at: now() };
    a.home.commands.push(cmd);
    return send(res, 200, { id: cmd.id });
  }

  // Phone: unpair itself.
  if (route === "POST /api/unpair") {
    const b = await readJSON(req);
    const a = b && parentAuth(b.hid, req);
    if (a) a.home.parents = a.home.parents.filter((p) => p !== a.parent);
    return send(res, 200, { ok: true });
  }

  return send(res, 404, { error: "not found" });
}

// ---------- static phone app ----------
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".png": "image/png",
  ".json": "application/json", ".webmanifest": "application/manifest+json", ".svg": "image/svg+xml" };
function serveStatic(req, res, url) {
  let p = decodeURIComponent(url.pathname);
  if (p === "/" ) { res.writeHead(302, { location: "/app/" + (url.search || "") }); return res.end(); }
  if (!p.startsWith("/app/")) return send(res, 404, "not found");
  p = p.slice("/app/".length) || "index.html";
  const file = path.join(PUBLIC, path.normalize(p).replace(/^(\.\.[/\\])+/, ""));
  if (!file.startsWith(PUBLIC)) return send(res, 404, "not found");
  fs.readFile(file, (err, data) => {
    if (err) return send(res, 404, "not found");
    res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream",
      "cache-control": file.endsWith("index.html") || file.endsWith("sw.js") ? "no-cache" : "public, max-age=3600",
      "x-content-type-options": "nosniff", "referrer-policy": "no-referrer" });
    res.end(data);
  });
}

http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://x");
    if (url.pathname === "/healthz") return send(res, 200, "ok");
    if (url.pathname.startsWith("/api/")) return await api(req, res, url);
    return serveStatic(req, res, url);
  } catch (e) {
    console.error(e);
    send(res, 500, { error: "server error" });
  }
}).listen(PORT, () => console.log(`Tube Timer relay on :${PORT}`));
