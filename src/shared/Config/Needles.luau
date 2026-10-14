--!strict
-- Needle types by barrel map. sortedValue is what one sells for sorted (Config/Prices).
local Prices = require(script.Parent.Prices)
return {
	{ id = "steel", name = "Steel", map = "Meadow", sortedValue = Prices.Needles.steel },
	{ id = "pine", name = "Pine", map = "Pine Forest", sortedValue = Prices.Needles.pine },
	{ id = "sand", name = "Sand", map = "Desert", sortedValue = Prices.Needles.sand },
	{ id = "ice", name = "Ice", map = "Snow Peak", sortedValue = Prices.Needles.ice },
	{ id = "bog", name = "Bog", map = "Swamp", sortedValue = Prices.Needles.bog },
	{ id = "coral", name = "Coral", map = "Thimble Keys", sortedValue = Prices.Needles.coral },
	{ id = "obsidian", name = "Obsidian", map = "Volcano", sortedValue = Prices.Needles.obsidian },
	{ id = "brass", name = "Brass", map = "Bobbin Rock", sortedValue = Prices.Needles.brass },
	{ id = "geode", name = "Geode", map = "Cave", sortedValue = Prices.Needles.geode },
	{ id = "cloud", name = "Cloud", map = "Sky Island", sortedValue = Prices.Needles.cloud },
	{ id = "phantom", name = "Phantom", map = "Haunted Grove", sortedValue = Prices.Needles.phantom },
	{ id = "cosmic", name = "Cosmic", map = "Star Hay", sortedValue = Prices.Needles.cosmic },
}
