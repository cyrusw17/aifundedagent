# Mockups

Preview sheets built from the house-style props in `blender/props/rustic_props.py`,
in studs. The style itself is described in `docs/STYLE.md`.

```
mock.py       shared helpers: props scaled to studs, bale stacks, labels, camera
map.py        top-down base camp map from src/server/Services/World.luau
tools.py      bare hands, shovel and rake (in game) plus the other modeled tools
hay_types.py  one hay per map as bale stacks, matching src/shared/Config/Needles.luau
renders/      the rendered PNGs
```

Run with Blender or the `bpy` pip module (see `blender/README.md`):

```sh
.bpyenv/bin/python blender/mockups/map.py blender/mockups/renders
```
