-- Headless checks for src/shared/RateLimit.luau. Run: luau tests/rate_limit.luau (exits non-zero on failure).
local RateLimit = require("../src/shared/RateLimit")

local failed = 0
local function check(name, ok, detail)
	if not ok then
		failed += 1
		print(("FAIL %s%s"):format(name, detail and (": " .. tostring(detail)) or ""))
	end
end

local now = 0
RateLimit.clock = function()
	return now
end
local warned = 0
RateLimit.report = function()
	warned += 1
end

local a, b = { name = "a" }, { name = "b" }
local limit = RateLimit.new("Test", 2, 3) -- 2 a second, bursts of 3

-- A burst goes through, the next call is refused, and refusing does not spend tokens.
check("burst 1", limit:allow(a))
check("burst 2", limit:allow(a))
check("burst 3", limit:allow(a))
check("4th call in the same instant is refused", not limit:allow(a))
check("refused calls spend nothing", limit:left(a) >= 0 and limit:left(a) < 1, limit:left(a))

-- Buckets are per player.
check("another player has a full bucket", limit:allow(b) and limit:left(b) == 2, limit:left(b))

-- Tokens refill at perSecond, capped at burst.
now = 0.5
check("half a second refills one call", limit:allow(a))
check("and only one", not limit:allow(a))
now = 100
check("a long wait refills only to the burst", limit:left(a) == 3, limit:left(a))

-- A steady caller at exactly the rate is never refused; twice the rate gets about half through.
local steady = RateLimit.new("Steady", 4, 1)
local p = {}
local refused = 0
for i = 1, 400 do
	now = 1000 + i * 0.25
	if not steady:allow(p) then
		refused += 1
	end
end
check("a caller at the rate is never refused", refused == 0, refused)
local through = 0
for i = 1, 800 do
	now = 2000 + i * 0.125
	if steady:allow(p) then
		through += 1
	end
end
check("a caller at twice the rate gets half through", math.abs(through - 400) <= 2, through)

-- Costs, bad input, and forgetting a player.
local big = RateLimit.new("Big", 1, 10)
check("a cost of 10 fits a burst of 10", big:allow(a, 10))
check("a cost over what is left is refused", not big:allow(a, 1))
check("a negative cost is refused", not big:allow(b, -5))
check("a NaN cost is refused", not big:allow(b, 0 / 0))
check("no player is refused", not big:allow(nil))
big:forget(a)
check("a forgotten player starts full", big:left(a) == 10, big:left(a))

-- Warnings: at most one a minute per player per limiter.
warned = 0
local w = RateLimit.new("Warn", 1, 1)
now = 5000
w:allow(a)
for _ = 1, 50 do
	w:allow(a)
end
check("spam warns once", warned == 1, warned)
now = 5061
w:allow(a)
w:allow(a)
check("and again after a minute", warned == 2, warned)

local ok = pcall(RateLimit.new, "Bad", 0, 1)
check("a zero rate is refused at creation", not ok)

if failed > 0 then
	print(("rate limit: %d failed"):format(failed))
	error("rate limit checks failed")
end
print("rate limit: all checks passed")
