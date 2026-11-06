// Local test server for online play: serves the web build (web/) and runs the real room API
// (web/api/room.js) against a small in-memory stand-in for Upstash Redis, so several browser
// tabs on this machine can create and join rooms without Vercel.
//   node tools/dev_server.js [port]      (default 8060) then open http://127.0.0.1:8060
const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = Number(process.argv[2]) || 8060;
const WEB = path.join(__dirname, "..", "web");
process.env.KV_REST_API_URL = `http://127.0.0.1:${PORT}/_redis`;
process.env.KV_REST_API_TOKEN = "local";
process.env.ADMIN_CODE = process.env.ADMIN_CODE || "local-test"; // this server only, for web/admin.html
const room = require(path.join(WEB, "api", "room.js"));

// --- the Redis commands room.js uses ---
const store = new Map(); // key -> {v, exp}
const live = (k) => {
  const e = store.get(k);
  if (e && e.exp && e.exp < Date.now()) store.delete(k);
  return store.get(k);
};
const run = ([cmd, ...a]) => {
  switch (cmd.toUpperCase()) {
    case "GET": return live(a[0]) ? live(a[0]).v : null;
    case "SET": {
      const nx = a.includes("NX");
      if (nx && live(a[0])) return null;
      const ex = a.indexOf("EX");
      store.set(a[0], { v: a[1], exp: ex >= 0 ? Date.now() + Number(a[ex + 1]) * 1000 : 0 });
      return "OK";
    }
    case "MGET": return a.map((k) => (live(k) ? live(k).v : null));
    case "SADD": { const s = live(a[0])?.v || new Set(); a.slice(1).forEach((m) => s.add(m)); store.set(a[0], { v: s }); return 1; }
    case "SREM": { const s = live(a[0])?.v; if (s) a.slice(1).forEach((m) => s.delete(m)); return 1; }
    case "SMEMBERS": return [...(live(a[0])?.v || [])];
    case "RPUSH": { const l = live(a[0])?.v || []; l.push(...a.slice(1)); store.set(a[0], { v: l, exp: live(a[0])?.exp || 0 }); return l.length; }
    case "EXPIRE": { const e = live(a[0]); if (e) e.exp = Date.now() + Number(a[1]) * 1000; return 1; }
    case "LRANGE": return [...(live(a[0])?.v || [])];
    case "ZADD": { const z = live(a[0])?.v || new Map(); z.set(a[2], Number(a[1])); store.set(a[0], { v: z, exp: live(a[0])?.exp || 0 }); return 1; }
    case "ZREMRANGEBYSCORE": { const z = live(a[0])?.v; if (z) for (const [m, s] of z) if (s >= Number(a[1]) && s <= Number(a[2])) z.delete(m); return 1; }
    case "ZCARD": return live(a[0])?.v.size || 0;
    case "INCR": { const n = Number(live(a[0])?.v || 0) + 1; store.set(a[0], { v: String(n), exp: live(a[0])?.exp || 0 }); return n; }
    case "DEL": a.forEach((k) => store.delete(k)); return 1;
  }
  throw new Error("unsupported " + cmd);
};

const TYPES = { ".html": "text/html", ".js": "application/javascript", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json" };

const readBody = (req) => new Promise((ok) => { let d = ""; req.on("data", (c) => (d += c)); req.on("end", () => ok(d)); });

http.createServer(async (req, res) => {
  const url = req.url.split("?")[0];
  if (url === "/_redis/pipeline") {
    const cmds = JSON.parse(await readBody(req));
    res.setHeader("Content-Type", "application/json");
    return res.end(JSON.stringify(cmds.map((c) => ({ result: run(c) }))));
  }
  if (url === "/api/room") {
    const raw = await readBody(req);
    const shim = {
      statusCode: 200,
      status(c) { this.statusCode = c; return this; },
      setHeader: (k, v) => res.setHeader(k, v),
      json(o) { res.statusCode = this.statusCode; res.setHeader("Content-Type", "application/json"); res.end(JSON.stringify(o)); },
    };
    let body = {};
    try { body = JSON.parse(raw || "{}"); } catch (e) {}
    return room({ method: req.method, body, headers: req.headers }, shim);
  }
  if (url === "/dual.html") {  // two copies of the game on one page (both keep running)
    res.setHeader("Content-Type", "text/html");
    return fs.createReadStream(path.join(__dirname, "dual.html")).pipe(res);
  }
  const file = path.join(WEB, url === "/" ? "index.html" : decodeURIComponent(url));
  if (!file.startsWith(WEB) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.statusCode = 404;
    return res.end("not found");
  }
  res.setHeader("Content-Type", TYPES[path.extname(file)] || "application/octet-stream");
  res.setHeader("Cache-Control", "no-store");
  fs.createReadStream(file).pipe(res);
}).listen(PORT, "127.0.0.1", () => console.log(`Roulette Fantasy test server: http://127.0.0.1:${PORT}`));
