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

if failed > 0 then
	error(("%d line math checks failed"):format(failed))
end
print("line math: all checks passed")
