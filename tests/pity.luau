-- Headless checks for src/shared/Pity.luau, and what pity adds to needle income. Run: luau tests/pity.luau.
local Pity = require("../src/shared/Pity")
local Prices = require("../src/shared/Config/Prices")

local failed = 0
local function check(name, ok, detail)
	if not ok then
		failed += 1
		print(("FAIL %s%s"):format(name, detail and (": " .. tostring(detail)) or ""))
	end
end

local cfg = Prices.Pity
local chance = 1 / Prices.Mutation.oneIn

-- roll: hit under the chance, near up to nearMiss times it, nothing above.
check("a low roll hits", Pity.roll(chance * 0.5, chance, cfg.nearMiss) == "hit")
check("just over the chance is a near miss", Pity.roll(chance * 1.01, chance, cfg.nearMiss) == "near")
check("well over is nothing", Pity.roll(chance * cfg.nearMiss, chance, cfg.nearMiss) == nil)

-- apply: counts dry bales, forces exactly at cfg.bales, resets on any mutation, waits through needle-less bales.
local dry = 0
for i = 1, cfg.bales do
	local m = { 1, 1 }
	local hit
	dry, hit = Pity.apply(dry, m, cfg)
	check("bale " .. i .. " is not forced", not hit and m[1] == 1)
end
check("40 dry bales counted", dry == cfg.bales, dry)
local d2, hit2, forced2 = Pity.apply(dry, {}, cfg)
check("a bale with no needles leaves the count alone", d2 == cfg.bales and not hit2 and not forced2, d2)
local m = { 1, 1, 1 }
local d3, hit3, forced3 = Pity.apply(d2, m, cfg)
check("the next bale with a needle is forced", hit3 and forced3 and d3 == 0 and m[1] == cfg.mult and m[2] == 1)
local d4, hit4, forced4 = Pity.apply(17, { 1, 9 }, cfg)
check("a natural mutation resets without forcing", d4 == 0 and hit4 and not forced4)
local wetMult = Prices.WetMutation.mult
local d5, hit5 = Pity.apply(17, { 1, wetMult }, cfg)
check("a Wet needle does not end a dry run", d5 == 18 and not hit5, d5)
check("Wet is under the smallest real mutation, so x2 always means Wet", wetMult > 1 and wetMult < Prices.Mutation.min and wetMult < cfg.mult)

-- chance: boosts multiply, are capped, and bad boosts count as 1.
check("no boost is the base chance", Pity.chance(chance) == chance)
check("a storm's 5x and a 3x bale multiply", math.abs(Pity.chance(chance, 15) - chance * 15) < 1e-12)
check("the chance is capped", Pity.chance(chance, 1e9) == Pity.MAX_CHANCE)
check("a NaN or negative boost counts as 1", Pity.chance(chance, 0 / 0) == chance and Pity.chance(chance, -4) == chance)

-- Uplift: needle value (sum of multipliers) with and without pity, by needles found a bale. Found needles are
-- Poisson around NeedlesPerBale * recovery, mutations roll as Needle.rollMutation does.
-- A seeded generator with Roblox Random's NextNumber and NextInteger (the luau CLI has no Random; math.random is PCG).
local function newRng(seed)
	math.randomseed(seed)
	local r = {}
	function r:NextNumber()
		return math.random()
	end
	function r:NextInteger(a, b)
		return math.random(a, b)
	end
	return r
end
local function poisson(rng, mean)
	local l, k, p = math.exp(-mean), 0, 1
	repeat
		k += 1
		p *= rng:NextNumber()
	until p <= l
	return k - 1
end
-- weather: { storm = share of time a Thunderstorm is on, odds = its chance multiplier, wet = it always rains }.
local function run(mean, bales, withPity, weather)
	local rng = newRng(7)
	local value, d, longest, run, needles = 0, 0, 0, 0, 0
	for _ = 1, bales do
		local mults = {}
		local c, wet = chance, false
		if weather then
			c = Pity.chance(chance, rng:NextNumber() < weather.storm and weather.odds or 1)
			wet = weather.wet
		end
		for i = 1, poisson(rng, mean) do
			if rng:NextNumber() < c then
				mults[i] = rng:NextInteger(Prices.Mutation.min, Prices.Mutation.max)
			elseif wet and rng:NextNumber() * Prices.WetMutation.oneIn < 1 then
				mults[i] = Prices.WetMutation.mult
			else
				mults[i] = 1
			end
		end
		local hit = false
		if withPity then
			d, hit = Pity.apply(d, mults, cfg)
		else
			for _, x in mults do
				hit = hit or x > 1
			end
		end
		if #mults > 0 then
			run = hit and 0 or run + 1 -- dry run in bales that found a needle
		end
		longest = math.max(longest, run)
		for _, x in mults do
			value += x
		end
		needles += #mults
	end
	return value, longest, needles
end
local report = {}
for _, case in { { "meadow hand sieve", 2 * 0.15 }, { "meadow conveyor", 2 * 0.55 }, { "desert magnet", 4 * 0.75 }, { "swamp optical", 6 * 0.92 }, { "star optical", 20 * 0.92 } } do
	local bales = 300000
	local base = run(case[2], bales, false)
	local with, longest = run(case[2], bales, true)
	local up = (with - base) / base
	table.insert(report, ("%s %.1f%%"):format(case[1], up * 100))
	check(case[1] .. " pity adds under 5%", up >= 0 and up < 0.05, up)
	check(case[1] .. " never goes more than 40 needle bales dry", longest <= cfg.bales, longest)
end
print("pity uplift: " .. table.concat(report, ", "))

-- Weather budget (H7): a Thunderstorm (5x odds; Map measured it at x1.19 mutations an hour, so on about
-- 0.19 / 4 of the time) plus Wet needles, as if it always rained, plus pity, must add no more than 2x the mutation
-- value (multiplier above plain) of today's rules (pity, no weather). Bought boosts (Hay Market) are paid for, so
-- they are not in this budget.
local storm = { storm = 0.19 / 4, odds = 5, wet = true }
local weatherReport = {}
for _, case in { { "meadow hand sieve", 2 * 0.15 }, { "meadow conveyor", 2 * 0.55 }, { "swamp optical", 6 * 0.92 }, { "star optical", 20 * 0.92 } } do
	local bales = 300000
	local today, _, n1 = run(case[2], bales, true)
	local stormy, _, n2 = run(case[2], bales, true, storm)
	local ratio = (stormy - n2) / (today - n1)
	table.insert(weatherReport, ("%s x%.2f"):format(case[1], ratio))
	check(case[1] .. " storm + Wet + pity stays within 2x of today's mutation value", ratio <= 2, ratio)
end
print("weather budget (always raining): " .. table.concat(weatherReport, ", "))

if failed > 0 then
	print(("pity: %d failed"):format(failed))
	error("pity checks failed")
end
print("pity: all checks passed")
