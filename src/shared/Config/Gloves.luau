--!strict
-- Gloves and hay weight. The only tools are the shovel and the rake; gloves are the upgrade. Carried hay slows
-- you down, rarer hay is heavier, and hay rarer than your gloves are rated for slows you much more and scoops
-- slower. Better gloves take the edge off. Every number here is a placeholder to tune from playtests.
local Prices = require(script.Parent.Prices)
return {
	-- Walk speed lost per unit of carried weight, before gloves. One meadow strand weighs 1.
	SlowPerWeight = 0.12,
	MinWalkSpeed = 5,
	-- A carried bale weighs this fraction of the hay inside it (it is packed tight and easier to hold).
	BaleWeightFactor = 0.8,
	-- For each tier your gloves fall short of the hay's tier, the slowdown is multiplied by (1 + this).
	UnderGearedSlow = 1.0,
	-- For each tier short, a scoop picks up this fraction fewer strands (at least 2 always).
	UnderGearedScoop = 0.35,

	-- Hay by map. map matches Config/Needles. tier is the glove tier needed to handle it comfortably.
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
		star = { name = "Star hay", map = "Star Hay", weight = 6.0, tier = 6 }, -- beyond every glove: always a struggle
	},
	DefaultHayType = "meadow",

	-- Glove tiers, worst to best. relief is the fraction of slowdown taken away. scoopBonus adds strands per shovel
	-- scoop, carryBonus adds to how much hay you can hold. prop names the Rustic Blender glove (one right glove,
	-- fingers +Y, back of hand -Z; mirror it for the left). color is for the placeholder until the mesh is in.
	-- carrySpeed is walk speed added while you carry anything (a bale, a scoop of hay, a full barrow), so better gloves
	-- move a load faster on top of the slowdown they take away. color and material are the wrist cuff every pair
	-- shows on the hands (GloveLooks.luau), so each tier reads at a glance even where two share a mesh.
	Tiers = {
		{ id = "bare", name = "Bare hands", tier = 0, price = Prices.Gloves.bare, relief = 0, scoopBonus = 0, carryBonus = 0, carrySpeed = 0, material = "Plastic", color = { 214, 178, 150 } },
		{ id = "work", prop = "work_gloves", name = "Work Gloves", tier = 1, price = Prices.Gloves.work, relief = 0.2, scoopBonus = 2, carryBonus = 15, carrySpeed = 0.5, material = "Fabric", color = { 189, 168, 112 } },
		{ id = "leather", prop = "leather_gloves", name = "Leather Gloves", tier = 2, price = Prices.Gloves.leather, relief = 0.35, scoopBonus = 4, carryBonus = 30, carrySpeed = 1, material = "Leather", color = { 128, 92, 62 } },
		{ id = "reinforced", prop = "reinforced_gloves", name = "Reinforced Gloves", tier = 3, price = Prices.Gloves.reinforced, relief = 0.5, scoopBonus = 6, carryBonus = 50, carrySpeed = 1.5, material = "Leather", color = { 92, 74, 54 } },
		{ id = "iron", prop = "iron_gauntlets", name = "Iron Gauntlets", tier = 4, price = Prices.Gloves.iron, relief = 0.62, scoopBonus = 9, carryBonus = 80, carrySpeed = 2, material = "Metal", color = { 107, 94, 84 } },
		{ id = "starlight", prop = "starlight_gloves", name = "Starlight Gloves", tier = 5, price = Prices.Gloves.starlight, relief = 0.78, scoopBonus = 14, carryBonus = 140, carrySpeed = 3, material = "Glass", color = { 70, 72, 96 } },
	},

	-- Quest gloves: earned from quests and rituals (Config/Quests.luau Rewards), never sold, so they are not on the
	-- glove stand. Each is a little better than the shop pair of the same tier, as a thank-you for the quest. They wear
	-- the shop pair's Blender mesh (prop) until they get their own.
	QuestTiers = {
		{ id = "scarecrow_gloves", prop = "leather_gloves", name = "Scarecrow Gloves", tier = 2, price = 0, quest = true, relief = 0.4, scoopBonus = 5, carryBonus = 35, carrySpeed = 1.2, material = "Fabric", color = { 189, 168, 112 } },
		{ id = "frostbite_mitts", prop = "reinforced_gloves", name = "Frostbite Mitts", tier = 3, price = 0, quest = true, relief = 0.55, scoopBonus = 7, carryBonus = 55, carrySpeed = 1.8, material = "Fabric", color = { 190, 210, 225 } },
		{ id = "magma_grips", prop = "iron_gauntlets", name = "Magma Grips", tier = 4, price = 0, quest = true, relief = 0.66, scoopBonus = 10, carryBonus = 90, carrySpeed = 2.2, material = "Basalt", color = { 140, 70, 50 } },
		{ id = "kraken_gauntlets", prop = "iron_gauntlets", name = "Kraken Gauntlets", tier = 5, price = 0, quest = true, relief = 0.8, scoopBonus = 15, carryBonus = 150, carrySpeed = 3, material = "Metal", color = { 60, 96, 110 } },
		{ id = "starweave_gloves", prop = "starlight_gloves", name = "Starweave Gloves", tier = 6, price = 0, quest = true, relief = 0.9, scoopBonus = 18, carryBonus = 180, carrySpeed = 3.5, material = "Glass", color = { 120, 140, 210 } },
	},
}
