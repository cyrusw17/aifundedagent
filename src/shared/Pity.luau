--!strict
-- Pity and near misses for mutated needles (CEO "Addiction push" H3). Pure, so tests/pity.luau checks it headlessly;
-- Machines (the sorter) keeps each owner's dry count and Needle.rollMutation uses roll().
--
--   Pity.chance(base, boost)         -> a needle's mutation chance: base times boost (a Hay Market bale's
--                                       MutationBoost times a storm's Weather.needleOdds), capped at MAX_CHANCE
--   Pity.roll(r, chance, nearMiss)   -> "hit", "near" or nil for one uniform roll r in [0, 1)
--   Pity.apply(dry, mults, cfg)      -> dry', hit, forced. mults: this bale's found needles' multipliers (1 = plain),
--                                       changed in place when pity forces the first one to cfg.mult.
-- cfg is Prices.Pity: { bales, mult, nearMiss }.
local Pity = {}

Pity.MAX_CHANCE = 0.5

function Pity.chance(base: number, boost: number?): number
	local b = boost or 1
	if typeof(b) ~= "number" or b ~= b or b < 0 then
		b = 1
	end
	return math.min(base * b, Pity.MAX_CHANCE)
end

function Pity.roll(r: number, chance: number, nearMiss: number): string?
	if r < chance then
		return "hit"
	elseif r < chance * nearMiss then
		return "near"
	end
	return nil
end

-- After cfg.bales dry bales the next one is guaranteed a mutation. Only a real mutation (cfg.mult, the smallest, or
-- more) ends a dry run; a Wet needle (x2, Prices.WetMutation) doesn't. Only bales that found a needle count: a bale with
-- nothing in it leaves the count alone, so a hand sieve (0.3 needles a bale) isn't handed a mutation every 40 bales.
function Pity.apply(dry: number, mults: { number }, cfg: { bales: number, mult: number }): (number, boolean, boolean)
	if #mults == 0 then
		return dry, false, false
	end
	for _, m in mults do
		if m >= cfg.mult then
			return 0, true, false
		end
	end
	if dry >= cfg.bales then
		mults[1] = cfg.mult
		return 0, true, true
	end
	return dry + 1, false, false
end

return Pity
