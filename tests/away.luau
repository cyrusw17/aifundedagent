-- Headless checks for src/shared/Away.luau. Run: luau tests/away.luau (exits non-zero on failure).
local Away = require("../src/shared/Away")

local failed = 0
local function check(name, ok, detail)
	if not ok then
		failed += 1
		print(("FAIL %s%s"):format(name, detail and (": " .. tostring(detail)) or ""))
	end
end

local now = 1_800_000_000
local H = 3600

-- The span: under a minute, a missing or future savedAt, and NaN pay nothing; long absences stop at 8 hours.
check("under a minute pays nothing", Away.span(now - 59, now) == 0)
check("a minute counts", Away.span(now - 60, now) == 60)
check("no savedAt pays nothing", Away.span(nil, now) == 0)
check("a savedAt in the future pays nothing", Away.span(now + 500, now) == 0)
check("NaN savedAt pays nothing", Away.span(0 / 0, now) == 0)
check("2 hours is 2 hours", Away.span(now - 2 * H, now) == 2 * H)
check("8 hours is the cap", Away.span(now - 8 * H, now) == 8 * H)
check("3 days stops at 8 hours", Away.span(now - 72 * H, now) == 8 * H, Away.span(now - 72 * H, now))

-- Bales: half the line's rate, whole bales, never more than the silos hold.
check("an hour at 8/min sorts 240 (half of 480)", Away.bales(H, 8, 10000) == 240, Away.bales(H, 8, 10000))
check("the silo bounds it", Away.bales(H, 8, 37) == 37)
check("an empty silo sorts nothing", Away.bales(H, 30, 0) == 0)
check("no line sorts nothing", Away.bales(H, 0, 100) == 0)
local capped = Away.bales(Away.span(now - 100 * H, now), 30, 1e9)
check("the 8 hour cap holds at the fastest sorter", capped == 30 * 60 * 8 / 2, capped)

-- Double pay: paying moves savedAt to now (as Land.mailbox does), so a second load straight after pays nothing,
-- and a rejoin an hour later pays only that hour.
local land = { savedAt = now - 5 * H, stored = 5000 }
local function pay(at)
	local span = Away.span(land.savedAt, at)
	local bales = Away.bales(span, 8, land.stored)
	if span > 0 then
		land.savedAt = at
	end
	land.stored -= bales
	return bales
end
local first = pay(now)
check("first load pays 5 hours", first == 8 * 60 * 5 / 2, first)
check("a second load at once pays nothing", pay(now) == 0)
check("a load 30 seconds later pays nothing", pay(now + 30) == 0)
local later = pay(now + H)
check("an hour later pays that hour only", later == 240, later)
check("bales taken match bales paid", land.stored == 5000 - first - later, land.stored)

if failed > 0 then
	print(("away: %d failed"):format(failed))
	error("away checks failed")
end
print("away: all checks passed")
