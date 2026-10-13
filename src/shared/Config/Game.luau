--!strict
-- Tunable numbers for the first slice. All placeholders to adjust from playtests.
local Prices = require(script.Parent.Prices)
return {
	CarryCapacity = 60, -- hay a player can hold in their arms and pockets at once
	NeedleChancePerHay = Prices.needleChance("meadow"), -- Meadow bales hide 2 needles on average (Config/Prices)
	AutosaveSeconds = 60,

	-- TESTING: every player has endless cash, so shops can be tried without grinding. Real balances are kept and
	-- saved as normal underneath; set this to false before launch.
	InfiniteMoney = true,

	-- Hay pieces: a bale breaks into loose pieces, tools move them
	HayPerPiece = 1,
	-- Per spill wave (3 per bale): a needle you can see and pick up. A quarter of a bale's hidden needles on average.
	VisibleNeedleChance = Prices.NeedlesPerBale.meadow * Prices.VisibleNeedleShare / 3,
	PiecesPerBale = 90, -- small straw strands spilled by one bale
	MaxHayPiles = 30, -- raked piles past this lose their oldest, so piles can't pile up without end
	MaxLoosePieces = 450, -- the oldest pieces vanish past this, so the server never fills with hay
	LooseHayLifetime = 90, -- seconds before untouched hay shrinks away
	LooseNeedleLifetime = 600, -- a spilled needle or a raked pile nobody picks up stays this long
	MaxLooseNeedles = 120, -- past this many lying around, the oldest needle goes
	BaleRefillSeconds = 45, -- placeholder until we decide how bales refill

	-- Tools
	ShovelReach = 9, -- with no click aim, a bale this close and in front of you gets smashed
	ToolReach = 18, -- how far from you a click can be for a tool to act on it
	PickupReach = 10, -- how close the Pick up button shows
	ShovelPieces = 12, -- strands per scoop
	ShovelRadius = 3, -- pieces this close to the clicked spot get scooped, nearest first
	ScoopCooldownSeconds = 0.85,
	-- Scoop combo: scoops landing within ComboWindowSeconds of each other chain. From ComboStart scoops on, each
	-- scoop takes ComboBonusPieces more strands per link past the start, up to ComboMaxBonus.
	-- Wheelbarrow: how many bales it holds, and the share of their weight you feel while pushing it.
	WheelbarrowBales = 3,
	WheelbarrowLoadFactor = 0.3,
	ComboWindowSeconds = 1.6,
	ComboStart = 3,
	ComboBonusPieces = 2,
	ComboMaxBonus = 10,
	RakeRadius = 6, -- strands this close to the click get gathered
	RakeGatherDistance = 2.5, -- the rake pulls hay to this far in front of you
	-- Hay piles: raking at least PileMin strands together into one spot packs them into a single pile the shovel
	-- takes in one scoop (it ignores the per-scoop size; only your carry room limits it).
	PileMin = 40,
	PileRadius = 3,
	RakeStrokeSeconds = 0.45, -- how long one stroke keeps pulling
	RakeMaxSpeed = 16,
	RakeCooldownSeconds = 0.75,

	-- Carrying a whole bale
	CarryWalkSpeed = 8,
	StackReach = 9, -- a bale set down lands on top of a stack up to this high in front of you
	-- Hold click (or G) with a bale to charge a throw, then let go to lob it. A plain click still sets it down.
	TossRange = 10, -- studs on flat ground at full charge
	TossMinRange = 3, -- at the least charge that throws at all
	TossMinPower = 0.12, -- charge below this (0..1) just sets the bale down
	TossChargeSeconds = 0.9, -- holding this long is full power
	TossFlightSeconds = 2.5, -- the server flies a thrown bale this long, then Roblox picks its owner again
	-- Wet hay. A bale out under the open sky while its region rains soaks through after WetSoakSeconds: it weighs
	-- WetWeightFactor times as much and its hay sells at WetPriceFactor of the price (needles in it are unharmed)
	-- until it dries, in the open once the rain stops (WetDrySeconds) or at once on a drying rack. Strands spilled
	-- from a wet bale are wet too.
	WetWeather = { rain = true },
	WetSoakSeconds = 20,
	WetDrySeconds = 150,
	WetWeightFactor = 1.5,
	WetPriceFactor = 0.6,
	-- Pouring the hay in your arms (shovel click on a truck bed, hopper, belt or sell pad).
	PourStrands = 40, -- strands per click; click again for more
	PourFlightSeconds = 0.55,
	PourSpread = 1.2, -- studs around the clicked spot
	PourStagger = 0.008, -- seconds between strands, so it streams out
	GoldenBaleOneIn = Prices.GoldenBale.oneIn, -- a field bale grows golden 1 time in this many (Config/Prices)
	GoldenBaleNeedles = Prices.GoldenBale.needles, -- a golden bale spills this many times the needles
	DoubleCarryTier = 3, -- gloves of this tier (Reinforced) and up carry two bales, one on top of the other
	StackMin = 3, -- a neat stack of this many bales or more is kept (no despawn) and gets a "Stack N" label
	DroppedBaleSeconds = 180, -- a dropped bale disappears after this long

	-- Scoop animation tuning (degrees of right-arm swing and seconds). Easy to adjust from playtests.
	DigBackDegrees = -35,
	DigForwardDegrees = 30,
	LiftDegrees = 75,
	DigBackSeconds = 0.16,
	DigForwardSeconds = 0.14,
	HayFlightSeconds = 0.4,

	-- Rake animation: reach out, then drag back
	RakeReachDegrees = 85,
	RakeDragDegrees = 20,
}
