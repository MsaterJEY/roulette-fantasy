// Room API for online play (Vercel Function). Lists open rooms and passes WebRTC connection
// offers between browsers; the game itself runs in the host's browser (scripts/net.gd).
// Storage: Upstash Redis, added from the Vercel project's Storage tab (free plan). Its REST
// URL and token arrive as environment variables. tools/dev_server.py is the same API for
// testing on this machine.
//
// POST /api/room with JSON {action, ...}:
//   create {name, max, rings, preset, password}  -> {code}
//   list                                          -> {rooms: [{code, name, count, max, rings, locked}]}
//   join   {code, password}                       -> {peer}  (or {error: not_found|full|playing|password})
//   send   {code, to, from, data}                 -> {ok}
//   poll   {code, peer, count?}                   -> {messages: [{from, data}]}  (host: count keeps the room listed)
//   update {code, status, count}                  -> {ok}
//   close  {code}                                 -> {ok}

const URL_ = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
const TOKEN = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
const ROOM_TTL = 90; // seconds a room stays listed without word from its host
const MSG_TTL = 120;

async function redis(...commands) {
  const res = await fetch(`${URL_}/pipeline`, {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify(commands),
  });
  if (!res.ok) throw new Error(`redis ${res.status}`);
  const out = await res.json();
  return out.map((r) => r.result);
}

const roomKey = (code) => `rf:room:${code}`;
const msgKey = (code, peer) => `rf:msg:${code}:${peer}`;
const isCode = (c) => typeof c === "string" && /^\d{6}$/.test(c);

async function getRoom(code) {
  if (!isCode(code)) return null;
  const [raw] = await redis(["GET", roomKey(code)]);
  return raw ? JSON.parse(raw) : null;
}

async function saveRoom(room) {
  await redis(["SET", roomKey(room.code), JSON.stringify(room), "EX", ROOM_TTL], ["SADD", "rf:rooms", room.code]);
}

const actions = {
  async create(b) {
    for (let tries = 0; tries < 10; tries++) {
      const code = String(Math.floor(100000 + Math.random() * 900000));
      const room = {
        code,
        name: String(b.name || "ห้องของฉัน").slice(0, 30),
        max: Math.min(6, Math.max(2, Number(b.max) || 4)),
        rings: Number(b.rings) || 0,
        preset: String(b.preset || ""),
        password: /^\d{4}$/.test(b.password || "") ? b.password : "",
        count: 1,
        status: "open",
        next_peer: 2,
      };
      const [ok] = await redis(["SET", roomKey(code), JSON.stringify(room), "EX", ROOM_TTL, "NX"]);
      if (ok) {
        await redis(["SADD", "rf:rooms", code]);
        return { code };
      }
    }
    return { error: "busy" };
  },

  async list() {
    const [codes] = await redis(["SMEMBERS", "rf:rooms"]);
    if (!codes || codes.length === 0) return { rooms: [] };
    const [raws] = await redis(["MGET", ...codes.map(roomKey)]);
    const rooms = [];
    const gone = [];
    codes.forEach((code, i) => {
      if (!raws[i]) return gone.push(code);
      const r = JSON.parse(raws[i]);
      if (r.status === "open")
        rooms.push({ code, name: r.name, count: r.count, max: r.max, rings: r.rings, locked: r.password !== "" });
    });
    if (gone.length) await redis(["SREM", "rf:rooms", ...gone]);
    return { rooms };
  },

  async join(b) {
    const room = await getRoom(b.code);
    if (!room) return { error: "not_found" };
    if (room.status !== "open") return { error: "playing" };
    if (room.count >= room.max) return { error: "full" };
    if (room.password && room.password !== String(b.password || "")) return { error: "password" };
    const peer = room.next_peer;
    room.next_peer += 1;
    await saveRoom(room);
    return { peer };
  },

  async send(b) {
    if (!isCode(b.code)) return { error: "not_found" };
    const key = msgKey(b.code, Number(b.to));
    await redis(["RPUSH", key, JSON.stringify({ from: Number(b.from), data: b.data })], ["EXPIRE", key, MSG_TTL]);
    return { ok: true };
  },

  async poll(b) {
    if (!isCode(b.code)) return { error: "not_found" };
    const key = msgKey(b.code, Number(b.peer));
    const [list] = await redis(["LRANGE", key, 0, -1], ["DEL", key]);
    const messages = (list || []).map((m) => JSON.parse(m));
    if (Number(b.peer) === 1) {
      // the host checks in: the room stays listed, with its player count
      const room = await getRoom(b.code);
      if (!room) return { error: "not_found", messages };
      if (b.count !== undefined) room.count = Number(b.count);
      await saveRoom(room);
    }
    return { messages };
  },

  async update(b) {
    const room = await getRoom(b.code);
    if (!room) return { error: "not_found" };
    if (b.status === "open" || b.status === "playing") room.status = b.status;
    if (b.count !== undefined) room.count = Number(b.count);
    await saveRoom(room);
    return { ok: true };
  },

  async close(b) {
    if (isCode(b.code)) await redis(["DEL", roomKey(b.code)], ["SREM", "rf:rooms", b.code]);
    return { ok: true };
  },
};

module.exports = async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (req.method !== "POST") return res.status(405).json({ error: "post_only" });
  if (!URL_ || !TOKEN) return res.status(503).json({ error: "no_storage" });
  const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body || {};
  const act = actions[body.action];
  if (!act) return res.status(400).json({ error: "unknown_action" });
  try {
    return res.status(200).json(await act(body));
  } catch (e) {
    return res.status(502).json({ error: "storage" });
  }
};
