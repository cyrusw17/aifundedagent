# Lumber / Needlewood art style: Rustic LT2

Cyrus picked this style on 2026-10-13 ("i actually like the rustic style the most, lets
implement that across all builds"). Everything in the game follows it: props, tools, hay,
buildings, the world and mockups.

The style lives in code, so code is the source of truth and this file describes it:
- `blender/lib/style.py` has the palette, textures and the `style.rustic()` finish. Every prop goes through it.
- `blender/props/rustic_props.py` has all the props built in the style (catalog: `blender/exports/rustic/catalog.png`).
- `blender/mockups/` has the map, tools and hay type sheets, built from those same props.
- Game colors (Roblox `Color3`) are in `World.luau`, `Bales.luau`, `Hay.luau` and `Avatar.luau`.

## The style in one line

**Lumber Tycoon 2 shapes with a weathered, rustic finish.** Simple blocks and cylinders,
small bevels, muted straw, bark and plank textures, weathered grey iron, dull twine, slightly uneven surfaces.

## Shapes (LT2)

- Build from blocks and cylinders only, the way LT2 builds from Roblox parts.
- Small bevels (about 1.2 cm, which is 0.04 studs) so edges catch light, no rounded or soft shapes.
- Cylinders use few sides: about 10 for logs and handles, 12 to 18 for bales and wheels, 5 to 6 for thin poles and tines.
- Surfaces are a little uneven (up to about 1.2 cm of random push), so nothing looks factory new.
- Real proportions, not cartoon ones: a shovel is a small spade, not an oversized toy.

## Hay

- Hay comes as **stackable square bales** tied with two twine bands, not barrels.
- A bale is **4.6 long x 2.6 high x 3.2 deep studs** (the game's size in `Bales.luau`), with flat tops
  and bottoms so bales stack.
- There is also a round bale (3.6 x 3.4 x 3.6 studs) with rolled ends.
- Loose hay pieces are 0.9 to 1.5 x 0.3 x 0.3 stud sticks in the hay colors.
- One hay per map (see `blender/mockups/hay_types.py`), keyed to `src/shared/Config/Needles.luau`.
  Every map uses the same bale and only swaps the hay colors, the twine on rarer maps, and a small extra.
  The map hays are a proposal; only Meadow hay is in the game.

## Tools

- The only held tools are the shovel and the rake. Upgrades are five glove tiers, made in leather (see palette).

## Palette

Each texture uses three shades (light, mid, dark). sRGB hex from `RUSTIC` in `lib/style.py`:

| Kind | Light | Mid | Dark | Used for |
|---|---|---|---|---|
| hay | #DBCC99 | #BDA870 | #857347 | bales, loose hay, crate fill |
| bark | #615445 | #4C4033 | #29211A | logs, tree trunks, wheels |
| wood (end grain) | #CCB28C | #B29973 | #856E52 | cut log ends |
| handle (planks) | #998061 | #80694C | #5C4A36 | tool handles, planks, buildings |
| metal (grey iron) | #949491 | #7A7A78 | #666159 (wear) | blades, tines; light wear spots, no orange rust |
| twine | #736652 | #615442 | #473D2E | bale bands |
| leather | #8F6645 | #755236 | #523826 | glove tiers |

Game-side colors (Roblox `Color3.fromRGB`) that match:

| Thing | RGB |
|---|---|
| Ground grass | 112, 128, 82 |
| Spawn, bale hay | 189, 168, 112 |
| Twine | 97, 84, 66 |
| Loose hay pieces | 219, 204, 153 / 189, 168, 112 / 168, 149, 95 / 133, 115, 71 |
| Shop floor, tool handles | 128, 105, 77 |
| Plank walls | 153, 128, 97 |
| Roof | 102, 66, 42 |
| Counter, drop-off pad | 92, 74, 54 |
| Sell pad | 219, 204, 153 |
| Tool metal | 148, 148, 145 / 122, 122, 120 |

New colors should be muted and warm: pull bright colors about 25 to 30% toward warm grey
(`mock.rustic_palette()` does this). Glow is the only exception and is kept for rare items.

## Regions

Each region keeps the Rustic house look and swaps a few palettes, plus **one accent color** used on signs, trim,
painted doors and UI highlights in that region, so regions read differently at a glance. Source of truth:
`blender/mockups/regions.py` (sheet: `/mnt/project-files/mockups/region_style_sheet.png`).
Each cell is light / mid / dark hex; the game-side RGB is the mid shade. A dash means the house palette.

| Region | Ground | Hay | Bark | Leaves | Accent | Sky / fog | Props |
|---|---|---|---|---|---|---|---|
| Meadow | #808F61 #708052 #5C6B42 (112, 128, 82) | – | – | #5C7547 #4C663B #3B4F2E (76, 102, 59) | barn red: #9E4C3D #853D30 #5C2E24 (133, 61, 48) | #BDC7C2 | oak |
| Pine Forest | #667552 #546342 #61523D (84, 99, 66) | #C2BD8A #9E9C66 #6B6B42 (158, 156, 102) | #574536 #423326 #241C14 (66, 51, 38) | #3D5C47 #304C3B #213629 (48, 76, 59) | pine teal: #4C7A70 #3D665E #294742 (61, 102, 94) | #9EB0AD | pine |
| Desert Dunes | #D1BA8F #C2A87D #9E8561 (194, 168, 125) | #E6D9AD #D1BA85 #9E8759 (209, 186, 133) | #948775 #7A6E5E #52473D (122, 110, 94) | #80946B #6B8059 #4C5E42 (107, 128, 89) | terracotta: #BD704C #A86140 #75422E (168, 97, 64) | #E0D1B8 | cactus |
| Snow Peak | #EBEDF0 #D6DBE0 #8F8F8F (214, 219, 224) | #E0DBC2 #BFB894 #8A8269 (191, 184, 148) | #5C524A #474038 #26211F (71, 64, 56) | #425C54 #364C47 #243633 (54, 76, 71) | ice blue: #8AADC7 #7096B2 #4C6B85 (112, 150, 178) | #D1DBE6 | snowpine |
| Swamp | #666B4A #54593D #3D402E (84, 89, 61) | #A8A36E #85804F #575233 (133, 128, 79) | #4C473D #3B362E #1F1C1A (59, 54, 46) | #5C7042 #4A5C36 #334026 (74, 92, 54) | firefly green: #B2C25C #99AD47 #6B7A33 (153, 173, 71) | #99A38F | deadtree |

- Props per region: Meadow blocky oaks; Pine Forest stacked-cone pines; Desert block cacti, bleached rocks, low dunes;
  Snow Peak the same pines with white caps on each tier, stone patches; Swamp leaning dead trees, reeds, dark water and firefly glows.
- Hay keeps one shape everywhere; only its colors change. These hays match the hay types sheet.
- Use the accent sparingly: one sign, trim or highlight per building, never a whole wall.
- Sky / fog is the `Atmosphere` and fog tint for that region in game.

## Needle rarity glow

One shared look per rarity tier, so value reads at a glance. Glow is the only place colors get bright.
Source of truth: `blender/mockups/rarity.py` (sheet: `/mnt/project-files/mockups/needle_rarity.png`).

| Tier | Needles | Material | PointLight range / brightness | Pulse | Extras |
|---|---|---|---|---|---|
| Common | Steel (150, 158, 166), Pine (96, 140, 84), Sand (214, 186, 120) | Metal | none | steady | none |
| Uncommon | Ice (170, 220, 240), Bog (110, 128, 70) | Metal | 3 / 0.5 | steady | soft light only, no Neon |
| Rare | Obsidian (96, 64, 112), Geode (170, 110, 220) | Neon | 5 / 1 | steady | steady glow |
| Epic | Cloud (240, 244, 255), Phantom (120, 230, 210) | Neon | 7 / 1.5 | 2 s | slow pulse (brightness 1.0 to 1.8) |
| Legendary | Cosmic (80, 70, 220) | Neon | 9 / 2.2 | 1.5 s | pulse + star motes (ParticleEmitter, 4/s) |
| Mythic (mutated) | any type, gold (255, 210, 60) | Neon | 8 / 2 | 1 s | gold, 1.6x size, Sparkles, server banner |

- Changes from `Needle.luau` LOOKS today: Ice moves from Neon to Metal with a soft light (uncommon), Bog gains a soft light,
  and Obsidian lifts to (96, 64, 112) so its glow shows. The other colors are unchanged.
- The light color is the needle color. Pulse tweens PointLight brightness between the value above and about 1.6x it.
- Bundles, display walls and bins use the same tier look as the needles inside them.

## New model designs (backlog Blender item 2 and 4)

Block-out mockups for the Blender asset pipeline: `mockups/buildings_sheet.png`, `mockups/items_sheet.png` and
`mockups/truck_skins.png` (scripts in `blender/mockups/`). Triangle budgets, rigs and tags are in the art director's
`art-review/MODEL_SPECS.md`; these sheets show the look. Where the spec and the game code disagree, the sheets follow
the game code, as below.

| Model | Size used (studs) | Design notes |
|---|---|---|
| homestead_bank | 26 x 20 x 22 | Dressed stone ground floor, plank upper floor, cream cornice and 4 columns, green roof. Vault door shows through the left teller window. Barn-red "BANK" board is the one accent |
| trading_post | 24 x 18 x 16 | Log walls, open front with a counter and a hanging scale, shelves of goods, plank awning on two posts, crates and barrels out front. Barn-red sign |
| field_bale_chute | 12 x 16 x 14 | Plank hopper on four log legs with a gate at the throat (`Gate`) and `HayFill`. **Clear width 12.5, not 11**: the pickup is 10.9 wide. Clear height 10. Lever on the driver's-side front leg with a red grip (`Lever`) |
| bounty_board | 8 x 1.5 x 9 | Plank board on two log posts, little shingle roof, red header plank, three pinned paper notices (`Notice1-3`) |
| wheelbarrow_loaded | tray 5 x 3.6 | Game tray size (Wheelbarrow.luau), plank tray with an iron rim, one front wheel (`Wheel_L1`), leather grips. Holds 3 bales stacked, loose |
| needle_display_wall | 6 x 1 x 7.6 | **One plot tile, as Display.luau builds it** (spec said 12 x 8): plank board between log posts, grey iron cap with a red name board, 6 pegs in 2 rows of 3 on velvet backs, brass plaques |
| needle_bundle | 1.3 x 0.55 x 0.55 | **Game size** (Needle.luau BUNDLE_SIZE; spec said 3 long): 10 grey needles in rows of 4-3-3, eyes all at one end, two twine bands |
| old_boot, horseshoe, rusty_key, old_radio, lost_ring, fossil | Config/Finds.luau sizes | Leather boot with a flopped shaft; grey iron shoe with nail holes; dark iron key (no rust colour); plank radio with a cloth grille and cream dial; gold ring with a blue stone (the only shiny find); stone slab with a raised cream spiral. `rusty_key` is not in MODEL_SPECS yet |
| Robux skins | same as the cash truck | Same mesh, paint and trim only, no glow: Homestead Classic (rusty_pickup, barn red with a cream belt line), Timber Wolf 4x4 (rusty_pickup, forest green, roof light bar), Midnight Express (box_truck, navy, pale-gold stripe), Prairie Schooner (farm_flatbed, weathered wood, canvas `Cover`), Founders' Semi (semi_rig, deep green, gold pinstripes and door crest) |

## Materials

- Blender: generated straw, bark, end grain, plank and metal textures from `lib/style.py`, matte
  (roughness about 0.9). Metal is half metallic grey iron with light wear spots, no rust. Twine is a flat color.
- Roblox: Fabric for bales and twine, WoodPlanks for planks and buildings, Wood for handles and logs,
  Metal for tools, Grass for ground. Neon only on rare-map extras.
- Glow means rarity. Common hay never glows; the top maps get embers, wisps or stars.

## Scale and budget

- Props are modeled in meters, with 1 stud = 0.28 m (scale by about 3.57 on import if needed).
  Mockups work in studs and scale the props up.
- Reference sizes: player about 5 studs, bale 4.6 x 2.6 x 3.2, small shovel about 2.7, rake and pitchfork about 5,
  wheelbarrow about 5 x 2.5 x 2.5, log 5 long.
- Keep props light: a few thousand triangles at most, much less for anything spawned many times.

## Renders and mockups

- Cycles CPU, one sun and a soft grey sky, Standard view transform, grass ground.
- Maps are top-down orthographic; prop sheets are front views on plain stone plinths or tiles.
- Labels: dark ink text, titles in capitals, one or two short lines under them.

## UI and text

- Gotham Bold in game (Blender's default font in renders). White text with a dark stroke over the world.
- Short signs in capitals ("SELL HERE", "BALE DROP-OFF"); hints in sentence case.

## Not matching yet

- Nothing known.
