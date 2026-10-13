--!strict
-- Every price in Needlewood, in one place. Shops, sorters, the land office, the dealer, the glove stand and the bank all
-- read their numbers from here, so changing a price means changing one line.
--
-- docs/ECONOMY.md explains why each number is what it is, and tools/economy_model.py re-derives the tables behind it.
-- The short version: a Meadow bale is worth $47 raw, a player hauls about 2.3 bales a minute by hand (about $6,500 an
-- hour), and every price is set from how long it takes to earn at the stage where you would buy it, and how fast it
-- pays you back.
local Prices = {}

-- Selling -----------------------------------------------------------------------------------------------------------

Prices.HayPerBale = 90 -- straw strands in one bale (Config/Game PiecesPerBale x HayPerPiece)
Prices.HayPrice = 0.5 -- dollars per strand, at the public shop and at your own hay buyer
Prices.RawNeedlePrice = 1 -- the public shop finds the needles in your hay but only pays this for each

-- A needle you spot and pick up yourself (one that tumbled out of a broken bale) pays this share of its sorted value.
-- Full value: it is rare and it is the first thing that shows a new player what sorting is worth.
Prices.HandFoundNeedleShare = 1
-- When a bale breaks, this share of its hidden needles tumbles out where you can see it. The rest stay in the hay.
Prices.VisibleNeedleShare = 0.25

-- Hidden needles per bale, by hay type (ids from Config/Gloves HayTypes). Richer hay pays twice: more needles, and
-- pricier needles. Meadow's 2 keeps a sorted bale worth 1.6x to 4.9x a raw one instead of 25x.
Prices.NeedlesPerBale = {
	meadow = 2,
	pine = 3,
	desert = 4,
	snow = 5,
	swamp = 6,
	volcano = 8,
	cave = 10,
	sky = 12,
	haunted = 14,
	star = 20,
}

-- Sorted needle value by needle id (Config/Needles). What the SELL NEEDLES pad pays for each.
Prices.Needles = {
	steel = 100,
	pine = 110,
	sand = 140,
	ice = 160,
	bog = 170,
	obsidian = 300,
	geode = 340,
	cloud = 700,
	phantom = 800,
	cosmic = 5000,
}

-- Finder's rewards for foreign objects in hay (Config/Finds, by id), paid once for the first of each kind. About $1
-- for every bale it takes on average to turn one up (Finds oneIn), with the two rarest doubled because they are the
-- finds players talk about. They are a moment, not an income: all six together are under an hour of pickup earnings.
Prices.FinderRewards = {
	boot = 50, -- 1 in 50 bales
	horseshoe = 150, -- 1 in 150
	key = 300, -- 1 in 300
	radio = 600, -- 1 in 600
	ring = 1500, -- 1 in 1,000, doubled
	fossil = 4000, -- 1 in 2,000, doubled
}

-- NPC buyer orders (Services/Orders.luau). Three local buyers post an order each, new ones every RotateSeconds. Every
-- unit delivered pays at once: its normal price times mult, up to the order's amount per player. Plain bales pay 1.5x
-- the public shop ($71 a bale), sorted bales 2x their hay ($90, double what a hay buyer pays, since the sorting is
-- done), and steel needles 1.25x list ($125). A full order is worth a few hundred to a thousand dollars over selling
-- normally: a 5 to 10 minute bonus at the pickup stage, and a reason to haul somewhere other than your own line.
Prices.Orders = {
	RotateSeconds = 1200,
	Buyers = { "Miller Joe", "Widow Hale", "Old Tobias", "Mabel at the feed store", "The Thatcher twins", "Pastor Reed" },
	Kinds = {
		bales = { amount = { 8, 16 }, mult = 1.5 },
		sorted = { amount = { 10, 20 }, mult = 2 },
		needles = { amount = { 6, 15 }, mult = 1.25 },
	},
}

-- The needle market (Services/Market.luau). Each server's needle prices drift up to Swing either side of the list price:
-- selling a type pushes its price down, and the push fades with HalfLifeSeconds. NormalSales recent steel sales (about a
-- solo shaker-table farm's pace) is exactly list price; rarer types need proportionally fewer, but never under
-- MinNormalSales. A quiet type pays up to 20% more, which nudges players toward regions nobody is farming.
Prices.Market = {
	Swing = 0.2,
	HalfLifeSeconds = 600,
	NormalSales = 40,
	MinNormalSales = 5,
}

-- Buying ------------------------------------------------------------------------------------------------------------

-- Trucks, at Homestead Motors. Each costs one to two hours of what you earn at the stage before it, so it is a real
-- goal, and the bank finances any of them with 20% down. The pickup is priced like a real used pickup on purpose: you
-- can't pay cash for it in your first 15 minutes, but you can put $1,200 down.
Prices.Trucks = {
	rusty_pickup = 6000,
	farm_flatbed = 25000,
	box_truck = 90000,
	heavy_hauler = 350000,
	semi_rig = 1500000,
}

-- Trailers cost about a quarter to a third of the truck that pulls them, like a real hitch-on trailer.
Prices.Trailers = {
	wagon_trailer = 1500,
	small_trailer = 8000,
	medium_trailer = 30000,
	large_trailer = 120000,
	bale_rack_trailer = 200000,
}

-- The wheelbarrow carries 3 bales a push: about 4.7 bales a minute to the sell pad, double what you carry by hand.
-- Doubling your income should cost about 10 minutes of hand hauling, so it lands about 12 minutes in, between Work
-- Gloves and the pickup (docs/ECONOMY.md).
Prices.Wheelbarrow = 1000

-- Gloves (Config/Gloves Tiers, by id). Each pair costs about 30 minutes of what you earn just before you need it for
-- the next region's heavier hay. Work Gloves are the first purchase, two or three minutes in.
Prices.Gloves = {
	bare = 0,
	work = 250,
	leather = 8000,
	reinforced = 45000,
	iron = 75000,
	starlight = 400000,
}

-- A land plot (Config/Land). Every plot is the same 12 x 10 tiles, and a save owns one. It is the first land goal, at
-- about 45 minutes in: roughly 15 minutes of pickup earnings once the pickup and wagon are paid for, or $500 down
-- with a land loan. With a hand sieve and a short line ($3,600 in all) it lifts a bale from $47 to $75.
Prices.Plot = 2500
-- Each extra row of 12 tiles at the back of a plot (two rows to buy). A new plot's 96 tiles hold a first line easily;
-- the extra rows matter when you add a second line around the shaker-table stage, so a row costs about 12 minutes of
-- earnings there. That is $417 a tile against the plot's $26, because by then you are buying room for income, not land.
Prices.PlotExpansion = 5000
-- A second farm per save. Hauling, not sorting, limits income at almost every stage, so a second plot buys room more
-- than money. It comes after the first plot is built out (plot + rows + conveyor sorter is about $37,500) and takes one
-- of a server's six plots, so it is a mid-game commitment: about 90 minutes at the conveyor-sorter stage.
Prices.SecondPlot = 60000
Prices.BinDividers = 1500 -- splits a plot's needle bin into one corner per needle type: tidiness, so cheap (ECONOMY.md)

-- Things you build on your land (Config/Land Pieces, by id). Removing one refunds RefundShare of its price.
-- Sorters are priced from the V8 payback targets: the hand sieve pays back in about 9 minutes, the shaker 15, the
-- conveyor sorter 30, the magnet drum about 75, and the optical sorter about 3.5 hours (Meadow hay, kept full).
Prices.Pieces = {
	belt = 25,
	hay_buyer = 400,
	parking = 250,
	silo = 5000,
	hand_sieve = 500,
	shaker_table = 4000,
	conveyor_sorter = 25000,
	magnet_drum = 175000,
	optical_sorter = 1100000,
	-- Blueprints are cheap templates; what you fill them with (bales or needles) is the real cost.
	blueprint_post = 10,
	blueprint_wall = 10,
	blueprint_floor = 10,
	-- Conveyor thread pieces: belt-priced fittings, a display that is pure pride, and a press that sells nothing
	-- (thatch is for building), so it is priced like a mid-game toy rather than from a payback.
	raised_belt = 60, -- a belt on the upper level, so one line can cross another
	ramp_up = 150,
	ramp_down = 150,
	splitter = 300,
	sort_splitter = 600,
	display_wall = 1000,
	hay_press = 8000,
	needle_vault = 6000, -- holds any number of needles with no parts; pure storage, so priced like a mid-game comfort
	hay_baler = 3000, -- packs raked or scooped strands back into bales: a convenience, so a cheap early buy
	needle_polisher = 12000,
	alloy_mixer = 20000,
	garage = 2000, -- swaps which owned truck is out; a convenience, so priced like a mid-early piece
	hay_barn = 15000, -- holds 150 bales to the silo's 60, so a long line can run unattended longer
	-- Decor (Land): looks only, no stats. Small cash sinks that make a farm worth visiting.
	decor_flowers = 200,
	decor_bench = 350,
	decor_lantern = 500,
	decor_scarecrow = 900,
	-- Late-game decor: pure show for players with money to spare (Economy: $10k-$50k sinks).
	decor_fountain = 15000,
	decor_windmill = 45000,
}
Prices.RefundShare = 0.5

-- The Starbeam Collector (alien gauntlet reward): beams one Star hay bale onto its belt every this many minutes.
-- A Star bale hides NeedlesPerBale.star Cosmic needles, so this is the richest feed in the game; tune with care.
Prices.Starbeam = {
	minutes = 10,
}

-- A needle polisher on a bin polishes needles that land in it: each sells for this much more. It works through
-- PolishPerMinute needles a minute; the rest stay plain.
Prices.PolishBonus = 0.25
Prices.PolishPerMinute = 30

-- Sorter oil: click the oil can on any sorter. A flat price, so it is a small treat on a cheap sorter and pocket
-- change on a big one; it only pays when the sorter is what holds the line back.
Prices.SorterOil = {
	price = 250,
	bales = 25, -- the next this many bales sort faster
	speedup = 0.1, -- 10% faster
	maxBales = 75, -- at most three cans stacked
}

-- Sorter speeds, in bales a minute (Config/Sorters turns them into hay per minute). Each tier doubles the last.
Prices.SorterBalesPerMinute = {
	hand_sieve = 2,
	shaker_table = 4,
	conveyor_sorter = 8,
	magnet_drum = 16,
	optical_sorter = 30,
}

-- Travel fares for the rest of the Stitched Isles (for the world map thread; nothing reads them yet). A fare is a small
-- share of what the trip carries, so it is felt but never decides whether a trip is worth it. Roads, including the
-- Longstitch Highway, stay free.
Prices.Travel = {
	ferry = 250, -- public ferry, per truck with its trailer, each way: under 5% of a box-truck load of Snow hay
	barge = 0, -- the Captain's Barge is earned by quest and free to use
	zeppelin = 1000, -- to Sky Island, per trip: under 5% of a pickup load of Sky hay
}

-- Robux store prices in Robux (V8 Part C). Recorded here so every price is in one place; the store itself waits until
-- the cash economy has been playtested. Paid trucks match their cash tier's stats exactly, and nothing is random.
Prices.Robux = {
	Trucks = {
		homestead_classic = 399, -- skin of the Rusty Pickup tier
		timber_wolf = 799, -- Farm Flatbed tier
		midnight_express = 1199, -- Box Truck tier
		prairie_schooner = 1799, -- Heavy Hauler tier
		founders_semi = 2499, -- Semi tier, launch edition
	},
	Passes = {
		vip = 249,
		auto_dock = 299,
		big_silo = 199,
		paint_studio = 149,
		plot_themes = 199,
		truck_radio = 99,
	},
	HarvestPass = 499,
	ServerBoost = 99,
	PrivateServer = 100, -- a month
}

-- The bank -----------------------------------------------------------------------------------------------------------

Prices.Bank = {
	-- Savings interest is paid every InterestSeconds of play, but only if you sold something in that time, so it
	-- rewards saving while you work and never pays an idle player. Tiered like a real savings account, but upside
	-- down: the first $10,000 earns the most, so it helps a new farm and stays small next to a big farm's income.
	InterestSeconds = 600,
	InterestTiers = {
		{ upTo = 10000, rate = 0.01 },
		{ upTo = 100000, rate = 0.005 },
	},

	-- Loans. You pick what you are financing, put DownPayment of its price in the bank yourself, and the bank lends
	-- the rest. Interest is one flat fee added up front, so "borrow $4,800, pay back $5,280" is the whole deal.
	-- Repayment comes out of your sales automatically (repayShare of each one) until it is paid; there are no due
	-- dates and no penalties, and you can pay the rest off early at any time.
	DownPayment = 0.2,
	Loans = {
		truck = { name = "Truck loan", interest = 0.10, repayShare = 0.25, blurb = "Trucks and trailers" },
		land = { name = "Land loan", interest = 0.08, repayShare = 0.20, blurb = "Land plots" },
	},
	-- How much you can owe in total: a base line of credit plus twice everything you have ever earned.
	CreditBase = 5000,
	CreditPerEarned = 2,

	HistoryLength = 40, -- transactions kept per save slot
}

-- Hidden needles per strand of a hay type, for the rolls in Economy.rollNeedles.
function Prices.needleChance(hayType: string?): number
	local perBale = Prices.NeedlesPerBale[hayType or "meadow"] or Prices.NeedlesPerBale.meadow
	return perBale / Prices.HayPerBale
end

return Prices
