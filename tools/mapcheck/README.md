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

## Reachability (reach.luau)

Runs after check.luau on the map it built. It walks the road graph from Meadow (roads, flat zones, the highway,
ferries between their port flats, the zeppelin to Sky Island) and warns on: a road not reachable from spawn; a lane
narrower than a Rusty Pickup with a Medium Trailer plus 2 studs (roads, highway, ferry lanes); a road steeper than
MaxGrade + 0.06; a region with no hay field; a hay field underwater, inside the ground, more than 70 studs from a
reachable road, or behind water or a slope over 0.45 on the way in; a landmark underwater or more than a 260-stud walk
from a road; a secret underwater or inside the rock.

`budget.luau` (#21) prints every container's parts against its slice of `Config/WorldMap.PartBudget` (the map's
12,000 of Health's 40,000) and checks streaming: regions are plain Models, Atomic models stay under 400 parts, and
only the listed models are Persistent. It ends with the same table as markdown for /mnt/project-files/map/PART_BUDGET.md.

`safety.luau` (#22) checks that every spawn, ferry and zeppelin landing, tow spot and hay wagon stop has ground and
headroom, that the kill floor (FallSafety.KILL_Y) is below all ground, and that a fall anywhere lands on a dry road.

