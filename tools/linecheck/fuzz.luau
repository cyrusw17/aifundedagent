local Needle = require({ __path = "Services.Needle" })
local LineMath = require({ __path = "Shared.LineMath" })
local Market = require({ __path = "Services.Market" })

local failures = 0
local function check(label, ok, detail)
	if not ok then
		failures += 1
		print("FAIL", label, detail or "")
	end
end

local rng = Random.new(20261013)
local IDS = { "steel", "pine", "sand", "ice", "bog", "obsidian", "geode", "cloud", "phantom", "cosmic" }
local GRADES = { "B", "A", "S" }
local function randomKey()
	local id = IDS[rng:NextInteger(1, #IDS)]
	local mult = rng:NextNumber() < 0.2 and rng:NextInteger(2, 25) or 1
	return LineMath.keyOf(id, mult, rng:NextNumber() < 0.3, GRADES[rng:NextInteger(1, 3)])
end

local function newPlayer(i)
	local p = Instance.new("Player")
	p.UserId = 1000 + i
	p.Name = "Fuzz" .. i
	STATES[p] = { pocket = {} }
	return p
end

local function total(map)
	local n = 0
	for _, c in map do
		n += c
	end
	return n
end

-- Key round trip for every random key.
for _ = 1, 5000 do
	local key = randomKey()
	local id, mult, polished, grade = LineMath.parseKey(key)
	check("key round trip " .. key, LineMath.keyOf(id, mult, polished, grade) == key)
end

-- Pocket sequences: count every needle in (given) and out (sold, taken, moved to a vault), and the money paid.
local ops, allPaid, allSales, allTaken = 0, 0, 0, 0
for run = 1, 300 do
	local player = newPlayer(run)
	local inn, out, paid, sold = 0, 0, 0, 0
	local vault = {}
	for _ = 1, 60 do
		ops += 1
		local roll = rng:NextInteger(1, 7)
		if roll <= 2 then
			local key, n = randomKey(), rng:NextInteger(1, 30)
			Needle.giveKey(player, key, n)
			inn += n
		elseif roll == 3 then
			local id = IDS[rng:NextInteger(1, #IDS)]
			local before, want = Needle.plainCount(player, id), rng:NextInteger(1, 20)
			local ok = Needle.take(player, id, want)
			check("take all-or-nothing", ok == (before >= want), ("had %d wanted %d ok %s"):format(before, want, tostring(ok)))
			if ok then
				out += want
				check("take removed exactly", Needle.plainCount(player, id) == before - want)
			end
		elseif roll == 4 then
			local held = Needle.heldCount(player)
			local expect = 0
			for key, n in Needle.held(player) do
				local id, mult, polished, grade = Needle.parseKey(key)
				expect += Needle.priceOf(id, mult, polished, grade) * n
			end
			local count, value = Needle.sellHeld(player)
			check("sell takes the whole pocket", count == held and Needle.heldCount(player) == 0, ("%d vs %d"):format(count, held))
			check("sell pays list x count", value == expect, ("%d vs %d"):format(value, expect))
			local again = { Needle.sellHeld(player) }
			check("selling twice pays nothing more", again[1] == 0 and again[2] == 0)
			out += count
			paid += value
			sold += 1
		elseif roll == 5 then
			local best = Needle.takeBest(player)
			if best then
				out += 1
				Needle.give(player, best) -- a display peg given back
				inn += 1
			else
				check("no best only when empty", Needle.heldCount(player) == 0)
			end
		elseif roll == 6 then
			-- Vault deposit then partial withdraw, as Vault.luau does it.
			for _, n in Needle.takeHeld(player) do
				local key = Needle.keyOf(n.id, n.mult, n.polished, n.grade)
				vault[key] = (vault[key] or 0) + 1
			end
			if rng:NextNumber() < 0.5 then
				for key, n in vault do
					Needle.giveKey(player, key, n)
				end
				table.clear(vault)
			end
		else
			-- A save round trip: the pocket survives as keys, and every key still parses.
			local copy = {}
			for key, n in STATES[player].pocket do
				copy[key] = n
				local id = Needle.parseKey(key)
				check("saved key parses to a real type", Needle.info(id).id == id, key)
			end
			STATES[player].pocket = copy
		end
		check("pocket never negative", (function()
			for _, n in Needle.held(player) do
				if n < 0 then
					return false
				end
			end
			return true
		end)())
		local nowHeld = Needle.heldCount(player)
		check("needles in = out + pocket + vault", inn == out + nowHeld + total(vault), ("in %d out %d pocket %d vault %d"):format(inn, out, nowHeld, total(vault)))
		check("NeedlesHeld attribute matches", (player:GetAttribute("NeedlesHeld") or 0) == nowHeld or nowHeld == 0)
	end
	check("money is never negative", paid >= 0)
	allPaid += paid
	allSales += sold
	allTaken += out
end

-- Piece guide lines: every sorter and region machine gets a line with real numbers in it.
local PieceGuide = require({ __path = "Shared.PieceGuide" })
for _, id in { "hand_sieve", "shaker_table", "conveyor_sorter", "magnet_drum", "optical_sorter" } do
	local line = PieceGuide.line({ id = id, kind = "separator" })
	check("guide line for " .. id, string.find(line, "%d+%%") ~= nil and string.find(line, "bales a minute") ~= nil, line)
end
check("optical guide names its grade", string.find(PieceGuide.line({ id = "optical_sorter", kind = "separator" }), "S grade") ~= nil)
for _, id in { "thawing_shed", "drying_rack", "ash_sifter" } do
	local line = PieceGuide.line({ id = id, kind = "treat", blurb = "BLURB" })
	check("guide line for " .. id, line ~= "BLURB" and #line > 20, line)
end
check("other pieces keep their blurb", PieceGuide.line({ id = "belt", kind = "belt", blurb = "One tile." }) == "One tile.")
print("guide:", PieceGuide.line({ id = "magnet_drum", kind = "separator" }), "|", PieceGuide.line({ id = "ash_sifter", kind = "treat" }))

-- Bottleneck lamps: the rules hold for every random line state.
local LineMathLamp = require({ __path = "Shared.LineMath" })
local lampRng = Random.new(29)
local seen = { green = 0, amber = 0, red = 0 }
for _ = 1, 20000 do
	local s = {
		sorting = lampRng:NextNumber() < 0.5,
		idleSeconds = lampRng:NextNumber(0, 30),
		queued = lampRng:NextInteger(0, 6),
		queuedSeconds = lampRng:NextNumber(0, 40),
		jammed = lampRng:NextNumber() < 0.1,
		refusedSeconds = lampRng:NextNumber() < 0.3 and lampRng:NextNumber(0, 30) or nil,
		need = "thawing_shed",
		beamDown = lampRng:NextNumber() < 0.1,
	}
	local color, why = LineMathLamp.lamp(s)
	seen[color] = (seen[color] or 0) + 1
	check("lamp is green, amber or red", color == "green" or color == "amber" or color == "red", tostring(color))
	check("a lamp that isn't green says why", color == "green" or (typeof(why) == "string" and #why > 0))
	if s.jammed then
		check("a jam is red", color == "red")
	end
	local backedUp = s.queued >= 2 and s.queuedSeconds >= LineMathLamp.BACKUP_SECONDS
	local refused = s.refusedSeconds and s.refusedSeconds < LineMathLamp.REFUSED_SECONDS
	if not s.jammed and not backedUp and not refused then
		check("only jams, refusals and backups are red", color ~= "red")
		if s.sorting then
			check("a sorting sorter is green", color == "green")
		elseif s.queued == 0 and s.idleSeconds >= LineMathLamp.STARVED_SECONDS then
			check("an idle sorter with no bales is amber", color == "amber")
		end
	end
	if s.queued > 0 and not s.beamDown then
		check("bales waiting never read as starved", why ~= "waiting for bales")
	end
end
check("the lamp fuzz saw every color", seen.green > 0 and seen.amber > 0 and seen.red > 0)
print(("lamps: green %d, amber %d, red %d"):format(seen.green, seen.amber, seen.red))

print(("linecheck: %d random keys, %d pocket operations over 300 players (%d sales paying $%d, %d needles out); %d failures"):format(5000, ops, allSales, allPaid, allTaken, failures))
check("the fuzz really sold and took needles", allSales > 100 and allPaid > 0 and allTaken > 1000)
if failures > 0 then
	print("FAIL linecheck")
end
