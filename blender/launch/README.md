# Launch art

Roblox store art for Needlewood, rendered from the same Rustic .glb props the game uses
(`blender/exports/rustic/`), in the house style (`/mnt/project-files/style/STYLE.md`).

| File (renders/final/) | Size | Where it goes on Roblox |
|---|---|---|
| `thumbnail_1_haul.png` | 1920x1080 | Experience thumbnails (first one is the cover) |
| `thumbnail_2_factory.png` | 1920x1080 | Experience thumbnails |
| `thumbnail_3_field.png` | 1920x1080 | Experience thumbnails |
| `thumbnail_4_needles.png` | 1920x1080 | Experience thumbnails |
| `thumbnail_*_clean.png` | 1920x1080 | The same shots without titles |
| `icon_512.png` | 512x512 | Experience icon |
| `loading_screen.png` | 1920x1080 | Upload as an Image, paste its id into `IMAGE_ID` in `src/first/Loading.client.luau` |

## Re-rendering

Needs the `bpy` pip module (Python 3.13, `pip install bpy==5.2.2 pillow`).

```
python blender/launch/shots.py -- --preview            # fast 40% previews of every shot
python blender/launch/shots.py -- --only haul,icon     # full size, 96 samples by default
python blender/launch/finish.py                        # titles, icon resize, final files
```

- `scene.py`: the kit (ground, sky, sun, roads, LT2 trees, fences, straw, needles, blocky farmers,
  the prop loader). Units are studs.
- `shots.py`: one function per shot. Truck beds are filled with loose standard 4.6 x 2.6 x 3.2 bales
  on the 3.5 floor, same as the game.
- `finish.py`: titles in white with a dark ink stroke (STYLE.md UI text), warm vignette.

## Second batch (shots2.py, finish2.py)

| File (renders/final/) | Use |
|---|---|
| `thumbnail_5_burst` .. `thumbnail_8_worldmap`, `thumbnail_9_regions` | More store thumbnails: bale burst, ferry and zeppelin, rich field, the isles diorama, 8-region collage |
| `events/event_winter`, `event_harvest`, `event_halloween` | Swap in as the cover thumbnail during seasonal events |
| `icon_A_bale`, `icon_B_truck`, `icon_C_farmer` | Three 512 icons for Roblox's free icon A/B test |
| `store/truck_*.png` | Robux truck skins from GAME_PLAN_V8 Part C 10 (Homestead Classic, Timber Wolf 4x4, Midnight Express, Prairie Schooner, Founders' Semi) |
| `store/pass_*.png` | Gamepasses (VIP, Auto-Dock, Big Silo, Paint Studio, Plot Themes, Truck Radio), server boosts (Hay Fever, Meteor Shower) and the Harvest Pass |

```
python blender/launch/shots2.py -- --preview --only "store_*"
python blender/launch/finish2.py
```

Note: these scenes assume the vehicle .glbs as exported on 2026-10-13 (front toward Blender -Y). If the Blender
thread's rig re-export flips vehicles to face the other way, turn them 180 degrees in `shots.rig` and the store shots.

## Character batch (main set)

`avatar.py` is an R15-style avatar: fifteen rounded parts on a joint tree (waist, neck, shoulders, elbows,
wrists, hips, knees, ankles), five outfits and three faces. `R15("farmer", "grin").pose(r_shoulder=(-160, 30, 0))
.place(loc, yaw)`; `hold(obj, "r")` puts a prop in a hand. Pose angles are degrees: x swings a limb forward (-)
or back (+), y splays it sideways (raised arms: left -, right +).

    python blender/launch/shots4.py -- --samples 64            # 7 hero shots, 1920x1080
    python blender/launch/shots4.py -- --res 1024x1024 --only icon_hero,icon_hero_golden
    python blender/launch/finish4.py /mnt/project-files/launch-art

Run each shot in its own process when a full run stops early. `finish4.py` also copies the clean haul shot to
`loading_screen.png`. `shots3.py` (scenery-only golden, Spindle and Hay Wagon) is kept for reference.
