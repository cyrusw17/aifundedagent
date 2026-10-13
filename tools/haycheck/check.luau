-- Unit checks for HayMath with the real Config/Game and Config/Gloves (bundled by run.py with mapcheck's mock).
local Game = require({ __path = "Shared.Config.Game" })
local Gloves = require({ __path = "Shared.Config.Gloves" })
local HayMath = require({ __path = "Shared.HayMath" })

local failed, passed = 0, 0
local function check(name, ok, detail)
	if ok then
		passed += 1
	else
		failed += 1
		print(("FAIL %s%s"):format(name, detail and (" (" .. tostring(detail) .. ")") or ""))
	end
end

local BASE = 16
local tiers = Gloves.Tiers
local hayIds = {}
for id in Gloves.HayTypes do
	table.insert(hayIds, id)
end
table.sort(hayIds, function(a, b)
	return Gloves.HayTypes[a].tier < Gloves.HayTypes[b].tier or (Gloves.HayTypes[a].tier == Gloves.HayTypes[b].tier and a < b)
end)

-- The walk-speed table: carrying one dry bale of each hay, by glove tier.
local header = ("%-14s"):format("bale \\ gloves")
for _, g in tiers do
	header ..= ("%11s"):format(g.id)
end
print(header)
for _, id in hayIds do
	local hay = Gloves.HayTypes[id]
	local row = ("%-14s"):format(id .. " (t" .. hay.tier .. ")")
	local last = -math.huge
	for _, g in tiers do
		local w = HayMath.baleWeight(hay, false, Game, Gloves)
		local s = HayMath.speed(g, BASE, w, hay.tier, Gloves)
		row ..= ("%11.1f"):format(s)
		-- Better gloves are never slower, for any hay.
		check(("%s: %s no slower than the tier below"):format(id, g.id), s >= last - 1e-9, ("%.2f < %.2f"):format(s, last))
		last = s
		check(("%s: %s within walk limits"):format(id, g.id), s >= Gloves.MinWalkSpeed - 1e-9 and s <= BASE + 1e-9, s)
	end
	print(row)
end

-- Speed basics.
local bare, starlight = tiers[1], tiers[#tiers]
check("empty hands walk at base speed", HayMath.speed(bare, BASE, 0, 0, Gloves) == BASE)
check("a heavy load bottoms out at MinWalkSpeed", HayMath.speed(bare, BASE, 1e6, 0, Gloves) == Gloves.MinWalkSpeed)
local meadowBale = HayMath.baleWeight(Gloves.HayTypes.meadow, false, Game, Gloves)
check("hay above your gloves slows you more", HayMath.speed(bare, BASE, meadowBale, 3, Gloves) < HayMath.speed(bare, BASE, meadowBale, 0, Gloves))
check("starlight carries a meadow bale at full speed", HayMath.speed(starlight, BASE, meadowBale, 0, Gloves) == BASE)

-- Weights.
local meadow = Gloves.HayTypes.meadow
check("wet bale weighs WetWeightFactor more", math.abs(HayMath.baleWeight(meadow, true, Game, Gloves) / meadowBale - Game.WetWeightFactor) < 1e-9)
check("wet strand weighs WetWeightFactor more", math.abs(HayMath.pieceWeight(meadow, true, Game) / HayMath.pieceWeight(meadow, false, Game) - Game.WetWeightFactor) < 1e-9)
check("a bale weighs less than its strands loose", meadowBale < Game.PiecesPerBale * HayMath.pieceWeight(meadow, false, Game))

-- Scoops.
for _, g in tiers do
	for _, id in hayIds do
		local n = HayMath.scoopSize(g, Gloves.HayTypes[id].tier, Game, Gloves)
		check(("scoop %s/%s at least 2"):format(g.id, id), n >= 2, n)
	end
end
check("better gloves scoop more meadow", HayMath.scoopSize(starlight, 0, Game, Gloves) > HayMath.scoopSize(bare, 0, Game, Gloves))

-- Combo.
check("no combo before ComboStart", HayMath.comboExtra(Game.ComboStart - 1, Game) == 0)
check("the combo starts at ComboStart", HayMath.comboExtra(Game.ComboStart, Game) == Game.ComboBonusPieces)
check("the combo is capped", HayMath.comboExtra(1000, Game) == Game.ComboMaxBonus)

-- Wet penalty.
check("dry hay has no penalty", HayMath.wetPenalty(0, 0.5, Game.WetPriceFactor) == 0)
check("wet hay costs (1 - WetPriceFactor) of its price", HayMath.wetPenalty(100, 0.5, Game.WetPriceFactor) == math.floor(100 * 0.5 * (1 - Game.WetPriceFactor)))
check("negative wet hay is no penalty", HayMath.wetPenalty(-5, 0.5, Game.WetPriceFactor) == 0)

-- Pours: never make needles or dry hay, and pouring everything gives everything back.
local rng = Random.new(7)
for trial = 1, 400 do
	local hay = rng:NextInteger(0, 300)
	local load = {
		hay = hay,
		sorted = rng:NextInteger(0, hay),
		needles = rng:NextInteger(0, 20),
		wet = rng:NextInteger(0, hay),
	}
	local start = table.clone(load)
	local outNeedles, outWet, outSorted, outStrands = 0, 0, 0, 0
	local guard = 0
	while load.hay >= Game.HayPerPiece and guard < 1000 do
		guard += 1
		local s = HayMath.pourSplit(load, Game.PourStrands, Game.HayPerPiece)
		check(("trial %d: a pour takes something"):format(trial), s.n > 0)
		check(("trial %d: parts fit the pour"):format(trial), s.sortedOut <= s.n and s.wetOut <= s.n and s.needlesOut >= 0)
		load.hay -= s.n * Game.HayPerPiece
		load.sorted = math.max(0, load.sorted - s.sortedOut * Game.HayPerPiece)
		load.needles -= s.needlesOut
		load.wet = math.max(0, load.wet - s.wetOut * Game.HayPerPiece)
		check(("trial %d: needles never go negative"):format(trial), load.needles >= 0, load.needles)
		outNeedles += s.needlesOut
		outWet += s.wetOut
		outSorted += s.sortedOut
		outStrands += s.n
	end
	local unsorted = start.hay - math.min(start.sorted, start.hay)
	check(("trial %d: every strand poured"):format(trial), outStrands == math.floor(start.hay / Game.HayPerPiece))
	check(("trial %d: pouring it all returns the needles exactly"):format(trial), unsorted == 0 or outNeedles == start.needles, ("%d of %d"):format(outNeedles, start.needles))
	check(("trial %d: wet hay pours out wet, all of it"):format(trial), outWet == math.min(start.wet, start.hay), ("%d of %d"):format(outWet, start.wet))
	check(("trial %d: sorted hay pours out sorted, all of it"):format(trial), outSorted == math.min(start.sorted, start.hay))
end

-- Toss.
local g = 196.2
for _, power in { 0, 0.5, 1 } do
	local v = HayMath.tossSpeed(power, Game, g)
	local range = 2 * v * v / g -- 45 degrees, v up and v forward: flight 2v/g, distance v * flight
	local want = Game.TossMinRange + (Game.TossRange - Game.TossMinRange) * power
	check(("toss at %.1f lands %.1f studs"):format(power, want), math.abs(range - want) < 1e-6, range)
end

-- Clumps: every strand of a bale spilled exactly once, none bigger than asked.
for total = 0, 200 do
	for per = 1, 7 do
		local sum, ok = 0, true
		for _, n in HayMath.clumps(total, per) do
			sum += n
			ok = ok and n >= 1 and n <= per
		end
		check(("clumps of %d from %d"):format(per, total), ok and sum == total)
	end
end
check("a meadow bale is 30 clumps", #HayMath.clumps(Game.PiecesPerBale, Game.StrandsPerClump) == math.ceil(Game.PiecesPerBale / Game.StrandsPerClump))

-- Scoop plans: never more than the room in your arms, strands and clumps never more than the scoop size, a pile
-- taken whole when there is room, nothing taken below zero.
local rng = Random.new(22)
for _ = 1, 2000 do
	local pieces = {}
	for i = 1, rng:NextInteger(0, 14) do
		local pile = rng:NextNumber() < 0.15
		pieces[i] = { strands = pile and rng:NextInteger(40, 120) or rng:NextInteger(1, 3), pile = pile }
	end
	local room, scoop = rng:NextInteger(0, 80), rng:NextInteger(1, 25)
	local takes = HayMath.scoopPlan(pieces, room, scoop)
	local total, loose, ok = 0, 0, true
	for i, piece in pieces do
		local t = takes[i]
		ok = ok and t >= 0 and t <= piece.strands
		total += t
		if not piece.pile then
			loose += t
		end
	end
	check("a scoop fits your arms", total <= room, total)
	check("a scoop's strands and clumps fit the scoop size", loose <= scoop, loose)
	check("a scoop never takes more than a piece holds", ok)
	-- And it is greedy: hay left behind with room still in your arms is only loose hay past the scoop size.
	local pileLeft = false
	local held = 0
	for i, piece in pieces do
		held += piece.strands
		pileLeft = pileLeft or (piece.pile and takes[i] < piece.strands)
	end
	if total < room and total < held then
		check("a scoop stops short only at the scoop size", loose == scoop and not pileLeft, ("%d/%d room, %d/%d scoop"):format(total, room, loose, scoop))
	end
end

-- Tooltips (ToolGuide): one line each, from the configs, with no unfilled format codes, and the numbers in them
-- are the config's.
local ToolGuide = require({ __path = "Shared.ToolGuide" })
local lines = {}
for _, kind in { "Shovel", "Rake", "Wheelbarrow" } do
	lines[kind] = ToolGuide.tool(kind)
end
for _, def in Gloves.Tiers do
	lines[def.id] = ToolGuide.glove(def)
end
for _, def in Gloves.QuestTiers do
	lines[def.id] = ToolGuide.glove(def)
end
lines.shop = ToolGuide.wheelbarrowShop()
for id, line in lines do
	check(("tooltip %s is filled in"):format(id), #line > 20 and not line:find("%%[%a]") and not line:find("nil"), line)
end
check("the shovel tooltip says the scoop size", lines.Shovel:find(tostring(Game.ShovelPieces), 1, true) ~= nil, lines.Shovel)
check("the rake tooltip says the pile size", lines.Rake:find(tostring(Game.PileMin), 1, true) ~= nil, lines.Rake)
for _, def in Gloves.Tiers do
	if def.tier > 0 then
		check(("%s tooltip says its carry bonus"):format(def.id), lines[def.id]:find(("(%d more)"):format(def.carryBonus), 1, true) ~= nil, lines[def.id])
		check(("%s tooltip says double carry only from DoubleCarryTier"):format(def.id), (lines[def.id]:find("two bales", 1, true) ~= nil) == (def.tier >= Game.DoubleCarryTier))
	end
end
print("tooltips:")
for _, id in { "Shovel", "Rake", "Wheelbarrow", "bare", "work", "leather", "reinforced", "iron", "starlight" } do
	print("  " .. lines[id])
end

print(("hay math: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("hay math checks failed")
end
