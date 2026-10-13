--!strict
-- Sorter tiers from the design docs. Placeholders to tune from playtests.
return {
	{ id = "hand_sieve", name = "Hand sieve", recovery = 0.15, hayPerMin = 20 },
	{ id = "shaker_table", name = "Shaker table", recovery = 0.35, hayPerMin = 60 },
	{ id = "conveyor_sorter", name = "Conveyor sorter", recovery = 0.55, hayPerMin = 150 },
	{ id = "magnet_drum", name = "Magnet drum", recovery = 0.75, hayPerMin = 400 },
	{ id = "optical_sorter", name = "Optical sorter", recovery = 0.92, hayPerMin = 900 },
	{ id = "alien_collector", name = "Alien collector", recovery = 1.0, hayPerMin = math.huge },
}
