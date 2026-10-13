# Headless boot: findings

Run against `claude/integration-check-krlhv6` merged into this branch (Data.luau with the UpdateAsync session lock).

```
python3 tools/headless/run.py path/to/luau              # Immediate signals
python3 tools/headless/run.py path/to/luau --deferred   # Deferred signals
```

Both end with `HEADLESS_RESULT errors=0 warnings=0`.

## Real game bugs (would also fail in Roblox)

**None found.** No runtime error, no failed `require`, no caught-and-warned error (`[Needlewood] ... failed`), and no
thread left stuck on `WaitForChild`, a signal or a `require`. That holds in both signal modes.

Every error the harness raised while it was being built turned out to be a mock gap or a scenario mistake, not the
game. Each was fixed in the mock or the scenario after checking the Roblox docs:

- `os` being read-only in the CLI.
- `typeof` being compiled as a builtin in game chunks (see below).
- `task.wait()` resuming in the same frame.
- The scenario calling Land remotes faster than Land's 0.12 s throttle.
- `LandRemotes.Remove` resolving to `Instance:Remove`, which is correct Roblox behaviour, so the scenario now uses
  `FindFirstChild("Remove")`.

## What the boot covered

Main.server ran, then:

- **Join.** A player joined: UserId 1001, HeadlessTester, R15 character.
- **Slot pick.** `SaveSlots.List` returned 3 slots, then `SaveSlots.Choose(1, plot 1)` loaded slot 1.
- **Build.** Land: Expand twice, then every piece in `LandConfig.Pieces` was placed. 26 placed; `alien_collector` and
  `starbeam_collector` are quest rewards, so they were rightly refused. Bales were dropped on every conveyor and new
  machine, the machines ran for 20 s, then Remove, Undo and Remove were exercised.
- **Client remotes.** Tutorial and Settings. Bank: view, deposit, withdraw, loan, payoff. Dealer: StudioCash plus a buy
  of every truck and trailer. Quests: Get, wear and truck.
- **Tools.** Shovel swings with a ToolAim at a bale, and DropBale.
- **Play.** 60 s of play.
- **Every tool.** Each tool was equipped and activated.
- **Every prompt.** All 496 ProximityPrompts and 5 ClickDetectors in the Workspace were triggered, with the
  character teleported next to each one first.
- **Leave and rejoin.** Leave saved `Player_1001_Slot1`, `_Slot1_Backup` and `_Slots`. A rejoin reloaded slot 1, then
  the BindToClose callbacks ran.
- **Remaining modules.** Every server and shared module not reached by the above was required.

The session lock in Data.luau held up across leave and rejoin: `UpdateAsync` was called with `(old, keyInfo)`, a
`nil` return cancelled the write, and transforms are not allowed to yield.

## Notes (not bugs)

- **Dealer counter.** After the first truck purchase, further `DealerRemotes.Buy` calls answer "Step up to the
  counter first". The purchase most likely spawns or seats the player with the new truck, moving them off the
  counter, so this looks intended (not verified further).
- **Earlier Deferred-mode difference was a harness bug.** Before the fix, scooping behaved differently under
  `--deferred`. The cause was the Luau CLI compiling `typeof(x)` in loadstring chunks as a fast builtin, so game
  code saw `"table"` for every mock Vector3. As a result, `Tools.luau`'s ToolAim handler rejected every aim. The fix
  is `getfenv(1)` in mock.luau, with a check in mocktest.luau. Both signal modes now behave the same.

## Limits

These limits mean "no bugs found" is not "no bugs":

- No physics: unanchored parts don't fall and `Touched` never fires.
- No terrain hits: raycasts ignore Terrain voxels.
- No clients: LocalScripts are bundled but not run.
- `type()` of a datatype returns `"table"`.

Driving, falling hay and other physics-driven paths are not exercised; see README.md.
