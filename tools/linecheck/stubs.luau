-- Fakes for what Needle.luau calls into. Data keeps one save state per fake player, like a loaded slot.
STATES = {}
MODULES["Services.Data"] = function()
	return {
		get = function(player) return STATES[player] end,
		toast = function() end,
		sync = function() end,
	}
end
MODULES["Services.Announce"] = function() return { needle = function() end, send = function() end } end
MODULES["Services.Groups"] = function() return { Loose = "Loose" } end
MODULES["Services.Feedback"] = function() return { needle = function() end, play = function() end, sale = function() end } end
MODULES["Services.Events"] = function() return { fire = function() end, on = function() end } end
