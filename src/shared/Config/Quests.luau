--!nonstrict
-- Quests, rituals, daily bounties and the mystery items they unlock. Server and client both read this file; only the
-- server decides progress (src/server/Services/Quests.luau). Every number is a placeholder to tune from playtests.
--
-- Quest gear is earned, never sold: no cash or Robux price anywhere buys it (GAME_PLAN_V8 section 9).
--
-- Step kinds:
--   event   count game events (Events.luau kinds, plus bale_lifted). filter matches the event's info.
--   own     something the save owns right now: truck, plot, gloves_tier (value), piece_kind (value)
--   visit   walk up to a spot, or to every spot in `spots` (any order)
--   talk    press the prompt on a spot. distinct = counts once each time the spot has moved (the wandering scarecrow)
--   collect press the prompt on an item spot, or on every spot in `spots`
--   offer   press the prompt on a spot and pay: needles = { [needleId] = count } from your pocket, needlesEach = that
--           many of every needle type you can reach, cash = dollars
--   pattern hay bales standing on the spot's pads: "stones" (four stones) or "daily" (tonight's 3 x 3 sign).
--           The bales are taken when it completes.
--   find    a rare item that can drop when you break a bale: chance per bale, pity = guaranteed by this many bales
-- when = "day", "dusk", "night" or "midnight" limits a step to that part of the day (see Time below).
-- hint = one line shown under the current step in the quest log; place = a UI Places id (dealer, landoffice, plot...)
-- for steps that send you to a building rather than a quest spot, so GO and "Show the way" work there too.
-- Spots belong to a region. `pos` is a Meadow Farm spot; `world` (X, Z) is a spot out on the Stitched Isles, set on the
-- ground there once the world map is built. A spot whose region is not built yet stands at its `fallback` in Meadow,
-- or waits (its quest says "Opens when ... is built"). A part tagged "QuestAnchor" with attribute SpotId = a spot id
-- (and Region = the region name) moves that spot onto the part, for hand-placed spots in Studio.
-- showWhen = a time window: the spot is only visible then (its prompt still answers, with "come back at ...").
-- inMaze = placed by the corn maze it stands in, not by a position here.
local Quests = {}

-- The day and night cycle (src/server/Services/DayNight.luau). Hours are game hours, 0-24.
Quests.Time = {
	DayMinutes = 20, -- one full day and night in real minutes
	StartHour = 10,
	Windows = {
		day = { 6, 18 },
		dusk = { 17.5, 20 },
		night = { 19.5, 5.5 },
		midnight = { 23, 1 }, -- about 1.7 real minutes each night
	},
}

Quests.WhenText = {
	day = "in daylight",
	dusk = "at dusk",
	night = "at night",
	midnight = "at midnight",
}

-- Places in the world. pos is on the ground in Meadow Farm (Y is found by a ray at build time). look is what the
-- spot is built as. radius is how close a visit has to be.
Quests.Spots = {
	-- Meadow Farm
	hank_board = { region = "Meadow", name = "Quest board", look = "board", pos = Vector3.new(-12, 0, -2) },
	wander_scarecrow = { region = "Meadow", name = "Wandering scarecrow", look = "scarecrow", wander = true },
	old_scarecrow = {
		region = "Meadow",
		name = "The Old Scarecrow",
		look = "ring",
		pos = Vector3.new(-205, 0, -150),
		radius = 14,
	},
	old_well = { region = "Meadow", name = "The old well", look = "well", pos = Vector3.new(205, 0, -175), radius = 10 },
	old_barn = { region = "Meadow", name = "The Old Barn", look = "barn", pos = Vector3.new(290, 0, -60), radius = 18 },
	barn_key = { region = "Meadow", name = "Rusty barn key", look = "key", pos = Vector3.new(282, 0, -52), item = true },
	journal_1 = {
		region = "Meadow",
		name = "Journal page",
		look = "page",
		pos = Vector3.new(-190, 0, 140),
		item = true,
	},
	journal_2 = {
		region = "Meadow",
		name = "Journal page",
		look = "page",
		pos = Vector3.new(-140, 0, -330),
		item = true,
	},
	journal_3 = { region = "Meadow", name = "Journal page", look = "page", pos = Vector3.new(-235, 0, 30), item = true },
	crop_circle = {
		region = "Meadow",
		name = "Crop circle",
		look = "circle",
		pos = Vector3.new(250, 0, -300),
		radius = 16,
	},
	-- The Corn Night Maze, east of the plots. Its corn walls are built from a fixed seed (Quests.luau LOOKS.maze); the
	-- three keys sit in its deepest dead ends and only show after dark.
	corn_maze = {
		region = "Meadow",
		name = "Heart of the maze",
		look = "maze",
		pos = Vector3.new(262, 0, 150),
		radius = 6,
	},
	maze_key_1 = {
		region = "Meadow",
		name = "Corn key",
		look = "cornkey",
		inMaze = true,
		item = true,
		showWhen = "night",
	},
	maze_key_2 = {
		region = "Meadow",
		name = "Corn key",
		look = "cornkey",
		inMaze = true,
		item = true,
		showWhen = "night",
	},
	maze_key_3 = {
		region = "Meadow",
		name = "Corn key",
		look = "cornkey",
		inMaze = true,
		item = true,
		showWhen = "night",
	},
	golden_bale = {
		region = "Meadow",
		name = "Golden Hay Bale",
		look = "golden",
		showWhen = "midnight",
		pos = Vector3.new(250, 0, -300),
		item = true,
	},

	-- The alien signal stones. Each stands in its own region; until the map has it, by the road out of Meadow toward it.
	signal_pine = {
		region = "Pine Forest",
		name = "Signal stone",
		look = "stone",
		fallback = Vector3.new(163, 0, 392),
		radius = 10,
		world = Vector2.new(-1090, 170),
	},
	signal_valley = {
		region = "Homestead Valley",
		name = "Signal stone",
		look = "stone",
		fallback = Vector3.new(-17, 0, -392),
		radius = 10,
		world = Vector2.new(180, -1450),
	},
	signal_grove = {
		region = "Haunted Grove",
		name = "Signal stone",
		look = "stone",
		fallback = Vector3.new(-330, 0, -250),
		radius = 10,
		world = Vector2.new(-1300, -950),
	},

	-- Old Bessie's parts, one from each of three regions. Traders leave them by the roads out of Meadow until the regions open.
	bessie_carb = {
		region = "Pine Forest",
		name = "Carburetor",
		look = "crate",
		fallback = Vector3.new(137, 0, 380),
		item = true,
		world = Vector2.new(-1240, 232),
	},
	bessie_radiator = {
		region = "Desert Dunes",
		name = "Radiator",
		look = "crate",
		fallback = Vector3.new(-43, 0, -385),
		item = true,
		world = Vector2.new(1312, -236),
	},
	bessie_spring = {
		region = "Snow Peak",
		name = "Seat spring",
		look = "crate",
		fallback = Vector3.new(-43, 0, -360),
		item = true,
		world = Vector2.new(-612, -1574),
	},

	-- Spots that only exist out in their region (no fallback). `world` places them on the Stitched Isles
	-- (Config/WorldMap.luau, Services/Regions.luau landmarks); a QuestAnchor part still overrides it.
	snow_door = { region = "Snow Peak", name = "Hidden door", look = "marker", world = Vector2.new(-1052, -1697) },
	volcano_crater = {
		region = "Volcano",
		name = "Crater rim",
		look = "stone",
		radius = 20,
		world = Vector2.new(1080, -1418),
	},
	graveyard_ghost = {
		region = "Bobbin Rock",
		name = "Captain's ghost",
		look = "ghost",
		world = Vector2.new(2585, -1760),
	},
	captains_log_1 = {
		region = "Bobbin Rock",
		name = "Log page",
		look = "page",
		item = true,
		world = Vector2.new(2770, -1878),
	},
	captains_log_2 = {
		region = "Bobbin Rock",
		name = "Log page",
		look = "page",
		item = true,
		world = Vector2.new(2680, -1960),
	},
	captains_log_3 = {
		region = "Bobbin Rock",
		name = "Log page",
		look = "page",
		item = true,
		world = Vector2.new(2860, -1770),
	},
	pyramid_garage = {
		region = "Desert Dunes",
		name = "Buried garage",
		look = "marker",
		radius = 16,
		world = Vector2.new(1500, -524),
	},
	pyramid_mechanic = {
		region = "Desert Dunes",
		name = "Old mechanic",
		look = "scarecrow",
		world = Vector2.new(1278, -212),
	},
	lantern_1 = {
		region = "Haunted Grove",
		name = "Lantern",
		look = "lantern",
		radius = 8,
		world = Vector2.new(-1073, -835),
	},
	lantern_2 = {
		region = "Haunted Grove",
		name = "Lantern",
		look = "lantern",
		radius = 8,
		world = Vector2.new(-990, -948),
	},
	lantern_3 = {
		region = "Haunted Grove",
		name = "Lantern",
		look = "lantern",
		radius = 8,
		world = Vector2.new(-908, -1060),
	},
	haunted_crossroads = {
		region = "Haunted Grove",
		name = "The crossroads",
		look = "stone",
		radius = 12,
		world = Vector2.new(-1176, -756),
	},
}

-- Where the wandering scarecrow can stand. He moves every WanderMinutes, never to the spot he is on.
Quests.WanderSpots = {
	Vector3.new(-262, 0, -60),
	Vector3.new(-90, 0, -262),
	Vector3.new(232, 0, 64),
	Vector3.new(255, 0, 300),
	Vector3.new(60, 0, -300),
	Vector3.new(-310, 0, 330),
}
Quests.WanderMinutes = 4

-- Quest trucks: built on a cash truck's body (base, from Config/Trucks) with their own name and paint. They are not
-- in the dealer's list and never go in the save's trucks list; the quest log calls them out.
Quests.Trucks = {
	old_bessie = {
		base = "rusty_pickup",
		name = "Old Bessie",
		paint = "PaintCream",
		maxSpeed = 52,
		blurb = "Hank's old pickup, rebuilt. A touch faster than a Rusty Pickup.",
	},
	sandrunner = {
		base = "rusty_pickup",
		name = "Sandrunner",
		paint = "PaintYellow",
		maxSpeed = 58,
		blurb = "The fastest pickup on sand.",
	},
	ghost_hauler = {
		base = "rusty_pickup",
		name = "Ghost Hauler",
		paint = "PaintBlue",
		maxSpeed = 54,
		glow = true,
		when = "night",
		blurb = "Glows in the dark and only comes out at night.",
	},
	starlight_hauler = {
		base = "rusty_pickup",
		name = "Starlight Hauler",
		paint = "PaintBlue",
		maxSpeed = 60,
		glow = true,
		blurb = "The alien collector's own truck. Glows, and outruns everything.",
	},
}

-- Everything a quest can give. kind: gear (a perk on a tool), gloves (an id in Config/Gloves QuestTiers), truck (an id
-- in Trucks above), relic (a mystery item for the collection), unlock (a quest-only build piece in Config/Land).
Quests.Rewards = {
	golden_shovel = {
		kind = "gear",
		name = "Golden Shovel",
		perk = "GoldenShovel",
		blurb = "Your shovel scoops twice as much hay.",
	},
	thread_rake = {
		kind = "gear",
		name = "Thread Rake",
		perk = "ThreadRake",
		blurb = "Every rake stroke pulls loose needles nearby into your pocket.",
	},
	scarecrow_gloves = {
		kind = "gloves",
		name = "Scarecrow Gloves",
		blurb = "Tier 2 gloves stuffed with straw. Wear them from the quest log.",
	},
	frostbite_mitts = {
		kind = "gloves",
		name = "Frostbite Mitts",
		blurb = "Tier 3 gloves. Frozen hay feels like meadow hay.",
	},
	magma_grips = { kind = "gloves", name = "Magma Grips", blurb = "Tier 4 gloves that shrug off the heat." },
	kraken_gauntlets = {
		kind = "gloves",
		name = "Kraken Gauntlets",
		blurb = "Tier 5 gauntlets from the bottom of the sea.",
	},
	starweave_gloves = {
		kind = "gloves",
		name = "Starweave Gloves",
		blurb = "Tier 6. Star hay is no heavier than meadow hay.",
	},
	old_bessie = { kind = "truck", name = "Old Bessie", blurb = "Call her from the quest log." },
	sandrunner = { kind = "truck", name = "Sandrunner", blurb = "Call it from the quest log." },
	ghost_hauler = { kind = "truck", name = "Ghost Hauler", blurb = "Call it from the quest log, at night." },
	starlight_hauler = { kind = "truck", name = "Starlight Hauler", blurb = "Call it from the quest log." },
	alien_collector = {
		kind = "unlock",
		name = "Alien Collector",
		blurb = "A sorter that finds every needle at once while its beam is up, once a day. Build it on your land.",
	},
	starbeam_collector = {
		kind = "unlock",
		name = "Starbeam Collector",
		blurb = "A beacon over one belt tile that pulls a bale of Star hay out of the sky now and then. Build it on your land.",
	},
	-- Daily streak rosettes (Streak below): a little ribbon pinned to your chest, the best one you have earned.
	streak_rosette_bronze = {
		kind = "cosmetic",
		name = "Bronze Rosette",
		blurb = "3 streak days. Pinned to your chest.",
		color = { 176, 124, 72 },
	},
	streak_rosette_silver = {
		kind = "cosmetic",
		name = "Silver Rosette",
		blurb = "7 streak days. Pinned to your chest.",
		color = { 196, 200, 204 },
	},
	streak_rosette_gold = {
		kind = "cosmetic",
		name = "Gold Rosette",
		blurb = "14 streak days. Pinned to your chest.",
		color = { 230, 186, 74 },
	},
	streak_rosette_star = {
		kind = "cosmetic",
		name = "Starlight Rosette",
		blurb = "30 streak days. It glows a little at night.",
		color = { 150, 170, 255 },
		glow = true,
	},
	captains_barge = {
		kind = "unlock",
		name = "Captain's Barge",
		blurb = "A private ferry. It docks when the boats arrive.",
	},
	-- Mystery items. Lucky Thimble has a perk; the rest are for the collection and the Spindle.
	lucky_thimble = {
		kind = "relic",
		name = "Lucky Thimble",
		perk = "LuckyThimble",
		blurb = "Broken bales spill an extra needle now and then.",
	},
	golden_hay_bale = {
		kind = "relic",
		name = "Golden Hay Bale",
		blurb = "Warm to the touch. Something in the sky wants it.",
	},
	star_beacon = { kind = "relic", name = "Star Beacon", blurb = "Three parts that hum when put together." },
	corn_moon_charm = {
		kind = "relic",
		name = "Corn Moon Charm",
		blurb = "Three corn keys tied with twine. The crop circle answers to it.",
	},
	shard_meadow = {
		kind = "relic",
		name = "Master Needle shard: Meadow",
		blurb = "One of twelve. The Spindle has a slot that fits it.",
	},
	shard_snow = { kind = "relic", name = "Master Needle shard: Snow", blurb = "One of twelve." },
	shard_volcano = { kind = "relic", name = "Master Needle shard: Volcano", blurb = "One of twelve." },
	shard_desert = { kind = "relic", name = "Master Needle shard: Desert", blurb = "One of twelve." },
	shard_haunted = { kind = "relic", name = "Master Needle shard: Haunted", blurb = "One of twelve." },
	shard_bobbin = { kind = "relic", name = "Master Needle shard: Bobbin Rock", blurb = "One of twelve." },
}

-- The order mystery items appear in the collection. Unfound ones show as ??? with a hint.
Quests.Collection = {
	{ id = "lucky_thimble", hint = "Something drops to the bottom of the old well at midnight." },
	{ id = "shard_meadow", hint = "The Old Scarecrow keeps what he is given." },
	{ id = "golden_hay_bale", hint = "Follow the signal." },
	{ id = "star_beacon", hint = "Deep in a bale, something hums." },
	{ id = "corn_moon_charm", hint = "The corn has paths only the night can show." },
	{ id = "shard_snow", hint = "Behind a door in the snow." },
	{ id = "shard_volcano", hint = "Where the mountain breathes." },
	{ id = "shard_desert", hint = "Under the dunes." },
	{ id = "shard_haunted", hint = "Where the lanterns burn." },
	{ id = "shard_bobbin", hint = "With the ships that never came home." },
}

-- Rare finds for "find" steps: a glowing part that pops out of a broken bale. Only the finder can pick it up.
Quests.Finds = {
	beacon_part = { name = "Beacon part", color = { 120, 210, 255 } },
	frozen_bobbin = { name = "Frozen Bobbin", color = { 190, 225, 255 } },
}
Quests.FindSeconds = 60 -- a find that is not picked up fades after this long

-- The story quests and rituals, in log order. requires: quests that must be done first. ritual = shown as a ritual.
-- Cash rewards follow Config/Prices.luau: a Meadow bale is about $47 and hand hauling earns about $6,500 an hour, so
-- an early reward pays back part of the purchase the quest asked for (never all of it), and the alien rituals pay
-- what a mid-game farm makes in under an hour. Cash goes through Bank.earn like any other income.
Quests.List = {
	{
		id = "first_haul",
		name = "First Haul",
		giver = "Hank, Homestead Motors",
		region = "Meadow",
		blurb = "Every bale hides needles. The shop only pays $1 for the ones it finds. You can do better.",
		steps = {
			{
				kind = "event",
				event = "bale_lifted",
				count = 1,
				hint = "Walk up to any bale and press F to lift it.",
				text = "Lift a hay bale (Pick up)",
			},
			{
				kind = "event",
				event = "bale_sold",
				count = 1,
				hint = "Carry it onto the SELL HERE pad at camp.",
				place = "sellpad",
				text = "Sell a whole bale on the SELL HERE pad",
			},
			{
				kind = "event",
				event = "bale_broken",
				count = 1,
				hint = "Equip the shovel and click a bale.",
				text = "Break a bale open with the shovel",
			},
			{
				kind = "event",
				event = "needle_found",
				count = 1,
				hint = "Look for a glint in the straw and click it.",
				text = "Pick up a needle that spills out",
			},
		},
		reward = { cash = 150 }, -- about three bales: a thank-you, not a shortcut
	},
	{
		id = "get_a_grip",
		name = "Get a Grip",
		giver = "Hank",
		region = "Meadow",
		requires = { "first_haul" },
		blurb = "Bare hands get tired fast. Gloves let you scoop more and carry heavier hay.",
		steps = {
			{
				kind = "own",
				what = "gloves_tier",
				value = 1,
				hint = "The glove stand is next to the sell pad.",
				place = "gloves",
				text = "Wear Work Gloves or better (glove stand by the shop)",
			},
			{
				kind = "event",
				event = "bale_broken",
				count = 5,
				hint = "Any bale in the meadow counts.",
				text = "Break open 5 bales",
			},
		},
		reward = { cash = 250 }, -- pays back the Work Gloves (Prices.Gloves.work)
	},
	{
		id = "wheels",
		name = "Wheels",
		giver = "Hank",
		region = "Meadow",
		requires = { "first_haul" },
		blurb = "Walking bales one at a time won't make you rich. A truck bed holds nine.",
		steps = {
			{
				kind = "own",
				what = "truck",
				hint = "The dealer is west of camp. The Rusty Pickup is the starter truck.",
				place = "dealer",
				text = "Buy a truck at Homestead Motors",
			},
			{
				kind = "event",
				event = "bale_sold",
				count = 9,
				hint = "Load the bed, back up to the HAY SELL SHOP dock and step on UNLOAD.",
				place = "sellshop",
				text = "Sell a truckload: 9 bales",
			},
		},
		reward = { cash = 600 }, -- a tenth of the Rusty Pickup
	},
	{
		id = "put_down_roots",
		name = "Put Down Roots",
		giver = "Hank",
		region = "Meadow",
		requires = { "wheels" },
		blurb = "Sorted needles sell for $100 each. You need land and a sorter to get them out.",
		steps = {
			{
				kind = "own",
				what = "plot",
				hint = "The Land Office is just north of the plots. The bank lends for land too.",
				place = "landoffice",
				text = "Buy a plot at the Land Office",
			},
			{
				kind = "own",
				what = "piece_kind",
				value = "separator",
				hint = "On your plot press BUILD and place a hand sieve on a belt.",
				place = "plot",
				text = "Build a needle sorter on your land",
			},
			{
				kind = "event",
				event = "needles_sold",
				count = 10,
				hint = "Sorted needles land in your bin. Step on SELL NEEDLES next to it.",
				place = "plot",
				text = "Sell 10 sorted needles",
			},
		},
		reward = { cash = 1250 }, -- half the plot (Prices.Plot)
	},
	{
		id = "wandering_scarecrow",
		name = "The Wandering Scarecrow",
		giver = "A note pinned to a fence post",
		region = "Meadow",
		requires = { "first_haul" },
		blurb = '"He never stands in the same field twice. Find him five times and he\'ll give you something shiny."',
		steps = {
			{
				kind = "talk",
				spot = "wander_scarecrow",
				count = 5,
				distinct = true,
				hint = "He moves to a new field every 4 minutes. Each new field counts once.",
				text = "Find the wandering scarecrow 5 times (he moves every few minutes)",
			},
		},
		reward = { gear = "golden_shovel" },
	},
	{
		id = "scarecrow_bargain",
		name = "The Scarecrow's Bargain",
		giver = "The wandering scarecrow",
		region = "Meadow",
		ritual = true,
		requires = { "wandering_scarecrow" },
		blurb = '"My old friend stands in a ring of stones in the west. Feed him hay at dusk, then a little steel."',
		steps = {
			{
				kind = "visit",
				spot = "old_scarecrow",
				hint = "Head north-west from the dealer, past the road.",
				text = "Find the Old Scarecrow's stone ring, north-west past the dealer",
			},
			{
				kind = "pattern",
				spot = "old_scarecrow",
				pads = "stones",
				when = "dusk",
				hint = "One bale per stone, all four at once, while it's dusk.",
				text = "Set a hay bale on each of the four stones",
			},
			{
				kind = "offer",
				spot = "old_scarecrow",
				needles = { steel = 5 },
				hint = "Keep loose needles in your pocket: click them to pick up.",
				text = "Give the Old Scarecrow 5 steel needles",
			},
		},
		reward = { gloves = "scarecrow_gloves", relic = "shard_meadow" },
	},
	{
		id = "tailors_journal",
		name = "The Tailor's Journal",
		giver = "A torn page in the hay shop",
		region = "Meadow",
		requires = { "first_haul" },
		blurb = '"The Tailor lost his journal in the wind. Three pages, three corners of the meadow."',
		steps = {
			{
				kind = "collect",
				spots = { "journal_1", "journal_2", "journal_3" },
				hint = "One by the pond, one in the north woods, one west of the dealer.",
				text = "Find the 3 journal pages",
			},
			{ kind = "visit", spot = "old_barn", text = "Read them at the Old Barn, east of camp" },
		},
		reward = { gear = "thread_rake" },
	},
	{
		id = "midnight_needle",
		name = "The Midnight Needle",
		giver = "The Tailor's Journal",
		region = "Meadow",
		ritual = true,
		requires = { "tailors_journal" },
		blurb = '"Drop ten needles down the old well when the night is deepest. The well gives back what it likes."',
		steps = {
			{
				kind = "offer",
				spot = "old_well",
				needles = { steel = 10 },
				when = "midnight",
				hint = "Midnight lasts about 2 real minutes. Wait by the well.",
				text = "Drop 10 steel needles down the old well",
			},
		},
		reward = { relic = "lucky_thimble" },
	},
	{
		id = "old_bessie",
		name = "Old Bessie",
		giver = "Hank",
		region = "Meadow",
		requires = { "wheels" },
		blurb = '"My first truck is rusting in the Old Barn. Fix her up and she\'s yours."',
		steps = {
			{ kind = "collect", spot = "barn_key", text = "Find the barn key in the Old Barn" },
			{ kind = "talk", spot = "old_barn", text = "Open the barn and look at Old Bessie" },
			{
				kind = "collect",
				spots = { "bessie_carb", "bessie_radiator", "bessie_spring" },
				hint = "Pine Mill in Pine Forest, the oasis camp in the desert, and the Snow Peak lodge.",
				text = "Bring back a carburetor, a radiator and a seat spring",
			},
			{
				kind = "offer",
				spot = "old_barn",
				cash = 2500,
				hint = "Cash comes from your wallet first, then the bank.",
				text = "Pay $2,500 for the rebuild",
			},
		},
		reward = { truck = "old_bessie" },
	},

	-- The alien collector gauntlet (GAME_PLAN_V7/V8 endgame), split into five quests so progress shows.
	{
		id = "alien_signal",
		name = "The Signal",
		giver = "Static on the truck radio",
		region = "Meadow",
		ritual = true,
		requires = { "put_down_roots", "scarecrow_bargain" },
		blurb = "Something flattened the hay in a perfect ring, and the radio hums at night.",
		steps = {
			{ kind = "visit", spot = "crop_circle", when = "night", text = "Find the crop circle, far north-east" },
			{
				kind = "visit",
				spots = { "signal_pine", "signal_valley", "signal_grove" },
				when = "night",
				hint = "They stand in Pine Forest, Homestead Valley and Haunted Grove, glowing blue.",
				text = "Touch the three signal stones",
			},
		},
		reward = { cash = 5000 },
	},
	{
		id = "alien_golden_bale",
		name = "The Golden Hay Bale",
		giver = "The crop circle",
		region = "Meadow",
		ritual = true,
		requires = { "alien_signal" },
		blurb = "At midnight, something gold rests in the middle of the circle.",
		steps = {
			{ kind = "collect", spot = "golden_bale", when = "midnight", text = "Claim the Golden Hay Bale" },
		},
		reward = { relic = "golden_hay_bale" },
	},
	{
		id = "alien_beacon",
		name = "Beacon Parts",
		giver = "The Golden Hay Bale",
		region = "Meadow",
		ritual = true,
		requires = { "alien_golden_bale" },
		blurb = "The golden bale hums near ordinary hay. Three parts of a beacon are hidden in bales somewhere.",
		steps = {
			{
				kind = "find",
				item = "beacon_part",
				count = 3,
				chance = 1 / 120,
				pity = 250,
				hint = "About 1 bale in 120 hides one, and you're sure to find one within 250. Grab it before it fades.",
				text = "Find 3 beacon parts by breaking bales",
			},
		},
		reward = { relic = "star_beacon" },
	},
	{
		id = "alien_pattern",
		name = "The Pattern",
		giver = "The Star Beacon",
		region = "Meadow",
		ritual = true,
		requires = { "alien_beacon" },
		blurb = "The beacon shows a new sign every day. Lay it out in hay at midnight.",
		steps = {
			{
				kind = "pattern",
				spot = "crop_circle",
				pads = "daily",
				when = "midnight",
				hint = "The sign post shows today's 3 x 3 pattern. Filled squares need a bale, empty ones must stay clear.",
				text = "Lay bales on tonight's sign in the crop circle",
			},
		},
		reward = { cash = 15000 },
	},
	{
		id = "corn_maze",
		name = "The Corn Night Maze",
		giver = "The crop circle",
		region = "Meadow",
		ritual = true,
		requires = { "alien_signal" },
		blurb = "East of the plots, a corn maze grows taller than a truck. After dark, three keys glow in its dead ends.",
		steps = {
			{
				kind = "collect",
				spots = { "maze_key_1", "maze_key_2", "maze_key_3" },
				when = "night",
				hint = "The keys sit in the deepest dead ends and only show after dark.",
				text = "Find the 3 corn keys in the maze",
			},
			{ kind = "talk", spot = "corn_maze", when = "night", text = "Bring them to the heart of the maze" },
		},
		reward = { relic = "corn_moon_charm" },
	},
	{
		id = "alien_offering",
		name = "The Offering",
		giver = "The crop circle",
		region = "Meadow",
		ritual = true,
		requires = { "alien_pattern", "corn_maze" },
		blurb = "The collector wants fifty of every needle that grows in the world.",
		steps = {
			{
				kind = "offer",
				spot = "crop_circle",
				needlesEach = 50,
				text = "Offer 50 sorted needles of every kind you can find",
			},
		},
		reward = {
			unlock = { "alien_collector", "starbeam_collector" },
			gloves = "starweave_gloves",
			truck = "starlight_hauler",
		},
	},

	-- Region quests. Their spots appear once the region is built.
	{
		id = "frozen_door",
		name = "The Frozen Door",
		giver = "A trapper's note",
		region = "Snow Peak",
		requires = { "first_haul" },
		blurb = "There is a door in the ice on Snow Peak. It only opens for a Frozen Bobbin.",
		steps = {
			{
				kind = "find",
				item = "frozen_bobbin",
				count = 1,
				chance = 1 / 60,
				pity = 120,
				filter = { hayType = "snow" },
				hint = "Break the frozen hay bales on Snow Peak.",
				text = "Find a Frozen Bobbin in frozen hay",
			},
			{ kind = "talk", spot = "snow_door", text = "Open the hidden door on Snow Peak" },
		},
		reward = { gloves = "frostbite_mitts", relic = "shard_snow" },
	},
	{
		id = "eruption",
		name = "Eruption",
		giver = "A scorched sign",
		region = "Volcano",
		requires = { "first_haul" },
		blurb = "When the volcano rumbles at night, the crater gives up its treasure.",
		steps = {
			{ kind = "visit", spot = "volcano_crater", when = "night", text = "Climb to the crater rim at night" },
			{
				kind = "event",
				event = "bale_broken",
				count = 20,
				filter = { hayType = "volcano" },
				hint = "Ashen hay grows on the Volcano's slopes. Good gloves help with the weight.",
				text = "Break 20 bales of ashen hay",
			},
		},
		reward = { gloves = "magma_grips", relic = "shard_volcano" },
	},
	{
		id = "graveyard_of_ships",
		name = "Graveyard of Ships",
		giver = "A bottle on the beach",
		region = "Bobbin Rock",
		requires = { "first_haul" },
		blurb = "A captain still walks the wrecks at night.",
		steps = {
			{ kind = "talk", spot = "graveyard_ghost", when = "night", text = "Find the captain's ghost at night" },
		},
		reward = { gloves = "kraken_gauntlets", relic = "shard_bobbin" },
	},
	{
		id = "captains_log",
		name = "The Captain's Log",
		giver = "The captain's ghost",
		region = "Bobbin Rock",
		requires = { "graveyard_of_ships" },
		blurb = '"Find my log and my barge is yours."',
		steps = {
			{
				kind = "collect",
				spots = { "captains_log_1", "captains_log_2", "captains_log_3" },
				text = "Find the 3 log pages",
			},
		},
		reward = { unlock = "captains_barge" },
	},
	{
		id = "buried_garage",
		name = "The Buried Garage",
		giver = "A mechanic's map",
		region = "Desert Dunes",
		requires = { "wheels" },
		blurb = "A truck garage is buried under the dunes, with something fast inside.",
		steps = {
			{ kind = "visit", spot = "pyramid_garage", text = "Find the buried garage" },
			{
				kind = "event",
				event = "bale_broken",
				count = 15,
				filter = { hayType = "desert" },
				hint = "Desert grass grows around the dunes and the oasis.",
				text = "Dig it out: break 15 bales of desert grass",
			},
			{ kind = "talk", spot = "pyramid_mechanic", text = "Talk to the old mechanic" },
		},
		reward = { truck = "sandrunner", relic = "shard_desert" },
	},
	{
		id = "lanterns",
		name = "Lanterns in the Fog",
		giver = "Whispers in the Haunted Grove",
		region = "Haunted Grove",
		requires = { "wheels" },
		blurb = "Light the three lanterns, then wait at the crossroads when the night is deepest.",
		steps = {
			{
				kind = "visit",
				spots = { "lantern_1", "lantern_2", "lantern_3" },
				when = "night",
				hint = "They stand along the Haunted Grove road. Visit each one at night.",
				text = "Light the 3 lanterns",
			},
			{ kind = "visit", spot = "haunted_crossroads", when = "midnight", text = "Wait at the crossroads" },
		},
		reward = { truck = "ghost_hauler", relic = "shard_haunted" },
	},
}

-- The gentle daily streak. Finishing any one bounty on a UTC day counts that day. A missed day pauses the streak; it
-- never resets. Rosettes are cosmetic. From LuckyField.fromDays on, each day you also get a personal lucky field (one
-- of the hay fields out on the isles, shown in the Bounties tab): bales you break there sometimes spill an extra
-- needle, a few times a day.
Quests.Streak = {
	Milestones = {
		{ days = 3, reward = "streak_rosette_bronze" },
		{ days = 7, reward = "streak_rosette_silver" },
		{ days = 14, reward = "streak_rosette_gold" },
		{ days = 30, reward = "streak_rosette_star" },
	},
	LuckyField = { fromDays = 2, radius = 22, chance = 0.3, perDay = 10 },
}

-- Daily bounties: three a day from this pool, the same three for everyone, new at midnight UTC. Cash only.
Quests.BountiesPerDay = 3
Quests.Bounties = {
	{ id = "sell_bales", event = "bale_sold", count = 15, cash = 450, text = "Sell 15 bales" },
	{ id = "break_bales", event = "bale_broken", count = 12, cash = 300, text = "Break open 12 bales" },
	{ id = "find_needles", event = "needle_found", count = 8, cash = 400, text = "Pick up 8 loose needles" },
	{ id = "sell_sorted", event = "needles_sold", count = 30, cash = 1200, text = "Sell 30 sorted needles" },
	{ id = "sell_hay", event = "hay_sold", count = 300, cash = 350, text = "Sell 300 loose hay" },
	{ id = "rake", event = "raked", count = 25, cash = 150, text = "Rake 25 strokes" },
}

return Quests
