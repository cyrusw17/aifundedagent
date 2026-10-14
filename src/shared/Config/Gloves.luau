--!strict
-- Shovels and hay weight. The tools are the shovel, the rake and the wheelbarrow; the shovel is the upgrade (Cyrus,
-- 2026-10-13: gloves are gone, a better shovel carries more). Carried hay slows you down, rarer hay is heavier, and
-- hay rarer than your shovel is rated for slows you much more and scoops slower. A better shovel takes the edge off.
-- The module, the tier ids and the save's state.gloves keep their old names so saves carry over: a pair of gloves
-- bought before is now the shovel of the same tier. Every number here is a placeholder to tune from playtests.
local Prices = require(script.Parent.Prices)
return {
	-- Walk speed lost per unit of carried weight, before the shovel eases it. One meadow strand weighs 1.
	SlowPerWeight = 0.12,
	MinWalkSpeed = 5,
	-- A carried bale weighs this fraction of the hay inside it (it is packed tight and easier to hold).
	BaleWeightFactor = 0.8,
	-- For each tier your shovel falls short of the hay's tier, the slowdown is multiplied by (1 + this).
	UnderGearedSlow = 1.0,
	-- For each tier short, a scoop picks up this fraction fewer strands (at least 2 always).
	UnderGearedScoop = 0.35,

	-- Hay by map. map matches Config/Needles. tier is the shovel tier needed to handle it comfortably.
	HayTypes = {
		meadow = { name = "Meadow hay", map = "Meadow", weight = 1.0, tier = 0 },
		pine = { name = "Pine straw", map = "Pine Forest", weight = 1.3, tier = 1 },
		desert = { name = "Desert grass", map = "Desert", weight = 1.6, tier = 2 },
		snow = { name = "Frozen hay", map = "Snow Peak", weight = 2.0, tier = 2 },
		keys = { name = "Sea grass", map = "Thimble Keys", weight = 2.2, tier = 3 },
		swamp = { name = "Bog reed", map = "Swamp", weight = 2.4, tier = 3 },
		volcano = { name = "Ashen hay", map = "Volcano", weight = 3.0, tier = 4 },
		bobbin = { name = "Thread grass", map = "Bobbin Rock", weight = 3.2, tier = 4 },
		cave = { name = "Crystal hay", map = "Cave", weight = 3.4, tier = 4 },
		sky = { name = "Cloud hay", map = "Sky Island", weight = 4.0, tier = 5 },
		haunted = { name = "Phantom hay", map = "Haunted Grove", weight = 4.5, tier = 5 },
		star = { name = "Star hay", map = "Star Hay", weight = 6.0, tier = 6 }, -- beyond every shovel: always a struggle
	},
	DefaultHayType = "meadow",

	-- Shovel tiers, worst to best. relief is the fraction of slowdown taken away. scoopBonus adds strands per scoop,
	-- carryBonus adds to how much hay one shovel load holds. carrySpeed is walk speed added while you carry anything (a
	-- bale, a shovel load, a full barrow). color and material are the band at the neck of the blade (GloveLooks.luau)
	-- and the shovel on the rack, so each tier reads at a glance on the one Blender shovel mesh.
	Tiers = {
		{ id = "bare", name = "Old Shovel", tier = 0, price = Prices.Gloves.bare, relief = 0, scoopBonus = 0, carryBonus = 0, carrySpeed = 0, material = "Wood", color = { 128, 105, 77 } },
		{ id = "work", name = "Garden Shovel", tier = 1, price = Prices.Gloves.work, relief = 0.2, scoopBonus = 2, carryBonus = 15, carrySpeed = 0.5, material = "Metal", color = { 150, 140, 128 } },
		{ id = "leather", name = "Steel Shovel", tier = 2, price = Prices.Gloves.leather, relief = 0.35, scoopBonus = 4, carryBonus = 30, carrySpeed = 1, material = "DiamondPlate", color = { 170, 172, 170 } },
		{ id = "reinforced", name = "Reinforced Shovel", tier = 3, price = Prices.Gloves.reinforced, relief = 0.5, scoopBonus = 6, carryBonus = 50, carrySpeed = 1.5, material = "Metal", color = { 92, 74, 54 } },
		{ id = "iron", name = "Iron Spade", tier = 4, price = Prices.Gloves.iron, relief = 0.62, scoopBonus = 9, carryBonus = 80, carrySpeed = 2, material = "CorrodedMetal", color = { 107, 94, 84 } },
		{ id = "starlight", name = "Starlight Shovel", tier = 5, price = Prices.Gloves.starlight, relief = 0.78, scoopBonus = 14, carryBonus = 140, carrySpeed = 3, material = "Glass", color = { 70, 72, 96 } },
	},

	-- Quest shovels: earned from quests and rituals (Config/Quests.luau Rewards), never sold, so they are not on the
	-- shovel rack. Each is a little better than the shop shovel of the same tier, as a thank-you for the quest. The ids
	-- keep their old glove names so quest rewards and saves still match.
	QuestTiers = {
		{ id = "scarecrow_gloves", name = "Scarecrow Shovel", tier = 2, price = 0, quest = true, relief = 0.4, scoopBonus = 5, carryBonus = 35, carrySpeed = 1.2, material = "Fabric", color = { 189, 168, 112 } },
		{ id = "frostbite_mitts", name = "Frostbite Spade", tier = 3, price = 0, quest = true, relief = 0.55, scoopBonus = 7, carryBonus = 55, carrySpeed = 1.8, material = "Fabric", color = { 190, 210, 225 } },
		{ id = "magma_grips", name = "Magma Shovel", tier = 4, price = 0, quest = true, relief = 0.66, scoopBonus = 10, carryBonus = 90, carrySpeed = 2.2, material = "Basalt", color = { 140, 70, 50 } },
		{ id = "kraken_gauntlets", name = "Kraken Spade", tier = 5, price = 0, quest = true, relief = 0.8, scoopBonus = 15, carryBonus = 150, carrySpeed = 3, material = "Metal", color = { 60, 96, 110 } },
		{ id = "starweave_gloves", name = "Starweave Shovel", tier = 6, price = 0, quest = true, relief = 0.9, scoopBonus = 18, carryBonus = 180, carrySpeed = 3.5, material = "Glass", color = { 120, 140, 210 } },
	},
}
