--!strict
-- Land plots, what can be built on them, and preset saves. Placeholders to tune from playtests.
-- Positions are world studs on Meadow Farm's flat ground (Y = 0). The flat zone, keep-clear rect and plot road that
-- make room for all this are in Meadow.luau ("Plots").
return {
	RefundShare = 0.5, -- removing a piece gives back this share of its price

	-- Every plot is a grid of 6 stud conveyor tiles: tiles.X across (east-west) by tiles.Z (north-south). corner is the
	-- ground corner with the lowest X and Z. Each plot also has an 8 stud strip on its north side with its sign, needle
	-- bin and SELL NEEDLES pad. The plot road runs south at x = 40, so west plots open east and east plots open west.
	Plots = {
		{ name = "Roadside Patch", price = 800, corner = Vector3.new(-16, 0, 56), tiles = Vector2.new(8, 8), open = "E" },
		{ name = "Fence Row", price = 1200, corner = Vector3.new(48, 0, 56), tiles = Vector2.new(9, 9), open = "W" },
		{ name = "Willow Lot", price = 2000, corner = Vector3.new(-28, 0, 116), tiles = Vector2.new(10, 10), open = "E" },
		{ name = "Creek Field", price = 3000, corner = Vector3.new(48, 0, 122), tiles = Vector2.new(9, 12), open = "W" },
		{ name = "Big Meadow", price = 6000, corner = Vector3.new(-52, 0, 188), tiles = Vector2.new(14, 14), open = "E" },
		{ name = "Homestead Acre", price = 5000, corner = Vector3.new(48, 0, 206), tiles = Vector2.new(10, 14), open = "W" },
	},
	StripDepth = 8,

	-- The land office, where plots are bought. Its open front faces north toward the main road.
	OfficeCenter = Vector3.new(14, 0, 40),

	-- Everything an owner can build. size is tiles across (to the right of the facing direction) by tiles along it.
	-- Separators are the Machines.luau needle sorter; their id is the tier in Sorters.luau, which sets how many needles
	-- they find and how fast they work.
	Pieces = {
		{ id = "belt", kind = "belt", name = "Conveyor belt", price = 20, size = { 1, 1 }, blurb = "One 6 stud tile. Rotate to turn corners." },
		{ id = "hay_buyer", kind = "buyer", name = "Hay buyer", price = 150, size = { 1, 1 }, blurb = "Pays full price for sorted hay. Unsorted bales sell cheap." },
		{ id = "silo", kind = "silo", name = "Hay silo", price = 3000, size = { 2, 2 }, blurb = "Drop bales next to it. Feeds them out the front onto a belt, one at a time." },
		{ id = "parking", kind = "parking", name = "Parking pad", price = 100, size = { 2, 6 }, blurb = "Your truck and trailer park here when you load in." },
		{ id = "hand_sieve", kind = "separator", name = "Hand sieve", price = 250, size = { 1, 2 }, blurb = "Finds 15% of the needles. Slow but cheap." },
		{ id = "shaker_table", kind = "separator", name = "Shaker table", price = 1500, size = { 1, 2 }, blurb = "Finds 35% of the needles." },
		{ id = "conveyor_sorter", kind = "separator", name = "Conveyor sorter", price = 5000, size = { 1, 2 }, blurb = "Finds 55% of the needles." },
		{ id = "magnet_drum", kind = "separator", name = "Magnet drum", price = 15000, size = { 1, 2 }, blurb = "Finds 75% of the needles." },
		{ id = "optical_sorter", kind = "separator", name = "Optical sorter", price = 50000, size = { 1, 2 }, blurb = "Finds 92% of the needles. The fastest." },
	},

	SiloCapacity = 60, -- bales
	SiloFeedSeconds = 3, -- one bale out every this many seconds while the belt in front is clear

	-- Preset saves: an empty save slot for these players starts as this farm instead of from nothing.
	-- items are in the plot's tiles (gx east, gz south, from its north-west corner); dir is the way each piece faces.
	Presets = {
		{
			userIds = { 11803361702 }, -- Cyrus
			cash = 25000,
			trucks = { "rusty_pickup" },
			trailers = { "wagon_trailer" },
			land = {
				owned = true,
				plot = 5, -- Big Meadow
				items = {
					-- Silo -> belts -> magnet drum -> belts -> hay buyer, along the north side.
					{ id = "silo", gx = 1, gz = 1, dir = "E", stored = 20 },
					{ id = "belt", gx = 3, gz = 1, dir = "E" },
					{ id = "belt", gx = 4, gz = 1, dir = "E" },
					{ id = "magnet_drum", gx = 5, gz = 1, dir = "E" },
					{ id = "belt", gx = 7, gz = 1, dir = "E" },
					{ id = "belt", gx = 8, gz = 1, dir = "E" },
					{ id = "hay_buyer", gx = 9, gz = 1, dir = "E" },
					-- A second, cheaper line for hand-fed bales.
					{ id = "belt", gx = 3, gz = 5, dir = "E" },
					{ id = "shaker_table", gx = 4, gz = 5, dir = "E" },
					{ id = "belt", gx = 6, gz = 5, dir = "E" },
					{ id = "hay_buyer", gx = 7, gz = 5, dir = "E" },
					-- Truck and hitched trailer park along the south side, facing the road.
					{ id = "parking", gx = 6, gz = 10, dir = "E" },
				},
			},
		},
	},
}
