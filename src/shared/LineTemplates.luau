--!strict
-- Starter line templates (CEO #37): three ready layouts in the build bar's LAYOUTS list, so a new builder sees a
-- sound line before they design one. Each loads like a saved layout (Blueprints.luau) and PASTE builds it for the sum
-- of its pieces. tools/linecheck/templates.py walks every template's belts the way bales would (silo chute, splitter
-- sides, sorter belts, buyer hoppers) and fails if a sorter is starved or downstream of another sorter, a bale can run
-- off a belt, or a path misses a buyer, then prints each template's $/hour from line_sim.
--
-- Pieces as Land's COPY writes them: id, dx/dz from the back-left corner, dir the way the belt runs.
-- Sorted bales are never sorted twice, so two sorters go side by side behind a splitter, never one after the other.
return {
	{
		name = "Starter: hand sieve",
		list = {
			{ id = "silo", dx = 0, dz = 0, dir = "E" },
			{ id = "belt", dx = 2, dz = 0, dir = "E" },
			{ id = "hand_sieve", dx = 3, dz = 0, dir = "E" },
			{ id = "belt", dx = 5, dz = 0, dir = "E" },
			{ id = "hay_buyer", dx = 6, dz = 0, dir = "E" },
		},
	},
	{
		name = "Mid: shaker + conveyor sorter",
		list = {
			{ id = "silo", dx = 0, dz = 1, dir = "E" },
			{ id = "belt", dx = 2, dz = 1, dir = "E" },
			{ id = "splitter", dx = 3, dz = 1, dir = "E" },
			{ id = "belt", dx = 3, dz = 0, dir = "E" },
			{ id = "shaker_table", dx = 4, dz = 0, dir = "E" },
			{ id = "belt", dx = 6, dz = 0, dir = "E" },
			{ id = "hay_buyer", dx = 7, dz = 0, dir = "E" },
			{ id = "belt", dx = 3, dz = 2, dir = "E" },
			{ id = "conveyor_sorter", dx = 4, dz = 2, dir = "E" },
			{ id = "belt", dx = 6, dz = 2, dir = "E" },
			{ id = "hay_buyer", dx = 7, dz = 2, dir = "E" },
		},
	},
	{
		name = "Pro: magnet drum + optical",
		list = {
			{ id = "silo", dx = 0, dz = 1, dir = "E" },
			{ id = "belt", dx = 2, dz = 1, dir = "E" },
			{ id = "splitter", dx = 3, dz = 1, dir = "E" },
			{ id = "belt", dx = 3, dz = 0, dir = "E" },
			{ id = "magnet_drum", dx = 4, dz = 0, dir = "E" },
			{ id = "belt", dx = 6, dz = 0, dir = "E" },
			{ id = "hay_buyer", dx = 7, dz = 0, dir = "E" },
			{ id = "belt", dx = 3, dz = 2, dir = "E" },
			{ id = "optical_sorter", dx = 4, dz = 2, dir = "E" },
			{ id = "belt", dx = 6, dz = 2, dir = "E" },
			{ id = "hay_buyer", dx = 7, dz = 2, dir = "E" },
		},
	},
}
