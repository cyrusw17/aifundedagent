-- Headless checks for Prices.DailyContracts (CEO H9): a full day of contracts stays under 25% of an hour's income at
-- every stage, and the tiers make sense. Run: luau tests/contracts.luau.
local Prices = require("../src/shared/Config/Prices")

local failed = 0
local function check(name, ok, detail)
	if not ok then
		failed += 1
		print(("FAIL %s%s"):format(name, detail and (": " .. tostring(detail)) or ""))
	end
end

local cfg = Prices.DailyContracts
local last = -1
for i, tier in cfg.Tiers do
	local day = 3 * tier.reward + tier.bonus
	local share = day / tier.perHour
	check(("tier %d: a full day is under 25%% of an hour"):format(i), share <= 0.25, ("%.0f%%"):format(share * 100))
	check(("tier %d: worth doing (over 10%%)"):format(i), share >= 0.10, ("%.0f%%"):format(share * 100))
	check(("tier %d: tiers climb"):format(i), tier.fromSold > last, tier.fromSold)
	last = tier.fromSold
	check(("tier %d: needle has a price"):format(i), Prices.Needles[tier.needle] ~= nil, tier.needle)
	local kinds = tier.kinds or { "bales", "sorted", "needles" }
	check(("tier %d: three contracts"):format(i), #kinds == 3)
	for _, k in kinds do
		check(("tier %d: kind %s exists"):format(i, k), cfg.Kinds[k] ~= nil)
	end
	print(("tier %d  from $%d sold  $%d a day  %.0f%% of $%d/h"):format(i, tier.fromSold, day, share * 100, tier.perHour))
end
check("the first tier starts at zero", cfg.Tiers[1].fromSold == 0)
for k, spec in cfg.Kinds do
	check(("kind %s: amount range"):format(k), spec.amount[1] >= 1 and spec.amount[2] >= spec.amount[1])
end

print(failed == 0 and "contracts: all checks passed" or ("contracts: %d FAILED"):format(failed))
if failed > 0 then
	error("contracts checks failed")
end
