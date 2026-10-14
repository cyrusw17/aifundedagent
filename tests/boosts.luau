-- Headless checks for src/shared/Boosts.luau (CEO H13): extras stack only up to Prices.Boosts.Cap, a bale's own boost
-- is never cut, and bad input is treated as no boost. Run: luau tests/boosts.luau.
local Boosts = require("../src/shared/Boosts")
local Prices = require("../src/shared/Config/Prices")

local failed = 0
local function check(name, ok, detail)
	if not ok then
		failed += 1
		print(("FAIL %s%s"):format(name, detail and (": " .. tostring(detail)) or ""))
	end
end
local function near(a, b)
	return math.abs(a - b) < 1e-6
end

local t = Boosts.terms(Prices)
local cap = Prices.Boosts.Cap
local storm, together = 5, 1.1 -- Weather.StormMutationOdds, LandConfig.TogetherBonus

check("a plain bale is worth 1", near(Boosts.value(t, 1, 1), 1))
local n, m = Boosts.fit(t, 1, 1, together, storm)
check("a plain bale keeps both extras", near(n, together) and m == storm, n)
n, m = Boosts.fit(t, 2, 1, together, storm)
check("a festival bale (2x) is already at the cap: no extras", near(n, 2) and m == 1, ("%s %s"):format(n, m))
check("and lands exactly on the cap", near(Boosts.value(t, n, m), cap))
n, m = Boosts.fit(t, 1.9, 1, together, storm)
check("a 1.9x bale is trimmed to the cap", near(Boosts.value(t, n, m), cap), Boosts.value(t, n, m))
n, m = Boosts.fit(t, 3, 1, together, storm)
check("a golden bale (3x) keeps its own 3x and gets nothing extra", near(n, 3) and m == 1)
n, m = Boosts.fit(t, 1, 25, together, storm)
check("a Moon Hay bale keeps its 25x odds", m >= 25 and Boosts.value(t, n, m) <= math.max(cap, Boosts.value(t, 1, 25)) + 1e-9)
n, m = Boosts.fit(t, 2, 5, together, storm)
check("a Storm Hay bale keeps exactly what it was sold with", near(n, 2) and m == 5, ("%s %s"):format(n, m))
n, m = Boosts.fit(t, 0 / 0, -3, math.huge, nil)
check("bad input counts as no boost", n == 1 and m == 1, ("%s %s"):format(n, m))
for _, own in { 1, 1.2, 1.5, 1.8, 2, 2.5 } do
	for _, ownMut in { 1, 5, 25 } do
		local a, b = Boosts.fit(t, own, ownMut, together, storm)
		local limit = math.max(cap, Boosts.value(t, own, ownMut))
		check(("never over the limit (%s, %s)"):format(own, ownMut), Boosts.value(t, a, b) <= limit + 1e-9)
		check(("never under the bale's own (%s, %s)"):format(own, ownMut), a >= own - 1e-9 and b >= ownMut)
	end
end

print(failed == 0 and "boosts: all checks passed" or ("boosts: %d FAILED"):format(failed))
if failed > 0 then
	error("boosts checks failed")
end
