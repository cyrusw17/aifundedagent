--!nonstrict
-- Exploration as a progression track: the first visit to each region (Config/WorldMap Regions, plus Sky Island and
-- the Crystal Cave) and each landmark (Config/WorldMap Discoveries) pays Prices.Discovery once per save slot and
-- stamps it as found. Kept in state.discovered and published as the player attribute "Discovered" ("old_well,pine,...")
-- for the map's stamps and the collection book's pages. Discoveries.all() lists every one in order, for those pages.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Prices = require(Shared.Config.Prices)
local WorldRegions = require(Shared.WorldRegions)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local WorldShape = require(script.Parent.WorldShape)

local Discoveries = {}

local CHECK_EVERY = 1 -- seconds

-- Every discovery: { id, name, kind = "region" | "landmark", at = Vector2? (landmarks), radius }
local list = {}
local byId = {}

local function add(entry)
	table.insert(list, entry)
	byId[entry.id] = entry
end

for _, r in Map.Regions do
	add({ id = r.id, name = r.name, kind = "region" })
end
add({ id = WorldRegions.Sky.id, name = WorldRegions.Sky.name, kind = "region" })
add({ id = WorldRegions.Cave.id, name = WorldRegions.Cave.name, kind = "region" })
local landmarks = {}
for _, d in Map.Discoveries do
	local at = d.at
	if d.flat then
		for _, zone in Map.Flat do
			if zone.name == d.flat then
				at = (zone.min + zone.max) / 2
			end
		end
	end
	if at then
		local entry = { id = d.id, name = d.name, kind = "landmark", at = at, radius = d.radius }
		add(entry)
		table.insert(landmarks, entry)
	end
end

-- Where the first-visit camera pan looks (#24): the region's first landmark, else its peak, else its middle.
-- Sky Island looks at the zeppelin platform; the Crystal Cave has no pan (the camera would clip the rock).
local focusCache = {}
function Discoveries.focus(id)
	if focusCache[id] ~= nil then
		return focusCache[id] or nil
	end
	local at = nil
	if id == WorldRegions.Sky.id then
		at = Map.Zeppelin.b.pos
	elseif id ~= WorldRegions.Cave.id then
		for _, entry in landmarks do
			local y = WorldShape.heightAt(entry.at.X, entry.at.Y)
			local region = WorldRegions.at(Vector3.new(entry.at.X, y + 2, entry.at.Y))
			if region and region.id == id then
				at = Vector3.new(entry.at.X, math.max(y, Map.SeaLevel), entry.at.Y)
				break
			end
		end
		local r = not at and WorldShape.region(id)
		if r then
			local c = r.peak and r.peak.center or Vector2.new(r.cx, r.cz)
			at = Vector3.new(c.X, math.max(WorldShape.heightAt(c.X, c.Y), Map.SeaLevel), c.Y)
		end
	end
	focusCache[id] = at or false
	return at
end

local introRemote = nil

-- A discovery made by finding something rather than by walking up to it (Wilds hidden spots): stamped by
-- Discoveries.discover when it's found; kind "hidden" pays nothing here (the find pays its own reward).
function Discoveries.addHidden(id, name)
	if not byId[id] then
		add({ id = id, name = name, kind = "hidden" })
	end
end

function Discoveries.all()
	return list
end

function Discoveries.info(id)
	return byId[id]
end

local function publish(player)
	local state = Data.get(player)
	local ids = {}
	for id in (state and state.discovered or {}) do
		table.insert(ids, id)
	end
	table.sort(ids)
	player:SetAttribute("Discovered", table.concat(ids, ","))
	player:SetAttribute("DiscoveredCount", #ids)
end

function Discoveries.has(player, id)
	local state = Data.get(player)
	return state ~= nil and state.discovered ~= nil and state.discovered[id] ~= nil
end

-- Marks a discovery found for this player (first time only); returns true when it was new.
function Discoveries.discover(player, id)
	local entry = byId[id]
	local state = Data.get(player)
	if not entry or not state then
		return false
	end
	state.discovered = state.discovered or {}
	if state.discovered[id] then
		return false
	end
	state.discovered[id] = 1
	local reward = Prices.Discovery[entry.kind] or 0
	if reward > 0 then
		Bank.earn(player, reward, "Discovered " .. entry.name)
	end
	local count = 0
	for _ in state.discovered do
		count += 1
	end
	if entry.kind ~= "hidden" then -- a hidden find already said so
		Data.toast(player, ("Discovered: %s! +$%d   (%d of %d)"):format(entry.name, reward, count, #list))
	end
	-- First time in a region on this save: a short camera pan over its landmark (RegionIntro.client.luau).
	local focus = entry.kind == "region" and Discoveries.focus(id)
	if focus and introRemote then
		task.spawn(function()
			pcall(player.RequestStreamAroundAsync, player, focus, 4)
			if player.Parent then
				pcall(introRemote.FireClient, introRemote, player, entry.name, focus)
			end
		end)
	end
	publish(player)
	return true
end

-- What a player standing at this position discovers (region first, then any landmark in reach).
function Discoveries.at(position)
	local found = {}
	local region = WorldRegions.at(position)
	if region and region.id ~= WorldRegions.Meadow.id then
		table.insert(found, region.id)
	end
	local flat = Vector2.new(position.X, position.Z)
	for _, entry in landmarks do
		if (flat - entry.at).Magnitude <= entry.radius then
			table.insert(found, entry.id)
		end
	end
	return found
end

local started = false
function Discoveries.start()
	if started then
		return
	end
	started = true
	introRemote = Instance.new("RemoteEvent")
	introRemote.Name = "RegionIntro"
	introRemote.Parent = ReplicatedStorage
	Data.loaded.Event:Connect(publish)
	for _, player in Players:GetPlayers() do
		if Data.get(player) then
			publish(player)
		end
	end
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and Data.get(player) then
					for _, id in Discoveries.at(root.Position) do
						if not Discoveries.has(player, id) then
							Discoveries.discover(player, id)
						end
					end
				end
			end
		end
	end)
end

return Discoveries
