--!nonstrict
-- The gilded sorter skin: a player who has filled 75% of the needle index (Needle index, player attribute
-- NeedleIndexSkin = "gilded") sees every sorter on their plot turn gold, part look and Blender mesh alike. Only a tint
-- of color and material on what is already there; clearing the attribute puts each part's own look back.
--
--   GildedSorters.start()   -- once at server start; Land tags each plot sorter "PlotSorter" with its OwnerId
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local GildedSorters = {}

local GOLD = Color3.fromRGB(212, 172, 72)
local SKIP = { [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }

local function gild(part, on)
	if on then
		if part:GetAttribute("GildOwnColor") == nil then
			if SKIP[part.Material] or part:HasTag("Needle") then
				return
			end
			part:SetAttribute("GildOwnColor", part.Color)
			part:SetAttribute("GildOwnMaterial", part.Material.Name)
			if part:IsA("MeshPart") then
				part:SetAttribute("GildOwnTexture", part.TextureID)
				pcall(function()
					part.TextureID = "" -- a textured mesh ignores Color
				end)
			end
		end
		part.Color = GOLD
		part.Material = Enum.Material.Foil
	elseif part:GetAttribute("GildOwnColor") ~= nil then
		part.Color = part:GetAttribute("GildOwnColor")
		part.Material = Enum.Material[part:GetAttribute("GildOwnMaterial")] or part.Material
		if part:IsA("MeshPart") then
			local texture = part:GetAttribute("GildOwnTexture")
			pcall(function()
				part.TextureID = texture or ""
			end)
		end
		part:SetAttribute("GildOwnColor", nil)
		part:SetAttribute("GildOwnMaterial", nil)
		part:SetAttribute("GildOwnTexture", nil)
	end
end

local function wantsGold(ownerId)
	local player = ownerId and Players:GetPlayerByUserId(ownerId)
	return player ~= nil and player:GetAttribute("NeedleIndexSkin") == "gilded"
end

function GildedSorters.apply(sorter)
	local on = wantsGold(sorter:GetAttribute("OwnerId"))
	sorter:SetAttribute("Gilded", on)
	for _, part in sorter:GetDescendants() do
		if part:IsA("BasePart") then
			gild(part, on)
		end
	end
end

local function refresh(userId)
	for _, sorter in CollectionService:GetTagged("PlotSorter") do
		if sorter:GetAttribute("OwnerId") == userId then
			GildedSorters.apply(sorter)
		end
	end
end

function GildedSorters.start()
	CollectionService:GetInstanceAddedSignal("PlotSorter"):Connect(function(sorter)
		task.defer(GildedSorters.apply, sorter) -- after the mesh is dressed on
	end)
	local function watch(player)
		player:GetAttributeChangedSignal("NeedleIndexSkin"):Connect(function()
			refresh(player.UserId)
		end)
		refresh(player.UserId)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return GildedSorters
