-- Headless checks for src/shared/LineMath.luau. Run: luau tests/line_math.luau (exits non-zero on failure).
local LineMath = require("../src/shared/LineMath")

local failed = 0
local function check(name, got, want)
	if got ~= want then
		failed += 1
		print(("FAIL %s: got %s, want %s"):format(name, tostring(got), tostring(want)))
	end
end

-- Keys round-trip for every combination of mutation and polish.
for _, case in { { "steel", 1, false }, { "steel", 12, false }, { "pine", 1, true }, { "cosmic", 25, true } } do
	local key = LineMath.keyOf(case[1], case[2], case[3])
	local id, mult, polished = LineMath.parseKey(key)
	check("id " .. key, id, case[1])
	check("mult " .. key, mult, case[2])
	check("polished " .. key, polished, case[3])
end
check("plain key is the bare id", LineMath.keyOf("steel", 1, false), "steel")
check("mutated key", LineMath.keyOf("steel", 7), "steel*7")
check("polished mutated key", LineMath.keyOf("ice", 3, true), "ice*3!")
-- An id with no suffix parses as plain.
local id, mult, polished = LineMath.parseKey("geode")
check("bare id", id, "geode")
check("bare mult", mult, 1)
check("bare polish", polished, false)

-- Grades: B is the default and adds nothing to the key; A and S go last.
check("A grade key", LineMath.keyOf("steel", 1, false, "A"), "steel#A")
check("B grade key is plain", LineMath.keyOf("steel", 1, false, "B"), "steel")
check("everything key", LineMath.keyOf("ice", 3, true, "S"), "ice*3!#S")
local gid, gmult, gpol, grade = LineMath.parseKey("ice*3!#S")
check("graded id", gid, "ice")
check("graded mult", gmult, 3)
check("graded polish", gpol, true)
check("graded grade", grade, "S")
local _, _, _, oldGrade = LineMath.parseKey("steel*5")
check("old keys read as B", oldGrade, "B")
check("plain keys", table.concat(LineMath.plainKeys("pine"), ","), "pine,pine#A,pine#S,pine!,pine!#A,pine!#S")
check("S grade price", LineMath.price(100, 1, false, 0.25, 1, 0.25), 125)

-- Prices: steel $100, x12 mutation, 25% polish, market +10%.
check("plain price", LineMath.price(100, 1, false, 0.25, 1), 100)
check("mutated price", LineMath.price(100, 12, false, 0.25, 1), 1200)
check("polished price", LineMath.price(100, 1, true, 0.25, 1), 125)
check("market price rounds", LineMath.price(110, 1, false, 0.25, 0.83), 91)
check("all together", LineMath.price(100, 3, true, 0.25, 1.1), 413)

-- Sort timing: 90 strands (one bale) at 180 hay/min is 30 s; tiny loads take at least 0.5 s; the Alien is instant.
check("bale at hand sieve", LineMath.sortSeconds(180, 90), 30)
check("floor", LineMath.sortSeconds(100000, 1), 0.5)
check("alien", LineMath.sortSeconds(math.huge, 90), 0.4)

-- Bundles of 10.
local b, rest = LineMath.bundles(27, 10)
check("bundles", b, 2)
check("loose", rest, 7)
b, rest = LineMath.bundles(9, 10)
check("no bundle", b, 0)
check("all loose", rest, 9)

-- Pocket merge: needles picked up before a save loads join the slot's pocket.
local slot = { steel = 3, ["steel*5"] = 1 }
LineMath.merge(slot, { steel = 2, ["pine!"] = 4 })
check("merged steel", slot.steel, 5)
check("merged mutated kept", slot["steel*5"], 1)
check("merged polished pine", slot["pine!"], 4)
check("total", LineMath.total(slot), 10)
check("merge nil", LineMath.total(LineMath.merge({ a = 1 }, nil)), 1)

-- A seeded stand-in for Roblox's Random, so roll tests are repeatable.
local function seeded(seed)
	local state = seed
	return {
		NextNumber = function()
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end,
	}
end

-- Recovery rolls: never more than hidden, none at 0%, all at 100%, and about recovery x hidden on average.
check("found none at 0%", LineMath.found(seeded(1), 50, 0), 0)
check("found all at 100%", LineMath.found(seeded(1), 50, 1), 50)
check("found is repeatable", LineMath.found(seeded(7), 40, 0.55), LineMath.found(seeded(7), 40, 0.55))
local total = 0
local rng = seeded(42)
for _ = 1, 2000 do
	total += LineMath.found(rng, 10, 0.55)
end
check("found averages recovery x hidden", math.abs(total / 2000 - 5.5) < 0.25, true)
local halved = 0
rng = seeded(42)
for _ = 1, 2000 do
	halved += LineMath.found(rng, 10, 0.75, 0.5)
end
check("ash penalty halves recovery", math.abs(halved / 2000 - 3.75) < 0.25, true)

-- Oil: cans stack to the cap and no further; each oiled bale is faster and uses one up.
check("first can", LineMath.oilAdd(0, 25, 75), 25)
check("third can", LineMath.oilAdd(50, 25, 75), 75)
check("fourth can refused", LineMath.oilAdd(75, 25, 75), nil)
local sec, left = LineMath.oiledSeconds(11, 25, 0.1)
check("oiled bale is 10% faster", sec, 10)
check("oiled bale uses one up", left, 24)
sec, left = LineMath.oiledSeconds(11, 0, 0.1)
check("unoiled bale", sec, 11)
check("no oil stays none", left, 0)

-- Region treatments (Config/Factory Treatments shape).
local treatments = {
	snow = { mark = "Thawed", required = true },
	volcano = { mark = "Sifted", required = false, penalty = 0.5 },
}
local what, mult = LineMath.treatment("snow", treatments, false)
check("frozen untreated is refused", what, "refuse")
what, mult = LineMath.treatment("snow", treatments, true)
check("frozen thawed sorts", what .. mult, "sort1")
what, mult = LineMath.treatment("volcano", treatments, false)
check("ashen untreated sorts at half", what .. mult, "sort0.5")
what, mult = LineMath.treatment("meadow", treatments, false)
check("meadow needs nothing", what .. mult, "sort1")

-- Grades by tier.
local grade, bonus = LineMath.grade("optical_sorter", { optical_sorter = "S", magnet_drum = "A" }, { B = 0, A = 0.1, S = 0.25 })
check("optical is S", grade .. bonus, "S0.25")
grade, bonus = LineMath.grade("hand_sieve", { optical_sorter = "S" }, { B = 0, A = 0.1, S = 0.25 })
check("unlisted tier is B", grade .. bonus, "B0")

-- The live configs: every sorter has a grade, grades never lower a price, and every treatment is well formed.
local Prices = require("../src/shared/Config/Prices")
local Factory = require("../src/shared/Config/Factory")
for tierId in Prices.SorterBalesPerMinute do
	check("grade for " .. tierId, Prices.SorterGrade[tierId] ~= nil, true)
end
for g, b in Prices.NeedleGrades do
	check("grade " .. g .. " bonus is not negative", b >= 0, true)
end
for hay, t in Factory.Treatments do
	check("treatment " .. hay .. " has a mark", typeof(t.mark) == "string" or type(t.mark) == "string", true)
	check("treatment " .. hay .. " refuses or has a penalty", t.required == true or (t.penalty and t.penalty > 0 and t.penalty < 1), true)
	check("treatment " .. hay .. " machine is priced", Prices.Pieces[t.machine] ~= nil, true)
end

if failed > 0 then
	error(("%d line math checks failed"):format(failed))
end
print("line math: all checks passed")
