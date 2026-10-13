--!strict
-- Land plots, what can be built on them, and preset saves. Placeholders to tune from playtests.
-- Positions are world studs on Meadow Farm's flat ground (Y = 0). The flat zone, keep-clear rect and plot road that
-- make room for all this are in Meadow.luau ("Plots").
return {
	RefundShare = 0.5, -- removing a piece gives back this share of its price

	-- The six plot zones are laid out by the biome thread in Meadow.luau (Plots, 72 x 72 each, a lane at z = 156 between
	-- the two rows). Each plot here fills one zone with a grid of 6 stud conveyor tiles, tiles.X east-west by tiles.Y
	-- north-south, plus an 8 stud strip along the lane side (open) with its sign, needle bin and SELL NEEDLES pad.
	-- The rest of the zone stays grass, so plots differ in size as well as price.
	Plots = {
		{ zone = "plot_1", name = "Roadside Patch", price = 800, tiles = Vector2.new(8, 8), open = "S" },
		{ zone = "plot_2", name = "Fence Row", price = 1500, tiles = Vector2.new(10, 8), open = "S" },
		{ zone = "plot_3", name = "Willow Lot", price = 2500, tiles = Vector2.new(10, 10), open = "S" },
		{ zone = "plot_4", name = "Big Meadow", price = 6000, tiles = Vector2.new(12, 10), open = "N" },
		{ zone = "plot_5", name = "Creek Corner", price = 1200, tiles = Vector2.new(9, 9), open = "N" },
		{ zone = "plot_6", name = "Homestead Acre", price = 4000, tiles = Vector2.new(11, 10), open = "N" },
	},
	StripDepth = 8,

	-- The land office, in Meadow.luau's LandOffice zone. Its open front faces north toward the main road.
	OfficeCenter = Vector3.new(-20, 0, 49),

	-- Everything an owner can build. size is tiles across (to the right of the facing direction) by tiles along it.
	-- Separators are the Machines.luau needle sorter; their id is the tier in Sorters.luau, which sets how many needles
	-- they find and how fast they work.
	Pieces = {
		{ id = "belt", kind = "belt", name = "Conveyor belt", price = 20, size = { 1, 1 }, blurb = "One 6 stud tile. Rotate to turn corners." },
		{ id = "hay_buyer", kind = "buyer", name = "Hay buyer", price = 150, size = { 1, 1 }, blurb = "Pays full price for sorted hay. Unsorted bales sell cheap." },
		{ id = "silo", kind = "silo", name = "Hay silo", price = 3000, size = { 2, 2 }, blurb = "Drop bales next to it. Feeds them out the front onto a belt, one at a time." },
		{ id = "parking", kind = "parking", name = "Parking pad", price = 100, size = { 2, 8 }, blurb = "Your truck and trailer park here when you load in." },
		{ id = "hand_sieve", kind = "separator", name = "Hand sieve", price = 250, size = { 1, 2 }, blurb = "Finds 15% of the needles. Slow but cheap." },
		{ id = "shaker_table", kind = "separator", name = "Shaker table", price = 1500, size = { 1, 2 }, blurb = "Finds 35% of the needles." },
		{ id = "conveyor_sorter", kind = "separator", name = "Conveyor sorter", price = 5000, size = { 1, 2 }, blurb = "Finds 55% of the needles." },
		{ id = "magnet_drum", kind = "separator", name = "Magnet drum", price = 15000, size = { 1, 2 }, blurb = "Finds 75% of the needles." },
		{ id = "optical_sorter", kind = "separator", name = "Optical sorter", price = 50000, size = { 1, 2 }, blurb = "Finds 92% of the needles. The fastest." },
		-- Quest-only: free to build once the alien ritual is done (Config/Quests.luau), never sold.
		{ id = "alien_collector", kind = "separator", name = "Starbeam Collector", price = 0, quest = true, size = { 1, 2 }, blurb = "Finds every needle at once. Earned from the alien ritual." },
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
				plot = 4, -- Big Meadow
				items = ({
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
					-- Truck and hitched trailer park on the east side, facing north toward the lane.
					{ id = "parking", gx = 10, gz = 9, dir = "N" },
				} :: { any }),
			},
		},
	},
}
