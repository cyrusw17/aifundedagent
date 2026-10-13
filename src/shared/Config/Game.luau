--!strict
-- Tunable numbers for the first slice. All placeholders to adjust from playtests.
return {
	WheelbarrowCapacity = 30, -- hay units the wheelbarrow carries
	ShovelHayPerScoop = 5, -- hay units per scoop with the basic shovel
	ScoopHoldSeconds = 0.35,
	BarrelScoops = 20, -- scoops in a full barrel
	BarrelRefillSeconds = 30, -- placeholder until we decide how barrels refill
	NeedleChancePerHay = 0.2, -- meadow barrels hide about 20 needles per 100 hay
	AutosaveSeconds = 60,

	-- Carrying a whole barrel
	CarryWalkSpeed = 8,
	BarrelPickupHoldSeconds = 0.6,
	DroppedBarrelSeconds = 180, -- a dropped barrel disappears after this long

	-- Scoop animation tuning (degrees of right-arm swing and seconds). Easy to adjust from playtests.
	DigBackDegrees = -35,
	DigForwardDegrees = 30,
	LiftDegrees = 75,
	DigBackSeconds = 0.16,
	DigForwardSeconds = 0.14,
	HayFlightSeconds = 0.4,
}
