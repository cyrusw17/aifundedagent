--!strict
-- Land plots, what can be built on them, and preset saves. Placeholders to tune from playtests.
-- Positions are world studs on Meadow Farm's flat ground (Y = 0). The flat zone, keep-clear rect and plot road that
-- make room for all this are in Meadow.luau ("Plots").
local Prices = require(script.Parent.Prices)
local Rustic = require(script.Parent.Rustic)
local PRICE = Prices.Plot -- every plot costs the same (Config/Prices explains why)
local TILES = Vector2.new(12, 10) -- and has the same grid

return {
	RefundShare = Prices.RefundShare, -- removing a piece gives back this share of its price

	-- Every plot is the same: the same price, the same grid of 6 stud conveyor tiles (tiles.X across by tiles.Y deep) and
	-- the same layout, so a save rebuilds the same on whichever free plot a player gets on any server. The six plot zones
	-- are laid out by the biome thread in Meadow.luau (Plots, 72 x 72 each, a lane at z = 156 between the two rows).
	-- open is the side facing the lane: the 8 stud strip with the sign, needle bin and SELL NEEDLES pad. Plots on the
	-- far side of the lane are the same plot turned around (Land.luau turns saved pieces with it).
	Plots = {
		{ zone = "plot_1", name = "Plot 1", price = PRICE, tiles = TILES, open = "S" },
		{ zone = "plot_2", name = "Plot 2", price = PRICE, tiles = TILES, open = "S" },
		{ zone = "plot_3", name = "Plot 3", price = PRICE, tiles = TILES, open = "S" },
		{ zone = "plot_4", name = "Plot 4", price = PRICE, tiles = TILES, open = "N" },
		{ zone = "plot_5", name = "Plot 5", price = PRICE, tiles = TILES, open = "N" },
		{ zone = "plot_6", name = "Plot 6", price = PRICE, tiles = TILES, open = "N" },
	},
	StripDepth = 8,
	-- The back ExpansionRows rows of every plot start locked; owners buy them one at a time at PlotExpansion each.
	ExpansionRows = 2,
	ExpansionPrice = Prices.PlotExpansion,
	SecondPlotPrice = Prices.SecondPlot, -- a save can own a second plot at this price
	PolisherPrice = Prices.Pieces.needle_polisher, -- the needle bin's polishing wheel (Machines bin.fitPolisher)
	BinDividersPrice = Prices.BinDividers, -- the needle bin's type dividers (Machines bin.splitByType)

	-- The land office, in Meadow.luau's LandOffice zone. Its open front faces north toward the main road.
	OfficeCenter = Vector3.new(-20, 0, 49),

	-- Everything an owner can build. size is tiles across (to the right of the facing direction) by tiles along it.
	-- Separators are the Machines.luau needle sorter; their id is the tier in Sorters.luau, which sets how many needles
	-- they find and how fast they work.
	Pieces = {
		{ id = "belt", kind = "belt", name = "Conveyor belt", price = Prices.Pieces.belt, size = { 1, 1 }, blurb = "One 6 stud tile. Rotate to turn corners." },
		{ id = "hay_buyer", kind = "buyer", name = "Hay buyer", price = Prices.Pieces.hay_buyer, size = { 1, 1 }, blurb = "Pays full price for sorted hay. Unsorted bales sell cheap." },
		{ id = "silo", kind = "silo", name = "Hay silo", price = Prices.Pieces.silo, size = { 2, 2 }, blurb = "Drop bales next to it. Feeds them out the front onto a belt, one at a time." },
		{ id = "parking", kind = "parking", name = "Parking pad", price = Prices.Pieces.parking, size = { 2, 8 }, blurb = "Your truck and trailer park here when you load in." },
		{ id = "hand_sieve", kind = "separator", name = "Hand sieve", price = Prices.Pieces.hand_sieve, size = { 1, 2 }, blurb = "Finds 15% of the needles. Slow but cheap." },
		{ id = "shaker_table", kind = "separator", name = "Shaker table", price = Prices.Pieces.shaker_table, size = { 1, 2 }, blurb = "Finds 35% of the needles." },
		{ id = "conveyor_sorter", kind = "separator", name = "Conveyor sorter", price = Prices.Pieces.conveyor_sorter, size = { 1, 2 }, blurb = "Finds 55% of the needles." },
		{ id = "magnet_drum", kind = "separator", name = "Magnet drum", price = Prices.Pieces.magnet_drum, size = { 1, 2 }, blurb = "Finds 75% of the needles." },
		{ id = "optical_sorter", kind = "separator", name = "Optical sorter", price = Prices.Pieces.optical_sorter, size = { 1, 2 }, blurb = "Finds 92% of the needles. The fastest." },
		{ id = "raised_belt", kind = "belt", level = 1, name = "Raised belt", price = Prices.Pieces.raised_belt, size = { 1, 1 }, blurb = "A belt on stilts, high enough for a loaded belt to run underneath." },
		{ id = "ramp_up", kind = "ramp", up = true, name = "Ramp up", price = Prices.Pieces.ramp_up, size = { 1, 2 }, blurb = "Two tiles long. Lifts loads from the ground belts up to raised belts." },
		{ id = "ramp_down", kind = "ramp", up = false, name = "Ramp down", price = Prices.Pieces.ramp_down, size = { 1, 2 }, blurb = "Two tiles long. Brings loads from raised belts back down to the ground." },
		{ id = "splitter", kind = "splitter", rule = "alternate", name = "Splitter", price = Prices.Pieces.splitter, size = { 1, 1 }, blurb = "Sends loads out its left and right sides in turn. Put belts on both sides." },
		{ id = "sort_splitter", kind = "splitter", rule = "sorted", name = "Sorted splitter", price = Prices.Pieces.sort_splitter, size = { 1, 1 }, blurb = "Sorted bales go left, everything else right, so unsorted hay can loop back to a sorter." },
		{ id = "display_wall", kind = "display", name = "Needle display", price = Prices.Pieces.display_wall, size = { 1, 1 }, blurb = "Show off your rarest needles. Click a peg to hang one from your pocket." },
		{ id = "alloy_mixer", kind = "mixer", name = "Alloy mixer", price = Prices.Pieces.alloy_mixer, size = { 1, 1 }, blurb = "Mixes two needle types from your pocket into an alloy block for blueprints. No belt needed." },
		{ id = "hay_press", kind = "press", name = "Hay press", price = Prices.Pieces.hay_press, size = { 1, 2 }, blurb = "Presses sorted bales into thatch blocks. Click a block to carry its thatch for blueprints." },
		-- Quest-only: free to build once the alien ritual is done (Config/Quests.luau), never sold.
		-- quest is the reward id (Quests.has) that unlocks the piece.
		{ id = "alien_collector", kind = "separator", name = "Alien Collector", price = 0, quest = "alien_collector", size = { 1, 2 }, blurb = "Sorts every needle at once while its beam is up, once a day. Earned from the alien offering." },
		{ id = "starbeam_collector", kind = "starbeam", name = "Starbeam Collector", price = 0, quest = "starbeam_collector", size = { 1, 1 }, blurb = "Pulls a bale of Star hay down onto its belt every few minutes. Earned from the alien offering." },
		-- Blueprints (LT2 style): place a see-through template, then fill it. Drop bales into it for thatch, or use
		-- needles from your pocket at it for iron, or thatch from a hay press. bales / needles / thatch is how much it takes.
		{ id = "blueprint_post", kind = "blueprint", shape = "post", name = "Fence post blueprint", price = Prices.Pieces.blueprint_post, size = { 1, 1 }, bales = 1, needles = 4, thatch = 1, blurb = "Fill with 1 bale or 1 thatch, or 4 needles for iron." },
		{ id = "blueprint_wall", kind = "blueprint", shape = "wall", name = "Wall blueprint", price = Prices.Pieces.blueprint_wall, size = { 1, 1 }, bales = 3, needles = 12, thatch = 4, blurb = "A wall along the back of the tile. Fill with 3 bales, 4 thatch or 12 needles." },
		{ id = "blueprint_floor", kind = "blueprint", shape = "floor", name = "Floor tile blueprint", price = Prices.Pieces.blueprint_floor, size = { 1, 1 }, bales = 2, needles = 8, thatch = 2, blurb = "Fill with 2 bales, 2 thatch or 8 needles." },
	},

	-- Plot themes: free looks for the fence, the sign and two lamps at the lane corners. The first is the default.
	-- style "rails" is a post-and-rail fence, "wall" a low dry-stone wall. Every color is from the Rustic palette.
	Themes = ({
		{
			id = "rustic", name = "Rustic",
			style = "rails", post = { color = Rustic.WoodDark, material = Enum.Material.Wood }, rail = { color = Rustic.Wood, material = Enum.Material.WoodPlanks },
			board = { color = Rustic.Wood, material = Enum.Material.WoodPlanks }, lamp = { color = Rustic.WoodDark, material = Enum.Material.Wood },
		},
		{
			id = "whitewash", name = "Whitewashed",
			style = "rails", post = { color = Rustic.PaintCream, material = Enum.Material.WoodPlanks }, rail = { color = Rustic.PaintCream, material = Enum.Material.WoodPlanks },
			board = { color = Rustic.PaintGreen, material = Enum.Material.WoodPlanks }, lamp = { color = Rustic.PaintGreen, material = Enum.Material.Metal },
		},
		{
			id = "fieldstone", name = "Fieldstone",
			style = "wall", post = { color = Rustic.StoneDark, material = Enum.Material.Slate }, rail = { color = Rustic.Stone, material = Enum.Material.Cobblestone },
			board = { color = Rustic.WoodDark, material = Enum.Material.WoodPlanks }, lamp = { color = Rustic.Metal, material = Enum.Material.Metal },
		},
		{
			id = "ironworks", name = "Ironworks",
			style = "rails", post = { color = Rustic.Metal, material = Enum.Material.Metal }, rail = { color = Rustic.Metal, material = Enum.Material.Metal },
			board = { color = Rustic.PaintBlue, material = Enum.Material.Metal }, lamp = { color = Rustic.Metal, material = Enum.Material.Metal },
		},
		{
			id = "barnyard", name = "Barn red",
			style = "rails", post = { color = Rustic.PaintRedDark, material = Enum.Material.WoodPlanks }, rail = { color = Rustic.PaintRed, material = Enum.Material.WoodPlanks },
			board = { color = Rustic.PaintCream, material = Enum.Material.WoodPlanks }, lamp = { color = Rustic.PaintRedDark, material = Enum.Material.Wood },
		},
	} :: { any }),

	SiloCapacity = 60, -- bales
	SiloFeedSeconds = 3, -- one bale out every this many seconds while the belt in front is clear

	-- Preset saves: an empty save slot for these players starts as this farm instead of from nothing.
	-- items are in plot tiles (from 0) as seen with the lane to the south: gx left to right, gz from the back fence to the
	-- lane, dir the way each piece faces. plot is only the plot to try first; any free plot works the same.
	Presets = {
		{
			userIds = { 11803361702 }, -- Cyrus
			cash = 25000,
			trucks = { "rusty_pickup" },
			trailers = { "wagon_trailer" },
			land = {
				owned = true,
				plot = 4,
				expansions = 2, -- the whole plot
				items = ({
					-- Silo -> belts -> magnet drum -> belts -> hay buyer, along the back fence.
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
					-- Truck and hitched trailer park near the right fence, facing the lane, with the driver's door on the
					-- free column 11, so getting out stays inside the fence.
					{ id = "parking", gx = 10, gz = 2, dir = "S" },
				} :: { any }),
			},
		},
	},
}
