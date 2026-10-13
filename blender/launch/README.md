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
