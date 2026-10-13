-- Save round trip for a maxed-out line (CEO #34). Builds the save a full farm writes (every Config/Land piece, a raised
-- level and ramps, all four directions, silos holding bales, a display and a vault full of graded and mutated needles,
-- a sorted and polished bin, a price hold, saved layouts), sends it through the save path the game uses
-- (Data.test.toSave, a DataStore-strict JSON encode and decode, Data.test.stateFrom, toSave again), and checks that
-- every piece, cell, rotation, count, needle key and hold comes back exactly.
local Data = require({ __path = "Services.Data" })
local LineMath = require({ __path = "Shared.LineMath" })
local LandConfig = require({ __path = "Shared.Config.Land" })

local failures = 0
local function check(name, ok, detail)
	if not ok then
		failures += 1
		print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
	end
end

-- JSON as a DataStore takes it: a table is an array (keys exactly 1..n) or an object (string keys only); numbers
-- must be finite; strings valid UTF-8. Anything else is an error here, because Roblox would drop or refuse it.
local function encode(v, path)
	local t = typeof(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "number" then
		assert(v == v and v ~= math.huge and v ~= -math.huge, "not a finite number at " .. path)
		return string.format("%.17g", v)
	elseif t == "string" then
		assert(utf8.len(v) ~= nil, "invalid UTF-8 at " .. path)
		return '"' .. v:gsub('[%c"\\]', function(c)
			return string.format("\\u%04x", string.byte(c))
		end) .. '"'
	elseif t == "table" then
		local n, count, strings = #v, 0, 0
		for k in v do
			count += 1
			if typeof(k) == "string" then
				strings += 1
			end
		end
		if count == 0 then
			return "[]"
		end
		if count == n then
			local parts = {}
			for i = 1, n do
				parts[i] = encode(v[i], path .. "[" .. i .. "]")
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		assert(strings == count, "a table mixing array and other keys at " .. path)
		local keys = {}
		for k in v do
			table.insert(keys, k)
		end
		table.sort(keys)
		local parts = {}
		for _, k in keys do
			table.insert(parts, encode(k, path) .. ":" .. encode(v[k], path .. "." .. k))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("can't save a " .. t .. " at " .. path)
end

local function decode(s)
	local i = 1
	local function ws()
		i = string.find(s, "[^ \n\r\t]", i) or #s + 1
	end
	local value
	function value()
		ws()
		local c = string.sub(s, i, i)
		if c == "{" then
			local out = {}
			i += 1
			ws()
			if string.sub(s, i, i) == "}" then
				i += 1
				return out
			end
			while true do
				local k = value()
				ws()
				i += 1 -- :
				out[k] = value()
				ws()
				local d = string.sub(s, i, i)
				i += 1
				if d == "}" then
					return out
				end
			end
		elseif c == "[" then
			local out = {}
			i += 1
			ws()
			if string.sub(s, i, i) == "]" then
				i += 1
				return out
			end
			while true do
				table.insert(out, value())
				ws()
				local d = string.sub(s, i, i)
				i += 1
				if d == "]" then
					return out
				end
			end
		elseif c == '"' then
			local j = i + 1
			local buf = {}
			while string.sub(s, j, j) ~= '"' do
				if string.sub(s, j, j) == "\\" then
					table.insert(buf, string.char(tonumber(string.sub(s, j + 2, j + 5), 16)))
					j += 6
				else
					table.insert(buf, string.sub(s, j, j))
					j += 1
				end
			end
			i = j + 1
			return table.concat(buf)
		elseif string.sub(s, i, i + 3) == "true" then
			i += 4
			return true
		elseif string.sub(s, i, i + 4) == "false" then
			i += 5
			return false
		elseif string.sub(s, i, i + 3) == "null" then
			i += 4
			return nil
		end
		local j = string.find(s, "[^%-%d%.eE+]", i) or #s + 1
		local n = tonumber(string.sub(s, i, j - 1))
		i = j
		return n
	end
	return value()
end

local function same(a, b, path, out)
	if typeof(a) ~= typeof(b) then
		table.insert(out, ("%s: %s became %s"):format(path, tostring(a), tostring(b)))
		return
	end
	if typeof(a) ~= "table" then
		if a ~= b then
			table.insert(out, ("%s: %s became %s"):format(path, tostring(a), tostring(b)))
		end
		return
	end
	for k, v in a do
		same(v, b[k], path .. "." .. tostring(k), out)
	end
	for k, v in b do
		if a[k] == nil then
			table.insert(out, ("%s.%s appeared: %s"):format(path, tostring(k), tostring(v)))
		end
	end
end

-- Every needle key form the game writes: plain, mutated, polished, graded, and all of them together.
local keys = {}
for _, id in { "steel", "pine", "ice", "cosmic" } do
	for _, mult in { 1, 3, 25 } do
		for _, polished in { false, true } do
			for _, grade in { "B", "A", "S" } do
				table.insert(keys, LineMath.keyOf(id, mult, polished, grade))
			end
		end
	end
end
for _, key in keys do
	local id, mult, polished, grade = LineMath.parseKey(key)
	check("needle key " .. key .. " survives parse and rebuild", LineMath.keyOf(id, mult, polished, grade) == key)
end
local binNeedles, vaultNeedles = {}, {}
for i, key in keys do
	binNeedles[key] = i * 7 + 3 -- odd counts, so bundles of 10 leave loose ones
	vaultNeedles[key] = i
end

-- Every piece in Config/Land, placed in rows over all four directions, plus a raised level above the belts.
local items, dirs = {}, { "N", "E", "S", "W" }
local gx, gz = 0, 0
for i, def in LandConfig.Pieces do
	local item = { id = def.id, gx = gx, gz = gz, dir = dirs[(i - 1) % 4 + 1], paid = def.price }
	if def.kind == "silo" then
		item.stored = 17
		item.fill = "snow"
	elseif def.kind == "display" then
		item.display = { { slot = 1, id = "cosmic", mult = 25, polished = true, grade = "S" }, { slot = 4, id = "steel", mult = 1, polished = false } }
	elseif def.kind == "vault" then
		item.display = vaultNeedles
	end
	table.insert(items, item)
	gx += (def.size and def.size[1] or 1) + 1
	if gx > 40 then
		gx, gz = 0, gz + 4
	end
end
for x = 0, 11 do
	table.insert(items, { id = "raised_belt", gx = x, gz = 60, dir = "E", paid = 0 })
end
check("the max line has every piece and a raised level", #items >= #LandConfig.Pieces + 12, #items)

local land = {
	owned = true,
	plot = 3,
	items = items,
	needles = binNeedles,
	crew = { 1111, 2222 },
	expansions = 2,
	binSorted = true,
	binPolisher = true,
	theme = "ironworks",
	name = "Hayfield Works",
	savedAt = 1760000000,
}
local state = Data.test.stateFrom({
	cash = 123456,
	pocket = { ["cosmic*3!#S"] = 2, steel = 40 },
	needleHold = 3,
	lineBlueprints = { { name = "Two sorters ✦", list = { { id = "belt", dx = 0, dz = 0, dir = "E" }, { id = "magnet_drum", dx = 1, dz = 0, dir = "E" } } } },
	land = land,
	land2 = land,
})

local first = Data.test.toSave(state)
local ok, json = pcall(encode, first, "save")
check("the save encodes as a DataStore takes it", ok, json)
if ok then
	print(("saves: a maxed line is %d bytes (DataStore limit 4,194,304), %d pieces, %d needle keys"):format(#json, #items, #keys))
	check("the save is far under the DataStore limit", #json < 1000000, #json)
	local second = Data.test.toSave(Data.test.stateFrom(decode(json)))
	local diffs = {}
	same(first, second, "save", diffs)
	check("everything comes back exactly", #diffs == 0, table.concat(diffs, "; ", 1, math.min(#diffs, 8)))
	check("every piece comes back", second.land and #second.land.items == #items)
	check("the price hold comes back", second.needleHold == 3)
	check("the bin keeps every needle key", second.land and LineMath.total(second.land.needles) == LineMath.total(binNeedles))
	check("the second farm comes back too", second.land2 and #second.land2.items == #items)
end

-- What the bin does with the saved counts: plain needles tied in bundles of 10 and the loose rest, never one lost.
for key, count in binNeedles do
	local _, mult = LineMath.parseKey(key)
	local whole, rest = LineMath.bundles(count, 10)
	local back = if mult == 1 then whole * 10 + rest else count
	check("bin refill of " .. key .. " keeps the count", back == count)
end

-- A broken save must not break loading: odd values are dropped, not carried.
local junk = Data.test.toSave(Data.test.stateFrom({ needleHold = 99, pocket = { steel = -4, [5] = 2, pine = 0 / 0 }, land = { items = "nope" } }))
check("a junk hold is clamped", junk.needleHold == 4, junk.needleHold)
check("junk pocket entries are dropped", next(junk.pocket) == nil)
check("a land with no item list is dropped", junk.land == nil)

print(("saves: %d failures"):format(failures))
if failures > 0 then
	print("FAIL saves")
end
