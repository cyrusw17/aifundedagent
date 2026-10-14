--!strict
-- Line rates (CEO #28): what one sorter line earns, kept full or fed at a set rate. The same arithmetic as
-- tools/line_sim.py line(), so the number on a sorter's sign and the offline sim can't drift apart:
-- tools/linecheck/rates.py runs both on sample layouts and fails on any difference.
--
--   LineRate.line(hayType, tierId, feed?, oil?, treated?, market?)
--     -> { bales, needles, perBale, perMin, perHour, grade, refused? }
--   LineRate.measured(log, now, window) -> bales/min, needles/min, $/hour of what a sorter really did
--   feed: bales a minute reaching the sorter (nil keeps it full); oil: the sorter is oiled; treated: region hay went
--   through its machine (default true); market: Market.multiplier for the needle type (default 1, list price).
local Shared = script.Parent
local Prices = require(Shared.Config.Prices)
local Sorters = require(Shared.Config.Sorters)
local Factory = require(Shared.Config.Factory)
local Needles = require(Shared.Config.Needles)
local HayTypes = require(Shared.Config.Gloves).HayTypes

local LineRate = {}

local tiers = {}
for _, tier in Sorters do
	tiers[tier.id] = tier
end
local needleForMap = {}
for _, n in Needles do
	needleForMap[n.map] = n.id
end

-- The needle type a hay type hides (same map name), as Needle.forHay.
function LineRate.needleFor(hayType: string): string
	local hay = HayTypes[hayType]
	return hay and needleForMap[hay.map] or Needles[1].id
end

-- What the public shop (or a buyer, unsorted) pays for one bale.
function LineRate.rawBale(hayType: string): number
	return Prices.HayPerBale * Prices.HayPrice + (Prices.NeedlesPerBale[hayType] or 0) * Prices.RawNeedlePrice
end

function LineRate.line(hayType: string, tierId: string, feed: number?, oil: boolean?, treated: boolean?, market: number?)
	local tier = tiers[tierId] or tiers.conveyor_sorter
	local rec = tier.recovery
	local full = Prices.SorterBalesPerMinute[tier.id] or 0
	local rate = if oil then full * (1 + Prices.SorterOil.speedup) else full
	local bales = if feed == nil then rate else math.min(feed, rate)
	local t = Factory.Treatments[hayType]
	if t and treated == false then
		if t.required then
			return { bales = 0, needles = 0, perBale = 0, perMin = 0, perHour = 0, grade = "B", refused = t.machine }
		end
		rec *= t.penalty
	end
	local grade = Prices.SorterGrade[tier.id] or "B"
	local needlePrice = Prices.Needles[LineRate.needleFor(hayType)] * (1 + (Prices.NeedleGrades[grade] or 0)) * (market or 1)
	local needles = (Prices.NeedlesPerBale[hayType] or 0) * rec
	local perBale = Prices.HayPerBale * Prices.HayPrice + needles * needlePrice
	return {
		bales = bales,
		needles = needles * bales,
		perBale = perBale,
		perMin = perBale * bales,
		perHour = perBale * bales * 60,
		grade = grade,
	}
end

-- What a sorter actually did lately. log: { { t, bales, needles, dollars } }, oldest first; entries older than window
-- seconds are dropped from it. Averaged over the time since the oldest entry, at least a minute, so a fresh line does
-- not read as huge. Returns bales/min, needles/min, $/hour.
function LineRate.measured(log: { { number } }, now: number, window: number): (number, number, number)
	while log[1] and now - log[1][1] > window do
		table.remove(log, 1)
	end
	local bales, needles, dollars = 0, 0, 0
	for _, e in log do
		bales += e[2]
		needles += e[3]
		dollars += e[4]
	end
	local span = math.clamp(now - (if log[1] then log[1][1] else now), 60, window)
	return bales / span * 60, needles / span * 60, dollars / span * 3600
end

-- "4.2", "38", "12k", "1.3M" for a sign.
function LineRate.short(n: number): string
	if n >= 1e6 then
		return ("%.1fM"):format(n / 1e6)
	elseif n >= 1e4 then
		return ("%.0fk"):format(n / 1e3)
	elseif n >= 10 then
		return ("%d"):format(math.round(n))
	end
	return ("%.1f"):format(n)
end

return LineRate
