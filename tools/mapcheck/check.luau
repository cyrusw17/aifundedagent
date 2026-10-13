local t0 = os.clock()
local world = Instance.new("Folder")
world.Name = "Needlewood"
world.Parent = workspace
local meadow = Instance.new("Folder")
meadow.Name = "Meadow"
meadow.Parent = world
local WorldMap = require({ __path = "Services.WorldMap" })
WorldMap.build(world)
local isles = world:FindFirstChild("StitchedIsles")
local function count(folder)
	local parts, models, guis, lights = 0, 0, 0, 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then parts += 1 elseif d.ClassName == "Model" then models += 1 elseif d:IsA("LayerCollector") then guis += 1 elseif d:IsA("Light") then lights += 1 end
	end
	return parts, models, guis, lights
end
for _, child in isles:GetChildren() do
	local p, m, g, l = count(child)
	print(("%-22s parts %6d  models %5d  guis %4d  lights %3d"):format(child.Name, p, m, g, l))
	if child.Name == "Isles" then
		for _, sub in child:GetChildren() do
			local p2 = count(sub)
			print(("    %-26s parts %6d"):format(sub.Name, p2))
		end
	end
end
local p, m, g, l = count(isles)
print(("TOTAL parts %d models %d guis %d lights %d; field bales %d; time %.2fs; warnings %d"):format(p, m, g, l, BALES, os.clock() - t0, #warnings))
for tag, n in TAGS do print("tag", tag, n) end
local Shape = require({ __path = "Services.WorldShape" })
local Map = require({ __path = "Shared.Config.WorldMap" })
local half = Map.RoadWidth / 2 - 1
local n = 0
for _, p in isles:FindFirstChild("Isles"):GetDescendants() do
	if p:IsA("BasePart") and p.Anchored and p.CanCollide and p.Transparency < 1 then
		local c, size = p.CFrame, p.Size
		local s = Vector3.new(math.abs(size.X), math.abs(size.Y), math.abs(size.Z))
		for _, o in { Vector3.zero, Vector3.new(s.X/2,0,s.Z/2), Vector3.new(-s.X/2,0,s.Z/2), Vector3.new(s.X/2,0,-s.Z/2), Vector3.new(-s.X/2,0,-s.Z/2) } do
			local at = c * (o * 0.9)
			local d, h, name = Shape.nearestRoad(at.X, at.Z)
			if d and d < half and c.Y + 4 > h + 0.6 and c.Y - 4 < h + 9 then
				n += 1
				print("BLOCK", p:GetFullName(), math.floor(at.X), math.floor(at.Z), name, math.floor(d), math.floor(c.Y - h))
				break
			end
		end
	end
end
print("blocking", n)

-- Every road starts at Meadow's edge, on another road, on a flat zone (plaza, port) or at the highway.
local loose = 0
for r, road in Map.Roads do
	local start = road.points[1]
	local joined = Shape.meadowDistance(start.X, start.Y) < 4 or Shape.highwayDistance(start.X, start.Y) < Map.Highway.width
	for _, zone in Map.Flat do
		if Shape.rectDistance(start.X, start.Y, zone.min, zone.max) <= 0 then
			joined = true
		end
	end
	for other = 1, #Map.Roads do
		local pts = Map.Roads[other].points
		for i = 1, #pts - 1 do
			if other ~= r and Shape.segment(start.X, start.Y, pts[i].X, pts[i].Y, pts[i + 1].X, pts[i + 1].Y) < 4 then
				joined = true
			end
		end
	end
	if not joined then
		loose += 1
		print("WARN loose road start", road.name, start.X, start.Y)
	end
end
print("loose road starts", loose)
