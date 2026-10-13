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
