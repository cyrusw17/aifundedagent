--!strict
-- Tunable numbers for the first slice. All placeholders to adjust from playtests.
return {
	CarryCapacity = 60, -- hay a player can hold in their arms and pockets at once
	NeedleChancePerHay = 0.2, -- meadow bales hide about 20 needles per 100 hay
	AutosaveSeconds = 60,

	-- Hay pieces: a bale breaks into loose pieces, tools move them
	HayPerPiece = 1,
	VisibleNeedleChance = 0.2, -- per spill wave (3 per bale): a needle you can see and scoop
	PiecesPerBale = 90, -- small straw strands spilled by one bale
	MaxLoosePieces = 450, -- the oldest pieces vanish past this, so the server never fills with hay
	LooseHayLifetime = 90, -- seconds before untouched hay shrinks away
	BaleRefillSeconds = 45, -- placeholder until we decide how bales refill

	-- Tools
	ShovelReach = 9, -- with no click aim, a bale this close and in front of you gets smashed
	ToolReach = 18, -- how far from you a click can be for a tool to act on it
	PickupReach = 10, -- how close the Pick up button shows
	ShovelPieces = 12, -- strands per scoop
	ShovelRadius = 3, -- pieces this close to the clicked spot get scooped, nearest first
	ScoopCooldownSeconds = 0.85,
	RakeRadius = 6, -- strands this close to the click get gathered
	RakeGatherDistance = 2.5, -- the rake pulls hay to this far in front of you
	RakeStrokeSeconds = 0.45, -- how long one stroke keeps pulling
	RakeMaxSpeed = 16,
	RakeCooldownSeconds = 0.75,

	-- Carrying a whole bale
	CarryWalkSpeed = 8,
	StackReach = 9, -- a bale set down lands on top of a stack up to this high in front of you
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
