--!nonstrict
-- Everything the shop page lists and the goal bar counts toward, read from the price configs. When the central
-- price config lands ("Economy and banking"), point the reads below at it; the shop and goal bar follow.
-- Client only: ownership comes from this player's attributes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Trucks = require(Config:WaitForChild("Trucks"))
local Trailers = require(Config:WaitForChild("Trailers"))
local Gloves = require(Config:WaitForChild("Gloves"))
local LandConfig = require(Config:WaitForChild("Land"))

local Catalog = {}

local player = Players.LocalPlayer

local function listAttr(name)
	local set = {}
	for id in string.gmatch(player:GetAttribute(name) or "", "[^,]+") do
		set[id] = true
	end
	return set
end

local function flags()
	return listAttr("TutorialFlags")
end

-- Robux items. Cosmetic and convenience only, nothing stronger than what cash buys, no random boxes (project rule).
-- Placeholders until the store is set up: they show as coming soon.
Catalog.Robux = {
	{
		id = "paint_pack",
		name = "Truck paint pack",
		blurb = "Six Rustic paint jobs for any truck you own. Looks only.",
	},
	{ id = "glove_skins", name = "Glove skins", blurb = "Stitched patterns for your gloves. Same stats as before." },
	{ id = "farm_sign", name = "Carved farm sign", blurb = "Your name on a carved board at your plot's gate." },
}

Catalog.Tabs = { "Trucks", "Gloves", "Land", "Build", "Trailers", "Robux" }

-- One shop row: { id, name, blurb, price, robux, state, place }
-- state: "owned" | "wearing" | "buy" | "soon" | "taken" | "needland"
-- place: where it is bought (a Places id), or nil.
function Catalog.items(tab)
	local rows = {}
	if tab == "Trucks" then
		local owned = listAttr("OwnedTrucks")
		for _, def in Trucks do
			table.insert(rows, {
				id = def.id,
				name = def.name,
				blurb = def.blurb,
				price = def.price,
				state = owned[def.id] and "owned" or def.available and "buy" or "soon",
				place = "dealer",
			})
		end
	elseif tab == "Gloves" then
		local owned = listAttr("GlovesOwned")
		local wearing = player:GetAttribute("GloveId")
		for _, def in Gloves.Tiers do
			if def.price > 0 then
				table.insert(rows, {
					id = def.id,
					name = def.name,
					blurb = ("Tier %d. +%d hay carried, +%d per scoop, %d%% less slowdown."):format(
						def.tier,
						def.carryBonus,
						def.scoopBonus,
						math.round(def.relief * 100)
					),
					price = def.price,
					state = def.id == wearing and "wearing" or owned[def.id] and "owned" or "buy",
					place = "gloves",
				})
			end
		end
	elseif tab == "Land" then
		local mine = player:GetAttribute("LandPlot") or 0
		local state = ReplicatedStorage:FindFirstChild("Land")
		local infos = {}
		for _, info in state and state:GetChildren() or {} do
			if info:IsA("Configuration") then
				infos[info:GetAttribute("Index")] = info
			end
		end
		for index, def in LandConfig.Plots do
			local info = infos[index]
			local ownerId = info and info:GetAttribute("OwnerId") or 0
			local rowState = index == mine and "owned" or ownerId ~= 0 and "taken" or mine > 0 and "soon" or "buy"
			table.insert(rows, {
				id = def.zone,
				name = def.name,
				blurb = ("%d x %d build tiles."):format(def.tiles.X, def.tiles.Y)
					.. (ownerId ~= 0 and index ~= mine and (" Owned by %s."):format(
						info:GetAttribute("OwnerName") or "someone"
					) or "")
					.. (mine > 0 and index ~= mine and " One plot per save." or ""),
				price = def.price,
				state = rowState,
				place = "landoffice",
			})
		end
	elseif tab == "Build" then
		local hasLand = (player:GetAttribute("LandPlot") or 0) > 0
		for _, def in LandConfig.Pieces do
			table.insert(rows, {
				id = def.id,
				name = def.name,
				blurb = def.blurb,
				price = def.price,
				state = hasLand and "buy" or "needland",
				place = hasLand and "plot" or "landoffice",
			})
		end
	elseif tab == "Trailers" then
		for _, def in Trailers do
			table.insert(rows, {
				id = def.id,
				name = def.name,
				blurb = ("Holds %d bales a layer."):format(def.along * def.across),
				price = def.price,
				state = "soon",
				place = nil,
			})
		end
	elseif tab == "Robux" then
		for _, def in Catalog.Robux do
			table.insert(rows, { id = def.id, name = def.name, blurb = def.blurb, robux = def.robux, state = "soon" })
		end
	end
	return rows
end

-- The goal bar's ladder: the first one you don't have yet is the goal.
local LADDER = {
	{
		name = "Work Gloves",
		price = 250,
		place = "gloves",
		have = function()
			return listAttr("GlovesOwned").work
		end,
	},
	{
		name = "your first plot",
		price = LandConfig.Plots[1].price,
		place = "landoffice",
		have = function()
			return (player:GetAttribute("LandPlot") or 0) > 0
		end,
	},
	{
		name = "a Hand Sieve",
		price = 250,
		place = "plot",
		have = function()
			return flags().sorter
		end,
	},
	{
		name = "Leather Gloves",
		price = 1500,
		place = "gloves",
		have = function()
			return listAttr("GlovesOwned").leather
		end,
	},
	{
		name = "the Rusty Pickup",
		price = 6000,
		place = "dealer",
		have = function()
			return listAttr("OwnedTrucks").rusty_pickup
		end,
	},
	{
		name = "Reinforced Gloves",
		price = 6000,
		place = "gloves",
		have = function()
			return listAttr("GlovesOwned").reinforced
		end,
	},
	{
		name = "Iron Gauntlets",
		price = 25000,
		place = "gloves",
		have = function()
			return listAttr("GlovesOwned").iron
		end,
	},
	{
		name = "Starlight Gloves",
		price = 150000,
		place = "gloves",
		have = function()
			return listAttr("GlovesOwned").starlight
		end,
	},
}

-- Prices in the ladder follow the configs where they exist.
for _, def in Gloves.Tiers do
	for _, step in LADDER do
		if step.name == def.name then
			step.price = def.price
		end
	end
end
for _, def in Trucks do
	if def.id == "rusty_pickup" then
		LADDER[5].price = def.price
	end
end
for _, def in LandConfig.Pieces do
	if def.id == "hand_sieve" then
		LADDER[3].price = def.price
	end
end
local cheapest = math.huge
for _, def in LandConfig.Plots do
	cheapest = math.min(cheapest, def.price)
end
LADDER[2].price = cheapest

-- { name, price, place } for the next thing to save for, or nil when the ladder is done.
function Catalog.nextGoal()
	for _, step in LADDER do
		if not step.have() then
			return step
		end
	end
	return nil
end

return Catalog
