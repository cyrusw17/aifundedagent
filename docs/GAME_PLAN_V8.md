# Needlewood V8: The full plan, then the improved plan

V8 has three parts:

1. **Part A** is the complete game as decided up to 2026-10-13. It is V7 plus every decision made in the project that day.
2. **Part B** critiques Part A.
3. **Part C** is the improved plan. Every change from Part A is tagged **[CHANGED]** or **[NEW]**.

All numbers are placeholders to tune in playtests. They are design judgement, not data.

Sources: docs/GAME_PLAN_V6.md, docs/GAME_PLAN_V7.md, docs/ITEMS.md, /mnt/project-files/BUILD_REGISTRY.md, and the code in `src/shared/Config` (Sorters, Trucks, Needles, Meadow).

---

## Part A: The full plan as decided

### Pitch
Needlewood is Lumber Tycoon 2 with hay. You haul hay bales, sort the hidden needles out of them, and turn needles into money and building blocks. You grow from carrying one bale by hand to running a farm of conveyor lines fed by semis and ferries across an archipelago.

### Look
- Lumber Tycoon 2 shapes with the Rustic finish.
- Muted, weathered straw, bark and plank colors.
- Metal is clean weathered grey iron, with no orange rust.
- 1 stud = 0.28 m.
- Glow is kept for rare items.

### Hay
- All hay is square, twine-wrapped bales. Every bale is the same size: 4.6 x 2.6 x 3.2 studs. There are no barrels and no round bales.
- Bales are free physics blocks. They are never welded.
- Each region has its own hay type and needle type.
- Every bale hides needles.

### Hand tools
- There are only two hand tools: the **shovel** breaks a bale and scoops the loose hay, and the **rake** gathers loose pieces.
- With bare hands you lift a whole bale.
- You use a tool by clicking the hay with it. The only overlay is a small pick-up prompt.
- Upgrades are **tiered gloves**, not new tools.
- Carrying hay slows you down, and rarer hay slows you more unless your gloves are good enough.

### Vehicles
- You buy trucks at Homestead Motors:

| Truck | Price | Bed |
|---|---|---|
| Rusty Pickup | $6,000 | 9 bales a layer |
| Farm Flatbed | $25,000 | |
| Box Truck | $90,000 | |
| Heavy Hauler | $350,000 | |
| Semi Rig | $1.5M | |

- Trailers hitch on: Wagon (2 bales), Small (4), Medium (10), Large (36), Double (12) and Bale Rack (30).
- Cargo rides loose in a real truck bed. Every bed floor sits at 3.5 studs, the same height as the dock belt.

### Selling
- The public **HAY SELL SHOP** has a loading dock and a conveyor. It pays $0.50 per piece of hay, but only $1 per hidden needle.
- Sorted needles sell for about $100 each, and more in richer regions.

| Needle | Sorted value |
|---|---|
| Steel | $100 |
| Pine | $110 |
| Sand | $140 |
| Ice | $160 |
| Bog | $170 |
| Obsidian | $300 |
| Geode | $340 |
| Cloud | $700 |
| Phantom | $800 |
| Cosmic | $5,000 |

### Land and the base
- At the Land Office you buy one of six **72 x 72 plots** (12 x 12 conveyor tiles).
- In build mode you place 6-stud conveyor tiles, a dock, a hay buyer, needle sorters and needle bins.
- Sorter tiers:

| Sorter | Recovery | Speed |
|---|---|---|
| Hand sieve | 15% | 20 hay/min |
| Shaker table | 35% | 60 hay/min |
| Conveyor sorter | 55% | 150 hay/min |
| Magnet drum | 75% | 400 hay/min |
| Optical sorter | 92% | 900 hay/min |
| Alien collector | 100% | instant |

- Sorted needles are **physical objects**. They stay needles, and you pick them up and sell them.
- Mills and silos add storage.

### Saves
- When you join, you pick Save 1, 2 or 3, or Load 1, 2 or 3.
- Each slot is its own farm: plot, trucks, money and collection.

### World
- The whole Stitched Isles map ships at launch.
- **Main island:**
  - Meadow Farm (the start)
  - Pine Forest
  - Snow Peak
  - Haunted Grove
  - Homestead Valley (the hub)
  - Volcano
  - Desert Dunes
  - Swamp
  - The Spindle, in the center
  - Cave, underground
  - Sky Island, reached by zeppelin
- **Thimble Keys** is reached by the Longstitch Highway or by boat.
- **Bobbin Rock** is boat only.
- Boats are **ferry-sized**, so they carry trucks with trailers.

### Building
- Blueprint building works like Lumber Tycoon 2: you place a hollow template and fill it with needles or hay.
- There are 20 shapes and 12 materials.
- Steel makes plates, Pine makes planks, Sand makes bricks, Ice makes glass, Bog makes mossy stone, Obsidian makes black glass, and so on.

### Endgame
- **Mazes:** Straw Labyrinth (daily), Drowned Rows (sea), and Corn Night Maze (night only).
- **Alien collector gauntlet:**
  1. A crop circle signal appears.
  2. Get the three Corn Night Maze keys.
  3. Claim the Golden Hay Bale.
  4. Find three beacon parts (about 1 in 2,000 scoops each).
  5. Lay hay bales in the daily pattern at midnight.
  6. Offer 100 sorted needles of each type.

  The reward is the Starbeam Collector. A first clear takes about two weeks.
- **Collection:** 460 items, including foreign objects and a collection book.
- **Mystery:** the Weaver and the 12 shards of the Master Needle that open the Spindle.

### Monetization (from V1)
Fair gamepasses: cosmetics, private servers and VIP. There are no paid maze skips, and hints stay cryptic.

---

## Part B: Critique

| Area | Grade | Main problem |
|---|---|---|
| First 10 minutes | D | Hand carrying earns about $14/min, so the $6,000 pickup takes about 7 hours. Most Roblox players leave in under 15 minutes. |
| Hauling payoff | C- | Loading 9 bales by hand takes as long as carrying them, so the first truck barely beats walking. |
| Sorter ladder | C | Tiers are priced on recovery, but the real limit is throughput. With no buffer, a sorter stands idle while you haul. |
| Economy curve | C | Sorting makes a load about 15-30x more valuable, so after tier 1 the public shop is pointless and loose hay feels worthless. |
| Progression gates | B- | Gloves slow you down, but there are no numbers yet for how much or for which region. Regions have no clear order. |
| Physical needles | C | An optical line makes about 1,000 needles an hour. As separate parts they will lag the server and bloat saves. |
| Retention | C+ | The endgame is strong, but there is no daily or weekly reason to log in between hour 2 and the mazes. |
| Multiplayer | C | Plots are private and there is no co-op, so the shared hub is just scenery. |
| Travel | B- | A full archipelago with ferries is great, but a long empty crossing alone is dull. |
| Monetization | B | Fair, but it lacks Roblox-standard convenience passes that don't sell power. |

**Overall: C+ (6.0/10).** The ideas are strong. The pacing and the numbers are what hold it back.

---

## Part C: The improved plan

### 1. Opening pacing [CHANGED]
These are target times for a new player:

| Time | Milestone |
|---|---|
| 0:00-2:00 | Lift a bale and sell it at the public shop. A short line of text explains each step. No pop-up wall. |
| ~3:00 | **[NEW]** The first bale you break always spills one glinting steel needle. Selling it shows the gap: $1 at the shop versus "$100 if sorted". |
| 15-20 min | Rusty Pickup **[CHANGED $6,000 -> $600]**. |
| 35-45 min | Plot **[CHANGED: $2,500]** plus a hand sieve ($500). The first steel fence from the blueprint shows needles as a building material straight away. |
| ~1.5 h | Shaker table, Work Gloves, first trip to Pine Forest. |
| ~3 h | Farm Flatbed plus a Small trailer, Desert Dunes. |
| ~6 h | Conveyor sorter, Leather Gloves, Snow Peak and Swamp, first highway run to Thimble Keys. |
| ~12 h | Box Truck, Magnet drum, Volcano and Cave. |
| ~25 h | Heavy Hauler, Optical sorter, Sky Island and Haunted Grove. |
| 40 h+ | Semi plus Double trailer, ferry to Bobbin Rock, the Spindle shards, the Alien gauntlet (about two weeks). |

### 2. Hauling [NEW]
- **Field bale chutes:** every hay field has a wooden chute. Park under it, pull the lever, and it drops a bed's worth of bales in loose (physics, no welds) in about 10 seconds. You can still load by hand.
- A pickup trip takes about 1.2 minutes and earns about $105/min raw. Walking earns about $34/min, so the truck is a clear step up.
- **Unloading:** at any dock, tipping the tailgate and the walking floor empty the bed in about 15 seconds.

### 3. Economy, per bale [CHANGED]
- **Hay:** a bale breaks into 24 pieces. The public shop pays $0.50 per piece, or $12 a bale. Your own hay buyer pays **[NEW] $0.60**.
- **Needles per bale [NEW]:**

| Region | Needles per bale |
|---|---|
| Meadow | 2 |
| Pine | 3 |
| Desert | 4 |
| Snow | 5 |
| Swamp | 6 |
| Volcano | 8 |
| Cave | 10 |
| Sky | 12 |
| Haunted | 14 |
| Star | 20 |

  Richer hay is worth more twice: more needles, and pricier needles.
- **Sorter ladder, re-tuned around throughput [CHANGED].** The value per bale is for Meadow hay.

| Sorter | Price | Recovery | Bales/min | Value per bale | $/min when kept full | Payback |
|---|---|---|---|---|---|---|
| Hand sieve | $500 | 15% | 2 | $42 | $84 | instant |
| Shaker table | $4,000 | 35% | 4 | $82 | $328 | ~16 min |
| Conveyor sorter | $20,000 | 55% | 8 | $122 | $976 | ~31 min |
| Magnet drum | $120,000 | 75% | 16 | $162 | $2,592 | ~74 min |
| Optical sorter | $700,000 | 92% | 30 | $196 | $5,880 | ~3.5 h |
| Alien collector | quest only | 100% | instant | | | once per day |

- **[NEW] Silo buffer:** hay you dump at your dock waits in the silo, and the line keeps sorting while you go out for the next load. That makes hauling and sorting a loop: you haul to keep the sorter full.
- **[NEW] Server market:** needle prices drift up to ±20% on each server, depending on how much of each type has been sold there recently. Flooding steel drops its price, which pushes players toward other regions.
- **Raw hay stays useful [NEW]:** it is thatch and straw-bale building material, and an input for the alien pattern.

### 4. Gloves as the region gate [CHANGED: numbers added]
- Each region's hay has a tier from 1 to 6.
- For each tier your gloves fall short, walking speed while carrying drops 15%, down to a floor of 40%. Shoveling slows by the same amount.
- Nothing is locked: you can haul Volcano hay in cotton gloves, just slowly.

| Gloves | Tier | Price | Regions it covers |
|---|---|---|---|
| Cotton | 1 | free | Meadow |
| Work | 2 | $1,500 | Pine, Desert |
| Leather | 3 | $15,000 | Snow, Swamp, Thimble Keys |
| Insulated | 4 | $80,000 | Volcano, Cave (heat) |
| Reinforced | 5 | $300,000 | Sky, Haunted, Bobbin Rock |
| Starweave | 6 | crafted from Cosmic needles | Star Hay |

- **[NEW]** Thimble Keys gets Pearl needles and Bobbin Rock gets Anchor needles. Both islands now have a needle of their own, which makes 12 types.

### 5. Physical needles that scale [CHANGED]
- A needle is still always a physical object. It never turns into a number.
- Sorters drop needles into a **needle bin**. A bin holds up to 200 needles, stacked visibly inside it.
- You sell by carrying the bin to the SELL NEEDLES pad, or by belting it there.
- Each plot can have at most 400 loose needles. Once a plot reaches that limit, its sorters pause until a bin is emptied.
- Saves store needle counts per bin and rebuild the needles when you join.
- **Question for Cyrus:** should bins be allowed to bundle 10 needles into one "needle bundle" object? That would cut part counts by 10x, and the V6 plan already sold needles in bundles.

### 6. Daily and weekly reasons to play [NEW]
- **Rich field:** every 20 minutes one hay field on the server is marked on the map with 2x needles.
- **Bounty board:** three jobs a day at the Homestead hub. Examples: deliver 30 Pine bales, or build a 4x4 sand wall. The rewards are cash and foreign objects.
- **Events:** Hay Fever (double bales), Meteor Shower, Low Tide, and the Hay Golem boss.
- **Collection book:** one weekly page. Finishing it gives a cosmetic, never power.
- **Mystery chapters:** one shard puzzle opens each week.

### 7. Multiplayer [NEW]
- **Farm crew:** an owner can whitelist friends to drive their trucks and run their line, like Lumber Tycoon 2. Earnings go to the owner, with an optional split.
- **Convoy bonus:** two or more crew trucks unloading together at a dock get +10% for that load.
- **Shared ferry:** a public ferry leaves every 3 minutes and carries up to 6 trucks with trailers. The crossing has a deck you can walk around, and it is where players meet and trade. Players can later buy a private cargo barge.
- **Trading post:** at Homestead. Players trade needles, blocks and foreign objects, with a 24-hour lock on mythic items.
- **Visit plots:** players can tour other farms and give them a "Best farm" like. A weekly leaderboard shows the most-liked farms.

### 8. Monetization [CHANGED]
- **Cosmetic:** truck paint packs, glove skins, plot themes (fences, signs, lights), and VIP name color with a hub lounge.
- **Convenience that doesn't sell power:**
  - Auto-Dock: the tailgate opens and unloads by itself when you park.
  - A bigger silo buffer: +50%, about 30 minutes of hauling saved.
  - Private servers.
- **Never sold:** cash, needles, sorter tiers, maze skips, alien steps, or any ranked advantage.
- Premium Payouts work automatically, since time played counts.

### 9. Saves [CHANGED: clarified]
- All three save slots are free.
- Each slot stores the plot layout, owned trucks and trailers, gloves, money, the collection, and needle counts per bin.
- Cyrus's preset dev save stays a test fixture. It is not something players get.

### 10. Build notes for the team
- Settle on one sorter module. `Machines.luau` and `Separators.luau` both sort hay at the moment.
- Ship with streaming on, using Atomic models for bales, before the full map lands.
- Region tiers, needles per bale, and glove tiers should live in one config file, so tuning stays in one place.

**Improved plan, expected grade: B+ (8.2/10).** This is design judgement, not playtest data. The biggest remaining risk is still evidence: none of these numbers have been tested yet.
