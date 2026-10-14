--!strict
-- How each region's hay looks (ids match Config/Gloves HayTypes). colors: the strand palette, the first is the bale's
-- own color. length/thick: strand size in studs. dust: the cloud a burst bale throws up. motes (optional): a few
-- drifting specks of that color in the burst, for the stranger hays. material (optional): strand material, Fabric
-- by default. Muted and weathered, in the Rustic style; only the far-off hays get a little glow.
type Look = {
	colors: { { number } },
	length: { number },
	thick: { number },
	dust: { number },
	motes: { number }?,
	material: string?,
}

local looks: { [string]: Look } = {
	meadow = {
		colors = { { 189, 168, 112 }, { 219, 204, 153 }, { 205, 189, 136 }, { 168, 149, 95 }, { 133, 115, 71 }, { 150, 148, 96 } },
		length = { 0.5, 1.1 },
		thick = { 0.1, 0.14 },
		dust = { 175, 160, 125 },
	},
	pine = { -- needles of rust-brown pine straw, thin and long
		colors = { { 138, 96, 62 }, { 160, 112, 70 }, { 120, 84, 56 }, { 112, 104, 70 } },
		length = { 0.9, 1.5 },
		thick = { 0.06, 0.09 },
		dust = { 130, 110, 85 },
	},
	desert = { -- pale, dry and brittle short grass
		colors = { { 214, 196, 150 }, { 228, 212, 170 }, { 200, 178, 128 }, { 190, 170, 120 } },
		length = { 0.35, 0.8 },
		thick = { 0.08, 0.12 },
		dust = { 214, 190, 140 },
	},
	snow = { -- frosted grey-white hay
		colors = { { 200, 204, 196 }, { 216, 220, 214 }, { 180, 184, 170 }, { 170, 172, 150 } },
		length = { 0.5, 1.1 },
		thick = { 0.1, 0.14 },
		dust = { 225, 230, 235 },
		motes = { 240, 246, 255 },
	},
	swamp = { -- dark wet reeds, long and thick
		colors = { { 96, 104, 70 }, { 84, 92, 60 }, { 110, 112, 76 }, { 74, 78, 52 } },
		length = { 1.0, 1.7 },
		thick = { 0.14, 0.2 },
		dust = { 90, 96, 70 },
	},
	keys = { -- pale salt-bleached sea grass, thin and wiry
		colors = { { 196, 190, 150 }, { 176, 178, 136 }, { 210, 200, 164 }, { 150, 160, 120 } },
		length = { 0.8, 1.4 },
		thick = { 0.08, 0.12 },
		dust = { 214, 206, 178 },
	},
	bobbin = { -- coppery thread-like grass, fine and long
		colors = { { 168, 120, 78 }, { 150, 104, 66 }, { 186, 140, 92 }, { 132, 94, 62 } },
		length = { 1.0, 1.6 },
		thick = { 0.06, 0.09 },
		dust = { 150, 118, 88 },
		motes = { 220, 180, 110 },
	},
	volcano = { -- scorched hay with ash
		colors = { { 92, 80, 70 }, { 70, 62, 56 }, { 120, 92, 66 }, { 140, 96, 60 } },
		length = { 0.4, 0.9 },
		thick = { 0.1, 0.14 },
		dust = { 80, 74, 70 },
		motes = { 210, 120, 60 },
	},
	cave = { -- pale crystal-flecked stalks
		colors = { { 170, 176, 186 }, { 150, 160, 176 }, { 186, 186, 196 }, { 140, 150, 160 } },
		length = { 0.5, 1.0 },
		thick = { 0.1, 0.13 },
		dust = { 150, 156, 170 },
		motes = { 170, 210, 230 },
	},
	sky = { -- soft cloud hay, light and fluffy
		colors = { { 226, 228, 230 }, { 210, 216, 226 }, { 236, 236, 232 }, { 200, 208, 220 } },
		length = { 0.4, 0.9 },
		thick = { 0.14, 0.2 },
		dust = { 235, 238, 245 },
		motes = { 255, 255, 255 },
	},
	haunted = { -- grey-violet phantom straw
		colors = { { 120, 112, 130 }, { 100, 94, 112 }, { 140, 132, 146 }, { 88, 84, 96 } },
		length = { 0.6, 1.3 },
		thick = { 0.08, 0.12 },
		dust = { 110, 104, 120 },
		motes = { 150, 220, 200 },
	},
	star = { -- night-blue straw with a faint glow
		colors = { { 70, 72, 96 }, { 90, 94, 130 }, { 120, 116, 160 }, { 200, 186, 120 } },
		length = { 0.6, 1.2 },
		thick = { 0.08, 0.12 },
		dust = { 80, 84, 120 },
		motes = { 255, 230, 150 },
		material = "Glass",
	},
}

return looks
