--!strict
-- Alloy mixer recipes: needles of two types melt into a block of building material for blueprints. Every recipe takes
-- `each` plain sorted needles of both types from the player's pocket and makes `units` of material. Steel is in every
-- recipe, so a Meadow farm always has half of what it needs and the other half pulls players into a new region.
-- color is the block's look (Rustic palette plus the second needle's accent).
return {
	{ id = "ironwood", name = "Ironwood", a = "steel", b = "pine", each = 5, units = 10, color = { 120, 104, 80 } },
	{ id = "brass", name = "Brass", a = "steel", b = "sand", each = 5, units = 10, color = { 181, 150, 90 } },
	{ id = "frost_steel", name = "Frost steel", a = "steel", b = "ice", each = 5, units = 10, color = { 170, 196, 210 } },
	{ id = "bog_iron", name = "Bog iron", a = "steel", b = "bog", each = 5, units = 10, color = { 98, 104, 76 } },
	{ id = "black_steel", name = "Black steel", a = "steel", b = "obsidian", each = 5, units = 10, color = { 52, 46, 56 } },
	{ id = "geode_steel", name = "Geode steel", a = "steel", b = "geode", each = 5, units = 10, color = { 140, 110, 170 } },
	{ id = "skysteel", name = "Skysteel", a = "steel", b = "cloud", each = 5, units = 10, color = { 220, 226, 236 } },
	{ id = "wraith_iron", name = "Wraith iron", a = "steel", b = "phantom", each = 5, units = 10, color = { 120, 200, 190 } },
	{ id = "starmetal", name = "Starmetal", a = "steel", b = "cosmic", each = 5, units = 10, color = { 90, 80, 210 } },
}
