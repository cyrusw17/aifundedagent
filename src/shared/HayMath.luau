--!strict
-- Pure hay math, with no Roblox services, so tools/haycheck can test it headless. Every function takes the config
-- tables it reads (Config/Game as game, Config/Gloves as gloves), so the tests can feed it the real configs or their
-- own. Gloves.luau, Tools.luau, Gameplay.luau and Bales.luau use these.
local HayMath = {}

-- Walk speed wearing glove (a Config/Gloves tier) and carrying weight of hay whose hardest tier is hayTier. The gloves
-- add their carrySpeed and take away relief of the slowdown; each tier the gloves fall short of the hay multiplies
-- the slowdown by (1 + UnderGearedSlow). Never faster than walking empty-handed, never slower than MinWalkSpeed.
function HayMath.speed(glove: any, baseSpeed: number, weight: number, hayTier: number?, gloves: any): number
	if weight <= 0 then
		return baseSpeed
	end
	local short = math.max(0, (hayTier or 0) - glove.tier)
	local slow = weight * gloves.SlowPerWeight * (1 - glove.relief) * (1 + gloves.UnderGearedSlow * short)
	return math.clamp(baseSpeed + (glove.carrySpeed or 0) - slow, gloves.MinWalkSpeed, baseSpeed)
end

-- Weight of one loose strand of hay (a Config/Gloves HayTypes entry); wet hay is heavier.
function HayMath.pieceWeight(hay: any, wet: boolean?, game: any): number
	return hay.weight * game.HayPerPiece * (wet and game.WetWeightFactor or 1)
end

-- Weight of a whole bale of hay: packed tight, so a fraction (BaleWeightFactor) of the strands inside; wet is heavier.
function HayMath.baleWeight(hay: any, wet: boolean?, game: any, gloves: any): number
	return game.PiecesPerBale * game.HayPerPiece * hay.weight * gloves.BaleWeightFactor * (wet and game.WetWeightFactor or 1)
end

-- Strands one shovel scoop picks up of hay at hayTier, before the combo: fewer for each tier the gloves fall short,
-- never fewer than 2.
function HayMath.scoopSize(glove: any, hayTier: number?, game: any, gloves: any): number
	local base = game.ShovelPieces + glove.scoopBonus
	local short = math.max(0, (hayTier or 0) - glove.tier)
	return math.max(2, math.floor(base * (1 - gloves.UnderGearedScoop * short) + 0.5))
end

-- Extra strands the combo adds to the count-th quick scoop in a row (0 until ComboStart, capped at ComboMaxBonus).
function HayMath.comboExtra(count: number, game: any): number
	if count < game.ComboStart then
		return 0
	end
	return math.min((count - game.ComboStart + 1) * game.ComboBonusPieces, game.ComboMaxBonus)
end

-- What rain costs at the sell pad: wet hay sells at wetFactor of hayPrice (needles in it are unharmed).
function HayMath.wetPenalty(wetHay: number, hayPrice: number, wetFactor: number): number
	return math.floor(math.max(wetHay, 0) * hayPrice * (1 - wetFactor))
end

-- How a pour splits the hay in your arms. load = { hay, sorted, needles, wet } (hay amounts in hay units, needles a
-- count). Pours up to maxStrands strands, sorted hay first (it is the kind with no hidden needles left). The hidden
-- needles rolled for the unsorted hay leave with it in proportion, and the wet hay in proportion to the whole, so a
-- pour never makes needles or dries hay. Returns { n, sortedOut, needlesOut, wetOut } (strand counts, and needles).
function HayMath.pourSplit(load: any, maxStrands: number, hayPerPiece: number): any
	local held = math.floor(load.hay / hayPerPiece)
	local n = math.min(held, maxStrands)
	if n <= 0 then
		return { n = 0, sortedOut = 0, needlesOut = 0, wetOut = 0 }
	end
	local sortedHeld = math.min(math.floor((load.sorted or 0) / hayPerPiece), held)
	local sortedOut = math.min(n, sortedHeld)
	local unsortedHeld = held - sortedHeld
	local unsortedOut = n - sortedOut
	local needles = load.needles or 0
	local needlesOut = 0
	if unsortedHeld > 0 then
		needlesOut = if unsortedOut == unsortedHeld then needles else math.min(needles, math.floor(needles * unsortedOut / unsortedHeld + 0.5))
	end
	local wetHeld = math.floor((load.wet or 0) / hayPerPiece)
	local wetOut = if n == held then wetHeld else math.min(n, wetHeld, math.floor(wetHeld * n / held + 0.5))
	return { n = n, sortedOut = sortedOut, needlesOut = needlesOut, wetOut = wetOut }
end

-- Launch speed (up and forward, each) for a 45 degree toss at power 0..1 to land TossMinRange..TossRange studs away
-- on flat ground under gravity.
function HayMath.tossSpeed(power: number, game: any, gravity: number): number
	local range = game.TossMinRange + (game.TossRange - game.TossMinRange) * math.clamp(power, 0, 1)
	return math.sqrt(range * gravity) / math.sqrt(2)
end

return HayMath
