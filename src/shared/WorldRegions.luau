--!nonstrict
-- Which region a point is in, for clients and servers alike (labels, sky tint, weather). Regions are the ovals in
-- Config/WorldMap; Meadow Farm is its square; Sky Island and the Crystal Cave are places of their own. Cheap: a
-- dozen ovals, no terrain math (WorldShape.regionAt on the server is the exact one, coasts included).
local Shared = script.Parent
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)

local WorldRegions = {}

local MEADOW_STYLE = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) }
WorldRegions.Meadow = { id = "meadow", name = "Meadow Farm", style = MEADOW_STYLE, hayType = "meadow" }
WorldRegions.Sky = { id = "sky", name = "Sky Island", style = { accent = Color3.fromRGB(200, 170, 90), fog = Color3.fromRGB(214, 226, 240), density = -0.08 }, hayType = "sky" }
WorldRegions.Cave = { id = "cave", name = "Crystal Cave", style = { accent = Color3.fromRGB(150, 110, 200), fog = Color3.fromRGB(70, 60, 90), density = 0.12 }, hayType = "cave" }

-- The region at a Vector3 (or nil out at sea).
function WorldRegions.at(position)
	if Map.SkyIsland and position.Y > Map.SkyIsland.top - 60 then
		local d = Vector2.new(position.X, position.Z) - Map.SkyIsland.center
		if d.Magnitude < Map.SkyIsland.radius + 40 then
			return WorldRegions.Sky
		end
	end
	local cave = Map.Cave.chamber
	if (position - cave.center).Magnitude < cave.radius * 1.2 then
		return WorldRegions.Cave
	end
	if math.abs(position.X) < Meadow.HalfSize and math.abs(position.Z) < Meadow.HalfSize then
		return WorldRegions.Meadow
	end
	local best, bestValue = nil, 0
	for _, r in Map.Regions do
		local dx = (position.X - r.center.X) / r.radius.X
		local dz = (position.Z - r.center.Y) / r.radius.Y
		local value = 1 - math.sqrt(dx * dx + dz * dz)
		if value > bestValue then
			best, bestValue = r, value
		end
	end
	return best
end

return WorldRegions
