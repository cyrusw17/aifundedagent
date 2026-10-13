--!strict
-- Conveyor lines, the loading dock and line machines. Placeholders to tune.
return {
	-- Every conveyor tile is the same square, so belts can be placed on a grid.
	-- 6 studs because a bale is 4.6 studs long and has to fit through a turn between the rails.
	TileSize = 6,
	BeltTop = 3.5, -- height of the belt surface above the ground
	BeltSpeed = 6, -- studs per second
	-- A raised belt (level 1) is this much higher, so a bale standing on its end still clears it on the belt below.
	LevelRise = 5,

	WalkingFloorSpeed = 4, -- the dock slides a parked truck's load out the back at this speed

	NeedleId = "steel", -- Meadow hay holds steel needles (Needles.luau)

	AlienWindowSeconds = 60, -- how long the Alien collector's daily beam stays up
	LooseBaleSeconds = 180, -- a sorted bale that falls off the line disappears after this long

	-- Region machines (Services/Treat.luau): some hay has to be treated on the line before a sorter will do it
	-- justice. Keyed by hay type (Config/Gloves HayTypes). mark is the bale attribute the machine sets; required
	-- means a sorter refuses an untreated bale (it rides on through), otherwise its recovery is multiplied by penalty.
	-- Only whole bales are checked: loose strands are already broken open.
	Treatments = {
		snow = { machine = "thawing_shed", mark = "Thawed", required = true, refuse = "Frozen hay has to thaw in a thawing shed before it can be sorted." },
		swamp = { machine = "drying_rack", mark = "Dried", required = true, refuse = "Bog reed has to dry on a drying rack before it can be sorted." },
		volcano = { machine = "ash_sifter", mark = "Sifted", required = false, penalty = 0.5, refuse = "Ashen hay sorts at half recovery until an ash sifter knocks the ash out." },
	},
	TreatSeconds = 2, -- how long a bale spends in a region machine (the belt stops it at a gate meanwhile)
}
