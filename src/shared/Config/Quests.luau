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
-- Spots belong to a region. A spot in a region that is not built yet waits for the map: the "Full world map build"
-- thread tags a part "QuestAnchor" with attribute SpotId = the spot's id (and Region = the region name) and the spot
-- moves there. Spots with a `fallback` position stand in Meadow Farm until then, so every chain can be played now.
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
	golden_bale = {
		region = "Meadow",
		name = "Golden Hay Bale",
		look = "golden",
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
	},
	signal_valley = {
		region = "Homestead Valley",
		name = "Signal stone",
		look = "stone",
		fallback = Vector3.new(-17, 0, -392),
		radius = 10,
	},
	signal_grove = {
		region = "Haunted Grove",
		name = "Signal stone",
		look = "stone",
		fallback = Vector3.new(-330, 0, -250),
		radius = 10,
	},

	-- Old Bessie's parts, one from each of three regions. Traders leave them by the roads out of Meadow until the regions open.
	bessie_carb = {
		region = "Pine Forest",
		name = "Carburetor",
		look = "crate",
		fallback = Vector3.new(137, 0, 380),
		item = true,
	},
	bessie_radiator = {
		region = "Desert Dunes",
		name = "Radiator",
		look = "crate",
		fallback = Vector3.new(-43, 0, -385),
		item = true,
	},
	bessie_spring = {
		region = "Snow Peak",
		name = "Seat spring",
		look = "crate",
		fallback = Vector3.new(-43, 0, -360),
		item = true,
	},

	-- Spots that only exist once their region is built (no fallback).
	snow_door = { region = "Snow Peak", name = "Hidden door", look = "door" },
	volcano_crater = { region = "Volcano", name = "Crater rim", look = "stone", radius = 20 },
	graveyard_ghost = { region = "Bobbin Rock", name = "Captain's ghost", look = "ghost" },
	captains_log_1 = { region = "Bobbin Rock", name = "Log page", look = "page", item = true },
	captains_log_2 = { region = "Bobbin Rock", name = "Log page", look = "page", item = true },
	captains_log_3 = { region = "Bobbin Rock", name = "Log page", look = "page", item = true },
	pyramid_garage = { region = "Desert Dunes", name = "Buried garage", look = "door", radius = 16 },
	pyramid_mechanic = { region = "Desert Dunes", name = "Old mechanic", look = "scarecrow" },
	lantern_1 = { region = "Haunted Grove", name = "Lantern", look = "lantern", radius = 8 },
	lantern_2 = { region = "Haunted Grove", name = "Lantern", look = "lantern", radius = 8 },
	lantern_3 = { region = "Haunted Grove", name = "Lantern", look = "lantern", radius = 8 },
	haunted_crossroads = { region = "Haunted Grove", name = "The crossroads", look = "stone", radius = 12 },
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
		name = "Starbeam Collector",
		blurb = "A sorter that finds every needle at once. Build it on your land.",
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
			{ kind = "event", event = "bale_lifted", count = 1, text = "Lift a hay bale (Pick up)" },
			{ kind = "event", event = "bale_sold", count = 1, text = "Sell a whole bale on the SELL HERE pad" },
			{ kind = "event", event = "bale_broken", count = 1, text = "Break a bale open with the shovel" },
			{ kind = "event", event = "needle_found", count = 1, text = "Pick up a needle that spills out" },
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
				text = "Wear Work Gloves or better (glove stand by the shop)",
			},
			{ kind = "event", event = "bale_broken", count = 5, text = "Break open 5 bales" },
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
			{ kind = "own", what = "truck", text = "Buy a truck at Homestead Motors" },
			{ kind = "event", event = "bale_sold", count = 9, text = "Sell a truckload: 9 bales" },
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
			{ kind = "own", what = "plot", text = "Buy a plot at the Land Office" },
			{ kind = "own", what = "piece_kind", value = "separator", text = "Build a needle sorter on your land" },
			{ kind = "event", event = "needles_sold", count = 10, text = "Sell 10 sorted needles" },
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
				text = "Find the Old Scarecrow's stone ring, north-west past the dealer",
			},
			{
				kind = "pattern",
				spot = "old_scarecrow",
				pads = "stones",
				when = "dusk",
				text = "Set a hay bale on each of the four stones",
			},
			{
				kind = "offer",
				spot = "old_scarecrow",
				needles = { steel = 5 },
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
			{ kind = "collect", spots = { "journal_1", "journal_2", "journal_3" }, text = "Find the 3 journal pages" },
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
				text = "Bring back a carburetor, a radiator and a seat spring",
			},
			{ kind = "offer", spot = "old_barn", cash = 2500, text = "Pay $2,500 for the rebuild" },
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
				text = "Lay bales on tonight's sign in the crop circle",
			},
		},
		reward = { cash = 15000 },
	},
	{
		id = "alien_offering",
		name = "The Offering",
		giver = "The crop circle",
		region = "Meadow",
		ritual = true,
		requires = { "alien_pattern" },
		blurb = "The collector wants a hundred of every needle you can reach.",
		steps = {
			{
				kind = "offer",
				spot = "crop_circle",
				needlesEach = 100,
				text = "Offer 100 sorted needles of every kind you can reach",
			},
		},
		reward = { unlock = "alien_collector", gloves = "starweave_gloves", truck = "starlight_hauler" },
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
				text = "Light the 3 lanterns",
			},
			{ kind = "visit", spot = "haunted_crossroads", when = "midnight", text = "Wait at the crossroads" },
		},
		reward = { truck = "ghost_hauler", relic = "shard_haunted" },
	},
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
