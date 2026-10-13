# Lumber / Needlewood art style

> **DRAFT, not chosen yet.** This is one candidate style ("stylized low-poly farm", from the hay barrel).
> Cyrus is picking the final style from mockups; this file gets rewritten for whichever he picks.

One style for everything in the game: props, tools, hay, world parts, UI and mockups.
The reference model is the hay barrel in `blender/props/hay_barrel.py`
(preview: `/mnt/project-files/blender/hay_barrel.png`). The mockup scripts in
`blender/mockups/` follow this file, with shared colors and builders in `mockups/mock.py`.

## The style in one line

**Stylized low-poly farm.** Flat-shaded facets, no textures, color painted per vertex,
darker at the roots and edges and lighter at the tips. Glow only on rare items.

## Shapes

- Hard, faceted, flat-shaded surfaces. No smooth shading, no bevels, no texture detail.
- Straw and hay: layered clumps of thin spikes (3 to 4 sided) pointing out and up
  from a darker core. Never smooth blobs. Loose straws stick out past the outline.
- Wood: separate planks or staves with small gaps, each plank a slightly different tone.
- Metal: chunky bands and plates, thicker than real life, so they read from far away.
- Chunky proportions: handles about 0.4 studs thick, nothing thinner than 0.1 studs.
- Characters and hands use Roblox R6 blocks (arm 1 x 2 x 1 studs).
- Cylinders: 14 to 16 sides for barrels and tubs, 24 for pads, 3 to 6 for straws and needles.

## Color (per-vertex, in the .glb)

Each mesh carries its color as a vertex color attribute, not as textures.
Roots, undersides and edges get the darkest shade, tips and top faces the lightest.

| Role | Hex | Notes |
|---|---|---|
| Hay mids | #F5D66B #EBC457 #FCE385 #E0B84F | mix across clumps |
| Hay root / core | #C79E45 | base of every straw and the core |
| Hay tip | #FFF2B3 | ends of the straws |
| Wood planks | #8C572E #996133 #804D29 | vary per plank |
| Wood inside / shadow | #4D2E1A | inside of barrels, gaps |
| Iron | #3D3D45 | bands, hoops, dark metal |
| Steel | #969EA6 | shovel blade, rake teeth (Roblox 150, 158, 166) |
| Grass | #6AA65A, patches #58914A | ground |
| Dirt path | #C4AA76 | paths |
| Spawn / shop floor | #C8B478 / #C8B48C | |
| Wall cream | #F4EFE0 | building walls |
| Barn red | #C0392B | roofs |
| Sell orange | #F0AD2E | sell pad, money UI |
| Ink | #28221C | text on light backgrounds |
| UI blue | #3C6EC8 | arrows, hints; player shirt #3476C4 |

### Hay types

One hay per map, matching `src/shared/Config/Needles.luau` (see `blender/mockups/hay_types.py`).
Every type keeps the same spiky clump shape and only swaps its 3 mid shades;
the root is 78% of the first mid and the tip is the last mid blended 45% toward white
(`mock.palette()`). Meadow uses the exact barrel colors above.

| Map | Mids | Extra |
|---|---|---|
| Meadow | barrel hay | none |
| Pine Forest | #C4BA5C #AAA04E #788C46 | pine cones |
| Desert | #ECD6A0 #DEC488 #F6E6BA | none |
| Snow Peak | #E2D6A8 #D2C8A0 #F5F8FC | snow cap |
| Swamp | #808040 #686C38 #5C5030 | moss clumps |
| Volcano | #463830 #342C28 #60402C | glowing embers |
| Cave | #96928C #7C7A78 #AAA092 | purple crystals |
| Sky Island | #ECF0FA #D6E0F4 #F6ECD2 | cloud puffs |
| Haunted Grove | #78688C #605474 #8C8096 | green wisps |
| Star Hay | #30286E #46328C #1E1C50 | star sparkles |

## Materials

- Blender: one matte Principled BSDF driven by the vertex color (roughness about 0.9).
  Metallic only on steel and iron.
- Roblox: SmoothPlastic by default, Wood / WoodPlanks for wood, Metal for steel and iron,
  Grass for ground, Slate for roofs. Neon only for pads and glowing rare items.
- Glow (emission) signals rarity. Common hay never glows; mid maps get a little (ice, geode),
  the top maps get the most (embers, wisps, stars).

## Scale and budget

- Model in studs (1 Blender unit = 1 stud) for new props. The barrel was built in meters
  (1 stud = 0.28 m); either is fine as long as the import scale is noted.
- Reference sizes: player about 5 studs tall, hay barrel about 4 studs, tools 6 to 8 studs,
  loose hay piece 0.9 to 1.5 x 0.3 x 0.3 studs.
- About 6,000 triangles per hero prop (the barrel), under 1,000 for anything spawned
  many times (hay pieces, needles). Separate meshes for parts the game treats separately.

## Renders and mockups

- Cycles CPU, one sun plus a soft light sky, Standard view transform.
- Maps are top-down orthographic; prop sheets are three-quarter views on cream plinths or tiles.
- Labels: dark ink text, titles in capitals, one or two short lines underneath.

## UI and text

- Gotham Bold in game (Blender's default font in renders). White text with a dark stroke over
  the world, ink text on light panels.
- Short signs in capitals ("SELL HERE", "BARREL DROP-OFF"); hints in sentence case.

## Not yet matching

- Loose hay pieces in `src/server/Services/Hay.luau` use older golds (232, 201, 90 and similar);
  they should move to the hay mids above when that file is next edited.
