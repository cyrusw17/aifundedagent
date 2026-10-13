--!strict
-- One rate limit for every remote and prompt (CEO #31, from the #25 audit): a token bucket per player per limiter.
-- A bucket holds up to `burst` calls and refills `perSecond` calls a second, so a player can click quickly a few
-- times, but a script firing a remote in a loop is cut off. Server-side only; the client never sees its buckets.
--
--   local buy = RateLimit.new("Dealer.Buy", 0.5, 2)   -- name (for warnings), perSecond, burst
--   remote.OnServerInvoke = function(player, ...)
--       if not buy:allow(player) then return false, RateLimit.BUSY end
--       ...
--   end
--
--   limiter:allow(player, cost?)  -> true if the call may go ahead (and takes cost tokens, default 1)
--   limiter:left(player)          -> tokens left now (for tests and debug)
--   limiter:forget(player)        -- drop a player's bucket (buckets are also weak-keyed, so a gone player frees them)
--   RateLimit.clock, .report      -- os.clock and warn by default; tests replace them
local RateLimit = {}
RateLimit.__index = RateLimit

RateLimit.BUSY = "Slow down a moment."
RateLimit.clock = os.clock
RateLimit.report = function(message: string) -- where refusals are logged; tests replace it
	warn(message)
end

type Bucket = { tokens: number, at: number, warned: number? }

function RateLimit.new(name: string, perSecond: number, burst: number)
	assert(perSecond > 0 and burst >= 1, "RateLimit.new: perSecond must be > 0 and burst >= 1")
	return setmetatable({
		name = name,
		perSecond = perSecond,
		burst = burst,
		buckets = setmetatable({}, { __mode = "k" }) :: { [any]: Bucket },
	}, RateLimit)
end

local function bucketOf(self, player): Bucket
	local now = RateLimit.clock()
	local b = self.buckets[player]
	if not b then
		b = { tokens = self.burst, at = now }
		self.buckets[player] = b
	else
		b.tokens = math.min(self.burst, b.tokens + (now - b.at) * self.perSecond)
		b.at = now
	end
	return b
end

function RateLimit.allow(self, player: any, cost: number?): boolean
	local c = cost or 1
	if player == nil or typeof(c) ~= "number" or c ~= c or c < 0 then
		return false
	end
	local b = bucketOf(self, player)
	if b.tokens >= c then
		b.tokens -= c
		return true
	end
	-- One warning a minute per player per limiter, so a spamming script shows up in the log without flooding it.
	local now = RateLimit.clock()
	if not b.warned or now - b.warned > 60 then
		b.warned = now
		RateLimit.report(("[Needlewood] rate limit %s: %s is calling too fast"):format(self.name, tostring(player)))
	end
	return false
end

function RateLimit.left(self, player: any): number
	return bucketOf(self, player).tokens
end

function RateLimit.forget(self, player: any)
	self.buckets[player] = nil
end

return RateLimit
