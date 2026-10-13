# Headless server boot

Boots the whole Needlewood server outside Roblox, in the plain [luau CLI](https://github.com/luau-lang/luau), so
runtime crashes (indexing nil, calling an API that doesn't exist, wrong property types, errors in module top-level
code or in `start()`/`build()`/handlers) show up before anyone presses Play in Studio.

```
python3 tools/headless/run.py path/to/luau           # the boot scenario; exit code 1 on any error
python3 tools/headless/run.py path/to/luau --mock-test   # checks the mock itself against known Roblox behaviour
```

Options: `--play SECONDS` (default 60), `--settle SECONDS` (default 10), `--no-poke`, `--deferred` (Deferred signal
behavior: handlers run at the end of the frame instead of inside `Fire`), `--selftests` (sets
`Workspace.RunSelfTests`; the physics checks in src/server/SelfTests can't pass headless), `--keep` (keeps the
bundle), `--bundle-only` (writes `.headless_bundle.luau` for `luau --profile`), `--timeout SECONDS` (default 600).
A full run takes about a minute.

## What it does

1. **Bundles** `mock.luau`, `mock_instances.luau`, `mock_services.luau` (a Roblox API stand-in) and every source file
   under `src/`, mounted where `default.project.json` puts it (`src/shared` -> `ReplicatedStorage.Shared`,
   `src/server` -> `ServerScriptService.Server`, `src/client` -> `StarterPlayer.StarterPlayerScripts.Client`,
   `src/first` -> `ReplicatedFirst.Loading`). Each file becomes a real ModuleScript / Script / LocalScript instance
   in a fake DataModel, so `script.Parent.Data`, `ReplicatedStorage:WaitForChild("Shared")` and friends resolve the
   way they do in Roblox. A module is compiled with `loadstring(source, "@src/...")`, so **every error and
   traceback names the real file and line**. Errors inside the mock are mapped to `tools/headless/mock*.luau:line`.
2. **Runs `scenario.luau`:**
   - runs `src/server/Main.server.luau` as a Script (Data.start, Bank.start, ... World.build, SelfTest.start);
   - advances 10 s of simulated time;
   - a player joins (UserId 1001, "HeadlessTester"): `Players.PlayerAdded` fires, an R15 character spawns at the
     SpawnLocation, then the client's slot picker is replayed: `ReplicatedStorage.SaveSlots.List` and
     `SaveSlots.Choose(1, firstFreePlot)` are invoked on the server like `src/client/Saves.client.luau` does, so
     `Data.loaded` fires and the player gets state, tools and a farm;
   - advances 60 s (autosave and every `while true do task.wait() end` loop runs);
   - **poke**: equips and swings every tool, then walks up to every enabled ProximityPrompt and ClickDetector in the
     Workspace and uses it (the character is moved next to it first, so the server's distance checks pass);
   - `PlayerRemoving` (Data.release saves), then every `game:BindToClose` callback;
   - requires every server/shared module nothing reached, so top-level errors still show.
3. **Prints a summary:** modules loaded, BaseParts in the Workspace, instances created by class, DataStore keys,
   threads still waiting (on WaitForChild, a signal or a require), warnings and every error with its file:line.

Exit code 1 if any error was reported, the luau process crashed, or the run hung past `--timeout`.

## The mock: rules

The point is to find real bugs, so the mock follows the Roblox docs, **including the errors Roblox throws**:

- Unknown members error like Roblox (`Foo is not a valid member of Part "Workspace.X"`) and say
  `MOCK MISSING: Part.Foo` so you can tell a gap in the mock from a typo in the game.
- Property writes are type checked (`Unable to assign property Size. Vector3 expected, got number`); enum
  properties take the EnumItem, its name or its number; read-only properties refuse writes; a destroyed instance's
  Parent is locked; circular parenting errors; methods called with `.` instead of `:` error.
- Datatypes (Vector3, CFrame, Color3, UDim2, NumberSequence...) are immutable, compare by value, can't be
  iterated, and do correct math (CFrame Angles/fromAxisAngle/lookAt/Lerp/ToObjectSpace/ToOrientation...).
- `SetNetworkOwner` errors outside the Workspace and on anchored assemblies (welds are followed); `FireClient`
  needs a Player; attributes only accept attribute types and valid names; `TweenService:Create` checks property
  names and types; `CollectionService:GetTagged` only returns instances inside the DataModel.
- DataStores live in memory (`H.dataStores`) with Roblox's rules: keys 1-50 chars, values must serialise to JSON (no
  Instances/Vector3s, no mixed or sparse tables, 4 MB), reads return copies, `UpdateAsync` passes `(old, keyInfo)`,
  writes the returned value, cancels on `nil`, and refuses a transform that yields. OrderedDataStores store integers
  and page with `GetSortedAsync`. `H.dataStoreFail = function(method, store, key) return "msg" end` simulates outages.
- `task.spawn/defer/delay/wait`, `wait/spawn/delay`, `Signal:Wait` and `WaitForChild` run on a scheduler with
  simulated time; `os.clock`, `os.time`, `tick`, `time` follow it. `WaitForChild` without a timeout keeps waiting
  like Roblox (and warns "Infinite yield possible" after 5 s); the summary lists threads still stuck.
- Signals run handlers immediately in a new thread (Roblox's Immediate signal mode), or at the end of the frame with
  `--deferred` (Workspace.SignalBehavior = Deferred, the default for new places). Run both. An error in a handler or
  thread is reported and the rest keeps running, like in Roblox.
- `typeof` names the Roblox type. `type()` of a datatype says `"table"` where Roblox says `"userdata"`; the game
  doesn't branch on that today.

What it does **not** simulate: physics (unanchored parts don't fall, Touched never fires), rendering, clients,
Terrain voxels (writes are validated, raycasts never hit Terrain, so code must cope with `nil`), Spherecast/
Blockcast (always nil), meshes from Import 3D (Props finds none and uses its part fallbacks), network latency.
Spatial queries (Raycast against part boxes, GetPartBoundsInBox/InRadius, GetPartsInPart) treat every part as its
box and use a grid index.

## Adding a mock API

- **A property, method or event on a class:** find the `class("Name", "Super", { props = ..., methods = ...,
  events = ... })` in `mock_instances.luau` (services are in `mock_services.luau`) and add it. Props are
  `Name = { "type", default, "ro"? }` with type one of `number int bool string any Instance Instance:Class
  Enum:Category <Datatype> <Datatype>?`; computed props take `get`/`set` functions. Look up the real default
  and behaviour on create.roblox.com before adding; don't make it return something convenient.
- **A new class:** `class("Name", "SuperClass", { ... })`. Get the superclass right: `IsA` follows it.
- **A service:** `service("Name", "Instance", { ... })` and `SERVICE_NAMES.Name = true` in `mock_services.luau`.
- **An enum:** listed categories in `ENUM_LISTS` (mock.luau) reject unknown items; unlisted categories accept any
  item name (and print a NOTE), so add the real item list when an enum matters.
- Then run `--mock-test`, and add a check to `mocktest.luau` for anything non-obvious.

If the game calls something that **doesn't exist in Roblox**, don't mock it: that's a bug for FINDINGS.md.
