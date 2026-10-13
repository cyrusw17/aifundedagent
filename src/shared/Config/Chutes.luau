--!strict
-- Field bale chutes (V8 plan, "pacing fix"). A wooden chute stands over a lane beside each big hay field: park a
-- truck or trailer bed under it and pull the lever, and it drops one layer of loose bales into the bed. The chute
-- holds a small stock that refills from the field, so one chute keeps one truck busy but cannot be farmed forever.
-- Tune here; Chutes.luau reads it.
return {
	Stock = 18, -- bales a full chute holds (two pickup layers)
	RefillSeconds = 6, -- one bale back every this many seconds (10 a minute)
	DropGap = 0.35, -- seconds between bales falling, so a layer lands in about 3 seconds
	LaneWidth = 14, -- between the posts; the widest bed (the large trailer) is about 11
	LaneLength = 18,
	Clearance = 13, -- the hopper's underside; the box truck stands about 11 tall
	-- The meadow chute, on the trailer road between the plots and the sell dock. lane is the way trucks drive through.
	Meadow = { at = Vector2.new(120, 110), lane = Vector2.new(0, 1) },
}
