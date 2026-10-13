--!nonstrict
-- Server-wide banners for big moments (a mutated needle, a rare find, events): a strip across the top of every
-- player's screen (Announce.client.luau). Rate limited so a lucky streak can't flood the screen.
--   Announce.say("Cyrus found a x3 MUTATED gold needle worth $900!", "gold")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Announce = {}

local MIN_GAP = 4 -- seconds between banners; anything sooner waits its turn
local MAX_QUEUE = 4

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
	table.insert(queue, { text = text, kind = kind })
	pump()
end

function Announce.start()
	remote = Instance.new("RemoteEvent")
	remote.Name = "Announce"
	remote.Parent = ReplicatedStorage
end

return Announce
