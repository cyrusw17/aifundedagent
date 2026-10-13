# Needlewood: Mac setup

You only do this once. Claude edits the code in this repo; you run it in Roblox Studio.

1. Install Roblox Studio from create.roblox.com and make a new Baseplate place called "Needlewood Dev".
2. Install Git (run `git --version` in Terminal; macOS offers the command line tools) and VS Code.
3. In VS Code install the extensions "Rojo" (evaera.vscode-rojo) and "Luau Language Server" (JohnnyMorganz.luau-lsp).
4. Use the Rojo extension's "Install Rojo Studio plugin" command, then restart Studio.
5. Clone this repo and switch to the branch:
   `git clone <repo url>` then `git checkout claude/roblox-lumber-tycoon-spinoff-z1nlm5`
6. Open the folder in VS Code and run the command "Rojo: Start Server" (or `rojo serve` in Terminal if you installed the Rojo command).
7. In Studio open the Rojo plugin and press Connect. Press Play. The Output window should show `[Needlewood] server started`.
8. When Claude pushes changes, run `git pull` and Rojo updates Studio live.

Blender: install Blender 4.x from blender.org. Model scripts will live in `blender/`. Run one with
`/Applications/Blender.app/Contents/MacOS/Blender --background --python blender/<script>.py`.

## Rustic props (one-time import in Studio)

The bale, shovel and rake use the Rustic Blender meshes once they are imported. Until then the game keeps its
part-built look, so nothing breaks if you skip this. The ten .glb files are in `rustic-import/` in your repo folder
(Claude copied them there; they also live in `blender/exports/rustic/`).

1. In Studio with your place open (Rojo can stay connected), go to **Home > Import 3D**.
2. Pick `rustic-import/hay_bale.glb`. In the import window leave the defaults and press **Import**.
   Repeat for the other files (or multi-select them, if your Studio version allows it).
   Keep the file's hierarchy and leave mesh merging off: vehicles, trailers, conveyors and machines carry their
   wheels, tailgate, coupler, belt and rollers as separate child meshes so they can move.
   When re-importing newer files, first delete the old `RusticProps` folder in ServerStorage and any `Scene` in Workspace.
3. Each one shows up in the **Explorer** under **Workspace** with its file name (hay_bale, basic_shovel, ...).
   Select all ten, right-click **Group as a Folder**, name the folder `RusticProps`, and drag it into **ServerStorage**.
   (Leaving them in Workspace also works: the game moves them out of sight when it starts.)
4. Save the place (**File > Save**, Cmd+S). Rojo never touches ServerStorage, so they stay.
5. Press Play. Output should say `[Needlewood] Rustic props: all 10 meshes found.` If it lists some as using parts,
   those files were not imported or were renamed.

Size and orientation are fixed up by the code, so it does not matter what unit the importer used. Tuning lives in
`src/shared/Config/Props.luau` (prop sizes, how the tools sit in the hand).

## Cloud session tools (for Claude)

GitHub release downloads are blocked in the cloud environment, so tools are built from crates.io. Add this to the environment's Setup script so every new session has them:

```
cargo install rojo --locked
cargo install stylua --locked
```

Checked so far: `rojo build default.project.json -o test.rbxl` builds the project, and `stylua --check src` parses and formats all Luau files.

## What to expect in the first slice

Press Play. You spawn on a small pad at base camp. Walk to the three hay bales, hold the prompt ("Scoop hay") and your wheelbarrow fills (HUD, top left). Walk to the hay shop on the right and press "Sell hay". The toast says how many hidden needles the shop found in your hay and paid $1 each for. Bales refill 30 seconds after they run empty.

Saving: DataStores only work in Studio if the place is published to Roblox and Game Settings > Security > "Enable Studio Access to API Services" is on. Otherwise you will see a warning in Output and progress simply will not save. The game still plays.

## Controls (current)

Each tool does one job. Number keys (or the hotbar) switch tools; press the same number again for bare hands.

- **Picking up a bale:** walk up to it and a small "Pick up" button appears. Click or tap it (or press F). It only shows with empty hands: press the tool's number again to put the tool away. With a tool out, clicks go to the tool. You carry the real bale and walk slower. The button changes to "Put down"; click it, click anywhere, or press G to set the bale down. It lands square on whatever is in front of you, so set one down facing another bale and it stacks on top. A bale left out in the field disappears after 3 minutes; set it on the brown BALE DROP-OFF pad by the spawn and it stays until you smash or sell it.
- **Shovel (slot 1, equipped on spawn):** click a bale: the twine snaps, the bale bursts and the hay spills out as a pile of loose pieces. Face the pile and click to scoop a few pieces at a time into your arms.
- **Rake (slot 2):** face loose hay and click. The rake drags the pieces toward you and spreads them across the ground.
- **Selling:** the glowing SELL pad in front of the hay shop sells automatically. Step onto it holding hay, set a whole bale on it, or rake loose pieces onto it.
- **HUD:** top left shows cash, the hay you carry, and one line saying what a click does with what is in your hands.
- Tuning numbers are in `src/shared/Config/Game.luau` (swing angles, carry speed, cooldowns).

## Meadow Farm: terrain, scattered bales and the truck dealer

Press Play. The ground is now scripted terrain (`src/server/Services/MeadowTerrain.luau`): a 1024 x 1024 stud meadow
with rolling hills, flat ground under base camp, the starter base and the dealer, dirt roads, a pond to the
south-west and tall hills around the edge. The template Baseplate is removed at runtime. Output prints how long the
terrain took and how many bales were scattered.

- **Hay bales** are scattered over the whole meadow in small groups (`MeadowDecor.luau`), but never within about 22
  studs of a building, on a road, in the pond or on the edge hills. They are the same bales as at camp: pick up,
  stack, shovel, and they grow back. Density is `BaleChance` in `src/shared/Config/Meadow.luau`.
- **Money for testing:** `InfiniteMoney = true` in `src/shared/Config/Game.luau` gives every player $1,000,000,000
  that never runs out. Saves keep the real balance underneath. Set it to false before launch.
- **Truck dealer (Homestead Motors)** is west of the spawn at the end of the main road. Walk in the front door,
  straight ahead to the red rug at Hank's counter; a panel opens on the right. The display pickup stands to your
  right on its stage, out of the way. The Rusty Pickup costs $6,000.
- **Land:** the land office (south of the main road, just past the spawn) and six 72 x 72 plots behind it are kept
  flat and clear in `Config/Meadow.luau` (`LandOffice`, `Plots`); the land shop is built by its own thread.
- **Buying** puts you in the driver's seat in the garage. The camera watches the roller door go up and follows your
  truck out onto the lot, then hands control back. Owners press GET MY TRUCK at the counter to have it brought round
  again (one truck per player). The other trucks wait on the lot as COMING SOON.
- **Driving:** W/S gas and reverse, A/D steer, Space to get out. Getting out puts you on the ground beside the
  driver's door; press E (or tap Drive) there to get back in. Only the owner can drive it.
- **Hauling:** carry bales to the truck and set them down in the bed (face the truck, press G). The pickup's bed is
  14.6 x 10.2 inside and holds 9 bales a layer (3 along, 3 across). They ride loose, not welded: drive gently and they stay, take a hill or a turn too hard and they
  slide or fall out. Bales in a truck bed do not despawn. Park on the SELL pad to sell what is in the bed.

### Baking the terrain (optional, faster loads)

The terrain takes about a second to write when the server starts. To skip that, bake it once: in Studio (not
playing), open View > Command Bar and run

```
require(game.ServerScriptService.Server.Services.MeadowTerrain).generate()
```

then save the place. Play sees the baked version and leaves it alone. After `Version` in `Config/Meadow.luau` changes,
Play rebuilds it again until you re-bake.

StreamingEnabled is off (set in `default.project.json`). With it on, each scattered bale's mesh streamed in apart from its body, so bales showed up wrong. The meadow is small enough to load whole. If streaming comes back as the map grows, wrap each bale's body and mesh in a Model with `ModelStreamingMode = Atomic` first.
