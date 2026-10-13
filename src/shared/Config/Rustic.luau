--!strict
-- The Rustic house palette as Roblox colors. Mid tones from blender/lib/style.py RUSTIC (PR #12), so part-built
-- placeholders match the Blender meshes that replace them later. Ground colors are new and kept just as muted.
local function rgb(r: number, g: number, b: number): Color3
	return Color3.new(r, g, b)
end

return {
	Hay = rgb(0.74, 0.66, 0.44),
	HayLight = rgb(0.86, 0.80, 0.60),
	Bark = rgb(0.30, 0.25, 0.20),
	BarkDark = rgb(0.16, 0.13, 0.10),
	Wood = rgb(0.70, 0.60, 0.45),
	WoodDark = rgb(0.52, 0.43, 0.32),
	Handle = rgb(0.50, 0.41, 0.30),
	Metal = rgb(0.42, 0.37, 0.33),
	Rust = rgb(0.40, 0.26, 0.16),
	Twine = rgb(0.38, 0.33, 0.26),
	PaintRed = rgb(0.52, 0.24, 0.19),
	PaintRedDark = rgb(0.36, 0.18, 0.14),
	PaintGreen = rgb(0.34, 0.42, 0.28),
	PaintBlue = rgb(0.32, 0.39, 0.46),
	PaintCream = rgb(0.78, 0.73, 0.60),
	PaintYellow = rgb(0.72, 0.58, 0.26),
	Stone = rgb(0.56, 0.53, 0.49),
	StoneDark = rgb(0.40, 0.38, 0.35),
	Cloth = rgb(0.74, 0.70, 0.58),
	Tire = rgb(0.13, 0.12, 0.11),
	Glass = rgb(0.20, 0.26, 0.28),

	-- Ground and plants
	Grass = Color3.fromRGB(112, 128, 82),
	LeafyGrass = Color3.fromRGB(96, 112, 70),
	Dirt = Color3.fromRGB(150, 128, 92),
	Mud = Color3.fromRGB(100, 84, 64),
	Sand = Color3.fromRGB(176, 160, 124),
	Rock = Color3.fromRGB(122, 116, 108),
	Water = Color3.fromRGB(74, 92, 84),
	Leaves = Color3.fromRGB(88, 104, 62),
	LeavesDark = Color3.fromRGB(70, 86, 52),
	LeavesDry = Color3.fromRGB(128, 122, 70),
}
