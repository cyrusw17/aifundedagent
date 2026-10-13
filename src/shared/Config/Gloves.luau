--!strict
-- Gloves and hay weight. The only tools are the shovel and the rake; gloves are the upgrade. Carried hay slows
-- you down, rarer hay is heavier, and hay rarer than your gloves are rated for slows you much more and scoops
-- slower. Better gloves take the edge off. Every number here is a placeholder to tune from playtests.
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
		swamp = { name = "Bog reed", map = "Swamp", weight = 2.4, tier = 3 },
		volcano = { name = "Ashen hay", map = "Volcano", weight = 3.0, tier = 4 },
		cave = { name = "Crystal hay", map = "Cave", weight = 3.4, tier = 4 },
		sky = { name = "Cloud hay", map = "Sky Island", weight = 4.0, tier = 5 },
		haunted = { name = "Phantom hay", map = "Haunted Grove", weight = 4.5, tier = 5 },
		star = { name = "Star hay", map = "Star Hay", weight = 6.0, tier = 6 }, -- beyond every glove: always a struggle
	},
	DefaultHayType = "meadow",

	-- Glove tiers, worst to best. relief is the fraction of slowdown taken away. scoopBonus adds strands per shovel
	-- scoop, carryBonus adds to how much hay you can hold. prop names the Rustic Blender glove (one right glove,
	-- fingers +Y, back of hand -Z; mirror it for the left). color is for the placeholder until the mesh is in.
	Tiers = {
		{ id = "bare", name = "Bare hands", tier = 0, price = 0, relief = 0, scoopBonus = 0, carryBonus = 0, color = { 214, 178, 150 } },
		{ id = "work", prop = "work_gloves", name = "Work Gloves", tier = 1, price = 250, relief = 0.2, scoopBonus = 2, carryBonus = 15, color = { 189, 168, 112 } },
		{ id = "leather", prop = "leather_gloves", name = "Leather Gloves", tier = 2, price = 1500, relief = 0.35, scoopBonus = 4, carryBonus = 30, color = { 128, 92, 62 } },
		{ id = "reinforced", prop = "reinforced_gloves", name = "Reinforced Gloves", tier = 3, price = 6000, relief = 0.5, scoopBonus = 6, carryBonus = 50, color = { 92, 74, 54 } },
		{ id = "iron", prop = "iron_gauntlets", name = "Iron Gauntlets", tier = 4, price = 25000, relief = 0.62, scoopBonus = 9, carryBonus = 80, color = { 107, 94, 84 } },
		{ id = "starlight", prop = "starlight_gloves", name = "Starlight Gloves", tier = 5, price = 150000, relief = 0.78, scoopBonus = 14, carryBonus = 140, color = { 70, 72, 96 } },
	},
}
