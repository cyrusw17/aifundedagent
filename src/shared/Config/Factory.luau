--!strict
-- Conveyor lines, the loading dock and line machines. Placeholders to tune.
return {
	-- Every conveyor tile is the same square, so belts can be placed on a grid.
	-- 6 studs because a bale is 4.6 studs long and has to fit through a turn between the rails.
	TileSize = 6,
	BeltTop = 3.5, -- height of the belt surface above the ground
	BeltSpeed = 6, -- studs per second

	WalkingFloorSpeed = 4, -- the dock slides a parked truck's load out the back at this speed

	NeedleId = "steel", -- Meadow hay holds steel needles (Needles.luau)

	LooseBaleSeconds = 180, -- a sorted bale that falls off the line disappears after this long
}
