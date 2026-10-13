--!nonstrict
-- Where things are in Meadow Farm, for the map, the shop's "Show me" buttons and the guide's arrows. Each place
-- looks for the real part first and falls back to the spot its builder uses, so it stays right if a building moves.
-- Client only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Meadow = require(Config:WaitForChild("Meadow"))
local LandConfig = require(Config:WaitForChild("Land"))

local Places = {}

local function world()
	return Workspace:FindFirstChild("Needlewood")
end

local function tagged(tag)
	local list = CollectionService:GetTagged(tag)
	return list[1] and list[1].Position or nil
end

local function named(name)
	local folder = world()
	local p = folder and folder:FindFirstChild(name, true)
	if p and p:IsA("BasePart") then
		return p.Position
	elseif p and p:IsA("Model") then
		return p:GetPivot().Position
	end
	return nil
end

local function glovePrompt()
	for _, d in Workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name == "GlovePrompt" and d.Parent and d.Parent:IsA("BasePart") then
			return d.Parent.Position
		end
	end
	return nil
end

-- The plot this player owns, as its center, or nil.
function Places.myPlot()
	local index = Players.LocalPlayer:GetAttribute("LandPlot") or 0
	if index <= 0 then
		return nil
	end
	local state = ReplicatedStorage:FindFirstChild("Land")
	for _, info in state and state:GetChildren() or {} do
		if info:IsA("Configuration") and info:GetAttribute("Index") == index then
			local corner = info:GetAttribute("Corner")
			local tx, tz = info:GetAttribute("TilesX") or 0, info:GetAttribute("TilesZ") or 0
			if corner then
				return corner + Vector3.new(tx * 3, 0, tz * 3)
			end
		end
	end
	local def = LandConfig.Plots[index]
	for _, zone in Meadow.Plots do
		if def and zone.id == def.zone then
			local c = (zone.min + zone.max) / 2
			return Vector3.new(c.X, 0, c.Y)
		end
	end
	return nil
end

-- Landmarks: id -> { name, find = function() -> Vector3, fallback = Vector3 }
Places.List = {
	{
		id = "camp",
		name = "Base camp",
		fallback = Vector3.new(0, 0, 14),
		find = function()
			return named("BaseCampSpawn")
		end,
	},
	{
		id = "sellpad",
		name = "Sell pad",
		fallback = Vector3.new(22, 0, -6),
		find = function()
			return named("SellPad")
		end,
	},
	{
		id = "hayshop",
		name = "Hay shop",
		fallback = Vector3.new(22, 0, -18),
		find = function()
			return named("HayShop")
		end,
	},
	{ id = "gloves", name = "Shovel rack", fallback = Vector3.new(12.5, 0, -6), find = glovePrompt },
	{
		id = "sellshop",
		name = "HAY SELL SHOP",
		fallback = Vector3.new(63, 0, -25),
		find = function()
			return named("HaySellShop")
		end,
	},
	{
		id = "dealer",
		name = "Homestead Motors",
		fallback = Meadow.DealerCenter,
		find = function()
			return tagged("DealerCounter")
		end,
	},
	{
		id = "landoffice",
		name = "Land Office",
		fallback = LandConfig.OfficeCenter,
		find = function()
			return tagged("LandCounter")
		end,
	},
}

local byId = {}
for _, place in Places.List do
	byId[place.id] = place
end

-- The world position of a place id, or of "plot" (your plot).
function Places.get(id)
	if id == "plot" then
		return Places.myPlot()
	end
	local place = byId[id]
	if not place then
		return nil
	end
	local ok, found = pcall(place.find)
	return ok and found or place.fallback
end

function Places.name(id)
	if id == "plot" then
		return "Your plot"
	end
	return byId[id] and byId[id].name or id
end

return Places
