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

## Cloud session tools (for Claude)

GitHub release downloads are blocked in the cloud environment, so tools are built from crates.io. Add this to the environment's Setup script so every new session has them:

```
cargo install rojo --locked
cargo install stylua --locked
```

Checked so far: `rojo build default.project.json -o test.rbxl` builds the project, and `stylua --check src` parses and formats all Luau files.

## What to expect in the first slice

Press Play. You spawn on a small pad at base camp. Walk to the three hay barrels, hold the prompt ("Scoop hay") and your wheelbarrow fills (HUD, top left). Walk to the hay shop on the right and press "Sell hay". The toast says how many hidden needles the shop found in your hay and paid $1 each for. Barrels refill 30 seconds after they run empty.

Saving: DataStores only work in Studio if the place is published to Roblox and Game Settings > Security > "Enable Studio Access to API Services" is on. Otherwise you will see a warning in Output and progress simply will not save. The game still plays.

## Controls (current)

Each tool does one job. Number keys (or the hotbar) switch tools; press the same number again for bare hands.

- **Picking up a barrel:** walk up to it and a small "Pick up" button appears. Click or tap it (or press F). It works with any tool in hand and puts the tool away. You carry the real barrel and walk slower. The button changes to "Put down"; click it, click anywhere, or press G to set the barrel down. It falls and rolls. A barrel left out in the field disappears after 3 minutes; set it on the brown BARREL DROP-OFF pad by the spawn and it stays until you smash or sell it.
- **Shovel (slot 1, equipped on spawn):** face a barrel and click: it smashes open, the staves and hoops fly apart and the hay spills out as a pile of loose pieces. Face the pile and click to scoop a few pieces at a time into your arms.
- **Rake (slot 2):** face loose hay and click. The rake drags the pieces toward you and spreads them across the ground.
- **Selling:** the yellow SELL pad in front of the hay shop sells automatically. Step onto it holding hay, set a whole barrel on it, or rake loose pieces onto it.
- **HUD:** top left shows cash, the hay you carry, and one line saying what a click does with what is in your hands.
- Tuning numbers are in `src/shared/Config/Game.luau` (swing angles, carry speed, cooldowns).
