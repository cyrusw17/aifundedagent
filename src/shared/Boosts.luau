--!strict
-- Stacked boosts (CEO H13). A bale can carry its own boost (a rich field, the festival, a chute or region event, a
-- golden field, a Hay Market kind) and pick up "extras" on the way: the play-together bonus (needles) and a
-- thunderstorm (mutation odds). The extras only stack until the bale is worth Prices.Boosts.Cap times a plain
-- bale's needles, or the bale's own boost if that is bigger, so a bale with a big boost of its own gets nothing extra.
-- Pure, so tests/boosts.luau checks it headlessly; Machines (the sorter) and Bales (hand breaking) call fit().
--
--   Boosts.terms(Prices)                   -> { cap, chance, extra, maxChance } from Prices.Boosts and Prices.Mutation
--   Boosts.value(t, needles, mutation)     -> a bale's needle value against a plain bale's (mutations included)
--   Boosts.fit(t, own, ownMut, extra, extraMut) -> needles, mutation: the boosts to use. The extras are dropped first
--                                            (storm odds, then the play-together needles) until value <= the limit.
local Boosts = {}

export type Terms = { cap: number, chance: number, extra: number, maxChance: number }

local function positive(v: any): number
	return (typeof(v) == "number" and v > 0 and v == v and v < math.huge) and v or 1
end

function Boosts.terms(prices: any): Terms
	local m = prices.Mutation
	return {
		cap = prices.Boosts.Cap,
		chance = 1 / m.oneIn,
		extra = (m.min + m.max) / 2 - 1,
		maxChance = 0.5, -- Pity.MAX_CHANCE
	}
end

function Boosts.value(t: Terms, needles: number, mutation: number): number
	local c = math.min(t.chance * positive(mutation), t.maxChance)
	return positive(needles) * (1 + c * t.extra) / (1 + t.chance * t.extra)
end

function Boosts.fit(t: Terms, own: number?, ownMut: number?, extra: number?, extraMut: number?): (number, number)
	local n0, m0 = positive(own), positive(ownMut)
	local limit = math.max(t.cap, Boosts.value(t, n0, m0))
	local n, m = n0 * positive(extra), m0 * positive(extraMut)
	if Boosts.value(t, n, m) <= limit + 1e-9 then
		return n, m
	end
	m = m0 -- drop the storm odds first
	if Boosts.value(t, n, m) > limit then
		-- then trim the extra needles to just fit, never below the bale's own
		n = math.max(n0, limit / Boosts.value(t, 1, m))
	end
	return n, m
end

return Boosts
