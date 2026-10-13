--!strict
-- The starter base: conveyor tiles, the hay trailer, the needle sorter and the hay buyer. Placeholders to tune.
return {
	-- Every conveyor tile is the same square, so belts can later be placed on a grid.
	-- 6 studs because a bale is 4.6 studs long and has to fit through a turn between the rails.
	TileSize = 6,
	BeltTop = 3.5, -- height of the belt surface above the ground
	BeltSpeed = 6, -- studs per second

	TrailerBales = 10, -- two layers of five
	TrailerCost = 0, -- free while we test the line
	TrailerDriveSpeed = 28,
	TrailerReverseSpeed = 8,
	WalkingFloorSpeed = 4, -- the trailer floor slides the load out the back at this speed

	SorterTier = "conveyor_sorter", -- id from Sorters.luau, sets how many hidden needles get found
	SortSecondsPerBale = 2.5,
	NeedleId = "steel", -- Meadow hay holds steel needles (Needles.luau)
	MaxVisibleNeedles = 150, -- needles drawn in the bin; the count keeps going past this

	LooseBaleSeconds = 180, -- a trailer bale that falls off the line disappears after this long
}
