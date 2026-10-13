-- Headless checks for src/shared/NeedleIndex.luau. Run: luau tests/needle_index.luau (exits non-zero on failure).
local NeedleIndex = require("../src/shared/NeedleIndex")
local Prices = require("../src/shared/Config/Prices")

local failed = 0
local function check(name, ok, detail)
	if not ok then
		failed += 1
		print(("FAIL %s%s"):format(name, detail and (": " .. tostring(detail)) or ""))
	end
end

local ids = {}
for id in Prices.Needles do
	table.insert(ids, id)
end
table.sort(ids)
local wet = Prices.WetMutation.mult
local milestones = {}
for _, r in Prices.NeedleIndex do
	table.insert(milestones, r.at)
end

-- Keys by kind.
check("a plain needle", NeedleIndex.key("steel", 1, wet) == "steel")
check("a Wet needle", NeedleIndex.key("steel", wet, wet) == "steel:wet")
check("a mutated needle", NeedleIndex.key("steel", 17, wet) == "steel:mutated")
check("no mult is plain", NeedleIndex.key("pine", nil, wet) == "pine")
local all = NeedleIndex.entries(ids)
check("every type in each kind", #all == #ids * #NeedleIndex.KINDS, #all)

-- Rewards: finding every entry in a shuffled order reaches each milestone exactly once, at its percent.
math.randomseed(3)
for i = #all, 2, -1 do
	local j = math.random(1, i)
	all[i], all[j] = all[j], all[i]
end
local index = NeedleIndex.clean(nil)
local paidAt = {}
for n, key in all do
	local isNew, reached = NeedleIndex.record(index, key, ids, milestones)
	check("entry " .. key .. " is new", isNew)
	for _, m in reached do
		check("milestone " .. m .. " paid once", paidAt[m] == nil)
		paidAt[m] = n
		check("milestone " .. m .. " reached at its percent", math.floor(n / #all * 100) >= m and math.floor((n - 1) / #all * 100) < m, n)
	end
	local again, more = NeedleIndex.record(index, key, ids, milestones)
	check("finding " .. key .. " again pays nothing", not again and #more == 0)
end
for _, m in milestones do
	check("milestone " .. m .. " was reached", paidAt[m] ~= nil)
end
check("100% at the end", NeedleIndex.percent(index, ids) == 100)

-- Save round trip: through toSave, a JSON-like string-key copy, and clean, nothing changes and nothing pays again.
local function copy(t)
	local out = {}
	for k, v in t do
		out[tostring(k)] = typeof(v) == "table" and copy(v) or v
	end
	return out
end
local back = NeedleIndex.clean(copy(NeedleIndex.toSave(index)))
local have, total = NeedleIndex.count(back, ids)
check("every entry comes back", have == total, have)
for _, m in milestones do
	check("paid milestone " .. m .. " comes back", back.paid[m] == true)
end
local _, again = NeedleIndex.record(back, "steel", ids, milestones)
check("a loaded full index pays nothing more", #again == 0)

-- A partial index reloads, keeps its paid marks, and goes on paying only what is left.
local part = NeedleIndex.clean(nil)
for i = 1, math.ceil(#all * 0.3) do
	NeedleIndex.record(part, all[i], ids, milestones)
end
local reloaded = NeedleIndex.clean(copy(NeedleIndex.toSave(part)))
check("30% keeps its 25% mark", reloaded.paid[25] == true and not reloaded.paid[50])
local later = {}
for i = math.ceil(#all * 0.3) + 1, #all do
	local _, r = NeedleIndex.record(reloaded, all[i], ids, milestones)
	for _, m in r do
		table.insert(later, m)
	end
end
check("after reload only 50, 75 and 100 pay", table.concat(later, ",") == "50,75,100", table.concat(later, ","))

-- Junk saves load as an empty or trimmed index.
local junk = NeedleIndex.clean({ found = { steel = true, ["bad key!"] = true, [4] = true, pine = "yes", ["ice:wet"] = true }, paid = { ["25"] = true, ["200"] = true, x = true } })
check("junk keys are dropped", junk.found.steel and junk.found["ice:wet"] and not junk.found.pine and not junk.found["bad key!"])
check("junk paid marks are dropped", junk.paid[25] and not junk.paid[200])
check("a non-table save is empty", next(NeedleIndex.clean("x").found) == nil)

if failed > 0 then
	print(("needle index: %d failed"):format(failed))
	error("needle index checks failed")
end
print(("needle index: all checks passed (%d entries)"):format(#all))
