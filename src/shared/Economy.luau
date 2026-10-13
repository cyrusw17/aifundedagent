--!strict
-- Pure economy math. No Roblox services in here, so it can be tested anywhere.
local Economy = {}

Economy.HAY_PRICE = 0.5 -- dollars per hay, placeholder
Economy.RAW_NEEDLE_PRICE = 1 -- the basic shop only pays this for needles it cannot see
-- A needle you found by hand and carry in your pocket sells at the public pad for this share of its sorted value.
-- Full value: finding one is rare and it is the first hook.
Economy.HAND_NEEDLE_SHARE = 1

-- Value of a load sold raw at the basic shop.
function Economy.rawLoadValue(hay: number, needlesInside: number): number
	return math.floor(hay * Economy.HAY_PRICE + needlesInside * Economy.RAW_NEEDLE_PRICE)
end

-- Value of a load after sorting. recovery is 0..1, sortedValue is dollars per needle.
function Economy.sortedLoadValue(hay: number, needlesInside: number, recovery: number, sortedValue: number): number
	return math.floor(hay * Economy.HAY_PRICE + needlesInside * recovery * sortedValue)
end

-- How many needles are hidden in a load of hay. rng is passed in so this stays testable.
function Economy.rollNeedles(rng: Random, hay: number, chancePerHay: number): number
	local count = 0
	for _ = 1, hay do
		if rng:NextNumber() < chancePerHay then
			count += 1
		end
	end
	return count
end

return Economy
