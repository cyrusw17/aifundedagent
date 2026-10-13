--!nonstrict
-- Every discovery in the order Services/Discoveries.luau keeps them (regions, Sky Island, the Crystal Cave, the
-- landmarks of Config/WorldMap Discoveries, then each region's hidden spot), with a map position for each, for the map's stamps and the collection
-- book's page. Which ones a player has found is the "Discovered" player attribute ("old_well,pine,...").
-- Safe on the server too (the UI self-test uses it).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared:WaitForChild("Config"):WaitForChild("WorldMap"))
local Prices = require(Shared.Config:WaitForChild("Prices"))
local WorldRegions = require(Shared:WaitForChild("WorldRegions"))

local DiscoveryList = {}

-- { id, name, kind = "region" | "landmark" | "hidden", at = Vector2 (nil for hidden), reward, near = region name }
local list = {}
local function rewardOf(kind)
	local d = Prices.Discovery
	return typeof(d) == "table" and d[kind] or 0
end
for _, r in Map.Regions do
	table.insert(list, { id = r.id, name = r.name, kind = "region", at = r.center, reward = rewardOf("region") })
end
if Map.SkyIsland then
	local sky = WorldRegions.Sky
	table.insert(
		list,
		{ id = sky.id, name = sky.name, kind = "region", at = Map.SkyIsland.center, reward = rewardOf("region") }
	)
end
if Map.Cave and Map.Cave.chamber then
	local cave, c = WorldRegions.Cave, Map.Cave.chamber.center
	table.insert(
		list,
		{ id = cave.id, name = cave.name, kind = "region", at = Vector2.new(c.X, c.Z), reward = rewardOf("region") }
	)
end
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
		local region = WorldRegions.at(Vector3.new(at.X, 0, at.Y))
		-- A landmark just past the terrain box (Ghost Isle) still stamps the map, at its edge.
		local margin = 8
		at = Vector2.new(
			math.clamp(at.X, Map.Bounds.min.X + margin, Map.Bounds.max.X - margin),
			math.clamp(at.Y, Map.Bounds.min.Y + margin, Map.Bounds.max.Y - margin)
		)
		table.insert(list, {
			id = d.id,
			name = d.name,
			kind = "landmark",
			at = at,
			reward = rewardOf("landmark"),
			near = region and region.name or "the isles",
		})
	end
end

-- Then one hidden spot per region (Wilds.luau adds them on the server in region order as "hidden_<region id>"). Where
-- they are is a secret, so they have no map spot (at = nil) and no stamp; the book lists them.
local secrets = Prices.Secrets
for _, r in Map.Regions do
	table.insert(list, {
		id = "hidden_" .. r.id,
		name = "Secret of " .. r.name,
		kind = "hidden",
		reward = typeof(secrets) == "table" and secrets.hidden or 0,
		near = r.name,
	})
end

function DiscoveryList.all()
	return list
end

-- { [id] = true } from a player's "Discovered" attribute (anything with GetAttribute).
function DiscoveryList.found(who)
	local set = {}
	for id in string.gmatch(who and who:GetAttribute("Discovered") or "", "[^,]+") do
		set[id] = true
	end
	return set
end

return DiscoveryList
