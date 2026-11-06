// Room API for online play (Vercel Function). Lists open rooms and passes WebRTC connection
// offers between browsers; the game itself runs in the host's browser (scripts/net.gd).
// Storage: Upstash Redis, added from the Vercel project's Storage tab (free plan). Its REST
// URL and token arrive as environment variables. tools/dev_server.py is the same API for
// testing on this machine.
//
// POST /api/room with JSON {action, ...}:
//   create {name, max, rings, preset, password}  -> {code}
//   list   {who}                                  -> {rooms: [{code, name, count, max, rings, locked, playing}], online, playing}
//          (online: people in rooms + browsers looking at the room list; playing: rooms in a game)
//   join   {code, password, watch?}               -> {peer}  (or {error: not_found|full|playing|password|over})
//          (watch: as a spectator of the game in progress)
//   send   {code, to, from, data}                 -> {ok}
//   poll   {code, peer, count?, watchers?}        -> {messages: [{from, data}]}  (host: count keeps the room listed)
//   update {code, status, count}                  -> {ok}
//   close  {code}                                 -> {ok}
//   questions {}                                  -> {questions: [...]}  (minigame questions; the
//          database's copy, first filled from questions_seed.json = data/minigame_ranks.json)
//   admin_check {secret}                          -> {ok}  (or {error: wrong_code|locked|no_admin_code})
//   admin_save  {secret, questions}               -> {ok}  (or those errors, or {error: bad_questions, detail})
//          (web/admin.html. The secret is the ADMIN_CODE environment variable in Vercel; it is
//          checked on every call and never reaches the game files. No ADMIN_CODE = no admin.)

const crypto = require("crypto");

const URL_ = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
const TOKEN = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
const ROOM_TTL = 90; // seconds a room stays listed without word from its host
const MSG_TTL = 120;
const SEEN_SECONDS = 15; // a browser counts as looking at the list this long after asking for it
const QUESTIONS_KEY = "rf:questions"; // no expiry: this is the game's data, not a room
const QUESTIONS_BACKUP_KEY = "rf:questions:previous"; // what the last admin save replaced
const ADMIN_TRIES = 10; // wrong codes from one address before it is locked out
const ADMIN_LOCK_SECONDS = 900;
const MAX_QUESTIONS = 200;
const MAX_ITEMS = 100; // score = 101 - rank, so rank 100 is the last that scores
const MAX_ALIASES = 30;

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

function sameCode(a, b) {
  const hash = (s) => crypto.createHash("sha256").update(String(s)).digest();
  return crypto.timingSafeEqual(hash(a), hash(b));
}

// "" if this request carries the admin code, or why not.
async function adminError(b, req) {
  const code = process.env.ADMIN_CODE;
  if (!code) return "no_admin_code";
  const ip = String((req.headers || {})["x-forwarded-for"] || "local").split(",")[0].trim();
  const key = `rf:adminfail:${ip}`;
  const [tries] = await redis(["GET", key]);
  if (Number(tries) >= ADMIN_TRIES) return "locked";
  if (sameCode(b.secret, code)) return "";
  await redis(["INCR", key], ["EXPIRE", key, ADMIN_LOCK_SECONDS]);
  return "wrong_code";
}

// The same comparison the game makes (Minigame.normalize).
const normalize = (s) => s.trim().toLowerCase().replace(/[ .]/g, "");

// {questions} with only the fields the game uses, or {detail}: what is wrong, for the admin.
function cleanQuestions(list) {
  if (!Array.isArray(list) || list.length === 0 || list.length > MAX_QUESTIONS) {
    return { detail: `ต้องมีคำถาม 1 ถึง ${MAX_QUESTIONS} ข้อ` };
  }
  const isText = (v, max) => typeof v === "string" && normalize(v) !== "" && v.length <= max;
  const questions = [];
  for (let i = 0; i < list.length; i++) {
    const q = list[i];
    const where = `คำถามข้อ ${i + 1}`;
    if (!q || !isText(q.question, 200)) return { detail: `${where}: ต้องมีข้อความคำถาม (ไม่เกิน 200 ตัวอักษร)` };
    if (!Array.isArray(q.items) || q.items.length === 0 || q.items.length > MAX_ITEMS) {
      return { detail: `${where}: ต้องมีคำตอบ 1 ถึง ${MAX_ITEMS} รายการ` };
    }
    const seen = new Set();
    const items = [];
    for (let k = 0; k < q.items.length; k++) {
      const item = q.items[k];
      if (!item || !isText(item.name, 100)) return { detail: `${where} อันดับ ${k + 1}: ต้องมีชื่อคำตอบ (ไม่เกิน 100 ตัวอักษร)` };
      if (seen.has(normalize(item.name))) return { detail: `${where} อันดับ ${k + 1}: ชื่อ "${item.name}" ซ้ำกับอันดับก่อนหน้า` };
      seen.add(normalize(item.name));
      const aliases = item.aliases === undefined ? [] : item.aliases;
      if (!Array.isArray(aliases) || aliases.length > MAX_ALIASES || !aliases.every((a) => isText(a, 100))) {
        return { detail: `${where} อันดับ ${k + 1}: ชื่ออื่นไม่ถูกต้อง (ไม่เกิน ${MAX_ALIASES} ชื่อ)` };
      }
      items.push({ name: item.name.trim(), aliases: aliases.map((a) => a.trim()) });
    }
    const out = { question: q.question.trim(), items };
    for (const field of ["source", "as_of"]) {
      if (typeof q[field] === "string" && q[field].trim() !== "") out[field] = q[field].trim().slice(0, 300);
    }
    questions.push(out);
  }
  return { questions };
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

  async list(b) {
    const now = Date.now();
    const seen = [["ZREMRANGEBYSCORE", "rf:seen", 0, now - SEEN_SECONDS * 1000]];
    if (typeof b.who === "string" && b.who) seen.push(["ZADD", "rf:seen", now, b.who.slice(0, 16)]);
    const looking = (await redis(...seen, ["ZCARD", "rf:seen"], ["SMEMBERS", "rf:rooms"], ["EXPIRE", "rf:seen", 60])).slice(-3);
    const codes = looking[1];
    if (!codes || codes.length === 0) return { rooms: [], online: looking[0], playing: 0 };
    const [raws] = await redis(["MGET", ...codes.map(roomKey)]);
    const rooms = [];
    const gone = [];
    let inRooms = 0;
    let playing = 0;
    codes.forEach((code, i) => {
      if (!raws[i]) return gone.push(code);
      const r = JSON.parse(raws[i]);
      inRooms += r.count + (r.watchers || 0);
      if (r.status === "playing") playing += 1;
      rooms.push({ code, name: r.name, count: r.count, max: r.max, rings: r.rings, locked: r.password !== "",
        playing: r.status === "playing" });
    });
    if (gone.length) await redis(["SREM", "rf:rooms", ...gone]);
    rooms.sort((a, b) => a.playing - b.playing); // rooms you can join first
    return { rooms, online: inRooms + looking[0], playing };
  },

  async join(b) {
    const room = await getRoom(b.code);
    if (!room) return { error: "not_found" };
    if (b.watch) {
      if (room.status !== "playing") return { error: "over" };
    } else {
      if (room.status !== "open") return { error: "playing" };
      if (room.count >= room.max) return { error: "full" };
    }
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
      if (b.watchers !== undefined) room.watchers = Number(b.watchers);
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

  async questions() {
    const [raw] = await redis(["GET", QUESTIONS_KEY]);
    if (raw) return { questions: JSON.parse(raw) };
    // required here, not at the top: a problem with this file must not take the rooms down
    const { questions } = require("./questions_seed.json");
    await redis(["SET", QUESTIONS_KEY, JSON.stringify(questions), "NX"]);
    return { questions };
  },

  async admin_check(b, req) {
    const error = await adminError(b, req);
    return error ? { error } : { ok: true };
  },

  async admin_save(b, req) {
    const error = await adminError(b, req);
    if (error) return { error };
    const { questions, detail } = cleanQuestions(b.questions);
    if (detail) return { error: "bad_questions", detail };
    const [old] = await redis(["GET", QUESTIONS_KEY]);
    const writes = [["SET", QUESTIONS_KEY, JSON.stringify(questions)]];
    if (old) writes.unshift(["SET", QUESTIONS_BACKUP_KEY, old]);
    await redis(...writes);
    return { ok: true, count: questions.length };
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
    return res.status(200).json(await act(body, req));
  } catch (e) {
    return res.status(502).json({ error: "storage" });
  }
};
