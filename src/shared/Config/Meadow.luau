--!strict
-- Meadow Farm, the starting biome. Everything the terrain script and the scatter need lives here so the layout can be
-- tuned without touching code. Positions are world studs on the ground (Y is the flat ground level, 0).
-- North is -Z (the way a new player faces), east is +X.
return {
	-- Change Version whenever the layout or noise changes. A place that was baked in Studio with an older version
	-- gets regenerated when you press Play.
	Version = 2,
	Seed = 7, -- shifts the noise; same seed always gives the same hills

	HalfSize = 512, -- the biome is 1024 x 1024 studs, centered on base camp
	EdgeStart = 400, -- hills start rising here so the biome feels closed in
	EdgeHeight = 55,
	Bottom = -24, -- lowest terrain written
	Top = 96, -- highest terrain written

	-- Rolling meadow hills: amplitude in studs and scale (bigger scale = wider hills)
	Hills = {
		{ amplitude = 14, scale = 220 },
		{ amplitude = 4, scale = 70 },
	},
	BaseHeight = 3,

	-- Ground kept flat (height 0) so buildings, pads and the trailer path sit on it. Rects are min/max X and Z;
	-- blend is how far the hills take to rise again.
	Flat = {
		{ name = "BaseCamp", min = Vector2.new(-45, -40), max = Vector2.new(45, 32), blend = 40 },
		{ name = "StarterBase", min = Vector2.new(40, -58), max = Vector2.new(100, 8), blend = 30 },
		{ name = "TrailerTurn", min = Vector2.new(84, -82), max = Vector2.new(132, -26), blend = 30 },
		{ name = "TrailerRoad", min = Vector2.new(108, -82), max = Vector2.new(132, 180), blend = 30 },
		{ name = "Dealer", min = Vector2.new(-190, -70), max = Vector2.new(-55, 50), blend = 40 },
		{ name = "LandOffice", min = Vector2.new(-45, 30), max = Vector2.new(5, 66), blend = 30 },
		{ name = "Plots", min = Vector2.new(-155, 70), max = Vector2.new(103, 240), blend = 30 },
	},

	-- Dirt roads, painted into the terrain and leveled. Each is a list of points.
	RoadWidth = 14,
	Roads = {
		{ name = "Main", points = { Vector2.new(-120, 26), Vector2.new(120, 26) } },
		{ name = "PlotRoad", points = { Vector2.new(18, 26), Vector2.new(18, 236) } },
		{ name = "PlotLane", points = { Vector2.new(-150, 156), Vector2.new(98, 156) } },
		{ name = "North", points = { Vector2.new(0, -36), Vector2.new(0, -200), Vector2.new(-30, -330), Vector2.new(-30, -512) } },
		{ name = "South", points = { Vector2.new(120, 26), Vector2.new(120, 260), Vector2.new(150, 380), Vector2.new(150, 512) } },
	},
	-- Where a road leaves the biome: a closed gate until the next map exists.
	Gates = {
		{ at = Vector2.new(-30, -490), facing = Vector2.new(0, 1), text = "HOMESTEAD VALLEY\nCOMING SOON" },
		{ at = Vector2.new(150, 490), facing = Vector2.new(0, -1), text = "PINE FOREST\nCOMING SOON" },
	},

	Pond = { center = Vector2.new(-250, 200), radius = 46, depth = 10, waterLevel = -1.5 },

	-- Places hay bales and trees keep away from, with a margin. Rects are min/max X and Z.
	KeepClear = {
		{ min = Vector2.new(-40, -32), max = Vector2.new(40, 22) }, -- base camp: spawn, hay shop, sell pad, drop-off
		{ min = Vector2.new(40, -56), max = Vector2.new(100, 6) }, -- starter base and conveyor line
		{ min = Vector2.new(84, -80), max = Vector2.new(132, -26) }, -- trailer turn
		{ min = Vector2.new(108, -80), max = Vector2.new(132, 180) }, -- trailer road
		{ min = Vector2.new(-185, -66), max = Vector2.new(-58, 44) }, -- truck dealer and its lot
		{ min = Vector2.new(-40, 36), max = Vector2.new(0, 62) }, -- land office
		{ min = Vector2.new(-150, 76), max = Vector2.new(98, 236) }, -- land plots and their lanes
	},
	BuildingMargin = 22, -- "not super close to things like the shop"
	RoadMargin = 10, -- from the road's center line
	MaxScatterHeight = 22, -- nothing on the tall edge hills

	-- Hay bales scattered over the meadow. The map is split into cells; each cell may get a small group.
	BaleCell = 36,
	BaleChance = 0.22,
	BalesPerGroup = { 1, 3 },

	-- Decoration
	TreeCount = 90,
	RockCount = 45,

	-- The truck dealer. Its front (shop entrance and garage door) faces east toward base camp.
	DealerCenter = Vector3.new(-150, 0, 6),

	-- Land you can buy (built by the land shop thread). The office faces north toward the main road and spawn.
	-- Plots are 72 x 72 and flat; a lane runs between the two rows and a road links them to the main road.
	LandOffice = { min = Vector2.new(-40, 36), max = Vector2.new(0, 62), facing = Vector2.new(0, -1) },
	Plots = {
		{ id = "plot_1", min = Vector2.new(-150, 76), max = Vector2.new(-78, 148) },
		{ id = "plot_2", min = Vector2.new(-62, 76), max = Vector2.new(10, 148) },
		{ id = "plot_3", min = Vector2.new(26, 76), max = Vector2.new(98, 148) },
		{ id = "plot_4", min = Vector2.new(-150, 164), max = Vector2.new(-78, 236) },
		{ id = "plot_5", min = Vector2.new(-62, 164), max = Vector2.new(10, 236) },
		{ id = "plot_6", min = Vector2.new(26, 164), max = Vector2.new(98, 236) },
	},
}
