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

-- Uplift: needle value (sum of multipliers) with and without pity, by needles found a bale. Found needles are
-- Poisson around NeedlesPerBale * recovery, mutations roll as Needle.rollMutation does.
-- A small seeded generator (the luau CLI has no Random): NextNumber and NextInteger like Roblox's Random.
local function newRng(seed)
	local state = seed
	local r = {}
	function r:NextNumber()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	function r:NextInteger(a, b)
		return a + math.floor(self:NextNumber() * (b - a + 1))
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
local function run(mean, bales, withPity)
	local rng = newRng(7)
	local value, d, longest, run = 0, 0, 0, 0
	for _ = 1, bales do
		local mults = {}
		for i = 1, poisson(rng, mean) do
			mults[i] = rng:NextNumber() < chance and rng:NextInteger(Prices.Mutation.min, Prices.Mutation.max) or 1
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
	end
	return value, longest
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

if failed > 0 then
	print(("pity: %d failed"):format(failed))
	error("pity checks failed")
end
print("pity: all checks passed")
