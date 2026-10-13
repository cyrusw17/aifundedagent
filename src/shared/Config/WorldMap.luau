--!strict
-- The Stitched Isles: every region outside Meadow Farm, the roads that join them, the sea, the ports and the ferries.
-- World studs, north = -Z, east = +X, Meadow Farm's flat ground is Y = 0. Meadow itself (the 1024 x 1024 square around
-- base camp) is Config/Meadow.luau and is never written from here; the land around it blends into its edge hills.
--
-- Layout, from docs/GAME_PLAN_V8.md and the world map board: Meadow sits on the south coast of the main island.
-- North of it are Mirror Lake and the Spindle, then Homestead Valley (the hub). Pine Forest and Haunted Grove are
-- west, Snow Peak north-west, the Volcano north-east, Desert Dunes east and the Swamp south-east. Thimble Keys lies
-- east across the sea (the Longstitch Highway or the ferry), Bobbin Rock north-east (ferry only), and Sky Island
-- floats above the hub (zeppelin).
--
-- Every number is a placeholder to tune in playtests.

export type Discovery = { id: string, name: string, at: Vector2?, flat: string?, radius: number }
type FlatZone = { name: string, min: Vector2, max: Vector2, height: number, blend: number, material: string? }
return {
	-- Bump when the shape changes: a place baked in Studio with an older version is rewritten on Play.
	Version = 2, -- 2: Cave Lane and Bobbin Track
	Seed = 23,

	SeaLevel = -4, -- the open sea's surface
	SeaFloor = -30, -- depth of open water
	Bounds = { min = Vector2.new(-2048, -2560), max = Vector2.new(3584, 1280) }, -- terrain is written inside this
	Top = 470, -- highest ground (the snow peak), for raycasts

	-- How the land meets Meadow's edge hills: the outside blends into them over this many studs.
	MeadowBlend = 200,
	MeadowShore = 260, -- land reaches at least this far past Meadow's square before the coast

	-- Each region is an oval of land (center, radius) with its own ground. Neighbors blend into each other; where no
	-- region reaches, there is sea. hayType is the Config/Gloves hay its bales carry.
	--   base: ground height; hills: { amplitude, scale } noise; peak: a mountain in the middle;
	--   materials: top, alt (patches), cliff (steep), beach; shore = "mud" for a swampy edge
	Regions = {
		{
			id = "shore",
			name = "Meadow Shore",
			center = Vector2.new(60, 760),
			radius = Vector2.new(980, 250),
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
			center = Vector2.new(150, -840),
			radius = Vector2.new(660, 390),
			base = 10,
			hills = { { 16, 160 }, { 4, 50 } },
			materials = { top = "LeafyGrass", alt = "Ground", cliff = "Rock", beach = "Sand" },
			hayType = "meadow",
			style = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) },
		},
		{
			id = "homestead",
			name = "Homestead Valley",
			center = Vector2.new(0, -1470),
			radius = Vector2.new(560, 380),
			base = 8,
			hills = { { 12, 200 }, { 3, 60 } },
			materials = { top = "LeafyGrass", alt = "Ground", cliff = "Rock", beach = "Sand" },
			hayType = "meadow",
			style = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) },
		},
		{
			id = "spindle",
			name = "The Spindle",
			center = Vector2.new(-90, -1010),
			radius = Vector2.new(300, 260),
			base = 20,
			hills = { { 8, 80 } },
			peak = { center = Vector2.new(-90, -1010), radius = 250, height = 360, power = 1.35 },
			materials = { top = "Limestone", alt = "Slate", cliff = "Slate", beach = "Sand" },
			hayType = "meadow",
			style = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) },
		},
		{
			id = "pine",
			name = "Pine Forest",
			center = Vector2.new(-1150, 120),
			radius = Vector2.new(600, 560),
			base = 16,
			hills = { { 26, 190 }, { 6, 60 } },
			materials = { top = "LeafyGrass", alt = "Ground", cliff = "Rock", beach = "Sand" },
			hayType = "pine",
			style = { accent = Color3.fromRGB(61, 102, 94), fog = Color3.fromRGB(158, 176, 173) },
		},
		{
			id = "haunted",
			name = "Haunted Grove",
			center = Vector2.new(-1240, -880),
			radius = Vector2.new(570, 430),
			base = 6,
			hills = { { 9, 110 }, { 3, 30 } },
			materials = { top = "Mud", alt = "Slate", cliff = "Basalt", beach = "Mud" },
			hayType = "haunted",
			style = { accent = Color3.fromRGB(110, 96, 130), fog = Color3.fromRGB(140, 140, 150), density = 0.14 },
		},
		{
			id = "snow",
			name = "Snow Peak",
			center = Vector2.new(-930, -1720),
			radius = Vector2.new(660, 560),
			base = 36,
			hills = { { 22, 150 }, { 6, 45 } },
			peak = { center = Vector2.new(-1000, -1820), radius = 470, height = 400, power = 1.25 },
			snowLine = 70, -- everything above this is snow
			materials = { top = "Snow", alt = "Glacier", cliff = "Slate", beach = "Snow" },
			hayType = "snow",
			style = { accent = Color3.fromRGB(112, 150, 178), fog = Color3.fromRGB(209, 219, 230), density = 0.04 },
		},
		{
			id = "volcano",
			name = "Volcano",
			center = Vector2.new(1030, -1460),
			radius = Vector2.new(590, 510),
			base = 18,
			hills = { { 10, 120 } },
			peak = { center = Vector2.new(1080, -1520), radius = 430, height = 340, power = 1.15, crater = 95, craterDepth = 70 },
			lavaRivers = true,
			materials = { top = "Basalt", alt = "Rock", cliff = "Basalt", beach = "Basalt" },
			hayType = "volcano",
			style = { accent = Color3.fromRGB(150, 70, 40), fog = Color3.fromRGB(150, 130, 120) },
		},
		{
			id = "desert",
			name = "Desert Dunes",
			center = Vector2.new(1290, -440),
			radius = Vector2.new(640, 480),
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
			center = Vector2.new(1120, 470),
			radius = Vector2.new(620, 380),
			base = 1.5,
			hills = { { 3.5, 60 } },
			pools = { level = -0.5, threshold = -0.18, scale = 55 }, -- low spots fill with bog water
			materials = { top = "Mud", alt = "LeafyGrass", cliff = "Ground", beach = "Mud" },
			hayType = "swamp",
			style = { accent = Color3.fromRGB(153, 173, 71), fog = Color3.fromRGB(153, 163, 143), density = 0.08 },
		},
		{
			id = "keys",
			name = "Thimble Keys",
			center = Vector2.new(3100, -200),
			radius = Vector2.new(430, 360),
			base = 4,
			hills = { { 9, 120 } },
			islets = true, -- broken up into keys by a channel noise
			materials = { top = "LeafyGrass", alt = "Sand", cliff = "Sandstone", beach = "Salt" },
			hayType = "keys",
			style = { accent = Color3.fromRGB(64, 132, 140), fog = Color3.fromRGB(196, 214, 216) },
		},
		{
			id = "bobbin",
			name = "Bobbin Rock",
			center = Vector2.new(2760, -1860),
			radius = Vector2.new(280, 260),
			base = 10,
			hills = { { 10, 60 } },
			peak = { center = Vector2.new(2790, -1890), radius = 230, height = 170, power = 0.8 },
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
		{ name = "HomesteadPlaza", min = Vector2.new(-130, -1560), max = Vector2.new(130, -1380), height = 8, blend = 60, material = "Cobblestone" },
		{ name = "ZeppelinField", min = Vector2.new(260, -1790), max = Vector2.new(380, -1660), height = 8, blend = 40 },
		{ name = "SkiLodge", min = Vector2.new(-700, -1640), max = Vector2.new(-600, -1560), height = 46, blend = 50 },
		{ name = "Lighthouse", min = Vector2.new(390, 830), max = Vector2.new(450, 890), height = 6, blend = 30 },
		{ name = "TailorShack", min = Vector2.new(-270, 640), max = Vector2.new(-230, 680), height = 4, blend = 30 },
		{ name = "PineMill", min = Vector2.new(-1240, 160), max = Vector2.new(-1180, 220), height = 18, blend = 40 },
		{ name = "Pyramid", min = Vector2.new(1440, -640), max = Vector2.new(1560, -520), height = 10, blend = 50 },
		{ name = "Oasis", min = Vector2.new(1160, -330), max = Vector2.new(1240, -250), height = 6, blend = 40 },
		{ name = "Quarry", min = Vector2.new(690, -1350), max = Vector2.new(790, -1250), height = 30, blend = 50 },
		{ name = "Wreck", min = Vector2.new(-1800, -900), max = Vector2.new(-1730, -820), height = -2, blend = 30 },
		{ name = "SwampPort", min = Vector2.new(1640, 470), max = Vector2.new(1730, 570), height = 3, blend = 40 },
		{ name = "AshDock", min = Vector2.new(1540, -1280), max = Vector2.new(1630, -1170), height = 3, blend = 40 },
		{ name = "KeysHarbor", min = Vector2.new(2780, 20), max = Vector2.new(2880, 130), height = 3, blend = 40 },
		{ name = "BobbinPier", min = Vector2.new(2510, -1840), max = Vector2.new(2570, -1760), height = 3, blend = 30 },
		{ name = "Workshop", min = Vector2.new(2760, -1920), max = Vector2.new(2820, -1860), height = 182, blend = 40 },
		-- A terrace above the Bobbin Track for the rock's only hay field (the rest of the rock is too steep).
		{ name = "BobbinFields", min = Vector2.new(2793, -1686), max = Vector2.new(2825, -1658), height = 14, blend = 24 },
		{ name = "HighwayWest", min = Vector2.new(1800, -460), max = Vector2.new(1880, -380), height = 3, blend = 40 },
		{ name = "HighwayEast", min = Vector2.new(2720, -330), max = Vector2.new(2800, -250), height = 3, blend = 40 },
	} :: { FlatZone }),

	-- Sea lanes kept deep so a ferry never scrapes the bottom (min depth along a line).
	Channels = {
		{ from = Vector2.new(1860, 500), to = Vector2.new(2720, 100), width = 90, depth = -22 },
		{ from = Vector2.new(1740, -1300), to = Vector2.new(2420, -1740), width = 90, depth = -22 },
	},

	-- Dirt roads, leveled into the land and joined to Meadow's two exits (Meadow.luau North and South end there).
	-- A road's height follows the land, smoothed and kept gentle enough to drive a loaded truck up.
	RoadWidth = 16,
	MaxGrade = 0.14, -- rise per stud along a road
	Roads = {
		{
			name = "North Road", -- Meadow's north exit, past Mirror Lake and the Spindle, into Homestead
			points = {
				Vector2.new(-30, -512), Vector2.new(-30, -620), Vector2.new(90, -760), Vector2.new(170, -900),
				Vector2.new(190, -1080), Vector2.new(120, -1260), Vector2.new(0, -1330), Vector2.new(0, -1390),
			},
		},
		{
			name = "Shore Road", -- Meadow's south exit along the coast: west to Pine Forest, east to the Swamp
			points = {
				Vector2.new(150, 512), Vector2.new(150, 640), Vector2.new(-60, 700), Vector2.new(-420, 690),
				Vector2.new(-760, 560), Vector2.new(-980, 380), Vector2.new(-1150, 160),
			},
		},
		{
			name = "Swamp Road",
			points = {
				Vector2.new(150, 640), Vector2.new(420, 700), Vector2.new(700, 620), Vector2.new(960, 520),
				Vector2.new(1300, 520), Vector2.new(1560, 520), Vector2.new(1700, 520),
			},
		},
		{
			name = "Pine Road", -- Pine Forest north through Haunted Grove to Homestead
			points = {
				Vector2.new(-1150, 160), Vector2.new(-1200, -120), Vector2.new(-1180, -420), Vector2.new(-1120, -760),
				Vector2.new(-900, -1060), Vector2.new(-620, -1300), Vector2.new(-360, -1420), Vector2.new(-125, -1400),
			},
		},
		{
			name = "Wreck Lane",
			points = { Vector2.new(-1120, -760), Vector2.new(-1500, -840), Vector2.new(-1730, -860) },
		},
		{
			name = "Snow Road",
			points = { Vector2.new(-620, -1300), Vector2.new(-640, -1460), Vector2.new(-650, -1595) },
		},
		{
			name = "Volcano Road", -- Homestead east to the quarry, then round the volcano's foot to Ash Dock
			points = {
				Vector2.new(130, -1445), Vector2.new(230, -1450), Vector2.new(460, -1420), Vector2.new(620, -1300), Vector2.new(690, -1245),
				Vector2.new(760, -1120), Vector2.new(980, -1020), Vector2.new(1260, -1010), Vector2.new(1480, -1150),
				Vector2.new(1585, -1225),
			},
		},
		{
			name = "Desert Road", -- from the North Road east across the desert to the highway
			points = {
				Vector2.new(90, -760), Vector2.new(420, -640), Vector2.new(760, -560), Vector2.new(1060, -500),
				Vector2.new(1300, -380), Vector2.new(1600, -420), Vector2.new(1840, -420),
			},
		},
		{
			name = "Dune Cut", -- desert south to the swamp
			points = { Vector2.new(1300, -380), Vector2.new(1240, -60), Vector2.new(1180, 250), Vector2.new(1300, 520) },
		},
		{
			name = "Pyramid Track",
			points = { Vector2.new(1600, -420), Vector2.new(1500, -520) },
		},
		{
			name = "Zeppelin Lane",
			points = { Vector2.new(120, -1545), Vector2.new(200, -1580), Vector2.new(320, -1640), Vector2.new(320, -1680) },
		},
		{
			name = "Keys Road", -- off the highway, across Thimble Keys to the harbor
			points = {
				Vector2.new(2760, -290), Vector2.new(2960, -300), Vector2.new(3160, -200), Vector2.new(3080, 20),
				Vector2.new(2880, 75),
			},
		},
		{
			name = "Cave Lane", -- off the North Road, west round the Spindle's south foot to the Crystal Cave mouth
			points = {
				Vector2.new(-30, -600), Vector2.new(-200, -760), Vector2.new(-320, -900), Vector2.new(-338, -948),
			},
		},
		{
			name = "Bobbin Track", -- from the Bobbin Rock pier round the rock's low south shore (the top is a climb)
			points = {
				Vector2.new(2544, -1800), Vector2.new(2615, -1715), Vector2.new(2706, -1659), Vector2.new(2811, -1645),
				Vector2.new(2913, -1677), Vector2.new(2984, -1739),
			},
		},
	},

	-- The Longstitch Highway: a bridge from the desert coast, the Midway Rest Stop, then an undersea tunnel up onto
	-- Thimble Keys. Built from parts; the terrain under it stays sea.
	-- Its height along X is the Profile (x, deck top), straight-line between the points.
	Highway = {
		width = 22,
		from = Vector2.new(1840, -420),
		to = Vector2.new(2720, -290),
		Profile = { { 1840, 3 }, { 1900, 10 }, { 2180, 10 }, { 2440, -24 }, { 2520, -24 }, { 2720, 3 } },
		restStop = { x = 2050, size = Vector2.new(70, 60) }, -- a wide stretch of deck with a pump and a stall
		toll = 1905, -- X of the toll gate
		tubeTop = 12, -- the undersea tube's inside height
	},

	-- Ports. A ferry runs between two piers; each pier points out to sea along the route. Deck tops are at
	-- Ferry.DeckTop, level with the pier.
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
				a = { name = "Swamp Port", shore = Vector2.new(1700, 520), pierEnd = Vector2.new(1860, 500) },
				b = { name = "Keys Harbor", shore = Vector2.new(2860, 80), pierEnd = Vector2.new(2720, 100) },
			},
			{
				id = "bobbin_ferry",
				name = "Bobbin Rock Ferry",
				a = { name = "Ash Dock", shore = Vector2.new(1590, -1225), pierEnd = Vector2.new(1740, -1300) },
				b = { name = "Bobbin Rock", shore = Vector2.new(2550, -1800), pierEnd = Vector2.new(2420, -1740) },
			},
		},
	},

	-- The zeppelin from Homestead up to Sky Island. Same rules as a ferry, flying.
	Zeppelin = {
		name = "Sky Island Zeppelin",
		-- Deck-top centers at each stop: it lands on the Homestead field, and docks off the south edge of Sky Island
		-- beside a platform that runs onto the island.
		a = { name = "Zeppelin Field", pos = Vector3.new(320, 9, -1720) },
		b = { name = "Sky Island", pos = Vector3.new(380, 449, -1958) },
		Length = 64,
		Width = 30,
		Speed = 22,
		Dock = 25,
	},
	SkyIsland = { center = Vector2.new(380, -2240), radius = 220, top = 448, thickness = 150 },

	-- The cave under the Spindle: a tunnel from its west foot into a crystal cavern.
	Cave = {
		mouth = Vector3.new(-330, 26, -960),
		path = { Vector3.new(-290, 22, -965), Vector3.new(-240, 14, -980), Vector3.new(-180, 8, -1000) },
		chamber = { center = Vector3.new(-100, 10, -1010), radius = 70 },
		hayType = "cave",
	},

	-- Places worth finding (Services/Discoveries.luau): the first visit pays Prices.Discovery.landmark, stamps the
	-- map and fills a collection page. at = the place (x, z); radius = how close counts. Every region (and Sky Island
	-- and the Crystal Cave) is a discovery too, worth Prices.Discovery.region. Set flat = a Flat zone's name to use
	-- its middle instead of at.
	Discoveries = ({
		{ id = "old_well", name = "The Old Well", at = Vector2.new(0, -1440), radius = 25 },
		{ id = "spindle_door", name = "The Spindle Door", at = Vector2.new(155, -990), radius = 40 },
		{ id = "observatory", name = "The Observatory", at = Vector2.new(30, -1080), radius = 40 },
		{ id = "mirror_lake", name = "Mirror Lake", at = Vector2.new(400, -880), radius = 170 },
		{ id = "lighthouse", name = "The Lighthouse", at = Vector2.new(420, 860), radius = 45 },
		{ id = "tailors_shack", name = "The Tailor's Shack", at = Vector2.new(-250, 660), radius = 40 },
		{ id = "wreck_bobbin", name = "Wreck of the Bobbin", at = Vector2.new(-1770, -860), radius = 60 },
		{ id = "ghost_isle", name = "Ghost Isle", at = Vector2.new(-2075, -780), radius = 50 },
		{ id = "ski_lodge", name = "Snow Peak Lodge", at = Vector2.new(-650, -1625), radius = 50 },
		{ id = "crater_rim", name = "The Crater Rim", at = Vector2.new(1080, -1520), radius = 115 },
		{ id = "old_quarry", name = "The Old Quarry", at = Vector2.new(740, -1300), radius = 50 },
		{ id = "buried_pyramid", name = "The Buried Pyramid", at = Vector2.new(1500, -580), radius = 80 },
		{ id = "graveyard_of_ships", name = "Graveyard of Ships", at = Vector2.new(2150, -1560), radius = 300 },
		{ id = "weavers_workshop", name = "The Weaver's Workshop", flat = "Workshop", radius = 50 },
	} :: { Discovery }),

	-- Mirror Lake, north of Meadow. Low Tide drains it later; for now it is a calm lake with a dock.
	Lake = { center = Vector2.new(400, -880), radius = 130, depth = 18, level = 3 },
	Oasis = { center = Vector2.new(1200, -290), radius = 30, depth = 6, level = 5 },

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
		["Meadow Shore"] = 600,
		["Mirror Lake Valley"] = 800,
		["Homestead Valley"] = 700,
		["The Spindle"] = 400,
		["Pine Forest"] = 1100,
		["Haunted Grove"] = 800,
		["Snow Peak"] = 1100,
		["Volcano"] = 400,
		["Desert Dunes"] = 600,
		["Swamp"] = 800,
		["Thimble Keys"] = 800,
		["Bobbin Rock"] = 300,
		["Crystal Cave"] = 200,
		["Graveyard of Ships"] = 150,
		["Sky Island"] = 200,
		["Signs"] = 150,
		["Longstitch Highway"] = 400,
		["Ferries"] = 400,
		["Wilds"] = 300,
		["RoadPolish"] = 300,
		["HayWagon"] = 100,
		["Field bales"] = 400,
		["Lighting"] = 400, -- landmark lights at night (#26)
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
