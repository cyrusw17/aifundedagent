--!strict
-- One plain line per hand tool, glove pair and the wheelbarrow, for the hotbar tooltips, the glove stand and the shop,
-- built from the configs so the numbers are always the real ones ("Leather Gloves: carry 30 more hay, ..."). The same
-- pattern as PieceGuide (Conveyor thread) for plot pieces.
--
--   ToolGuide.tool("Shovel" | "Rake" | "Wheelbarrow")
--   ToolGuide.glove(def)          -- def: a Config/Gloves Tiers or QuestTiers entry
local Shared = script.Parent
local Game = require(Shared.Config.Game)
local Gloves = require(Shared.Config.Gloves)
local Prices = require(Shared.Config.Prices)
local HayMath = require(Shared.HayMath)

local ToolGuide = {}

local WALK = 16 -- Roblox's default walk speed, what every avatar starts with

local function percent(x: number): string
	return ("%d%%"):format(math.round(x * 100))
end

-- Walk speed carrying one dry meadow bale with these gloves.
local function baleSpeed(def: any): number
	local meadow = Gloves.HayTypes.meadow
	return HayMath.speed(def, WALK, HayMath.baleWeight(meadow, false, Game, Gloves), meadow.tier, Gloves)
end

-- The rarest hays these gloves handle with no extra slowdown, by name ("Desert grass and Frozen hay").
local function rated(def: any): string?
	local bestTier = -1
	for _, hay in Gloves.HayTypes do
		if hay.tier <= def.tier and hay.tier > bestTier then
			bestTier = hay.tier
		end
	end
	local names = {}
	for _, hay in Gloves.HayTypes do
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
	if def.tier == 0 then
		return ("Bare hands: walk %.1f with a meadow bale. Better gloves carry more, scoop more and walk faster under a load."):format(baleSpeed(def))
	end
	local parts = {
		("carry %d more hay"):format(def.carryBonus),
		("%d more per scoop"):format(def.scoopBonus),
		("%s less slowdown"):format(percent(def.relief)),
	}
	local line = ("%s: %s. Walk %.1f with a meadow bale (bare hands %.1f)."):format(
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
		return ("Click a bale to smash it, or loose hay to scoop %d strands (more with gloves and quick combos). With hay in your arms, click a truck bed, belt or the sell pad to pour %d."):format(
			Game.ShovelPieces,
			Game.PourStrands
		)
	elseif kind == "Rake" then
		return ("Pulls loose hay within %d studs toward you. Rake %d or more strands together for a pile the shovel takes in one go. End a stroke at a belt to flick the hay onto it."):format(
			Game.RakeRadius,
			Game.PileMin
		)
	elseif kind == "Wheelbarrow" then
		return ("Holds %d bales and you feel %s of their weight. Click a bale to load it, a truck bed to tip the load in, or the ground to set it down."):format(
			Game.WheelbarrowBales,
			percent(Game.WheelbarrowLoadFactor)
		)
	end
	return ""
end

-- The wheelbarrow's shop line, with its price.
function ToolGuide.wheelbarrowShop(): string
	return ("Wheelbarrow ($%d): holds %d bales, you feel %s of their weight."):format(
		Prices.Wheelbarrow,
		Game.WheelbarrowBales,
		percent(Game.WheelbarrowLoadFactor)
	)
end

return ToolGuide
