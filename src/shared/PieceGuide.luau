--!strict
-- One line per plot piece for the build bar and shop tooltips, in plain player words, built from the configs so the
-- numbers are always right ("Finds 35% of the needles, 4 bales a minute."). Pieces with nothing to compute keep
-- their blurb from Config/Land.
--
--   PieceGuide.line(def)   -- def: a Config/Land Pieces entry
local Shared = script.Parent
local Prices = require(Shared.Config.Prices)
local Sorters = require(Shared.Config.Sorters)
local Factory = require(Shared.Config.Factory)
local HayTypes = require(Shared.Config.Gloves).HayTypes

local PieceGuide = {}

local tiers = {}
for _, tier in Sorters do
	tiers[tier.id] = tier
end

local function percent(x: number): string
	return ("%d%%"):format(math.round(x * 100))
end

local function gradeText(tierId: string): string
	local grade = Prices.SorterGrade[tierId] or "B"
	local bonus = Prices.NeedleGrades[grade] or 0
	if bonus > 0 then
		return (" Needles come out %s grade (+%s at sale)."):format(grade, percent(bonus))
	end
	return ""
end

function PieceGuide.line(def: any): string
	if def.kind == "separator" then
		local tier = tiers[def.id]
		if tier and tier.hayPerMin == math.huge then
			return ("Finds every needle at once while its beam is up (%d s, once a day).%s"):format(Factory.AlienWindowSeconds, gradeText(def.id))
		elseif tier then
			local perMin = Prices.SorterBalesPerMinute[def.id] or tier.hayPerMin / Prices.HayPerBale
			return ("Finds %s of the needles, %g bales a minute.%s"):format(percent(tier.recovery), perMin, gradeText(def.id))
		end
	elseif def.kind == "treat" then
		for hayType, t in Factory.Treatments do
			if t.machine == def.id then
				local name = HayTypes[hayType] and HayTypes[hayType].name or hayType
				if t.required then
					return ("%s must pass through here before a sorter will take it."):format(name)
				end
				return ("Without it, sorters find only %s of the needles in %s."):format(percent(t.penalty or 1), name)
			end
		end
	elseif def.kind == "baler" then
		return ("Packs every %d loose strands on the belt into a bale, so raked hay can feed your line."):format(Prices.HayPerBale)
	elseif def.kind == "vault" then
		return "Holds any number of needles with no clutter and saves them. E puts your pocket in, T takes it all out."
	end
	return def.blurb or ""
end

return PieceGuide
