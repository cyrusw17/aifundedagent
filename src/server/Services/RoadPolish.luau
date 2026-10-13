--!nonstrict
-- Finishing on the roads: where a road crosses water (bog pools on the Swamp Road, the Dune Cut's creek) its causeway
-- becomes a timber bridge, with guard rails on the water side, trestle legs down into the water and a name board at
-- each end. The driving surface stays the terrain causeway WorldShape lays at road height, so a truck with a trailer
-- crosses it like any road (the rails stand outside the 16-stud lane). Roads with a steep drop beside them get the
-- same rail on that side.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Map = require(ReplicatedStorage.Shared.Config.WorldMap)
local Rustic = require(ReplicatedStorage.Shared.Config.Rustic)
local WorldShape = require(script.Parent.WorldShape)

local RoadPolish = {}

local STEP = 8 -- studs between rail posts
local ROAD_HALF = Map.RoadWidth / 2
local PROBE = ROAD_HALF + 5 -- how far out from the center line to look for water or a drop
local RAIL_AT = ROAD_HALF + 1.5 -- rail posts stand just off the lane
local DROP = 4 -- a drop this much below the road at PROBE gets a rail
local MIN_RUN = 3 -- posts; shorter stretches are left plain

RoadPolish.bridges = {} -- { road, from = Vector3, to = Vector3, side }

local function part(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- One side of a road along one straight piece: the runs of samples that need a rail. Each run is a list of
-- { post = Vector3 (top of the road at the rail line), water = bool, bed = ground height out there }.
local function runsAlong(a, b, side)
	local dir = (b - a).Unit
	local normal = Vector2.new(-dir.Y, dir.X) * side
	local runs, current = {}, nil
	local steps = math.floor((b - a).Magnitude / STEP)
	for k = 0, steps do
		local p = a + dir * (k * STEP)
		local need = nil
		if not WorldShape.inMeadow(p.X, p.Y) then
			local _, h = WorldShape.nearestRoad(p.X, p.Y)
			if h then
				local q = p + normal * PROBE
				local ground, water = WorldShape.column(q.X, q.Y)
				if water or ground < h - DROP then
					local r = p + normal * RAIL_AT
					need = { post = Vector3.new(r.X, h, r.Y), water = water ~= nil, bed = ground }
				end
			end
		end
		if need then
			current = current or {}
			table.insert(current, need)
		elseif current then
			table.insert(runs, current)
			current = nil
		end
	end
	if current then
		table.insert(runs, current)
	end
	return runs
end

local function rail(folder, run)
	local wood, dark = Rustic.Wood, Rustic.WoodDark
	for i, s in run do
		part(folder, "RailPost", Vector3.new(0.7, 3.2, 0.7), CFrame.new(s.post + Vector3.new(0, 1.6, 0)), dark, Enum.Material.Wood)
		if s.water then
			-- A trestle leg down to the bed under the water.
			local depth = math.max(2, s.post.Y - s.bed)
			part(folder, "Trestle", Vector3.new(1, depth, 1), CFrame.new(s.post + Vector3.new(0, -depth / 2, 0)), dark, Enum.Material.Wood)
		end
		local nextOne = run[i + 1]
		if nextOne then
			local mid = (s.post + nextOne.post) / 2 + Vector3.new(0, 2.6, 0)
			local length = (nextOne.post - s.post).Magnitude
			part(folder, "Rail", Vector3.new(0.4, 0.5, length + 0.6), CFrame.lookAt(mid, nextOne.post + Vector3.new(0, 2.6, 0)), wood, Enum.Material.Wood)
		end
	end
end

-- A name board on a post at the rail line, its face along the road (so it never reaches into the lane), readable
-- from both sides as a truck rolls past.
local function nameBoard(folder, at, along, text)
	local across = Vector3.new(-along.Z, 0, along.X)
	local cf = CFrame.lookAt(at + Vector3.new(0, 4.4, 0), at + Vector3.new(0, 4.4, 0) + across)
	local board = part(folder, "BridgeBoard", Vector3.new(7, 1.6, 0.3), cf, Rustic.PaintCream, Enum.Material.WoodPlanks)
	part(folder, "BridgeBoardPost", Vector3.new(0.5, 4, 0.5), CFrame.new(at + Vector3.new(0, 2, 0)), Rustic.WoodDark, Enum.Material.Wood)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(280, 64)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Merriweather
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(40, 32, 26)
		label.Text = text
		label.Parent = gui
		gui.Parent = board
	end
end

function RoadPolish.build(parent)
	local folder = Instance.new("Folder")
	folder.Name = "RoadPolish"
	folder.Parent = parent
	local posts = 0
	for _, road in Map.Roads do
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			for _, side in { -1, 1 } do
				for _, run in runsAlong(a, b, side) do
					if #run >= MIN_RUN then
						rail(folder, run)
						posts += #run
						local wet = 0
						for _, s in run do
							wet += s.water and 1 or 0
						end
						if wet >= MIN_RUN then
							local first, last = run[1].post, run[#run].post
							table.insert(RoadPolish.bridges, { road = road.name, from = first, to = last, side = side })
							-- Name boards once per bridge, on the left-hand rail only.
							if side == 1 then
								local name = road.name:gsub(" Road", ""):gsub(" Lane", ""):gsub(" Cut", "")
								local along = (last - first).Unit
								nameBoard(folder, first - along * 5, along, name:upper() .. " BRIDGE")
								nameBoard(folder, last + along * 5, along, name:upper() .. " BRIDGE")
							end
						end
					end
				end
			end
		end
	end
	print(("[Needlewood] road polish: %d rail posts, %d bridge sides"):format(posts, #RoadPolish.bridges))
end

return RoadPolish
