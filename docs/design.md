# Roulette Fantasy: design (one page, MVP)

**Engine:** Godot 4.7.2 (2D) · **Genre:** digital tabletop card/board, 4 players (1 human + 3 AI bots)
**Full spec:** `../Roullet Fantasy.md` (3D first-person, online, voice chat = later)

## Pitch
Sit at a fantasy tavern table with three rivals: throw dice for gold, buy and play cards, attack and
curse each other, win minigames for ring shards, and be the first to forge 5 rings.

## Core loop
- **Every turn (~30 s):** throw 3 dice (gold), draw 2 cards, shop, attack or defend.
- **Every 2 rounds:** minigame → ring shards and gold.
- **Whole game (~20 min):** shards → rings at the shop; first to 5 rings wins.

## Player
HP 4 · Gold 2 · 1 random item card · Shards 0 · Rings 0. Hand limit 7.

## Round
Opening roll: everyone throws 3 dice; highest total plays first, lowest last (ties throw
again among themselves). The top-bar cards line up in that turn order. Each player's turn:
1. **Roll (ทอยลูกเต๋า):** may play up to 2 item cards first; throw 3d6, gold = floor(sum / 2), minimum 1;
   draw 2 cards; 20 s to plan.
2. **Preparation (เตรียมตัว):** buy cards; exchange 2 shards → 1 ring (only after minigame 1);
   play cards allowed in this phase.
3. **Combat (ต่อสู้):** play an **Attack card** on a target. The target may play a **Defense card**:
   blocked = the Defense card is used up, no HP lost (shield effect + clang); not blocked = −1 HP
   (red flash + hurt sound). There is no shield stat. Curses/Buffs here.

After every 2nd round: **minigame**.

## Death
HP 0 → **eliminated** (spectates). Last player alive also wins.

## Effects and your own knockout (2026-10-31)
- Every effect icon (top-bar cards, and over the bots' heads) shows its count: turns left,
  or stacks for a free block.
- Cards that may target anyone (cleanses) show a "ใช้กับตัวเอง" button over your hand while
  you aim them (you have no body to click; your top-bar card works too).
- The blow that ends the game always plays at full length, and the win banner stays 3 s, even
  when you are out and the bots are on fast-forward.
- When you are knocked out, your own hero appears in your seat and the camera glides up over
  the far side of the table (narrower view) to watch the finisher on you; then it glides back
  to first person and you spectate. The game waits for all of it.

## Dice tip and hand cards (2026-10-31)
- Top right of the table: a dice button with a "?"; hover (or click to keep it open) shows how a
  roll scores: total of 3 dice / 2 rounded down = gold (min 1, max 9), the full total→gold
  table, the 2 cards drawn, and what Bad Luck does.
- Cards in your hand no longer show their price (only the shop does).

## Shrinking table (2026-10-31, v3, the user's design)
No HP drain, no clock. Every 5 finished rounds (a round = the first player through the last;
GameController.SHRINK_ROUNDS) everyone's max HP and hand limit drop by 1 (not below 1 / 3):
HP over the new max is lost, extra cards discarded newest first, heals stop at the new max.
Under the round plate only a number: rounds left until the next drop (5 → 1, orange on 1, then
back to 5); its tooltip says what it means. Hidden once both are at their floor.
Bots: with a full hand and no Attack card (drawn cards are thrown away when the hand is full,
which a shrunk hand makes common) a bot swaps a spare Defense for an Attack from the shop; they
also keep fewer Defense cards when the hand limit is low. Without that, rings-off games stalled.
Measured (tests/balance_sim.gd, 40 games each): every game ends. Rings off: 2 players ~15
rounds (~12 min), 4 players ~18 rounds (~18 min), 6 players ~19 rounds (~23 min). Rings on
unchanged: 4 players ~10 rounds (~18 min), 6 players ~11 (~23 min), always won by rings.
(v1: HP drain from round 10/16; v2: drain + shrink every 3 turns after 10 minutes; both dropped.)

## Minigame: guess the rank (1–100)
A "top 100" question. Whoever runs the game (web) loads the questions from the database at game
start (`questions` in web/api/room.js, key `rf:questions`); `data/minigame_ranks.json` is packed
with the game as the fallback, and fills the database the first time (web/api/questions_seed.json,
same content). Once filled, editing the JSON no longer changes the live questions: use /admin.html (secret code = ADMIN_CODE in Vercel). 3 rounds, same question; each
player names an item; score = 101 − its rank (not in list = 0); no repeating any earlier answer;
Thai or English answers (aliases in the JSON). Bots pick answers from the list with some error.
Rewards: 1st 3 shards + 10 gold, 2nd 2 + 5, 3rd 1 + 5, 4th 0 + 3.
Answers go in turn order, 15 s each (empty or timeout = pass, 0 points); equal scores share
the place and its reward. Turns pause while it runs.

## Cards (MVP set, data in `data/cards.json`)
| type | cards |
| --- | --- |
| Basic | Attack ×22, Defense ×6 in the draw pile; the shop always has 2 Defense cards |
| Help | Heal 1, Heal 2, Gain Defense (เสริมป้องกัน: next Defense card you block with is not used up; stacks), Cleanse 1, Cleanse all, กันห้ามไอเทม (ward_no_items, 2026-10-31, renamed shorter from ล้างคำสาปห้ามใช้ไอเทม: never played by hand; lifts a No Items curse by itself the moment it lands, or at once if you get it while cursed; max 1 per hand: the shop refuses a second, a drawn second is set aside for another card; 3 in the deck, price 3) |
| Curse | No items (1 turn), No shopping (2 turns), Truce (2 turns), Bad luck, Blind (2 turns) |
Shop prices (first guess, tune in playtest): Attack/Defense 2, Help 3, Curse 4.

## MVP (finish these first)
1. Table screen: 4 seats, each with HP, gold, shards, rings, card count; your hand; game log.
2. Turn engine: seat order, dice roll + draw, Preparation, Combat, 20 s timer, round counter.
3. Cards from JSON: Attack/Defense combat, Help and Curse effects with durations.
4. Shop: buy cards, shards → ring exchange (after minigame 1).
5. Minigame "guess the rank" every 2 rounds, with the reward table.
6. AI bots that buy, attack, defend, use help/curse cards and play the minigame.
7. End: 5 rings or last alive → result screen (summary table) + Rematch.

## Later (only after the MVP plays)
Black market cards (ตลาดมืด 1–3 and their 9 rare cards), VIP/BOGO, Reflect curse, Buffs
(Attack/Defense/Luck), more minigames, sound/art pass, 3D first-person table, online rooms,
voice chat, collection/trophies, reconnect/AFK bots, spectator mode.

## Screen: first-person pixel 3D (2026-10-25)
A 3D tavern (scripts/tavern_view.gd) rendered at full 960x540 with 4x anti-aliasing (blocky
look from the models and nearest-filtered textures),
camera at your seat. Bots are blocky 3D chibi heroes built in code (scripts/character3d.gd),
seated a little turned towards you; they blink, breathe and pull faces. Dice are 3D (scripts/dice3d.gd): thrown from the roller's seat,
land showing the rule result. 2D HUD on top (layout from the user's 2nd mockup): a top bar
of four player cards in turn order (yours blue with a star: portrait, name, effect icons, HP, rings, hand size,
shards), a round/phase plate under it, the game history top-right (icons per line; starts
folded into a tab on the right edge), gold bottom-left, a brass rail to the hand fan bottom-centre, Shop/Next buttons with
icons bottom-right. To attack (or aim any card), click the 3D bot itself or its card: the
bots you may pick glow orange, the one under the mouse brighter.

## Menus and rooms (2026-10-25, from the user's interface mockups)
Offline for now: you against bots. Flow: main menu (menu.tscn, scripts/main_menu.gd; behind it
scripts/menu_scene.gd: a bird's eye view down on the table, swaying side to side on a
spring (eases out, glides, settles), all four heroes seated one per side playing:
dice throws, cheers and pained faces, coins from the pot, cards flung at rivals; silent) → Create Room → lobby → table (main.tscn) → results.
- **Main menu:** logo, สร้างห้อง / ค้นหาห้อง / ใส่เลขห้อง, ตั้งค่า (name, volume; saved in
  user://settings.cfg), วิธีเล่น, ออกจากเกม, player badge top-right.
- **วิธีเล่น:** a 9-page slideshow of real game screenshots (assets/howto, 640x360, made with
  tests/shot_shop.gd and tests/shot_seats.gd), a title and a two-line caption each; ◀ ▶, page
  dots, click the picture for the next page. Retake the shots when the table's look changes.
- **Find Room / Join by Code (6 digits):** the screens exist; they say online play is coming.
- **Create Room** (2026-10-25, from the user's settings outline): presets on top: ห้องมาตรฐาน
  (4 players, 5 rings, 20 s), เล่นเร็ว (3, 3 rings, 15 s, auto start), สายปั่น (4, 7 rings,
  30 s; the user's "สายปั่น Roulette", without the roulette), กำหนดเอง (opens every setting;
  changing any setting by hand also switches to it). Below, folding sections:
  ตั้งค่าห้อง (name, players 2-4, public / password room with a 4-digit password),
  กติกาการแข่งขัน (turn time 15/20/30/45 s, rings 3/5/7 or "ไม่ใช้แหวน" = win only by being the
  last one standing, start: host presses Start / starts by itself when everyone is ready),
  มินิเกม (on/off; off also turns rings off, since minigames are the only source of shards;
  with rings off a minigame pays gold only, and ring pips / the shop's ring exchange are hidden), สมดุลและความยาก and ผู้เล่นและสิทธิ์ (shown, marked "ระยะถัดไป").
  Characters may repeat (always; the bots still spread over the others first). Summary on the
  right. Room type and password only matter once online play exists.
- **Roadmap for room settings:** phase 2: starting HP, items on/off, random events, joining
  mid-game (spectators, AFK bots); phase 3: custom dice odds, rule presets of your own, saved
  setting sets.
- **Lobby:** room name, #code (and password), everyone's character in 3D, pick yours (the
  bots re-seat around it; changing character takes your Ready back), player list with ready
  state, room messages, พร้อม / เริ่มเกม. Bots get ready after 1-3 s. Host start: Start unlocks
  when everyone is ready; auto start: a 3 s countdown once everyone is ready (cancelled if
  anyone un-readies).
- **Table:** 2-6 seats (2026-10-25: the user wants 2 to 6 players). 2-4 use tavern_view
  LAYOUTS; 5-6 sit on an arc round the far side (ARC_LAYOUTS). With 5-6 the top-bar cards are
  narrower with no portrait and the "Roulette Fantasy" title is hidden to make room. Only 4
  characters exist, so with 5-6 some repeat.
  Names: you are called by your own name (Settings); bots get random names from
  GameConfig.BOT_NAMES, drawn once per room (they keep them when you change character, and in
  a rematch); the character shows under each name. Minigame places 5th-6th get the
  4th-place reward. The room settings live in scripts/game_config.gd.
- **Results** (scripts/result_panel.gd): left menu (summary / score details / what everyone
  had left / main menu), the winner's card in 3D, ranked cards (rank, character, score, HP,
  rings, status), your stats (kills, deaths, help cards, damage, gold), and เล่นต่อ (same
  room, same seats), ค้นหาห้องใหม่, กลับหน้าหลัก. Score is for show (rank = winner first,
  then standings): ring 100, shard 20, kill 50, damage 10, HP left 5, win 300.
- Headless runs (smoke tests) skip the menu and go straight to the table.

## Look and sound
Fantasy tavern (pixel art, see the first-person mockup): green felt table, candle light, wood and brass UI. Placeholder shapes first.
Window 960x540, scales up.

## Balance (2026-10-25, tests/balance_sim.gd, 300 bot games)
| | before (HP 5, 3 shards/ring, Attack 14, Defense 12) | now (HP 4, 2 shards/ring, Attack 18, Defense 8) |
| --- | --- | --- |
| rounds / est. minutes | 15.2 / ~32 | 9.8 / ~18 |
| eliminations per game | 0.9 | 1.65 |
| won by last alive | 0% | 3% |
| attacks blocked | 63% | 50% |

Bots defending (2026-10-25): bots bought Attack before Defense and 41% of attacks hit a bot
with no Defense card. Now bots shop by need (Defense first, keep gold for one) and the shop
always stocks 2 Defense: blocked 49% -> 58%, unarmed targets 41% -> 33%, eliminations 1.54/game,
~18 min.

## Characters (2026-10-25, from the user's roulette-fantasy-Character.md)
Bodies have legs (2026-10-25): seated (thighs forward, shins down) on chairs with seats at the
table and in the menu scene, standing in the lobby and results previews.
You pick one before the game (CharacterSelect, rotating 3D previews); the bots get the
others in random seats and go by their character's name. Data: data/characters.json.
A character's Attack card is only renamed and redrawn (its weapon; still -1 HP). Its attack
plays when an attack resolves; if the hit knocks the target out, its finisher plays.

| character | weapon (Attack card) | attack | finisher |
| --- | --- | --- | --- |
| นักล่าอาคม Demon Hunter | ดาบโลหิต | Blood Slash: lunge + red slash | Soul Reap: slash flurry, target bursts into pieces |
| อัศวินเวท Arcane Knight | ดาบเวทมนตร์ | Arcane Slash: cyan crescent | King's Verdict: giant light blade, target cut in half, charred cut |
| เรนเจอร์พฤกษา Verdant Ranger | ธนูไม้เวท | Thorn Shot: green arrow | Final Arrow: arrow to the sky, giant arrow through the head into the table |
| มังกรเพลิง Flame Dragon | กรงเล็บเพลิง | Inferno Claw: fire claws | Dragon's Judgment: fire stream, target burnt to charcoal |

The game waits (GameController.hold) while an attack or finisher plays. Finishers on you
are shown as screen effects. Two more characters are planned (6 in the user's file).

## Sound (2026-10-25)
Few sounds on purpose. Every sound is picked by the user, by ear, in the sound lab
(tools/sound_lab/sound_lab.gd: CC0 candidates per slot, a "no sound" choice; picks in
tools/sound_lab/choices.json, copied to assets/sounds/<slot>.wav|ogg). Silent by choice:
turn. All sources are CC0: Kenney (kenney.nl), artisticdude's RPG Sound Pack
(opengameart.org), SSE Library WEAPONS / FIRE / EXPLOSIONS (archive.org).
| slot | when | source |
| --- | --- | --- |
| select | picking a character | Kenney Interface Sounds, drop_002 |
| confirm | the start button | Kenney Interface Sounds, confirmation_001 |
| dice | any dice throw | Kenney Casino Audio, dice-throw-2 |
| sword | sword hits, Soul Reap slashes, King's Verdict chop | SSE WEAPONS, Hitting large object with sword (hit 1) |
| bow | ranger shots, Final Arrow sky shot | SSE WEAPONS, Five arrows whoosh by (1st) |
| claw | dragon's Inferno Claw | artisticdude RPG Sound Pack, swing3 |
| magic_wave | knight's Arcane Slash wave | SSE FIRE, Flare whoosh |
| dragon_roar | Dragon's Judgment growl | artisticdude RPG Sound Pack, gutteral beast mnstr3 |
| dragon_fire | Dragon's Judgment jet | SSE FIRE, Flame thrower (part 4) |
| burning | the target burning | SSE FIRE, Flame thrower (tail 1) |
| burst | Soul Reap burst | artisticdude RPG Sound Pack, slime7 |
| arrow_pin | Final Arrow pinning the table | SSE EXPLOSIONS, Dull explosion |
| block | a block | Kenney Impact Sounds, impactPlate_heavy_000 |
| card_play | playing a non-attack card | Kenney Casino Audio, card-place-1 |
| coin | you buying in the shop (bots' purchases are silent) | artisticdude RPG Sound Pack, coin |
| hurt | anyone losing HP to a normal hit | artisticdude RPG Sound Pack, beetle bite-small2 |
| verdict | King's Verdict slam | Kenney Impact Sounds, impactMining_002 |
| win | you win | Kenney Music Jingles, STEEL00 |
| lose | you lose | Kenney Music Jingles, PIZZI09 |

## No gambling look
No roulette wheel or casino props (user, 2026-10-24): gold comes from a dice throw on the
table. The title "Roulette Fantasy" stays for now.

## Assumptions made from the spec (check these)
- The second "ฟื้นเกราะ 1/2" pair (cleanse a curse + 1 shield) is named **Cleanse 1 / Cleanse all**.
- "coin" and "บาท" are the same currency: **gold**.
- Ring exchange rate: 2 shards (spec said 3; lowered for a ~20 min game, see Balance).
