--!strict
-- Pure economy math. No Roblox services in here, so it can be tested anywhere.
local Economy = {}

Economy.HAY_PRICE = 0.5 -- dollars per hay, placeholder
Economy.RAW_NEEDLE_PRICE = 1 -- the basic shop only pays this for needles it cannot see

-- Value of a load sold raw at the basic shop.
function Economy.rawLoadValue(hay: number, needlesInside: number): number
	return math.floor(hay * Economy.HAY_PRICE + needlesInside * Economy.RAW_NEEDLE_PRICE)
end

-- Value of a load after sorting. recovery is 0..1, sortedValue is dollars per needle.
function Economy.sortedLoadValue(hay: number, needlesInside: number, recovery: number, sortedValue: number): number
	return math.floor(hay * Economy.HAY_PRICE + needlesInside * recovery * sortedValue)
end

return Economy
