--!nonstrict
-- The rest of the Stitched Isles around Meadow Farm: opens Meadow's two road exits, writes the islands' terrain in the
-- background, and builds everything on them (Regions), the Longstitch Highway, the ferries and the zeppelin. Also
-- runs the rich field: every few minutes one hay field somewhere on the map gets a gold beam and 2x needles.
-- Config: src/shared/Config/WorldMap.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local Announce = require(script.Parent.Announce)
local WorldTerrain = require(script.Parent.WorldTerrain)
local Regions = require(script.Parent.Regions)
local Highway = require(script.Parent.Highway)
local Ferry = require(script.Parent.Ferry)
local WorldShape = require(script.Parent.WorldShape)
local WorldClock = require(script.Parent.WorldClock)
local Weather = require(script.Parent.Weather)
local RegionEvents = require(script.Parent.RegionEvents)
local Wilds = require(script.Parent.Wilds)
local RoadPolish = require(script.Parent.RoadPolish)
local HayWagon = require(script.Parent.HayWagon)
local Discoveries = require(script.Parent.Discoveries)
local SpindleDoor = require(script.Parent.SpindleDoor)

local WorldMap = {}

local RICH_BOOST = 2

-- Meadow was built as a closed valley (gates and invisible walls at its edge). Its roads now lead somewhere.
local function openMeadow(worldFolder)
	local meadow = worldFolder:FindFirstChild("Meadow")
	if not meadow then
		return
	end
	for _, child in meadow:GetChildren() do
		if child.Name == "ClosedGate" or child.Name == "EdgeWall" then
			child:Destroy()
		elseif child.Name == "Signpost" then
			for _, label in child:GetDescendants() do
				if label:IsA("TextLabel") then
					if string.find(label.Text, "COMING SOON") then
						child:Destroy()
						break
					end
					label.Text = string.gsub(label.Text, " %(soon%)", "")
				end
			end
		end
	end
end

-- Invisible walls at the edge of the world, out at sea, so nobody drives or swims off the map.
local function worldWalls(folder)
	local min, max = Map.Bounds.min, Map.Bounds.max
	local mid = (min + max) / 2
	local size = max - min
	for _, def in {
		{ Vector3.new(min.X, 0, mid.Y), Vector3.new(2, 1200, size.Y) },
		{ Vector3.new(max.X, 0, mid.Y), Vector3.new(2, 1200, size.Y) },
		{ Vector3.new(mid.X, 0, min.Y), Vector3.new(size.X, 1200, 2) },
		{ Vector3.new(mid.X, 0, max.Y), Vector3.new(size.X, 1200, 2) },
	} do
		local wall = Instance.new("Part")
		wall.Name = "WorldEdge"
		wall.Size = def[2]
		wall.Position = def[1] + Vector3.new(0, 500, 0)
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CanTouch = false
		wall.Parent = folder
	end
end

-- In Studio: lists anything solid standing in a road lane (a truck would hit it), so a blocked road shows up in the
-- Output the first time the map is built rather than when someone drives into it.
local function auditRoads(folder)
	local half = Map.RoadWidth / 2 - 1
	local blocked = {}
	for _, p in folder:GetDescendants() do
		if not (p:IsA("BasePart") and p.Anchored and p.CanCollide and p.Transparency < 1) then
			continue
		end
		local cf, size = p.ExtentsCFrame, p.ExtentsSize
		local bottom, top = cf.Y - size.Y / 2, cf.Y + size.Y / 2
		for _, o in { Vector3.zero, Vector3.new(size.X / 2, 0, size.Z / 2), Vector3.new(-size.X / 2, 0, size.Z / 2), Vector3.new(size.X / 2, 0, -size.Z / 2), Vector3.new(-size.X / 2, 0, -size.Z / 2) } do
			local at = cf * (o * 0.9)
			local d, h = WorldShape.nearestRoad(at.X, at.Z)
			if d and d < half and top > h + 0.6 and bottom < h + 9 then
				table.insert(blocked, ("%s at (%d, %d) on the %s"):format(p:GetFullName(), at.X, at.Z, select(3, WorldShape.nearestRoad(at.X, at.Z)) or "road"))
				break
			end
		end
	end
	if #blocked > 0 then
		warn(("[Needlewood] %d parts stand in a road lane:\n  %s"):format(#blocked, table.concat(blocked, "\n  ", 1, math.min(#blocked, 25))))
	else
		print("[Needlewood] Road check: every road lane is clear")
	end
end

-- Rich field ------------------------------------------------------------------------------------------------------

local rich = nil -- the field entry that is rich right now
local beacon = nil

local function setBoost(entry, boost)
	for b in entry.bales do
		if b.body and b.body.Parent then
			b.body:SetAttribute("NeedleBoost", boost)
		end
	end
end

local function makeBeacon(entry, parent)
	local model = Instance.new("Model")
	model.Name = "RichFieldBeacon"
	-- Always sent to every client, even with StreamingEnabled, so the beam shows from across the map.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(300, 3, 3)
	beam.CFrame = CFrame.new(entry.center + Vector3.new(0, 150, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	beam.Color = Color3.fromRGB(242, 196, 70)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.45
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Parent = model
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 30 - 150, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 6000
	gui.LightInfluence = 0
	gui.Parent = beam
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(250, 214, 110)
	label.TextStrokeTransparency = 0.3
	label.Text = "RICH FIELD\n2x needles"
	label.Parent = gui
	model.Parent = parent
	return model
end

local function pickRich(parent)
	local fields = Regions.fields
	if #fields == 0 then
		return
	end
	if rich then
		setBoost(rich, nil)
		rich.rich = false
	end
	if beacon then
		beacon:Destroy()
		beacon = nil
	end
	local choice
	repeat
		choice = fields[math.random(1, #fields)]
	until choice ~= rich or #fields == 1
	rich = choice
	rich.rich = true
	setBoost(rich, RICH_BOOST)
	beacon = makeBeacon(rich, parent)
	-- For map screens: where the rich field is now (a UI can mark it).
	ReplicatedStorage:SetAttribute("RichField", rich.center)
	ReplicatedStorage:SetAttribute("RichFieldRegion", rich.region)
	Announce.say(("Rich field in %s: 2x needles for %d minutes. Follow the gold beam!"):format(rich.region, Map.RichMinutes), "event")
end

function WorldMap.build(worldFolder)
	local folder = Instance.new("Folder")
	folder.Name = "StitchedIsles"
	folder.Parent = worldFolder

	openMeadow(worldFolder)
	worldWalls(folder)
	-- Day and night (the clock, the lamps; the sky colors are client side).
	WorldClock.start()
	Weather.start()

	-- The terrain takes a while, nearest Meadow first; everything on top only needs the shape, so it goes up now.
	task.spawn(function()
		local ok, err = pcall(WorldTerrain.ensure)
		if not ok then
			warn("[Needlewood] Stitched Isles terrain failed: " .. tostring(err))
		end
	end)
	for _, step in {
		{ "regions", Regions.build },
		{ "highway", Highway.build },
		{ "ferries", Ferry.build },
		{ "wilds", Wilds.build },
		{ "road polish", RoadPolish.build },
		{ "hay wagon", HayWagon.build },
	} do
		local ok, err = pcall(step[2], folder)
		if not ok then
			warn(("[Needlewood] Stitched Isles %s failed: %s"):format(step[1], tostring(err)))
		end
	end

	if RunService:IsStudio() then
		local isles = folder:FindFirstChild("Isles")
		if isles then
			task.spawn(auditRoads, isles)
		end
	end

	-- Moves the rich field on now (the rotation below does this every few minutes; self-tests call it directly).
	function WorldMap.rotateRich()
		pickRich(folder)
	end

	task.spawn(function()
		while folder.Parent do
			pickRich(folder)
			task.wait(Map.RichMinutes * 60)
		end
	end)
	RegionEvents.start()
	Discoveries.start()
	SpindleDoor.start()
end

return WorldMap
