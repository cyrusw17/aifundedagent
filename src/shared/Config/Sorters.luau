--!strict
-- Sorter tiers from the design docs. Placeholders to tune from playtests.
local Prices = require(script.Parent.Prices)
return {
	{ id = "hand_sieve", name = "Hand sieve", recovery = 0.15, hayPerMin = Prices.SorterBalesPerMinute.hand_sieve * Prices.HayPerBale },
	{ id = "shaker_table", name = "Shaker table", recovery = 0.35, hayPerMin = Prices.SorterBalesPerMinute.shaker_table * Prices.HayPerBale },
	{ id = "conveyor_sorter", name = "Conveyor sorter", recovery = 0.55, hayPerMin = Prices.SorterBalesPerMinute.conveyor_sorter * Prices.HayPerBale },
	{ id = "magnet_drum", name = "Magnet drum", recovery = 0.75, hayPerMin = Prices.SorterBalesPerMinute.magnet_drum * Prices.HayPerBale },
	{ id = "optical_sorter", name = "Optical sorter", recovery = 0.92, hayPerMin = Prices.SorterBalesPerMinute.optical_sorter * Prices.HayPerBale },
	{ id = "alien_collector", name = "Alien collector", recovery = 1.0, hayPerMin = math.huge },
}
