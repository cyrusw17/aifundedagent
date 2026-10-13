# Working Title: **Needlewood** (Lumber Tycoon 2 x Needle in a Haystack)

## 1. Research summary

**Lumber Tycoon 2 (LT2) — what makes it sticky**
- Physical, sandbox loop: chop tree -> drag log -> sawmill -> planks (much higher value) -> sell -> buy axe/truck/sawmill.
- Biomes each hold unique woods; rarer woods (e.g. Frost Wood from Snow Peak, Phantom Wood) sell for far more. Access to rare woods is gated by exploration/puzzle/tools.
- Physical size limits (logs must fit the sawmill) create gear-gating without a level system.
- Persistent player base; items (planks) save, raw logs don't.
- Player trading of rare woods/axes/vehicles is a big community driver.
- Likely pain points (needs verification on the LT2 fandom/Reddit/Discord — my web search could not reach them): tedious hauling, aging UI/systems, dupe/exploit history, grind, little reason to return once rich.

**Search For The Needle (current hit; ~57M visits, ~55-86K CCU peak per trackers)**
- Loop: grab hay -> sell -> upgrade tools (Hand, Pitchfork, Dynamite, Vacuum, Drone) -> bigger bag -> find the needle -> chapters/areas, clans, gems, pets, Infinite Bag gamepass.
- Takeaway: "dig through a huge pile" is a proven, very satisfying, short-session hook; tool-upgrade tiers drive retention.

**Gap we fill:** Needle games are shallow (one pile, one scene). LT2 is deep but has no collection-chase "aha" moment. Combine LT2's world + crafting + base + trading with needle-hunting's treasure-hunt dopamine.

> Caveat: the above comes from limited sources (wiki fetch was blocked). Before locking design, spend a day on the LT2 wiki, r/LumberTycoon2, and Discord for current wood list, prices, complaints.

## 2. Core concept

You are a lumberjack-prospector. Every biome has a giant **Stack** (hay bale mountain, pine-needle drift, snow drift, sand dune, ash heap...). Hidden inside are **Needles**. Trees still matter: wood funds tools, bases, and the "Stack-cracking" gear; needles give prestige, hats, and mythic crafting.

Pun anchor: pine **needles** — the forest-floor "haystack" is literal.

### Core loop (2-5 min)
1. Chop trees / harvest -> logs -> sawmill -> planks -> sell (LT2 economy, simplified hauling).
2. Spend cash on **Search Tools** and **Axes**.
3. Dig the Stack with tools (sift, rake, vacuum, metal detector, dynamite...).
4. Find needles (common -> mythic), turn in at the **Needle Forge** for hats/crafts/prestige.
5. Complete a biome's Needle Set -> unlock **Biome Hat** + next biome.

### Meta loop
Base building (plank-based, saved) -> trading -> Biome sets -> **Rebirth ("Re-Stack")**: stacks regenerate bigger with new needle variants; keep hats/cosmetics.

## 3. Biomes, Stacks, and signature hats

One signature hat per environment, earned by completing that biome's Needle Set + a capstone event. Hats give a **small gameplay perk + big flex** (kept non-pay-to-win; also tradable only after N days to limit dupes).

| # | Biome | Stack | Signature Needle (set capstone) | Hat | Hat perk |
|---|-------|-------|--------------------------------|-----|----------|
| 1 | Meadow Farm | Hay mountain | Golden Darning Needle | **Straw Boater** | +5% hay/bag capacity |
| 2 | Pine Forest | Pine-needle drift | Living Pine Needle | **Lumberjack Beanie** | +5% chop speed |
| 3 | Snow Peak | Snow drift | Icicle Needle | **Frost Ushanka** | Cold-zone stamina regen |
| 4 | Desert Dunes | Sand dune | Scarab Needle | **Pharaoh Headwrap** | Metal detector range +10% |
| 5 | Swamp | Peat/reed bog | Glowworm Needle | **Mossy Bog Hat** | Reveals faint needle glints |
| 6 | Volcano | Ash heap | Obsidian Needle | **Magma Hard-Hat** | Heat immunity, dynamite +power |
| 7 | Cave / Underground | Crystal rubble | Geode Needle | **Miner's Lamp Helmet** | Light radius, finds buried needles |
| 8 | Sky Island | Cloud drift | Stormthread Needle | **Cloud Halo** | Float/glide longer |
| 9 | Haunted Grove | Cobweb pile | Phantom Needle | **Spectral Top Hat** | See ghost needles (night event) |
| 10 | Endgame: The Infinite Stack | Mixed | Needle of Needles | **Crown of Thorns & Needles** | Cosmetic aura + prestige title |

(Ten is a roadmap; ship 3 biomes at launch, add one every 2-3 weeks.)

## 4. Special needles

**Rarity tiers:** Common (Steel) -> Uncommon (Bronze) -> Rare (Silver) -> Epic (Gold) -> Legendary (Biome Signature) -> Mythic (event/secret).

**Special needle types (utility, not just trophies):**
- **Compass Needle** — points toward the nearest hidden needle in the Stack.
- **Lumberjack Needle** — "stitches" two logs together (lets you carry oversize logs / solves sawmill size limits).
- **Magnet Needle** — pulls loose planks/logs to you.
- **Thread Needle** — fast-travel anchor to your base.
- **Lightning Needle** (Sky Island) — chain-fells trees.
- **Echo Needle** (Cave) — sonar ping for buried finds.
- **Ghost Needle** (Haunted) — only visible at night; trade-locked, cosmetic trail.
- **Golden Needle (daily)** — one guaranteed rare spawn per server per day -> server-wide hunt event.
- **Mutated Needles** — random modifiers (Rainbow, Glitch, Giant, Tiny) that multiply value; main trading currency.

**Pity/fairness:** hidden bad-luck protection, and an on-screen "needles remaining in this Stack" counter so hunts feel finite and winnable.

## 5. Systems

- **Search tools (tiered, all upgradable):** Hands -> Rake -> Pitchfork -> Sieve -> Metal Detector -> Dynamite -> Vacuum -> Drone. Each changes *how* you search (area vs. precision vs. speed).
- **Wood economy:** ~8 woods across biomes; planks > logs; sell-price shifts slightly per server (simple supply/demand).
- **Hauling QoL (LT2's biggest friction):** auto-attach rope, wheelbarrow -> cart -> truck, log-to-sawmill conveyor unlock.
- **Base:** claimable plot, plank building, Needle Display Wall, Hat Rack. Saved via DataStore.
- **Trading:** safe trade window; only fully-owned, non-bound items; trade-lock on new finds (24h) to curb scams.
- **Social:** co-op digs (multi-person Stack blasts), clan Stack goals, global "needle found" announcements.
- **Collection log:** per-biome needle codex with silhouettes — the completion driver.
- **Monetization (fair):** Infinite Bag-style gamepass, 2x cash, extra plot, VIP cosmetic hats/pets, private servers. Signature hats are *earned only*.

## 6. How to build it (Roblox tech plan)

**Stack:** Roblox Studio + **Rojo** (filesystem sync) + **Wally** (packages) + Git. Luau with strict typing; **Selene** + **StyLua** for lint/format; **TestEZ/Jest-Lua** for unit tests. Optional: **Knit** or plain module services; **ProfileService/ProfileStore** for data; **Replica/Net** for replication.

**Repo layout (proposed)**
```
default.project.json
src/
  server/   (Services: Data, Economy, Stacks, Needles, Trade, Base, Hats)
  client/   (Controllers: Input, UI, Tools, VFX)
  shared/   (Config: Biomes, Needles, Woods, Tools, Hats; Types; Util)
assets/     (place files, models exported)
docs/
```

**Key technical decisions**
1. **Stacks without 10k parts:** don't simulate every hay piece. Use a **voxel/cell grid of "dig cells"** per Stack (server owns truth: which cells hold needles via seeded RNG). Render with instanced/pooled particle-like parts + terrain/mesh swap as cells clear. Digging = removing cells in a radius; needle reveal = server event. This keeps it cheap and exploit-resistant.
2. **Server-authoritative finds:** needle positions/rolls generated server-side with per-player seeds; client only displays. Never trust client "I found it".
3. **Data:** ProfileStore (session-locked) for inventory, hats, codex, plot; schema versioned with migrations.
4. **Trees/logs:** reuse a simple tree model (cut into segments) with physics-light logs (anchor when idle; unanchor when dragged); network ownership to dragging player; hard cap on active logs per server.
5. **Content as data:** biomes/needles/hats/tools defined in `shared/Config` tables so adding a biome = data + art, not code.
6. **Streaming + perf:** `StreamingEnabled`, biome zones loaded by distance, mobile-first UI (large Roblox playerbase on phone).
7. **Anti-exploit:** rate-limit remotes, validate distances/tool cooldowns server-side, trade-locks, audit log of rare finds.
8. **Analytics/live-ops:** Roblox Analytics custom events (time to first needle, D1/D7, funnel per biome); feature flags via MemoryStore/config module.

## 7. Roadmap

| Phase | Goal | Deliverables |
|-------|------|--------------|
| 0 (1 wk) | Validate | Deeper LT2 + needle-game research, finalize name/pillars, greybox design doc, art style (low-poly cozy, Roblox-friendly) |
| 1 (3-4 wk) | **Vertical slice** | Rojo project, Data service, Meadow Farm biome, hay Stack (dig cells), Hands->Pitchfork->Sieve, sell loop, 5 needles, Straw Boater, basic UI |
| 2 (4 wk) | **Core + LT2 layer** | Pine Forest: trees, logs, sawmill, planks, axes, hauling, base plot save, Lumberjack Beanie, Compass/Lumberjack Needles |
| 3 (3 wk) | Social/economy | Trading, codex, leaderboards, co-op digs, daily Golden Needle |
| 4 (2-3 wk) | Soft launch | Snow Peak (3rd biome), monetization, mobile polish, anti-exploit pass, private test group, analytics |
| 5+ | Live ops | New biome every 2-3 wks, seasonal needles/hats, Re-Stack rebirth, events |

**Team (small):** 1 scripter (can be us/Claude-assisted), 1 builder/artist, 1 UI/VFX; sound via marketplace + one composer.

## 8. Risks
- "Needle" clone saturation -> differentiate via LT2 depth (base, trading, woods) and biome hats.
- Physics log hauling can lag -> caps, anchoring, pooling.
- Trading = dupe/scam surface -> trade-locks, server-side ownership, logging.
- IP: don't copy LT2 assets, names (e.g. Phantom Wood is LT2's) or map; use original woods/names (rename Phantom/Frost in our final content).

## 9. Next steps
1. Confirm direction (name, art style, launch biomes).
2. I scaffold the Rojo repo (project file, folder layout, config tables, DataService, Stack dig-cell prototype) in this repo.
3. Build the Meadow Farm vertical slice.
