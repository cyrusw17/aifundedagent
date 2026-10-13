--!strict
-- Away earnings (CEO "Addiction push" H1): while a farm's owner is offline its line keeps sorting at half speed,
-- for at most 8 hours, and only from bales already in its silos (no income out of nothing). Pure arithmetic, so
-- tests/away.luau can check the cap and the double-pay guard headlessly; Land.mailbox does the paying.
--
--   Away.span(savedAt, now)               -> seconds to pay for: 0 if under a minute or the clock went backwards
--   Away.bales(span, balesPerMinute, stored) -> bales sorted while away (whole bales, never more than stored)
--
-- Double pay: Land.mailbox moves land.savedAt to now as it pays, so a second load (or a rejoin before the next
-- save) finds a span under a minute and pays nothing.
local Away = {}

Away.SHARE = 0.5 -- of the line's full rate (LineRate.line(...).bales)
Away.MAX_SECONDS = 8 * 3600
Away.MIN_SECONDS = 60

function Away.span(savedAt: any, now: number): number
	if typeof(savedAt) ~= "number" or savedAt ~= savedAt then
		return 0
	end
	local seconds = now - savedAt
	if seconds < Away.MIN_SECONDS then
		return 0
	end
	return math.min(seconds, Away.MAX_SECONDS)
end

function Away.bales(span: number, balesPerMinute: number, stored: number): number
	if span <= 0 or balesPerMinute <= 0 or stored <= 0 then
		return 0
	end
	return math.min(math.floor(stored), math.floor(span / 60 * balesPerMinute * Away.SHARE))
end

return Away
