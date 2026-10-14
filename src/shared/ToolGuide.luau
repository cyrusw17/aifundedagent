--!strict
-- One plain line per hand tool, shovel tier and the wheelbarrow, for the hotbar tooltips, the shovel rack and the
-- shop, built from the configs so the numbers are always the real ones ("Steel Shovel: carries 90 hay a load, ..."). The same
-- pattern as PieceGuide (Conveyor thread) for plot pieces.
--
--   ToolGuide.tool("Shovel" | "Rake" | "Wheelbarrow")
--   ToolGuide.glove(def)          -- def: a Config/Gloves Tiers or QuestTiers entry (a shovel tier)
local Shared = script.Parent
local Game = require(Shared.Config.Game)
local Gloves = require(Shared.Config.Gloves)
local Prices = require(Shared.Config.Prices)
local HayMath = require(Shared.HayMath)

local ToolGuide = {}

local WALK = Game.WalkSpeed -- the empty-handed walk every avatar starts with (Avatar)

local function percent(x: number): string
	return ("%d%%"):format(math.round(x * 100))
end

-- Walk speed carrying one dry meadow bale with this shovel.
local function baleSpeed(def: any): number
	local meadow = Gloves.HayTypes.meadow
	return HayMath.speed(def, WALK, HayMath.baleWeight(meadow, false, Game, Gloves), meadow.tier, Gloves)
end

-- The rarest hays this shovel handles with no extra slowdown, by name ("Desert grass and Frozen hay").
local function rated(def: any): string?
	local bestTier = -1
	for _, hay: any in Gloves.HayTypes do
		if hay.tier <= def.tier and hay.tier > bestTier then
			bestTier = hay.tier
		end
	end
	local names = {}
	for _, hay: any in Gloves.HayTypes do
		if hay.tier == bestTier then
			table.insert(names, hay.name)
		end
	end
	table.sort(names)
	if #names == 0 then
		return nil
	elseif #names == 1 then
		return names[1]
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

function ToolGuide.glove(def: any): string
	local load = Game.CarryCapacity + def.carryBonus
	if def.tier == 0 then
		return ("%s: carries %d hay a load. Walk %.1f with a meadow bale. Better shovels carry more, scoop more and slow you less under a load."):format(
			def.name,
			load,
			baleSpeed(def)
		)
	end
	local parts = {
		("carries %d hay a load (%d more)"):format(load, def.carryBonus),
		("%d more per scoop"):format(def.scoopBonus),
		("%s less slowdown"):format(percent(def.relief)),
	}
	local line = ("%s: %s. Walk %.1f with a meadow bale (Old Shovel %.1f)."):format(
		def.name,
		table.concat(parts, ", "),
		baleSpeed(def),
		baleSpeed(Gloves.Tiers[1])
	)
	local hay = rated(def)
	if hay then
		line ..= (" Rated up to %s."):format(hay)
	end
	if def.tier >= Game.DoubleCarryTier then
		line ..= " Carries two bales at once."
	end
	return line
end

function ToolGuide.tool(kind: string): string
	if kind == "Shovel" then
		return ("Click a hay pile or loose hay to scoop %d strands (more with a better shovel and quick combos). With a load on it, click your parked wheelbarrow to tip it in, or a truck bed, belt or the sell pad to pour %d. Click a bale to smash it."):format(
			Game.ShovelPieces,
			Game.PourStrands
		)
	elseif kind == "Rake" then
		return ("Pulls loose hay within %d studs toward you, and a few strands off a field's pile each stroke. Rake %d or more strands together for a pile the shovel takes in one go. End a stroke at a belt to flick the hay onto it."):format(
			Game.RakeRadius,
			Game.PileMin
		)
	elseif kind == "Wheelbarrow" then
		return ("Put it away to park it, then tip shovel loads in: every %d hay presses a bale. Rolling, it holds %d bales and you feel %s of their weight. Click a bale to load it, or a truck bed to tip the load in."):format(
			Game.PiecesPerBale,
			Game.WheelbarrowBales,
			percent(Game.WheelbarrowLoadFactor)
		)
	end
	return ""
end

-- The wheelbarrow's shop line, with its price.
function ToolGuide.wheelbarrowShop(): string
	return ("Wheelbarrow ($%d): fill it from your shovel and every %d hay presses a bale. Holds %d bales to roll to the truck."):format(
		Prices.Wheelbarrow,
		Game.PiecesPerBale,
		Game.WheelbarrowBales
	)
end

return ToolGuide
