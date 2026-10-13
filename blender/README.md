# Blender asset pipeline

Game props are built from Python (`bpy`) scripts, so every model is
reproducible and tweakable by editing numbers instead of hand-modeling.

## House style: LT2 shapes, Rustic finish

Every prop uses Lumber Tycoon 2 style shapes (blocks and cylinders, small
bevels) with the **Rustic** finish: muted, weathered straw / bark / plank
textures, clean weathered grey metal with light wear, dull twine, and slightly uneven surfaces. It lives in
`lib/style.py`; build new props with `style.rustic()` so they match.

```
blender/
  lib/common.py            scene reset, materials, textures, join, export, preview render
  lib/style.py             the house style (palettes, textures, Finish) and shape helpers
  props/rustic_props.py    hay and starter tools; also runs every category and renders catalogs
  props/tools.py           shop hand tools
  props/vehicles.py        carriers, trucks, boats, trailers (beds sized for loose bales)
  props/storage.py         bins, silos, bale rack, needle tray and vault, fence, road tile
  props/buildings.py       mill, sheds, barn, garage, shops, forge, museum, observatory, dock...
  props/machines.py        conveyor pieces (6x6-stud tiles, belt top 3.5) and every machine
  props/hay_bale.py        bale shape, 4.6 long x 2.6 high x 3.2 deep studs (the game's bale)
  styles/lt2_mockups.py    the six finishes that were compared when picking the style
  tools/render_preview.py  renders a PNG preview of any exported .glb
  exports/rustic/          one .glb per prop, plus catalog_<category>.png
  exports/styles/          the style comparison renders
```

## Props

One `.glb` per item in `exports/rustic/`, named by its snake_case key (for
example `rusty_pickup.glb`). Catalogs:

| category | catalog | items |
|---|---|---|
| hay and starter tools | `catalog_hay_and_tools.png` | hay bale, round bale, basic shovel, wide scoop, garden rake, pitchfork, hay hook, wheelbarrow, hay crate, log |
| shop tools | `catalog_tools.png` | steel fork, needle tweezers, silver sieve net, magnet wand, barrel auger, hay vacuum hose |
| vehicles | `catalog_vehicles.png` | handcart, pull wagon, 6 trucks, rowboat, sailboat, cargo barge, 6 trailers |
| storage | `catalog_storage.png` | 3 mill bins, 3 silos, bale rack, needle tray, needle vault, fence post set, road tile |
| buildings | `catalog_buildings.png` | mill, sorter shed, barn, garage, sell depot, needle forge, workshop, museum, observatory, greenhouse, harbor dock, warehouse |
| machines | `catalog_machines.png` | conveyor straight/corner/ramp, splitter, merger, hopper feeder, 6 sorter tiers, needle type splitter, bundler, polisher, hay baler, hay press, alloy mixer, boost oil, alien collector |

### Truck and trailer beds

Hay rides loose in the beds with real physics, so no bales are part of any
vehicle model. Every bed floor top is 3.5 studs above the ground (the
conveyor dock height). Floors, sidewalls and tailgates are plain unbeveled
boxes so their collision is clean. Interiors are sized in whole bales lying
lengthwise: length n x 4.6 + 0.8, width 7 for two across or 10.2 for three
across. Every truck bed is three across (10.8 outside); trailers keep 7 except the large one.
`vehicles.BEDS` lists each bed's interior size and capacity.

| vehicle | bed inside (L x W x wall) | bales |
|---|---|---|
| rusty pickup | 14.6 x 10.2 x 3.2 | 9 |
| farm flatbed | 14.6 x 10.2 x 2.8 | 9 |
| box truck | 19.2 x 10.2 x 6.4 (roofed) | 24 |
| heavy hauler | 23.8 x 10.2 x 5.4 | 30 |
| wagon trailer | 5.4 x 7.0 x 2.6 | 2 |
| small trailer | 10.0 x 7.0 x 2.6 | 4 |
| medium trailer | 24.0 x 7.0 x 2.6 | 10 |
| large trailer | 28.4 x 10.2 x 5.4 | 36 |
| double trailer | 2 x (14.6 x 7.0 x 2.8) | 12 |
| bale rack trailer | 23.8 x 7.0 x 8.0 | 30 |

## Build

With Blender installed (4.2+ / 5.x):

```sh
blender --background --python blender/props/rustic_props.py -- --out blender/exports/rustic
# just some:  ... -- --out blender/exports/rustic --only basic_shovel,log
```

Without Blender, the `bpy` pip module works the same way (needs Python 3.13
for bpy 5.x):

```sh
python3.13 -m venv .bpyenv
.bpyenv/bin/pip install bpy==5.2.2
.bpyenv/bin/python blender/props/rustic_props.py --out blender/exports/rustic
```

Harmless log noise: "Draco is not available" / "MeshOptimizer is not
available" come from the pip `bpy` build and don't affect the export.

Preview any export:

```sh
blender --background --python blender/tools/render_preview.py -- blender/exports/rustic/log.glb log.png
```

## Import into Roblox

1. Studio → **Home → Import 3D**, pick a `.glb` from `exports/rustic/`.
2. Keep **Import as a model**. Textures are embedded in the .glb and come in
   with the mesh.
3. Scale: props are modeled in meters. If the importer doesn't convert, 1 stud
   = 0.28 m, so scale by ~3.57 (a hay bale should be 4.6 long x 2.6 high x 3.2 deep).

## Adding a new prop

Add a builder to the category module it belongs in (`props/<category>.py`)
and list it in that module's `PROPS`. A builder makes parts with `cyl()` /
`box()`, passes each through `f.shape(part)` (bevel and weathering) and
`f.apply(part, kind, along=...)`. Kinds: hay, bark, wood (end grain), handle
(planks), metal (weathered grey iron, light wear), steel (unrusted), twine, paint_red,
paint_green, paint_blue, paint_cream, paint_yellow, stone, cloth, dirt, tire,
glass, glow (alien and mythic items only). Size things in studs
(`STUD = 0.28`) and keep each prop under about 8,000 triangles.

## Mockups

`mockups/` renders preview sheets from the props above, in studs (see `docs/STYLE.md`):

```
mockups/mock.py       shared helpers: props scaled to studs, bale stacks, labels, camera
mockups/map.py        top-down base camp map from src/server/Services/World.luau
mockups/tools.py      bare hands, shovel and rake (in game) plus the other modeled tools
mockups/hay_types.py  one hay per map as bale stacks, matching src/shared/Config/Needles.luau
mockups/renders/      the rendered PNGs
```

```sh
.bpyenv/bin/python blender/mockups/map.py blender/mockups/renders
```
