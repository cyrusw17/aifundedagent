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

-- Bottleneck lamp on a sorter (CEO #29): "green", "amber" or "red", and the reason the sign shows (nil when green).
-- s: { sorting, idleSeconds (since it last sorted, or since it was built), queued (bales waiting upstream),
-- queuedSeconds (how long a queue of 2+ has stood), jammed (a jammed bale at it), refusedSeconds (since it last
-- refused untreated hay), need (that hay's machine name), beamDown (Alien collector waiting for its beam) }.
LineMath.STARVED_SECONDS = 6
LineMath.BACKUP_SECONDS = 20
LineMath.REFUSED_SECONDS = 10
function LineMath.lamp(s: { [string]: any }): (string, string?)
	if s.jammed then
		return "red", "belt jammed: press J at the bale"
	end
	if s.refusedSeconds and s.refusedSeconds < LineMath.REFUSED_SECONDS then
		return "red", ("needs a %s first"):format(s.need or "region machine")
	end
	if (s.queued or 0) >= 2 and (s.queuedSeconds or 0) >= LineMath.BACKUP_SECONDS then
		return "red", "backed up: this sorter is the slow one"
	end
	if s.sorting then
		return "green", nil
	end
	if s.beamDown then
		return "amber", "waiting for its beam"
	end
	if (s.queued or 0) == 0 and (s.idleSeconds or 0) >= LineMath.STARVED_SECONDS then
		return "amber", "waiting for bales"
	end
	return "green", nil
end

-- How a needle bin keeps its part count bounded however long a line runs (CEO #35). parts: { { key, count } }, one per
-- needle part in the bin (a single is count 1). Returns the merges to make: { { key = key, parts = { indices },
-- count = total } }. Per key: plain singles tie into bundles of `bundle`; once a key has `crateAt` or more stacked
-- parts (bundles and crates), or `crateAt` mutated singles, they all become one crate. So a key never holds more than
-- bundle - 1 plain singles, crateAt - 1 mutated singles and crateAt - 1 bundles plus one crate.
LineMath.CRATE_AT = 5
function LineMath.pack(parts: { { any } }, bundle: number, crateAt: number?): { { [string]: any } }
	local at = crateAt or LineMath.CRATE_AT
	local byKey: { [string]: { singles: { number }, stacks: { number } } } = {}
	for i, p in parts do
		local g = byKey[p[1]] or { singles = {}, stacks = {} }
		byKey[p[1]] = g
		table.insert(if p[2] > 1 then g.stacks else g.singles, i)
	end
	local merges = {}
	for key, g in byKey do
		local _, mult = LineMath.parseKey(key)
		if mult == 1 then
			while #g.singles >= bundle do
				local tie = {}
				for _ = 1, bundle do
					table.insert(tie, table.remove(g.singles))
				end
				table.insert(merges, { key = key, parts = tie, count = bundle })
				table.insert(g.stacks, -#merges) -- a bundle made this round, counted toward the crate below
			end
		elseif #g.singles >= at then
			table.insert(merges, { key = key, parts = g.singles, count = #g.singles })
			continue
		end
		if #g.stacks >= at then
			local crate, total = {}, 0
			for _, i in g.stacks do
				if i < 0 then
					-- Fold a bundle made this round straight into the crate instead.
					local made = merges[-i]
					for _, j in made.parts do
						table.insert(crate, j)
					end
					total += made.count
					merges[-i] = false :: any
				else
					table.insert(crate, i)
					total += parts[i][2]
				end
			end
			table.insert(merges, { key = key, parts = crate, count = total })
		end
	end
	local out = {}
	for _, m in merges do
		if m then
			table.insert(out, m)
		end
	end
	return out
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
