--!strict
-- Pure math for the conveyor line and needles, with no Roblox services, so tests/line_math.luau can run it headless
-- (luau tests/line_math.luau). Needle.luau and Machines.luau use these.
local LineMath = {}

-- Pocket and save key for a needle: its id, or "id*mult" when mutated, then "!" when polished, then "#A" or "#S" for
-- a grade above B (B, the default, adds nothing, so keys from before grades still read as B).
function LineMath.keyOf(id: string, mult: number?, polished: boolean?, grade: string?): string
	local key = (mult and mult > 1) and ("%s*%d"):format(id, mult) or id
	if polished then
		key ..= "!"
	end
	if grade and grade ~= "B" then
		key ..= "#" .. grade
	end
	return key
end

-- The id, multiplier, polish and grade of a key from keyOf.
function LineMath.parseKey(key: string): (string, number, boolean, string)
	local grade = "B"
	local base, g = string.match(key, "^(.*)#(%u)$")
	if base then
		key, grade = base, g :: string
	end
	local polished = string.sub(key, -1) == "!"
	if polished then
		key = string.sub(key, 1, -2)
	end
	local id, mult = string.match(key, "^(.-)%*(%d+)$")
	if id then
		return id, tonumber(mult) :: number, polished, grade
	end
	return key, 1, polished, grade
end

-- Every key a plain (unmutated) needle of this id can have, cheapest first: B, A, S, then the polished ones.
function LineMath.plainKeys(id: string): { string }
	local keys = {}
	for _, polished in { false, true } do
		for _, grade in { "B", "A", "S" } do
			table.insert(keys, LineMath.keyOf(id, 1, polished, grade))
		end
	end
	return keys
end

-- Dollars for one needle: list value x mutation x polish x grade x market, rounded to whole dollars.
function LineMath.price(listValue: number, mult: number?, polished: boolean?, polishBonus: number, market: number, gradeBonus: number?): number
	local polish = if polished then 1 + polishBonus else 1
	return math.floor(listValue * (mult or 1) * polish * (1 + (gradeBonus or 0)) * market + 0.5)
end

-- Seconds a sorter spends on `hay` strands at hayPerMin (math.huge for the Alien collector), before oil.
function LineMath.sortSeconds(hayPerMin: number, hay: number): number
	if hayPerMin == math.huge then
		return 0.4
	end
	return math.max(hay / hayPerMin * 60, 0.5)
end

-- How many of `hidden` needles a sorter finds: each one is found with chance recovery x recoveryMult. rng is anything
-- with NextNumber() (a Roblox Random, or a seeded stand-in in tests).
function LineMath.found(rng: any, hidden: number, recovery: number, recoveryMult: number?): number
	local chance = recovery * (recoveryMult or 1)
	local n = 0
	for _ = 1, hidden do
		if rng:NextNumber() < chance then
			n += 1
		end
	end
	return n
end

-- Sorter oil: bales already oiled plus one more can, or nil when that would go over the cap.
function LineMath.oilAdd(oiled: number, perCan: number, maxBales: number): number?
	if oiled + perCan > maxBales then
		return nil
	end
	return oiled + perCan
end

-- Seconds for one bale with oil: faster by speedup while any oiled bales are left. Returns seconds and oiled bales left.
function LineMath.oiledSeconds(seconds: number, oiled: number, speedup: number): (number, number)
	if oiled > 0 then
		return seconds / (1 + speedup), oiled - 1
	end
	return seconds, oiled
end

-- What a sorter does with a whole bale of hayType given its treatments table (Config/Factory Treatments) and whether
-- the bale carries the treatment's mark: "sort" with a recovery multiplier, or "refuse" (it rides on unsorted).
function LineMath.treatment(hayType: string, treatments: { [string]: any }, marked: boolean): (string, number)
	local t = treatments[hayType]
	if not t or marked then
		return "sort", 1
	end
	if t.required then
		return "refuse", 0
	end
	return "sort", t.penalty or 1
end

-- The grade a sorter tier gives (sorterGrade: Prices.SorterGrade) and that grade's sale bonus (grades: NeedleGrades).
function LineMath.grade(tierId: string, sorterGrade: { [string]: string }, grades: { [string]: number }): (string, number)
	local g = sorterGrade[tierId] or "B"
	return g, grades[g] or 0
end

-- How a pile of plain needles packs: whole bundles of `size` and the loose rest.
function LineMath.bundles(count: number, size: number): (number, number)
	return count // size, count % size
end

-- Adds every count in `from` into `into` (both { [key] = count }). Returns into.
function LineMath.merge(into: { [string]: number }, from: { [string]: number }?): { [string]: number }
	for key, count in (from or {}) :: { [string]: number } do
		into[key] = (into[key] or 0) + count
	end
	return into
end

-- Total needles in a { [key] = count } map.
function LineMath.total(map: { [string]: number }): number
	local n = 0
	for _, count in map do
		n += count
	end
	return n
end

return LineMath
