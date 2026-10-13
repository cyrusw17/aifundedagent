--!strict
-- Tunable numbers for the first slice. All placeholders to adjust from playtests.
return {
	CarryCapacity = 30, -- hay a player can hold in their arms and pockets at once
	NeedleChancePerHay = 0.2, -- meadow barrels hide about 20 needles per 100 hay
	AutosaveSeconds = 60,

	-- Hay pieces: a barrel breaks into loose pieces, tools move them
	HayPerPiece = 1,
	PiecesPerBarrel = 60,
	MaxLoosePieces = 400, -- the oldest pieces vanish past this, so the server never fills with hay
	LooseHayLifetime = 90, -- seconds before untouched hay shrinks away
	BarrelRefillSeconds = 45, -- placeholder until we decide how barrels refill

	-- Tools
	ShovelReach = 9, -- with no click aim, a barrel this close and in front of you gets smashed
	ToolReach = 18, -- how far from you a click can be for a tool to act on it
	PickupReach = 10, -- how close the Pick up button shows
	ShovelPieces = 6, -- pieces per scoop
	ShovelRadius = 3, -- pieces this close to the clicked spot get scooped, nearest first
	ScoopCooldownSeconds = 0.85,
	RakeRadius = 7,
	RakeCooldownSeconds = 0.75,

	-- Carrying a whole barrel
	CarryWalkSpeed = 8,
	DroppedBarrelSeconds = 180, -- a dropped barrel disappears after this long

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
