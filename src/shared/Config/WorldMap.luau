--!strict
-- The Stitched Isles: every region outside Meadow Farm, the roads that join them, the sea, the ports and the ferries.
-- World studs, north = -Z, east = +X, Meadow Farm's flat ground is Y = 0. Meadow itself (the 1024 x 1024 square around
-- base camp) is Config/Meadow.luau and is never written from here; the land around it blends into its edge hills.
--
-- Layout A3 at twice the old size (Cyrus, 2026-10-13; atlas https://claude.ai/artifact/SwNVTFwxTteZGma2pVdXs8):
-- Meadow sits on the south coast. Stitch Ridge runs north from it to Homestead Valley with a bay on each side, so you
-- cross other regions to get anywhere. The West Road goes Pine Forest, the Haunted Grove (monster woods), the Snow Peak
-- switchbacks, Homestead. The East Road crosses the river on the drawbridge, then Mirror Lake, the Swamp and the
-- Desert to Homestead. The Spindle is north of Homestead, the Volcano north-east. Thimble Keys lies east across a
-- strait (ferry from Swamp Port, or the Longstitch Highway from the Desert), Bobbin Rock north-east (ferry only).
-- Shortcuts home: the Ridge Cut (Homestead straight down the ridge to Meadow) and the Return Ferry (Swamp Port to
-- Meadow Shore). Sky Island is out for now (SkyIsland / Zeppelin are nil).
--
-- Every number is a placeholder to tune in playtests.

export type Discovery = { id: string, name: string, at: Vector2?, flat: string?, radius: number }
type FlatZone = { name: string, min: Vector2, max: Vector2, height: number, blend: number, material: string? }
return {
	-- Bump when the shape changes: a place baked in Studio with an older version is rewritten on Play.
	Version = 3, -- 3: layout A3 at 2x
	Seed = 23,

	SeaLevel = -4, -- the open sea's surface
	SeaFloor = -30, -- depth of open water
	Bounds = { min = Vector2.new(-4352, -7168), max = Vector2.new(5376, 1792) }, -- terrain is written inside this
	Top = 470, -- highest ground (the snow peak), for raycasts

	-- How the land meets Meadow's edge hills: the outside blends into them over this many studs.
	MeadowBlend = 200,
	Coast = 1.2, -- a region's coast is this many radii out (a region can set its own coast)
	MeadowShore = 260, -- land reaches at least this far past Meadow's square before the coast

	-- Each region is an oval of land (center, radius) with its own ground. Neighbors blend into each other; where no
	-- region reaches, there is sea. hayType is the Config/Gloves hay its bales carry.
	--   base: ground height; hills: { amplitude, scale } noise; peak: a mountain in the middle;
	--   materials: top, alt (patches), cliff (steep), beach; shore = "mud" for a swampy edge
	Regions = {
		{
			id = "shore",
			name = "Meadow Shore",
			center = Vector2.new(-300, 900),
			radius = Vector2.new(1500, 400),
			base = 4,
			hills = { { 5, 90 } },
			materials = { top = "LeafyGrass", alt = "Ground", cliff = "Rock", beach = "Sand" },
			hayType = "meadow",
			-- STYLE.md Regions: the accent for signs and trim, and the sky / fog tint.
			style = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) },
		},
		{
			id = "valley",
			name = "Mirror Lake Valley",
			center = Vector2.new(1750, -800),
			radius = Vector2.new(1150, 900),
			base = 10,
			hills = { { 16, 160 }, { 4, 50 } },
			materials = { top = "LeafyGrass", alt = "Ground", cliff = "Rock", beach = "Sand" },
			hayType = "meadow",
			style = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) },
		},
		{
			id = "homestead",
			name = "Homestead Valley",
			center = Vector2.new(0, -4550),
			radius = Vector2.new(900, 650),
			base = 8,
			hills = { { 12, 200 }, { 3, 60 } },
			materials = { top = "LeafyGrass", alt = "Ground", cliff = "Rock", beach = "Sand" },
			hayType = "meadow",
			style = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) },
		},
		{
			id = "spindle",
			name = "The Spindle",
			center = Vector2.new(-90, -5950),
			radius = Vector2.new(520, 450),
			base = 20,
			hills = { { 8, 80 } },
			peak = { center = Vector2.new(-90, -5950), radius = 300, height = 380, power = 1.35 },
			materials = { top = "Limestone", alt = "Slate", cliff = "Slate", beach = "Sand" },
			hayType = "meadow",
			style = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) },
		},
		{
			-- The rocky spine between the two roads. No road goes over it; the Ridge Cut runs down its middle.
			id = "ridge",
			name = "Stitch Ridge",
			center = Vector2.new(0, -2350),
			radius = Vector2.new(430, 1550),
			base = 14,
			hills = { { 10, 120 }, { 4, 40 } },
			spine = { from = Vector2.new(0, -1150), to = Vector2.new(0, -3650), width = 360, height = 170, power = 1.3 },
			noFields = true, -- no hay up here
			materials = { top = "Rock", alt = "LeafyGrass", cliff = "Slate", beach = "Sand" },
			hayType = "meadow",
			style = { accent = Color3.fromRGB(120, 112, 100), fog = Color3.fromRGB(180, 184, 182) },
		},
		{
			id = "pine",
			name = "Pine Forest",
			center = Vector2.new(-1900, -700),
			radius = Vector2.new(1250, 950),
			base = 16,
			hills = { { 26, 190 }, { 6, 60 } },
			materials = { top = "LeafyGrass", alt = "Ground", cliff = "Rock", beach = "Sand" },
			hayType = "pine",
			style = { accent = Color3.fromRGB(61, 102, 94), fog = Color3.fromRGB(158, 176, 173) },
		},
		{
			id = "haunted",
			name = "Haunted Grove",
			center = Vector2.new(-2470, -2860),
			radius = Vector2.new(950, 1150),
			base = 6,
			hills = { { 9, 110 }, { 3, 30 } },
			materials = { top = "Mud", alt = "Slate", cliff = "Basalt", beach = "Mud" },
			hayType = "haunted",
			style = { accent = Color3.fromRGB(110, 96, 130), fog = Color3.fromRGB(140, 140, 150), density = 0.14 },
		},
		{
			id = "snow",
			name = "Snow Peak",
			center = Vector2.new(-2000, -5200),
			radius = Vector2.new(1200, 1000),
			base = 36,
			hills = { { 22, 150 }, { 6, 45 } },
			peak = { center = Vector2.new(-2070, -5330), radius = 560, height = 420, power = 1.25 },
			snowLine = 70, -- everything above this is snow
			materials = { top = "Snow", alt = "Glacier", cliff = "Slate", beach = "Snow" },
			hayType = "snow",
			style = { accent = Color3.fromRGB(112, 150, 178), fog = Color3.fromRGB(209, 219, 230), density = 0.04 },
		},
		{
			id = "volcano",
			name = "Volcano",
			center = Vector2.new(2300, -5950),
			radius = Vector2.new(850, 700),
			base = 18,
			hills = { { 10, 120 } },
			peak = { center = Vector2.new(2350, -6010), radius = 480, height = 340, power = 1.15, crater = 95, craterDepth = 70 },
			lavaRivers = true,
			materials = { top = "Basalt", alt = "Rock", cliff = "Basalt", beach = "Basalt" },
			hayType = "volcano",
			style = { accent = Color3.fromRGB(150, 70, 40), fog = Color3.fromRGB(150, 130, 120) },
		},
		{
			id = "desert",
			name = "Desert Dunes",
			center = Vector2.new(1700, -4200),
			radius = Vector2.new(1100, 800),
			base = 8,
			hills = { { 6, 160 } },
			dunes = { amplitude = 16, scale = 70 },
			materials = { top = "Sand", alt = "Sandstone", cliff = "Sandstone", beach = "Sand" },
			hayType = "desert",
			style = { accent = Color3.fromRGB(168, 97, 64), fog = Color3.fromRGB(224, 209, 184) },
		},
		{
			id = "swamp",
			name = "Swamp",
			center = Vector2.new(2400, -2400),
			radius = Vector2.new(900, 1050),
			base = 1.5,
			hills = { { 3.5, 60 } },
			pools = { level = -0.5, threshold = -0.18, scale = 55 }, -- low spots fill with bog water
			materials = { top = "Mud", alt = "LeafyGrass", cliff = "Ground", beach = "Mud" },
			hayType = "swamp",
			style = { accent = Color3.fromRGB(153, 173, 71), fog = Color3.fromRGB(153, 163, 143), density = 0.08 },
		},
		{
			id = "keys",
			coast = 1, -- islands keep their own coast
			name = "Thimble Keys",
			center = Vector2.new(4400, -3050),
			radius = Vector2.new(600, 650),
			base = 4,
			hills = { { 9, 120 } },
			islets = true, -- broken up into keys by a channel noise
			materials = { top = "LeafyGrass", alt = "Sand", cliff = "Sandstone", beach = "Salt" },
			hayType = "keys",
			style = { accent = Color3.fromRGB(64, 132, 140), fog = Color3.fromRGB(196, 214, 216) },
		},
		{
			id = "bobbin",
			coast = 1,
			name = "Bobbin Rock",
			center = Vector2.new(4600, -5500),
			radius = Vector2.new(430, 420),
			base = 10,
			hills = { { 10, 60 } },
			peak = { center = Vector2.new(4630, -5530), radius = 260, height = 170, power = 0.8 },
			materials = { top = "Rock", alt = "Slate", cliff = "Slate", beach = "Slate" },
			hayType = "bobbin",
			fieldFlat = "BobbinFields", -- too steep for fields to find their own spot: one goes on this terrace
			style = { accent = Color3.fromRGB(120, 110, 150), fog = Color3.fromRGB(180, 180, 196) },
		},
	},

	-- Terrain colors for the materials Meadow doesn't color (Meadow sets Grass, LeafyGrass, Ground, Mud, Sand, Rock).
	Colors = {
		Snow = Color3.fromRGB(226, 228, 226),
		Glacier = Color3.fromRGB(176, 192, 196),
		Slate = Color3.fromRGB(96, 92, 98),
		Basalt = Color3.fromRGB(64, 58, 56),
		CrackedLava = Color3.fromRGB(196, 92, 46),
		Limestone = Color3.fromRGB(162, 154, 170),
		Sandstone = Color3.fromRGB(186, 156, 112),
		Salt = Color3.fromRGB(222, 214, 192),
		Cobblestone = Color3.fromRGB(128, 120, 108),
		Pavement = Color3.fromRGB(112, 108, 102),
	},

	-- Ground pulled to a set height under buildings and ports. Rects are min/max X and Z.
	Flat = ({
		{ name = "HomesteadPlaza", min = Vector2.new(-130, -4640), max = Vector2.new(130, -4460), height = 8, blend = 60, material = "Cobblestone" },
		{ name = "SkiLodge", min = Vector2.new(-1715, -5097), max = Vector2.new(-1615, -5017), height = 46, blend = 50 },
		{ name = "Lighthouse", min = Vector2.new(270, 1250), max = Vector2.new(330, 1310), height = 6, blend = 30 },
		{ name = "TailorShack", min = Vector2.new(-284, 800), max = Vector2.new(-244, 840), height = 4, blend = 30 },
		{ name = "MeadowDock", min = Vector2.new(670, 1150), max = Vector2.new(760, 1240), height = 3, blend = 40 },
		{ name = "PineMill", min = Vector2.new(-2040, -810), max = Vector2.new(-1980, -750), height = 18, blend = 40 },
		{ name = "Pyramid", min = Vector2.new(1874, -4415), max = Vector2.new(1994, -4295), height = 10, blend = 50 },
		{ name = "Oasis", min = Vector2.new(1569, -4088), max = Vector2.new(1649, -4008), height = 6, blend = 40 },
		{ name = "Quarry", min = Vector2.new(1893, -5809), max = Vector2.new(1993, -5709), height = 30, blend = 50 },
		{ name = "Wreck", min = Vector2.new(-3530, -2847), max = Vector2.new(-3460, -2767), height = -2, blend = 30 },
		{ name = "SwampPort", min = Vector2.new(3175, -2312), max = Vector2.new(3265, -2180), height = 3, blend = 40 },
		{ name = "AshDock", min = Vector2.new(3055, -5682), max = Vector2.new(3145, -5572), height = 3, blend = 40 },
		{ name = "KeysHarbor", min = Vector2.new(3973, -2608), max = Vector2.new(4073, -2498), height = 3, blend = 40 },
		{ name = "BobbinPier", min = Vector2.new(4233, -5443), max = Vector2.new(4293, -5363), height = 3, blend = 30 },
		{ name = "Workshop", min = Vector2.new(4570, -5500), max = Vector2.new(4630, -5440), height = 182, blend = 40 },
		-- A terrace above the Bobbin Track for the rock's only hay field (the rest of the rock is too steep).
		{ name = "BobbinFields", min = Vector2.new(4657, -5222), max = Vector2.new(4689, -5194), height = 14, blend = 24 },
		{ name = "HighwayWest", min = Vector2.new(2820, -4050), max = Vector2.new(2900, -3970), height = 3, blend = 40 },
		{ name = "HighwayEast", min = Vector2.new(3886, -3252), max = Vector2.new(3966, -3172), height = 3, blend = 40 },
	} :: { FlatZone }),

	-- Sea lanes kept deep so a ferry never scrapes the bottom (min depth along a line).
	Channels = {
		{ from = Vector2.new(3474, -2317), to = Vector2.new(3870, -2508), width = 90, depth = -22 },
		{ from = Vector2.new(3323, -5586), to = Vector2.new(4080, -5443), width = 90, depth = -22 },
		-- The Return Ferry, round the east coast from Swamp Port to Meadow Shore.
		{ from = Vector2.new(3360, -1960), to = Vector2.new(3550, -1700), width = 90, depth = -22 },
		{ from = Vector2.new(3550, -1700), to = Vector2.new(3350, -400), width = 90, depth = -22 },
		{ from = Vector2.new(3350, -400), to = Vector2.new(2700, 700), width = 90, depth = -22 },
		{ from = Vector2.new(2700, 700), to = Vector2.new(1800, 1500), width = 90, depth = -22 },
		{ from = Vector2.new(1800, 1500), to = Vector2.new(715, 1660), width = 90, depth = -22 },
		{ from = Vector2.new(715, 1660), to = Vector2.new(715, 1380), width = 90, depth = -22 },
	},

	-- Rivers: a trench of sea-level water along a line, from a spring in the hills to the sea.
	Rivers = {
		{
			name = "Stitchwater",
			points = {
				Vector2.new(780, -1300), Vector2.new(820, -900), Vector2.new(860, -450), Vector2.new(890, 0),
				Vector2.new(905, 450), Vector2.new(950, 950), Vector2.new(1000, 1450),
			},
			width = 70,
			depth = -12,
		},
	},

	-- Dirt roads, leveled into the land and joined to Meadow's two exits (Meadow.luau North and South end there).
	-- A road's height follows the land, smoothed and kept gentle enough to drive a loaded truck up. A road with a
	-- level is held at that height instead (the Ridge Cut runs level through the rock).
	RoadWidth = 16,
	MaxGrade = 0.14, -- rise per stud along a road
	Roads = {
		{
			name = "West Road", -- Meadow's south exit, round the west: Pine Forest, the Haunted Grove, up Snow Peak's
			-- switchbacks and down into Homestead
			points = {
				Vector2.new(150, 512), Vector2.new(150, 660), Vector2.new(-200, 760), Vector2.new(-700, 700),
				Vector2.new(-1150, 520), Vector2.new(-1500, 250), Vector2.new(-1750, -150), Vector2.new(-1930, -700),
				Vector2.new(-2000, -1100), Vector2.new(-2150, -1500), Vector2.new(-2250, -1800), Vector2.new(-2350, -2200),
				Vector2.new(-2500, -2600), Vector2.new(-2560, -2900), Vector2.new(-2480, -3300), Vector2.new(-2350, -3700),
				Vector2.new(-2200, -4000), Vector2.new(-2050, -4120), Vector2.new(-1880, -4150), Vector2.new(-1842, -4160),
				Vector2.new(-1815, -4188), Vector2.new(-1805, -4225), Vector2.new(-1815, -4262), Vector2.new(-1842, -4290),
				Vector2.new(-1880, -4300), Vector2.new(-2170, -4300), Vector2.new(-2208, -4310), Vector2.new(-2235, -4338),
				Vector2.new(-2245, -4375), Vector2.new(-2235, -4412), Vector2.new(-2208, -4440), Vector2.new(-2170, -4450),
				Vector2.new(-1880, -4450), Vector2.new(-1842, -4460), Vector2.new(-1815, -4488), Vector2.new(-1805, -4525),
				Vector2.new(-1815, -4562), Vector2.new(-1842, -4590), Vector2.new(-1880, -4600), Vector2.new(-2170, -4600),
				Vector2.new(-2208, -4610), Vector2.new(-2235, -4638), Vector2.new(-2245, -4675), Vector2.new(-2235, -4712),
				Vector2.new(-2208, -4740), Vector2.new(-2170, -4750), Vector2.new(-1700, -4750),
				Vector2.new(-1350, -4800), Vector2.new(-1000, -4700),
				Vector2.new(-650, -4600), Vector2.new(-300, -4560), Vector2.new(-130, -4550),
			},
		},
		{
			name = "East Road", -- Meadow's south exit, round the east: over the river, up the valley, the swamp, the
			-- desert and west into Homestead
			points = {
				Vector2.new(150, 660), Vector2.new(450, 760), Vector2.new(780, 690), Vector2.new(1060, 620),
				Vector2.new(1150, 450), Vector2.new(1300, 150), Vector2.new(1450, -200), Vector2.new(1550, -500),
				Vector2.new(1650, -900), Vector2.new(1800, -1300), Vector2.new(2050, -1650), Vector2.new(2300, -2000),
				Vector2.new(2450, -2350), Vector2.new(2400, -2700), Vector2.new(2300, -3100), Vector2.new(2100, -3600),
				Vector2.new(1900, -3950), Vector2.new(1500, -4300), Vector2.new(1100, -4450), Vector2.new(700, -4520),
				Vector2.new(300, -4540), Vector2.new(130, -4550),
			},
		},
		{
			name = "Ridge Cut", -- the shortcut home: Meadow's north exit, level through Stitch Ridge to Homestead
			level = 8,
			-- Where the ridge stands more than cover studs over the road, the road runs in a tunnel this tall.
			tunnel = { height = 22, cover = 34 },
			points = {
				Vector2.new(-30, -512), Vector2.new(-30, -1000), Vector2.new(0, -2300), Vector2.new(-30, -3600),
				Vector2.new(-15, -4100), Vector2.new(0, -4460),
			},
		},
		{
			name = "Dock Lane", -- off the East Road down to the Return Ferry's Meadow Shore dock
			points = { Vector2.new(450, 760), Vector2.new(600, 940), Vector2.new(690, 1100), Vector2.new(712, 1170) },
		},
		{
			name = "Lighthouse Lane", -- off the West Road down to the Lighthouse on the south point
			points = { Vector2.new(-200, 760), Vector2.new(-20, 980), Vector2.new(180, 1180), Vector2.new(290, 1262) },
		},
		{
			name = "Snow Road", -- off the switchbacks up to the lodge
			points = { Vector2.new(-1700, -4750), Vector2.new(-1680, -4900), Vector2.new(-1665, -5017) },
		},
		{
			name = "Wreck Lane",
			points = { Vector2.new(-2560, -2900), Vector2.new(-2900, -2950), Vector2.new(-3150, -2880), Vector2.new(-3460, -2812) },
		},
		{
			name = "Spindle Road", -- from the plaza's north-east corner up to the Spindle's door
			points = {
				Vector2.new(130, -4600), Vector2.new(200, -4750), Vector2.new(150, -4950), Vector2.new(80, -5300),
				Vector2.new(250, -5700), Vector2.new(320, -5880),
			},
		},
		{
			name = "Cave Lane", -- off the Spindle Road, west round the Spindle's foot to the Crystal Cave mouth
			points = { Vector2.new(150, -4950), Vector2.new(-250, -5300), Vector2.new(-450, -5650), Vector2.new(-505, -5828) },
		},
		{
			name = "Port Lane", -- off the East Road to Swamp Port
			points = { Vector2.new(2450, -2350), Vector2.new(2750, -2250), Vector2.new(3000, -2270), Vector2.new(3175, -2262) },
		},
		{
			name = "Highway Road", -- off the East Road to the Longstitch Highway
			points = { Vector2.new(2100, -3600), Vector2.new(2400, -3850), Vector2.new(2700, -3990), Vector2.new(2860, -4010) },
		},
		{
			name = "Pyramid Track",
			points = { Vector2.new(1900, -3950), Vector2.new(1934, -4150), Vector2.new(1934, -4295) },
		},
		{
			name = "Volcano Road", -- the desert south to the quarry, then round the volcano's foot to Ash Dock
			points = {
				Vector2.new(1500, -4300), Vector2.new(1550, -4700), Vector2.new(1700, -5100), Vector2.new(1850, -5450),
				Vector2.new(2150, -5420), Vector2.new(2500, -5330), Vector2.new(2800, -5430), Vector2.new(3055, -5627),
			},
		},
		{
			name = "Quarry Lane",
			points = { Vector2.new(1850, -5450), Vector2.new(1910, -5600), Vector2.new(1943, -5709) },
		},
		{
			name = "Keys Road", -- off the highway, across Thimble Keys to the harbor
			points = {
				Vector2.new(3926, -3212), Vector2.new(4252, -3161), Vector2.new(4460, -3050), Vector2.new(4375, -2723),
				Vector2.new(4093, -2553),
			},
		},
		{
			name = "Bobbin Track", -- from the Bobbin Rock pier round the rock's low south shore (the top is a climb)
			points = {
				Vector2.new(4270, -5404), Vector2.new(4383, -5272), Vector2.new(4518, -5179), Vector2.new(4678, -5153),
				Vector2.new(4835, -5204), Vector2.new(4944, -5305),
			},
		},
	},

	-- The Longstitch Highway: a bridge from the desert coast, the Midway Rest Stop, then an undersea tunnel up onto
	-- Thimble Keys. Built from parts; the terrain under it stays sea.
	-- Its height along X is the Profile (x, deck top), straight-line between the points.
	Highway = {
		width = 22,
		from = Vector2.new(2860, -4010),
		to = Vector2.new(3926, -3212),
		Profile = { { 2860, 3 }, { 2930, 10 }, { 3240, 10 }, { 3560, -24 }, { 3660, -24 }, { 3926, 3 } },
		restStop = { x = 3090, size = Vector2.new(70, 60) }, -- a wide stretch of deck with a pump and a stall
		toll = 2935, -- X of the toll gate
		tubeTop = 12, -- the undersea tube's inside height
	},

	-- Ports. A ferry runs between two piers; each pier points out to sea along the route. Deck tops are at
	-- Ferry.DeckTop, level with the pier. A route with via sails round those points (x, z) on the way.
	Ferry = {
		DeckTop = 3,
		Length = 150, -- ferry deck, end to end
		Width = 54, -- three lanes of trucks with trailers
		Speed = 26, -- studs per second at cruise
		Dock = 25, -- seconds boarding at each pier
		Warn = 8, -- seconds of horn before the gates close
		Routes = {
			{
				id = "keys_ferry",
				name = "Thimble Keys Ferry",
				a = { name = "Swamp Port", shore = Vector2.new(3242, -2262), pierEnd = Vector2.new(3474, -2317) },
				b = { name = "Keys Harbor", shore = Vector2.new(4065, -2544), pierEnd = Vector2.new(3870, -2508) },
			},
			{
				id = "bobbin_ferry",
				name = "Bobbin Rock Ferry",
				a = { name = "Ash Dock", shore = Vector2.new(3107, -5627), pierEnd = Vector2.new(3323, -5586) },
				b = { name = "Bobbin Rock", shore = Vector2.new(4282, -5405), pierEnd = Vector2.new(4080, -5443) },
			},
			{
				id = "return_ferry",
				name = "Return Ferry",
				a = { name = "Swamp Port", shore = Vector2.new(3240, -2200), pierEnd = Vector2.new(3360, -1960) },
				b = { name = "Meadow Shore", shore = Vector2.new(715, 1200), pierEnd = Vector2.new(715, 1380) },
				via = {
					Vector2.new(3550, -1700), Vector2.new(3350, -400), Vector2.new(2700, 700), Vector2.new(1800, 1500),
					Vector2.new(715, 1660),
				},
			},
		},
	},

	-- Sky Island and its zeppelin are out for now (Cyrus 2026-10-13); every user checks for nil.
	Zeppelin = nil :: any,
	SkyIsland = nil :: any,

	-- The cave under the Spindle: a tunnel from its west foot into a crystal cavern.
	Cave = {
		mouth = Vector3.new(-520, 26, -5864),
		path = { Vector3.new(-430, 22, -5880), Vector3.new(-320, 14, -5910), Vector3.new(-200, 8, -5940) },
		chamber = { center = Vector3.new(-100, 10, -5950), radius = 70 },
		hayType = "cave",
	},

	-- Places worth finding (Services/Discoveries.luau): the first visit pays Prices.Discovery.landmark, stamps the
	-- map and fills a collection page. at = the place (x, z); radius = how close counts. Every region (and the
	-- Crystal Cave) is a discovery too, worth Prices.Discovery.region. Set flat = a Flat zone's name to use its
	-- middle instead of at.
	Discoveries = ({
		{ id = "old_well", name = "The Old Well", at = Vector2.new(0, -4520), radius = 25 },
		{ id = "spindle_door", name = "The Spindle Door", at = Vector2.new(333, -5916), radius = 40 },
		{ id = "observatory", name = "The Observatory", at = Vector2.new(1830, -1000), radius = 40 },
		{ id = "mirror_lake", name = "Mirror Lake", at = Vector2.new(2014, -844), radius = 200 },
		{ id = "lighthouse", name = "The Lighthouse", at = Vector2.new(300, 1280), radius = 45 },
		{ id = "tailors_shack", name = "The Tailor's Shack", at = Vector2.new(-264, 820), radius = 40 },
		{ id = "wreck_bobbin", name = "Wreck of the Bobbin", at = Vector2.new(-3495, -2807), radius = 60 },
		{ id = "ghost_isle", name = "Ghost Isle", at = Vector2.new(-3880, -2780), radius = 50 },
		{ id = "ski_lodge", name = "Snow Peak Lodge", at = Vector2.new(-1665, -5090), radius = 50 },
		{ id = "crater_rim", name = "The Crater Rim", at = Vector2.new(2350, -6010), radius = 115 },
		{ id = "old_quarry", name = "The Old Quarry", at = Vector2.new(1943, -5759), radius = 50 },
		{ id = "buried_pyramid", name = "The Buried Pyramid", at = Vector2.new(1934, -4355), radius = 80 },
		{ id = "graveyard_of_ships", name = "Graveyard of Ships", at = Vector2.new(3700, -5560), radius = 300 },
		{ id = "weavers_workshop", name = "The Weaver's Workshop", flat = "Workshop", radius = 50 },
	} :: { Discovery }),

	-- Mirror Lake, up the valley. Low Tide drains it later; for now it is a calm lake with a dock.
	Lake = { center = Vector2.new(2014, -844), radius = 160, depth = 18, level = 3 },
	Oasis = { center = Vector2.new(1609, -4048), radius = 30, depth = 6, level = 5 },

	-- Hay fields: groups of bales per region (a field is a circle). Bales regrow like Meadow's.
	BalesPerField = { 6, 9 },
	FieldsPerRegion = 3,

	-- The rich field: every RichMinutes, one field on the server glows on the map and its bales carry 2x needles.
	RichMinutes = 20,

	-- Part budget (#21). Health's Workspace budget is 40,000 parts (Main.server.luau); the map's share is 12,000.
	-- Each container under Needlewood.StitchedIsles (and each region under Isles) gets a slice; mapcheck and the Map
	-- self-test fail any container over its slice. "Field bales" is the hay lying in the region fields.
	-- Regions are plain Models (Default streaming): parts stream in and out one by one. Only buildings, windmill
	-- sails and vehicles are Atomic, and only the skyline labels and the rich-field beam are Persistent.
	PartBudget = {
		["Meadow Shore"] = 450,
		["Mirror Lake Valley"] = 650,
		["Homestead Valley"] = 700,
		["The Spindle"] = 400,
		["Stitch Ridge"] = 300,
		["Pine Forest"] = 950,
		["Haunted Grove"] = 800,
		["Snow Peak"] = 950,
		["Volcano"] = 400,
		["Desert Dunes"] = 600,
		["Swamp"] = 800,
		["Thimble Keys"] = 800,
		["Bobbin Rock"] = 300,
		["Crystal Cave"] = 200,
		["Graveyard of Ships"] = 150,
		["Signs"] = 150,
		["Longstitch Highway"] = 400,
		["Ferries"] = 400,
		["Wilds"] = 300,
		["RoadPolish"] = 900, -- rails and bridge sides along twice the road (A3 at 2x)
		["HayWagon"] = 100,
		["Field bales"] = 400,
		["Lighting"] = 600, -- landmark lights at night (#26)
		["Festival"] = 60, -- this week's festival bunting (Festival.luau)
	} :: { [string]: number },
	PartShare = 12000, -- the slices above must add up to no more than this

	-- Weekly region festival (Addiction push H11, Services/Festival.luau). Weeks count from FestivalEpoch (a Monday,
	-- 00:00 UTC), so every server agrees on the region and the dates. The festival region's field bales carry
	-- FestivalBoost times the needles (not stacked on the rich field's 2x), it gets bunting and a banner, and a
	-- player who visits it that week earns that week's festival ribbon (cosmetic, kept in the save).
	FestivalEpoch = 1704067200, -- Monday 2024-01-01 00:00 UTC
	FestivalWeek = 7 * 24 * 3600,
	FestivalBoost = 1.5, -- Economy (H13): 2 put a stacked week over the 2x cap (tools/boost_sim.py)
	FestivalOrder = { "pine", "valley", "desert", "snow", "swamp", "shore", "haunted", "volcano", "keys", "homestead", "bobbin" }, -- the Spindle has no hay field
}
