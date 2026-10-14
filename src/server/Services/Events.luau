--!nonstrict
-- A tiny game event bus with no dependencies, so any service can report what a player did without requiring the
-- services that care (quests, bounties, rituals). One line at the place it happens:
--   Events.fire(player, "bale_sold", 1, { hayType = "meadow" })
-- `who` may be a Player or a UserId. Listeners never throw back into the caller.
--
-- Kinds in use: bale_sold, hay_sold (amount = hay), bale_broken (info.position, info.hayType), needle_found
-- (info.needleId), needles_sold (amount = count, info.byType), raked (info.center).
local Players = game:GetService("Players")

local Events = {}

local listeners = {}
local isolated = {} -- player -> the one listener that hears their events (Quests.sandbox, so tests leave saves alone)

function Events.on(fn)
	table.insert(listeners, fn)
end

function Events.fire(who, kind, amount, info)
	local player = who
	if typeof(who) == "number" then
		player = Players:GetPlayerByUserId(who)
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	for _, fn in (isolated[player] and { isolated[player] }) or listeners do
		task.spawn(function()
			local ok, err = pcall(fn, player, kind, amount or 1, info or {})
			if not ok then
				warn("[Needlewood] event listener failed for " .. tostring(kind) .. ": " .. tostring(err))
			end
		end)
	end
end

-- While set, only `fn` hears this player's events (nil clears it). For Quests.sandbox: self-test events must not
-- reach the codex, achievements or anything else that writes the real save.
function Events.isolate(player, fn)
	isolated[player] = fn
end

return Events
