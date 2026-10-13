--!nonstrict
-- Everything the shop page lists and the goal bar counts toward. Prices come from Config/Prices (the one price
-- config, "Economy and banking"); the item configs give names and blurbs.
-- Ownership comes from the local player's attributes. Catalog.who can be set to any object with GetAttribute (a
-- Player, or a stand-in table) so the server self-test can run the same logic (SelfTests/UI.luau).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Trucks = require(Config:WaitForChild("Trucks"))
local Trailers = require(Config:WaitForChild("Trailers"))
local Gloves = require(Config:WaitForChild("Gloves"))
local LandConfig = require(Config:WaitForChild("Land"))
local Prices = require(Config:WaitForChild("Prices"))
local PieceGuide = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PieceGuide"))
local ToolGuide = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ToolGuide")) -- glove lines (Hay thread)

local Catalog = {}

Catalog.who = Players.LocalPlayer

local function attr(name)
	local who = Catalog.who
	if who == nil then
		return nil
	end
	return who:GetAttribute(name)
end

local function listAttr(name)
	local set = {}
	for id in string.gmatch(attr(name) or "", "[^,]+") do
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
				price = Prices.Trucks[def.id] or def.price,
				state = owned[def.id] and "owned" or def.available and "buy" or "soon",
				place = "dealer",
			})
		end
	elseif tab == "Gloves" then
		local owned = listAttr("GlovesOwned")
		local wearing = attr("GloveId")
		for _, def in Gloves.Tiers do
			if def.price > 0 then
				table.insert(rows, {
					id = def.id,
					name = def.name,
					blurb = ToolGuide.glove(def), -- built from the configs, with the walk speed under a bale
					price = Prices.Gloves[def.id] or def.price,
					state = def.id == wearing and "wearing" or owned[def.id] and "owned" or "buy",
					place = "gloves",
				})
			end
		end
	elseif tab == "Land" then
		local mine = attr("LandPlot") or 0
		local state = ReplicatedStorage:FindFirstChild("Land")
		local infos = {}
		for _, info in state and state:GetChildren() or {} do
			if info:IsA("Configuration") then
				infos[info:GetAttribute("Index")] = info
			end
		end
		-- A save owns up to two farms (Land.luau onBuy): the first at the plot price, the second at
		-- LandConfig.SecondPlotPrice. FarmCount says how many this save has.
		local farms = attr("FarmCount") or (mine > 0 and 1 or 0)
		local who = Catalog.who
		local myId = who and (who :: any).UserId
		for index, def in LandConfig.Plots do
			local info = infos[index]
			local ownerId = info and info:GetAttribute("OwnerId") or 0
			local isMine = index == mine or (myId ~= nil and ownerId == myId)
			local rowState = isMine and "owned" or ownerId ~= 0 and "taken" or farms >= 2 and "full" or "buy"
			local second = farms == 1 and not isMine
			local blurb = ("%d x %d build tiles."):format(def.tiles.X, def.tiles.Y)
			if ownerId ~= 0 and not isMine then
				blurb ..= (" Owned by %s."):format(info:GetAttribute("OwnerName") or "someone")
			elseif second and ownerId == 0 then
				blurb ..= " Your second farm: more room to store and sort."
			elseif farms >= 2 and not isMine then
				blurb ..= " Two farms per save."
			end
			table.insert(rows, {
				id = def.zone,
				name = def.name,
				blurb = blurb,
				price = second and (LandConfig.SecondPlotPrice or Prices.SecondPlot) or Prices.Plot or def.price,
				state = rowState,
				place = "landoffice",
			})
		end
	elseif tab == "Build" then
		local hasLand = (attr("LandPlot") or 0) > 0
		for _, def in LandConfig.Pieces do
			-- Quest rewards (Starbeam Collector) are earned, not bought.
			if not def.quest then
				table.insert(rows, {
					id = def.id,
					name = def.name,
					blurb = PieceGuide.line(def), -- built from the configs, so stats and prices can't drift
					price = Prices.Pieces[def.id] or def.price,
					state = hasLand and "buy" or "needland",
					place = hasLand and "plot" or "landoffice",
				})
			end
		end
	elseif tab == "Trailers" then
		local ownedTrailers = listAttr("OwnedTrailers")
		for _, def in Trailers do
			table.insert(rows, {
				id = def.id,
				name = def.name,
				blurb = ("Holds %d bales a layer."):format(def.along * def.across),
				price = Prices.Trailers[def.id] or def.price,
				state = ownedTrailers[def.id] and "owned" or "buy",
				place = "dealer",
			})
		end
	elseif tab == "Robux" then
		for _, def in Catalog.Robux do
			table.insert(rows, { id = def.id, name = def.name, blurb = def.blurb, robux = def.robux, state = "soon" })
		end
	end
	return rows
end

-- The goal bar's ladder, in the order ECONOMY.md plans the first hours: Work Gloves, Wheelbarrow, Pickup (on a loan),
-- Wagon, Plot and a hand sieve, Shaker table, Leather Gloves, Flatbed (on a loan), Conveyor sorter, then the higher
-- glove tiers. The first one you don't have yet is the goal. Prices come from Config/Prices.
local function hasGlove(id)
	return function()
		return listAttr("GlovesOwned")[id] == true
	end
end
local function built(id)
	return function()
		return flags()["built_" .. id] == true
	end
end
local LADDER = {
	{ name = "Work Gloves", price = Prices.Gloves.work, place = "gloves", have = hasGlove("work") },
	{
		name = "a Wheelbarrow",
		price = Prices.Wheelbarrow,
		place = "sellpad", -- the stand is beside the sell pad
		have = function()
			return listAttr("Gear").wheelbarrow == true
		end,
	},
	{
		name = "the Rusty Pickup",
		price = Prices.Trucks.rusty_pickup,
		loan = true,
		place = "dealer",
		have = function()
			return listAttr("OwnedTrucks").rusty_pickup == true
		end,
	},
	{
		name = "a Wagon Trailer",
		price = Prices.Trailers.wagon_trailer,
		place = "dealer",
		have = function()
			return listAttr("OwnedTrailers").wagon_trailer == true
		end,
	},
	{
		name = "your first plot",
		price = Prices.Plot,
		place = "landoffice",
		have = function()
			return (attr("LandPlot") or 0) > 0
		end,
	},
	{ name = "a Hand Sieve", price = Prices.Pieces.hand_sieve, place = "plot", have = built("hand_sieve") },
	{ name = "a Shaker Table", price = Prices.Pieces.shaker_table, place = "plot", have = built("shaker_table") },
	{ name = "Leather Gloves", price = Prices.Gloves.leather, place = "gloves", have = hasGlove("leather") },
	{
		name = "the Farm Flatbed",
		price = Prices.Trucks.farm_flatbed,
		loan = true,
		place = "dealer",
		have = function()
			return listAttr("OwnedTrucks").farm_flatbed == true
		end,
	},
	{
		name = "a Conveyor Sorter",
		price = Prices.Pieces.conveyor_sorter,
		place = "plot",
		have = built("conveyor_sorter"),
	},
	{ name = "Reinforced Gloves", price = Prices.Gloves.reinforced, place = "gloves", have = hasGlove("reinforced") },
	{ name = "Iron Gauntlets", price = Prices.Gloves.iron, place = "gloves", have = hasGlove("iron") },
	{ name = "Starlight Gloves", price = Prices.Gloves.starlight, place = "gloves", have = hasGlove("starlight") },
}
Catalog.Ladder = LADDER

-- { name, price, place, loan } for the next thing to save for, or nil when the ladder is done.
function Catalog.nextGoal()
	for _, step in LADDER do
		if not step.have() then
			return step
		end
	end
	return nil
end

return Catalog
