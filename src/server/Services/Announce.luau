--!nonstrict
-- Server-wide banners for big moments (a mutated needle, a rare find, events): a strip across the top of every
-- player's screen (Announce.client.luau). Rate limited so a lucky streak can't flood the screen: lucky finds are
-- capped at one every 30 seconds.
--   Announce.say("Cyrus found a x3 MUTATED gold needle worth $900!", "gold")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Announce = {}

local MIN_GAP = 4 -- seconds between banners; anything sooner waits its turn
local MAX_QUEUE = 4
-- Lucky-find banners ("gold": mutated needles, rare finds, golden bales) at most one every LUCKY_GAP seconds server
-- wide; the rest are dropped, so a big line rolling mutations can't fill everyone's screen (CEO #32). Events still
-- queue as before.
local LUCKY_GAP = 30
local lastLucky = -math.huge

local remote = nil
local queue = {}
local busy = false

local function pump()
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		while #queue > 0 do
			local item = table.remove(queue, 1)
			if remote then
				remote:FireAllClients(item.text, item.kind)
			end
			task.wait(MIN_GAP)
		end
		busy = false
	end)
end

-- kind: "gold" (lucky finds), "event" (rich field, weather) or nil (plain).
function Announce.say(text, kind)
	if typeof(text) ~= "string" or text == "" then
		return
	end
	if #queue >= MAX_QUEUE then
		return
	end
	if kind == "gold" then
		if os.clock() - lastLucky < LUCKY_GAP then
			return
		end
		lastLucky = os.clock()
	end
	table.insert(queue, { text = text, kind = kind })
	pump()
end

function Announce.start()
	remote = Instance.new("RemoteEvent")
	remote.Name = "Announce"
	remote.Parent = ReplicatedStorage
end

return Announce
