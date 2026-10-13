--!nonstrict
-- Show-off name tags (CEO "Addiction push" H8): a line over every player's head naming the best needle they have ever
-- held, so a x12 mutated Cosmic is seen across base camp. Gold for a mutated needle, the rarity colour for an Epic or
-- Legendary type, white otherwise. No tag until a slot is loaded and a needle has been in the pocket.
-- The best needle is kept in the save slot as state.codex.bestNeedle (a pocket key, Needle.keyOf), best by
-- Needle.priceOf, so it never goes down when the needle is sold, traded or hung on a display wall. Published as the
-- player attribute "BestNeedle" (the same key) for the UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLabel = require(ReplicatedStorage.Shared.WorldLabel)
local Data = require(script.Parent.Data)
local Needle = require(script.Parent.Needle)

local NameTags = {}

local GOLD = Color3.fromRGB(255, 206, 96)
local TAG = "BestNeedleTag"

local function valueOf(key)
	if typeof(key) ~= "string" then
		return -1
	end
	local ok, value = pcall(function()
		local id, mult, polished, grade = Needle.parseKey(key)
		return Needle.priceOf(id, mult, polished, grade)
	end)
	return ok and typeof(value) == "number" and value or -1
end

-- The tag's text and colour for a pocket key, or nil for no tag.
local function tagFor(key)
	if valueOf(key) < 0 then
		return nil
	end
	local id, mult, polished = Needle.parseKey(key)
	local name = Needle.info(id).name
	if polished then
		name = "Polished " .. name
	end
	if mult > 1 then
		return ("★ x%d MUTATED %s"):format(mult, name:upper()), GOLD
	end
	local rarity = Needle.rarity(id)
	return ("Best needle: %s"):format(name), rarity and rarity.color or Color3.new(1, 1, 1)
end

-- The better of the saved best and everything in the pocket now. Returns the key, or nil.
local function bestOf(saved, pocket)
	local bestKey, bestValue = nil, -1
	if valueOf(saved) >= 0 then
		bestKey, bestValue = saved, valueOf(saved)
	end
	for key, count in pocket or {} do
		if typeof(count) == "number" and count > 0 then
			local value = valueOf(key)
			if value > bestValue then
				bestKey, bestValue = key, value
			end
		end
	end
	return bestKey
end

local function draw(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local text, color = tagFor(player:GetAttribute("BestNeedle"))
	local gui = head:FindFirstChild(TAG)
	if not text then
		if gui then
			gui:Destroy()
		end
		return
	end
	local label = gui and gui:FindFirstChild("Text")
	if not label then
		label = WorldLabel.billboard(head, text, { kind = "tag", offset = Vector3.new(0, 3.1, 0), distance = 80 })
		label.Parent.Name = TAG
	end
	label.Text = text
	label.TextColor3 = color
end

-- Re-reads the pocket, keeps the best in the save, and redraws the tag if it changed.
local function refresh(player)
	local state = Data.get(player)
	if not state then
		return
	end
	if typeof(state.codex) ~= "table" then
		state.codex = {}
	end
	local best = bestOf(state.codex.bestNeedle, state.pocket)
	if best ~= state.codex.bestNeedle then
		state.codex.bestNeedle = best
	end
	if player:GetAttribute("BestNeedle") ~= best then
		player:SetAttribute("BestNeedle", best)
		draw(player)
	end
end

local function watch(player)
	player:GetAttributeChangedSignal("NeedlesHeld"):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		draw(player)
	end)
	if player.Character then
		draw(player)
	end
end

function NameTags.start()
	Data.loaded.Event:Connect(function(player)
		player:SetAttribute("BestNeedle", nil) -- a different slot has its own best
		refresh(player)
		draw(player)
	end)
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
		refresh(player)
	end
end

-- For SelfTests only.
NameTags.test = { tagFor = tagFor, bestOf = bestOf }

return NameTags
