# Blender asset pipeline

Game props are built from Python (`bpy`) scripts, so every model is
reproducible and tweakable by editing numbers instead of hand-modeling.

```
blender/
  lib/common.py            shared helpers: scene reset, materials, join, export
  props/hay_barrel.py      hay barrel (stylized low-poly; separate barrel and hay meshes)
  styles/mockups.py        the same props in three candidate art styles (A/B/C)
  tools/render_preview.py  renders a PNG preview of an exported .glb
  exports/                 generated .glb / .obj / .png (committed for easy import)
```

## Build a prop

With Blender installed (4.2+ / 5.x):

```sh
blender --background --python blender/props/hay_barrel.py -- --out blender/exports
```

Without Blender, the `bpy` pip module works the same way (needs Python 3.13
for bpy 5.x):

```sh
python3.13 -m venv .bpyenv
.bpyenv/bin/pip install bpy==5.2.2
.bpyenv/bin/python blender/props/hay_barrel.py --out blender/exports
```

Options (after `--` when running through `blender`):

| flag        | default            | meaning                                  |
|-------------|--------------------|------------------------------------------|
| `--out`     | `blender/exports`  | output folder                            |
| `--name`    | prop name          | base file name                           |
| `--formats` | `glb,obj`          | any of `glb`, `obj`, `fbx`, `blend`      |

Harmless log noise: "Draco is not available" / "MeshOptimizer is not
available" come from the pip `bpy` build and don't affect the export.

Preview a result:

```sh
blender --background --python blender/tools/render_preview.py -- blender/exports/hay_barrel.glb blender/exports/hay_barrel.png
```

## Import into Roblox

1. Studio → **Home → Import 3D** (or Avatar → Import 3D), pick `exports/hay_barrel.glb`
   (`.obj` and `.fbx` also work).
2. Keep **Import as a model**. The barrel and hay come in as two MeshParts:
   - `HayBarrel_Barrel` — the container; give it physics / collision.
   - `HayBarrel_Hay` — the fill; hide or scale it down as hay is removed.
3. Scale: props are modeled in meters. If the importer doesn't convert, 1 stud
   = 0.28 m, so scale by ~3.57 (the hay barrel should be ~4 studs tall).
4. Colors are painted as vertex colors (no textures needed), which the importer keeps. Optionally set
   `MeshPart.Material` (e.g. WoodPlanks, Metal, Grass) in Studio as needed.

## Adding a new prop

Copy `props/hay_barrel.py`, keep the `common.parse_args / reset_scene /
export` calls, and replace the build functions. Keep each mesh under Roblox's
per-mesh triangle limit (the hay barrel is ~6.3k triangles total).
