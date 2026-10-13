# mapcheck: the world map build, headless

Runs `WorldMap.build` (terrain shape, every region, the highway, ferries, zeppelin) outside Roblox in a few
seconds, then reports part counts, any solid part standing in a road lane, and any road that starts disconnected.

    python3 tools/mapcheck/run.py path/to/luau      # from the repo root; exit code 1 on a crash, WARN or blocked lane

**Runtime:** the plain Luau CLI, not Lune and not Roblox. Get it from the Luau releases, for example on Linux
`curl -L -o luau.zip https://github.com/luau-lang/luau/releases/download/0.700/luau-ubuntu.zip && unzip luau.zip`
(macOS: `luau-macos.zip`). Only the `luau` binary is needed.

**Files**
- `mock.luau`: a small stand-in for the Roblox API: Vector2/3, CFrame (new, Angles, lookAt, fromMatrix, *, Inverse),
  Color3, Instance (properties, Parent, children, attributes, GetDescendants, PivotTo...), services
  (CollectionService, Players, RunService, ...), `task` (spawned threads do not run), `Random`. Missing services
  modules become do-nothing stubs and print `STUB name`.
- `stubs.luau`: fakes for the services the map only calls into (Props, Bales, Data, Vehicles, WorldTerrain, Bank,
  WorldLabel).
- `check.luau`: the checks. `run.py` bundles every module in its `MODULES` table with these and runs `luau`.

To run another service headless, add it (and the configs it needs) to `MODULES` in `run.py`, add stubs for what it
calls, and call its build/start from a check file. Gaps in the mock show up as Luau errors naming the missing member.
