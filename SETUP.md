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
