--!nonstrict
-- Everything standing on the Stitched Isles outside Meadow: each region's trees in its own LT2 style, rocks, hay
-- fields with that region's hay, signposts, and the landmarks from the world map (the Homestead hub, the Spindle
-- door and cave, the lighthouse, the pyramid, the wreck, the quarry, the Weaver's workshop and more).
-- Placement uses a fixed seed, so every server looks alike. Ground heights come from WorldShape, the same math the
-- terrain was written from, so nothing waits for the terrain to finish.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local GloveConfig = require(Shared.Config.Gloves)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local WorldShape = require(script.Parent.WorldShape)
local Bales = require(script.Parent.Bales)
local Props = require(script.Parent.Props)
local Data = require(script.Parent.Data)

local Regions = {}

local IRON = Color3.new(0.48, 0.48, 0.47) -- weathered grey iron (BUILD_REGISTRY.md), never rusty orange
local SNOW = Color3.fromRGB(226, 228, 226)
local BARN_RED = Color3.fromRGB(133, 61, 48) -- the Meadow accent, for anything outside a region

-- The region's accent (Config/WorldMap style, from STYLE.md Regions) at a point: one sign or trim per building.
local function accentAt(x, z)
	local region = WorldShape.regionAt(x, z)
	return region and region.style and region.style.accent or BARN_RED
end

-- Tree colors from the STYLE.md region sheet (mid shades). Regions not on the sheet keep the house palette.
local PALETTE = {
	pine = { leaves = Color3.fromRGB(48, 76, 59), bark = Color3.fromRGB(66, 51, 38) },
	snow = { leaves = Color3.fromRGB(54, 76, 71), bark = Color3.fromRGB(71, 64, 56) },
	desert = { leaves = Color3.fromRGB(107, 128, 89), bark = Color3.fromRGB(122, 110, 94) },
	swamp = { leaves = Color3.fromRGB(74, 92, 54), bark = Color3.fromRGB(59, 54, 46) },
}
local palette: { leaves: Color3?, bark: Color3? } = {} -- the region being planted right now (set in Regions.build)
local SEA = Map.SeaLevel

-- Every hay field in the world, for the rich field rotation: { region, center, bales = { bale record } }
Regions.fields = {}

-- Parts ---------------------------------------------------------------------------------------------------------

local function part(parent, name, size, cframe, color, material, shape, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	if collide == false then
		p.CanCollide = false
	end
	p.Parent = parent
	return p
end

local function wedge(parent, name, size, cframe, color, material)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- A cylinder standing upright (Roblox cylinders lie along X).
local function post(parent, name, height, thick, base, color, material, collide)
	return part(parent, name, Vector3.new(height, thick, thick), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder, collide)
end

local function light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1
	l.Shadows = false
	l.Parent = p
	return l
end

local function ground(x, z)
	return WorldShape.heightAt(x, z)
end

local function at(x, z, yOffset)
	return Vector3.new(x, ground(x, z) + (yOffset or 0), z)
end

-- A spot on the ground facing a direction (Vector2).
local function spot(x, z, facing, y)
	local p = Vector3.new(x, y or ground(x, z), z)
	facing = facing or Vector2.new(0, -1)
	return CFrame.lookAt(p, p + Vector3.new(facing.X, 0, facing.Y))
end

-- A label floating over a part, seen from a distance.
local function billboard(parent, text, offset, distance)
	return WorldLabel.billboard(parent, text, {
		offset = offset or Vector3.new(0, 6, 0),
		kind = "sign",
		distance = distance or 140,
		color = Color3.fromRGB(240, 232, 210),
		-- Landmarks read from far away get bigger letters.
		studs = (distance or 140) > 300 and 10 or nil,
	})
end
Regions.billboard = billboard

local function boardText(board, text, faces)
	return WorldLabel.surface(board, text, faces or { Enum.NormalId.Front, Enum.NormalId.Back })
end

-- Moves a point off any road, out to clearance studs past its edge (signs placed by hand must never stand in a lane).
local ROAD_HALF = Map.RoadWidth / 2
local function offRoad(x, z, clearance)
	for _ = 1, 12 do
		local d = WorldShape.nearestRoad(x, z)
		if not d or d >= ROAD_HALF + clearance then
			break
		end
		-- Step away from the center line: the direction in which the distance grows.
		local function far(px, pz)
			return WorldShape.nearestRoad(px, pz) or ROAD_HALF + clearance + 50
		end
		local g = Vector2.new(far(x + 1, z) - far(x - 1, z), far(x, z + 1) - far(x, z - 1))
		if g.Magnitude < 1e-3 then
			g = Vector2.new(1, 0)
		end
		g = g.Unit * (ROAD_HALF + clearance - d + 0.5)
		x += g.X
		z += g.Y
	end
	return x, z
end
Regions.offRoad = offRoad

-- A wooden board on a post, readable from both sides. Never on a road: it steps to the roadside.
local function signpost(parent, x, z, facing, text, width)
	width = width or 11
	-- The board can stand across the road's direction, so keep half its width clear as well.
	x, z = offRoad(x, z, width / 2 + 2)
	local model = Instance.new("Model")
	model.Name = "Signpost"
	local base = spot(x, z, facing)
	part(model, "Post", Vector3.new(0.6, 7, 0.6), base * CFrame.new(0, 3, 0.4), Rustic.WoodDark, Enum.Material.Wood)
	local board = part(model, "Board", Vector3.new(width, 3.6, 0.4), base * CFrame.new(0, 6.2, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	part(model, "Trim", Vector3.new(width + 0.4, 0.4, 0.6), base * CFrame.new(0, 8.2, 0), accentAt(x, z), Enum.Material.WoodPlanks)
	boardText(board, text)
	model.Parent = parent
	return model
end
Regions.signpost = signpost

-- A simple plank building: four walls with a door gap in front, a gable roof. Used as the collision shell and as the
-- look until a Blender building of that name is imported (then the mesh rides on it, PropMeshes.client.luau).
-- Blender batch 2 props (hub, regions, scatter) that face -Z already; every other building prop faces +Z.
local FORWARD_PROPS = {
	trading_post = true,
	homestead_bank = true,
	pine_lodge = true,
	snow_cabin = true,
	haunted_barn = true,
	volcano_forge = true,
	swamp_stilt_house = true,
	bobbin_captain_shack = true,
	land_office = true,
}

local function building(parent, name, cframe, w, d, h, opts)
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = name
	local wall = opts.wall or Rustic.Wood
	local roofColor = opts.roof or Rustic.PaintRedDark
	local material = opts.material or Enum.Material.WoodPlanks
	local t = 0.8
	local door = math.min(opts.door or 8, w - 4)
	local floor = part(model, "Floor", Vector3.new(w, 1, d), cframe * CFrame.new(0, 0.5, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	part(model, "Back", Vector3.new(w, h, t), cframe * CFrame.new(0, h / 2 + 1, d / 2 - t / 2), wall, material)
	for _, side in { -1, 1 } do
		part(model, "Side", Vector3.new(t, h, d), cframe * CFrame.new(side * (w / 2 - t / 2), h / 2 + 1, 0), wall, material)
		local front = (w - door) / 2
		part(model, "Front", Vector3.new(front, h, t), cframe * CFrame.new(side * (w / 2 - front / 2), h / 2 + 1, -d / 2 + t / 2), wall, material)
	end
	-- The lintel over the door is the one trim in the region's accent color.
	part(model, "Lintel", Vector3.new(door, h * 0.3, t), cframe * CFrame.new(0, h * 0.85 + 1, -d / 2 + t / 2), accentAt(cframe.X, cframe.Z), material)
	-- Gable roof: two slabs meeting over the middle.
	local rise = math.min(w, d) * 0.3
	local slant = math.sqrt((w / 2) ^ 2 + rise ^ 2) + 0.6
	local angle = math.atan2(rise, w / 2)
	for _, side in { -1, 1 } do
		part(
			model,
			"Roof",
			Vector3.new(slant, 0.8, d + 1.6),
			cframe * CFrame.new(side * w / 4, h + 1 + rise / 2, 0) * CFrame.Angles(0, 0, -side * angle),
			roofColor,
			Enum.Material.WoodPlanks
		)
	end
	for _, side in { -1, 1 } do
		wedge(model, "Gable", Vector3.new(0.6, rise, w / 2), cframe * CFrame.new(side * w / 4, h + 1 + rise / 2, d / 2 - t / 2) * CFrame.Angles(0, side * math.pi / 2, 0), wall, material)
	end
	if opts.sign then
		local board = part(model, "Sign", Vector3.new(math.min(w - 2, 16), 2.4, 0.3), cframe * CFrame.new(0, h + 0.2, -d / 2 - 0.2), Rustic.PaintCream, Enum.Material.WoodPlanks)
		boardText(board, opts.sign, { Enum.NormalId.Front })
	end
	-- Night lights (#26): a lantern beside the door and a warm glow inside that spills out of the doorway. Their
	-- names hold "Lantern" / "Lamp", so WorldClock switches them on at dusk and off at dawn.
	if opts.lit ~= false then
		local lantern = part(model, "DoorLantern", Vector3.new(0.8, 1.2, 0.8), cframe * CFrame.new(door / 2 + 1.2, math.min(h * 0.6, 7) + 1, -d / 2 - 1), Color3.fromRGB(255, 196, 110), Enum.Material.Neon, nil, false)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 120)
		light.Range = 16
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = lantern
		local inside = part(model, "LampGlow", Vector3.new(1, 1, 1), cframe * CFrame.new(0, h * 0.6 + 1, 0), Color3.fromRGB(255, 196, 110), Enum.Material.Neon, nil, false)
		inside.Transparency = 1
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 180, 110)
		glow.Range = math.min(24, math.max(w, d))
		glow.Brightness = 1.5
		glow.Shadows = false
		glow.Parent = inside
	end
	model.PrimaryPart = floor
	-- With StreamingEnabled: a building streams in whole (never a roof without walls), and from far away it still
	-- shows as a low-detail mesh, so the skyline never pops.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	-- The Blender building of this kind, when imported, takes over the look. Its front faces cframe's LookVector.
	-- The older buildings (mill, warehouse, museum...) were exported front at +Z, hence their half turn, stretched to
	-- the box. The hub and region props (Blender batch 2) already face -Z: no turn, scaled evenly to the footprint
	-- and stood on the floor.
	if opts.prop and Props.has(opts.prop) then
		local mesh
		if FORWARD_PROPS[opts.prop] then
			mesh = Props.make(opts.prop, cframe * CFrame.new(0, h / 2 + 1, 0), math.max(w, d) + 1)
			if mesh then
				local box, size = mesh:GetBoundingBox()
				mesh:PivotTo(mesh:GetPivot() + Vector3.new(0, (cframe.Y + 1) - (box.Y - size.Y / 2), 0))
			end
		else
			mesh = Props.make(opts.prop, cframe * CFrame.new(0, (h + rise) / 2 + 1, 0), Vector3.new(w + 1, h + rise + 1, d + 1), CFrame.Angles(0, math.pi, 0))
		end
		if mesh then
			Props.weldTo(mesh, floor, model)
		end
	end
	model.Parent = parent
	return model
end
Regions.building = building

-- A townsperson: a blocky figure in work clothes with a name over their head and a Talk prompt. Tagged "QuestGiver"
-- with a QuestGiver id, so the quest system can take the prompt over (set QuestHandled on the model and it stops
-- saying its own lines). Until then each one says its lines in turn.
local function townsperson(parent, id, name, cframe, shirt, lines)
	local model = Instance.new("Model")
	model.Name = name
	local skin = Color3.fromRGB(204, 162, 128)
	for _, side in { -1, 1 } do
		part(model, "Leg", Vector3.new(0.9, 2.6, 1), cframe * CFrame.new(side * 0.5, 1.3, 0), Rustic.WoodDark, Enum.Material.Fabric)
		part(model, "Arm", Vector3.new(0.8, 2.4, 0.9), cframe * CFrame.new(side * 1.45, 3.6, 0), shirt, Enum.Material.Fabric)
	end
	local torso = part(model, "Torso", Vector3.new(2, 2.4, 1.1), cframe * CFrame.new(0, 3.8, 0), shirt, Enum.Material.Fabric)
	local head = part(model, "Head", Vector3.new(1.2, 1.2, 1.2), cframe * CFrame.new(0, 5.6, 0), skin, Enum.Material.SmoothPlastic)
	part(model, "HatBrim", Vector3.new(2.2, 0.15, 2.2), cframe * CFrame.new(0, 6.25, 0), Rustic.Cloth, Enum.Material.Fabric)
	part(model, "HatTop", Vector3.new(1.3, 0.6, 1.3), cframe * CFrame.new(0, 6.6, 0), Rustic.Cloth, Enum.Material.Fabric)
	model.PrimaryPart = torso
	for _, p in model:GetChildren() do
		p.CanCollide = false
	end
	billboard(head, name, Vector3.new(0, 2.2, 0), 60)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = name
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = torso
	model:SetAttribute("QuestGiver", id)
	model:SetAttribute("Lines", table.concat(lines, "\n")) -- Quests says them once it takes the prompt over
	CollectionService:AddTag(model, "QuestGiver")
	local turn = setmetatable({}, { __mode = "k" }) -- players who left drop out on their own
	prompt.Triggered:Connect(function(player)
		if model:GetAttribute("QuestHandled") then
			return
		end
		local i = (turn[player] or 0) % #lines + 1
		turn[player] = i
		if Data.get(player) then
			Data.toast(player, ("%s: %s"):format(name, lines[i]))
		end
	end)
	model.Parent = parent
	return model
end
Regions.townsperson = townsperson

-- Trees in each region's style ---------------------------------------------------------------------------------

local TREES = {}

function TREES.oak(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local height = rng:NextNumber(10, 14) * s
	local thick = rng:NextNumber(1.4, 1.9) * s
	post(model, "Trunk", height, thick, base, Rustic.Bark, Enum.Material.Wood)
	local colors = { Rustic.Leaves, Rustic.LeavesDark, Rustic.LeavesDry }
	for i = 1, 3 do
		local size = Vector3.new(rng:NextNumber(6, 9), rng:NextNumber(4, 6), rng:NextNumber(6, 9)) * s
		local offset = Vector3.new(rng:NextNumber(-2.5, 2.5) * s, height + rng:NextNumber(-1.5, 2.5), rng:NextNumber(-2.5, 2.5) * s)
		part(model, "Leaves", size, base * CFrame.new(offset) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), colors[rng:NextInteger(1, 3)], Enum.Material.Grass, nil, false)
	end
	model.Parent = parent
end

local function pineTiers(model, base, height, s, rng, color, snowy)
	local tiers = 3
	for i = 1, tiers do
		local k = 1 - (i - 1) / tiers
		local size = Vector3.new(9 * k + 2, 4.2, 9 * k + 2) * Vector3.new(s, s, s)
		local y = height * (0.42 + (i - 1) * 0.22)
		local cf = base * CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(45 * i) + rng:NextNumber(-0.2, 0.2), 0)
		part(model, "Needles", size, cf, color, Enum.Material.Grass, nil, false)
		if snowy then
			part(model, "Snow", Vector3.new(size.X * 0.85, 0.8, size.Z * 0.85), cf * CFrame.new(0, size.Y / 2 + 0.3, 0), SNOW, Enum.Material.Snow, nil, false)
		end
	end
end

function TREES.pine(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "PineTree"
	local height = rng:NextNumber(18, 26) * s
	post(model, "Trunk", height, rng:NextNumber(1.3, 1.8) * s, base, palette.bark or Rustic.Bark, Enum.Material.Wood)
	local dark = rng:NextNumber() < 0.5
	pineTiers(model, base, height, s, rng, palette.leaves and (dark and palette.leaves:Lerp(Color3.new(), 0.15) or palette.leaves) or (dark and Rustic.LeavesDark or Color3.fromRGB(62, 80, 54)), false)
	model.Parent = parent
end

function TREES.snowpine(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "SnowPine"
	local height = rng:NextNumber(16, 22) * s
	post(model, "Trunk", height, rng:NextNumber(1.2, 1.6) * s, base, palette.bark or Rustic.Bark, Enum.Material.Wood)
	pineTiers(model, base, height, s, rng, palette.leaves or Color3.fromRGB(64, 82, 66), true)
	model.Parent = parent
end

function TREES.dead(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "DeadTree"
	local bark = palette.bark or Color3.fromRGB(58, 50, 52)
	local height = rng:NextNumber(12, 18) * s
	local thick = rng:NextNumber(1.2, 1.7) * s
	local lean = CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12))
	post(model, "Trunk", height, thick, base * lean, bark, Enum.Material.Wood)
	for i = 1, 3 do
		local length = height * rng:NextNumber(0.25, 0.4)
		local cf = base
			* lean
			* CFrame.new(0, height * (0.45 + i * 0.13), 0)
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(35, 65)))
			* CFrame.new(0, length / 2, 0)
		part(model, "Branch", Vector3.new(length, thick * 0.45, thick * 0.45), cf * CFrame.Angles(0, 0, math.pi / 2), bark, Enum.Material.Wood, Enum.PartType.Cylinder, false)
	end
	model.Parent = parent
end

function TREES.charred(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "CharredTree"
	local height = rng:NextNumber(6, 11) * s
	local thick = rng:NextNumber(1.1, 1.6) * s
	post(model, "Trunk", height, thick, base * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), Color3.fromRGB(38, 34, 32), Enum.Material.Slate)
	local length = height * 0.4
	local cf = base * CFrame.new(0, height * 0.7, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(50)) * CFrame.new(0, length / 2, 0)
	part(model, "Branch", Vector3.new(length, thick * 0.4, thick * 0.4), cf * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(38, 34, 32), Enum.Material.Slate, Enum.PartType.Cylinder, false)
	model.Parent = parent
end

function TREES.palm(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "PalmTree"
	local height = rng:NextNumber(14, 20) * s
	local bend = rng:NextNumber(0.1, 0.25)
	local turn = base * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local half = height / 2
	local lower = turn * CFrame.Angles(bend * 0.5, 0, 0)
	post(model, "Trunk", half + 0.4, 1.3 * s, lower, Rustic.Wood, Enum.Material.Wood)
	local upper = lower * CFrame.new(0, half, 0) * CFrame.Angles(bend, 0, 0)
	post(model, "Trunk", half, 1.1 * s, upper, Rustic.Wood, Enum.Material.Wood)
	local crown = upper * CFrame.new(0, half, 0)
	for i = 1, 5 do
		local leaf = crown * CFrame.Angles(0, i * math.pi * 2 / 5, 0) * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(0, 0, -3.5 * s)
		part(model, "Frond", Vector3.new(2.2 * s, 0.3, 7 * s), leaf, Color3.fromRGB(96, 120, 70), Enum.Material.Grass, nil, false)
	end
	model.Parent = parent
end

function TREES.cactus(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "Cactus"
	local green = Color3.fromRGB(92, 116, 74)
	local height = rng:NextNumber(5, 9) * s
	post(model, "Stem", height, 1.6 * s, base, green, Enum.Material.Grass)
	for _, side in { -1, 1 } do
		if rng:NextNumber() < 0.75 then
			local y = height * rng:NextNumber(0.35, 0.6)
			part(model, "Arm", Vector3.new(1.8 * s, 1, 1) * Vector3.new(1, s, s), base * CFrame.new(side * 1.3 * s, y, 0), green, Enum.Material.Grass, nil, false)
			post(model, "ArmUp", height * 0.35, 1.0 * s, base * CFrame.new(side * 2 * s, y, 0), green, Enum.Material.Grass, false)
		end
	end
	model.Parent = parent
end

function TREES.willow(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "Willow"
	local height = rng:NextNumber(10, 14) * s
	post(model, "Trunk", height, 1.8 * s, base * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1)), Color3.fromRGB(70, 62, 50), Enum.Material.Wood)
	local canopy = base * CFrame.new(0, height, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	part(model, "Canopy", Vector3.new(12, 3, 12) * Vector3.new(s, 1, s), canopy, palette.leaves or Rustic.LeavesDark, Enum.Material.Grass, nil, false)
	for _, side in { -1, 1 } do
		part(model, "Drape", Vector3.new(11 * s, height * 0.55, 1.2), canopy * CFrame.new(0, -height * 0.27, side * 5.2 * s), Color3.fromRGB(84, 98, 60), Enum.Material.Grass, nil, false)
	end
	model.Parent = parent
end

function TREES.reeds(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "Reeds"
	for _ = 1, 3 do
		local cf = base * CFrame.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2)) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15))
		post(model, "Reed", rng:NextNumber(4, 6) * s, 0.35, cf, Color3.fromRGB(110, 120, 70), Enum.Material.Grass, false)
	end
	model.Parent = parent
end

function TREES.crystal(parent, base, s, rng)
	local colors = { Color3.fromRGB(176, 150, 220), Color3.fromRGB(140, 196, 214), Color3.fromRGB(214, 160, 190) }
	local color = colors[rng:NextInteger(1, 3)]
	local height = rng:NextNumber(4, 9) * s
	local p = part(parent, "Crystal", Vector3.new(1.6 * s, height, 1.6 * s), base * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)) * CFrame.new(0, height / 2, 0), color, Enum.Material.Neon)
	p.Transparency = 0.15
	if rng:NextNumber() < 0.4 then
		light(p, color, 18, 0.8)
	end
end

-- How many of each kind of tree grow in each region.
local PLANTING = {
	shore = { { "oak", 45 } },
	valley = { { "oak", 75 }, { "pine", 14 } },
	homestead = { { "oak", 40 } },
	spindle = { { "pine", 30 } },
	pine = { { "pine", 190 }, { "oak", 10 } },
	haunted = { { "dead", 110 } },
	snow = { { "snowpine", 110 } },
	volcano = { { "charred", 55 } },
	desert = { { "cactus", 70 } },
	swamp = { { "willow", 60 }, { "reeds", 45 } },
	keys = { { "palm", 70 } },
	bobbin = { { "dead", 14 } },
}

local ROCK_COLORS = {
	default = { Rustic.Stone, Rustic.StoneDark, Rustic.Rock },
	snow = { Color3.fromRGB(150, 150, 156), Color3.fromRGB(120, 120, 128) },
	volcano = { Color3.fromRGB(64, 58, 56), Color3.fromRGB(44, 40, 40) },
	desert = { Color3.fromRGB(186, 156, 112), Color3.fromRGB(160, 132, 96) },
	haunted = { Color3.fromRGB(80, 76, 84), Color3.fromRGB(60, 58, 64) },
}

-- Placement -----------------------------------------------------------------------------------------------------

local taken = {} -- grid cell -> list of Vector2 already used

local function crowded(x, z, gap)
	local cx, cz = math.floor(x / 32), math.floor(z / 32)
	for i = cx - 1, cx + 1 do
		for k = cz - 1, cz + 1 do
			for _, p in taken[i * 65536 + k] or {} do
				if (p.X - x) ^ 2 + (p.Y - z) ^ 2 < gap * gap then
					return true
				end
			end
		end
	end
	return false
end

local function claim(x, z)
	local key = math.floor(x / 32) * 65536 + math.floor(z / 32)
	taken[key] = taken[key] or {}
	table.insert(taken[key], Vector2.new(x, z))
end

-- Marks the ground under everything in a folder as taken, so no tree grows through a landmark.
local function claimParts(folder)
	for _, p in folder:GetDescendants() do
		if p:IsA("BasePart") then
			local cf, size = p.ExtentsCFrame, p.ExtentsSize
			local nx, nz = math.min(12, math.ceil(size.X / 8)), math.min(12, math.ceil(size.Z / 8))
			for i = 0, nx do
				for k = 0, nz do
					local at = cf * Vector3.new((i / nx - 0.5) * size.X, 0, (k / nz - 0.5) * size.Z)
					claim(at.X, at.Z)
				end
			end
		end
	end
end

-- Whether something can stand here: on dry, not too steep land, off roads, the highway and building spots.
local function buildable(x, z, margin)
	if WorldShape.inMeadow(x, z) then
		return false
	end
	local h, water, material = WorldShape.column(x, z)
	if water or h < SEA + 1.5 or material == "CrackedLava" then
		return false
	end
	local d = WorldShape.nearestRoad(x, z)
	if d and d < Map.RoadWidth / 2 + margin then
		return false
	end
	if WorldShape.highwayDistance(x, z) < Map.Highway.width / 2 + margin then
		return false
	end
	for _, zone in Map.Flat do
		if WorldShape.rectDistance(x, z, zone.min, zone.max) < margin then
			return false
		end
	end
	local sx = WorldShape.heightAt(x + 4, z) - WorldShape.heightAt(x - 4, z)
	local sz = WorldShape.heightAt(x, z + 4) - WorldShape.heightAt(x, z - 4)
	if math.sqrt(sx * sx + sz * sz) / 8 > 0.7 then
		return false
	end
	return true, h
end

-- A random spot inside a region's oval (well clear of its coast).
local function randomIn(r, rng)
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = math.sqrt(rng:NextNumber()) * 0.92
	return r.cx + math.cos(angle) * r.rx * radius, r.cz + math.sin(angle) * r.rz * radius
end

local function plant(folder, r, kind, count, rng)
	local placed, tries = 0, 0
	while placed < count and tries < count * 30 do
		tries += 1
		local x, z = randomIn(r, rng)
		if WorldShape.regionAt(x, z) ~= r or crowded(x, z, kind == "reeds" and 5 or 10) then
			continue
		end
		local ok, h = buildable(x, z, 6)
		if not ok then
			continue
		end
		-- Trees thin out high on the snow peak and the volcano.
		if (kind == "snowpine" and h > 190) or (kind == "charred" and h > 120) then
			continue
		end
		TREES[kind](folder, CFrame.new(x, h - 1, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng:NextNumber(0.85, 1.3), rng)
		claim(x, z)
		placed += 1
	end
	return placed
end

local function rocks(folder, r, count, rng)
	local colors = ROCK_COLORS[r.id] or ROCK_COLORS.default
	for _ = 1, count do
		local x, z = randomIn(r, rng)
		if WorldShape.regionAt(x, z) == r and not crowded(x, z, 6) then
			local ok, h = buildable(x, z, 4)
			if ok then
				local size = Vector3.new(rng:NextNumber(2, 8), rng:NextNumber(1.5, 5), rng:NextNumber(2, 7))
				local cf = CFrame.new(x, h + size.Y * 0.2, z) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.3, 0.3))
				part(folder, "Rock", size, cf, colors[rng:NextInteger(1, #colors)], Enum.Material.Slate)
				claim(x, z)
			end
		end
	end
end

-- Hay ---------------------------------------------------------------------------------------------------------------

-- Bale colors by hay, so each region's hay reads at a glance (the mesh, when imported, keeps its own straw look).
local HAY_TINT = {
	pine = Color3.fromRGB(158, 156, 102), -- STYLE.md Regions hay (mid shade)
	desert = Color3.fromRGB(209, 186, 133),
	snow = Color3.fromRGB(191, 184, 148),
	swamp = Color3.fromRGB(133, 128, 79),
	volcano = Color3.fromRGB(120, 96, 80),
	cave = Color3.fromRGB(170, 160, 196),
	sky = Color3.fromRGB(226, 220, 196),
	haunted = Color3.fromRGB(132, 120, 140),
	keys = Color3.fromRGB(214, 196, 150),
	bobbin = Color3.fromRGB(150, 140, 120),
}

local function tint(b, hayType)
	local color = HAY_TINT[hayType]
	if color and b and b.body then
		b.body.Color = color
	end
end

-- A field of bales around a point. y is the ground height there.
local function field(regionName, hayType, center, y, count, rng)
	local entry = { region = regionName, hayType = hayType, center = center, bales = {}, rich = false }
	local function track(b)
		if not b then
			return
		end
		tint(b, hayType)
		entry.bales[b] = true
		-- The bale that grows back is the same hay, and stays in this field.
		b.onRegrow = function(fresh)
			entry.bales[b] = nil
			track(fresh)
			if entry.rich and fresh then
				fresh.body:SetAttribute("NeedleBoost", 2)
				fresh.body:SetAttribute("RichBoost", true)
			end
		end
	end
	local placed = {}
	for _ = 1, count * 4 do
		if #placed >= count then
			break
		end
		local p = center + Vector3.new(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9))
		local ok = true
		for _, other in placed do
			if (other - p).Magnitude < 5.5 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(placed, p)
			local gy = y or WorldShape.heightAt(p.X, p.Z)
			track(Bales.spawn(Vector3.new(p.X, gy - 0.35, p.Z), true, false, hayType))
		end
	end
	table.insert(Regions.fields, entry)
	return entry
end

-- Fields beside the roads of a region, so a truck can pull up to them.
local FIELD_REACH = 60 -- a field's center at most this far from its road, so a trailer backs right up to it
local FIELD_SLOPE = 0.4 -- rise per stud a pickup and trailer can pull up between the road and the field

-- Can a truck with a trailer drive straight from (ax, az) to (bx, bz)? Dry the whole way and never too steep.
local function drivable(ax, az, bx, bz)
	local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local steps = math.max(1, math.floor(length / 4))
	local step = length / steps
	local last = nil
	for s = 0, steps do
		local t = s / steps
		local h, water = WorldShape.column(ax + (bx - ax) * t, az + (bz - az) * t)
		if water and water > h + 1 then
			return false
		end
		if last and math.abs(h - last) / step > FIELD_SLOPE then
			return false
		end
		last = h
	end
	return true
end
Regions.drivable = drivable

local function hayFields(r, rng)
	if r.noFields then
		return -- bare rock (Stitch Ridge)
	end
	local made = 0
	for _ = 1, 400 do
		if made >= Map.FieldsPerRegion then
			break
		end
		local x, z = randomIn(r, rng)
		local d, _, _, rx, rz = WorldShape.nearestRoad(x, z)
		if WorldShape.regionAt(x, z) ~= r or not d or d < 24 or d > FIELD_REACH or crowded(x, z, 22) then
			continue
		end
		if not drivable(rx, rz, x, z) then
			continue
		end
		local ok, h = buildable(x, z, 18)
		if not ok then
			continue
		end
		-- The whole field must be fairly level.
		local level = true
		for _, o in { Vector2.new(10, 0), Vector2.new(-10, 0), Vector2.new(0, 10), Vector2.new(0, -10) } do
			if math.abs(WorldShape.heightAt(x + o.X, z + o.Y) - h) > 2.5 then
				level = false
				break
			end
		end
		if not level then
			continue
		end
		field(r.name, r.hayType, Vector3.new(x, h, z), nil, rng:NextInteger(Map.BalesPerField[1], Map.BalesPerField[2]), rng)
		for i = -1, 1 do
			for k = -1, 1 do
				claim(x + i * 10, z + k * 10)
			end
		end
		made += 1
	end
	if made == 0 and r.fieldFlat then
		for _, zone in Map.Flat do
			if zone.name == r.fieldFlat then
				local mid = (zone.min + zone.max) / 2
				field(r.name, r.hayType, Vector3.new(mid.X, zone.height, mid.Y), zone.height, rng:NextInteger(Map.BalesPerField[1], Map.BalesPerField[2]), rng)
			end
		end
	end
end

-- Farm life ------------------------------------------------------------------------------------------------------

-- The nearest open spot to (x, z): dry, gentle, off roads, and clear of anything already placed.
local function findSpot(x, z, margin)
	for radius = 0, 240, 12 do
		local steps = math.max(1, math.floor(radius / 6))
		for i = 0, steps - 1 do
			local a = i / steps * math.pi * 2
			local px, pz = x + math.cos(a) * radius, z + math.sin(a) * radius
			local ok, h = buildable(px, pz, margin)
			if ok and not crowded(px, pz, margin) then
				return px, pz, h
			end
		end
	end
	return nil
end

-- A windmill on a stone base. Its sails are their own model, tagged "WindmillSails"; Ambient.client.luau turns them.
local function windmill(folder, x, z)
	local px, pz, h = findSpot(x, z, 14)
	if not px then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Windmill"
	local base = CFrame.new(px, h - 1, pz) * CFrame.Angles(0, math.rad(30), 0)
	post(model, "Tower", 26, 10, base, Rustic.PaintCream, Enum.Material.WoodPlanks)
	post(model, "Footing", 3, 13, base * CFrame.new(0, -1, 0), Rustic.Stone, Enum.Material.Cobblestone)
	part(model, "Cap", Vector3.new(9, 5, 9), base * CFrame.new(0, 27.5, 0), Rustic.PaintRedDark, Enum.Material.WoodPlanks)
	part(model, "Door", Vector3.new(4, 7, 0.4), base * CFrame.new(0, 4.5, -5.1), Rustic.WoodDark, Enum.Material.WoodPlanks)
	local sails = Instance.new("Model")
	sails.Name = "WindmillSails"
	local hubCF = base * CFrame.new(0, 27, -5.2)
	local hub = part(sails, "Hub", Vector3.new(1.6, 2, 2), hubCF * CFrame.Angles(0, math.pi / 2, 0), IRON, Enum.Material.Metal, Enum.PartType.Cylinder, false)
	for i = 0, 3 do
		local arm = hubCF * CFrame.Angles(0, 0, i * math.pi / 2)
		part(sails, "Spar", Vector3.new(0.5, 18, 0.4), arm * CFrame.new(0, 9, -0.3), Rustic.WoodDark, Enum.Material.Wood, nil, false)
		part(sails, "Sail", Vector3.new(4, 14, 0.15), arm * CFrame.new(2.2, 10, -0.4), Rustic.Cloth, Enum.Material.Fabric, nil, false)
	end
	sails.PrimaryPart = hub
	-- Streams in whole, so the client never sees sails without their hub.
	sails.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	sails.Parent = model
	CollectionService:AddTag(sails, "WindmillSails")
	model.Parent = folder
	claim(px, pz)
	return model
end

-- A cow standing in a field, head down. Purely scenery: nothing collides, so it never blocks a truck.
local COW_COATS = { { Color3.fromRGB(236, 230, 218), Color3.fromRGB(46, 40, 36) }, { Color3.fromRGB(122, 78, 52), Color3.fromRGB(236, 230, 218) }, { Color3.fromRGB(70, 58, 48), Color3.fromRGB(70, 58, 48) } }
local function cow(folder, x, z, h, rng)
	local model = Instance.new("Model")
	model.Name = "Cow"
	local coat = COW_COATS[rng:NextInteger(1, #COW_COATS)]
	local base = CFrame.new(x, h, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local body = part(model, "Body", Vector3.new(3.2, 3, 6), base * CFrame.new(0, 3.6, 0), coat[1], Enum.Material.Fabric, nil, false)
	part(model, "Patch", Vector3.new(3.3, 1.8, 2.2), base * CFrame.new(0, 4, 0.8), coat[2], Enum.Material.Fabric, nil, false)
	part(model, "Head", Vector3.new(2, 2, 2.4), base * CFrame.new(0, 2.6, -3.8) * CFrame.Angles(math.rad(-35), 0, 0), coat[1], Enum.Material.Fabric, nil, false)
	part(model, "Muzzle", Vector3.new(1.6, 1, 0.6), base * CFrame.new(0, 1.7, -4.9) * CFrame.Angles(math.rad(-35), 0, 0), Color3.fromRGB(214, 170, 160), Enum.Material.SmoothPlastic, nil, false)
	for _, lx in { -1, 1 } do
		for _, lz in { -1, 1 } do
			part(model, "Leg", Vector3.new(0.8, 2.4, 0.8), base * CFrame.new(lx * 1.1, 1.2, lz * 2.2), coat[1], Enum.Material.Fabric, nil, false)
		end
	end
	model.PrimaryPart = body
	CollectionService:AddTag(model, "Cow")
	model.Parent = folder
end

local function herd(folder, r, count, rng)
	local made, tries = 0, 0
	while made < count and tries < count * 20 do
		tries += 1
		local cx, cz = randomIn(r, rng)
		local ok = WorldShape.regionAt(cx, cz) == r and buildable(cx, cz, 14) and not crowded(cx, cz, 14)
		if not ok then
			continue
		end
		-- A few cows together.
		for _ = 1, rng:NextInteger(2, 4) do
			local x, z = cx + rng:NextNumber(-12, 12), cz + rng:NextNumber(-12, 12)
			local fine, h = buildable(x, z, 4)
			if fine and not crowded(x, z, 4) then
				cow(folder, x, z, h, rng)
				claim(x, z)
				made += 1
			end
		end
	end
	return made
end

-- Landmarks -----------------------------------------------------------------------------------------------------

local LANDMARKS = {}

function LANDMARKS.homestead(folder)
	local y = 8
	-- The plaza: market stalls, the trading post, the museum, a sawmill row and the bounty board round a well.
	local stalls = Instance.new("Folder")
	stalls.Name = "NeedleMarket"
	stalls.Parent = folder
	local colors = { Rustic.PaintRed, Rustic.PaintGreen, Rustic.PaintBlue, Rustic.PaintYellow }
	for i = 0, 3 do
		local base = CFrame.new(-100, y, -4610 + i * 34) * CFrame.Angles(0, -math.pi / 2, 0)
		part(stalls, "Counter", Vector3.new(12, 3.5, 3), base * CFrame.new(0, 1.75, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
		for _, x in { -5.5, 5.5 } do
			post(stalls, "Pole", 9, 0.5, base * CFrame.new(x, 0, 2), Rustic.Wood, Enum.Material.Wood)
		end
		part(stalls, "Canopy", Vector3.new(13, 0.4, 7), base * CFrame.new(0, 9, 0.5) * CFrame.Angles(math.rad(10), 0, 0), colors[i + 1], Enum.Material.Fabric)
	end
	billboard(part(stalls, "MarketSign", Vector3.new(1, 1, 1), CFrame.new(-100, y + 12, -4560), Rustic.Wood, nil, nil, false), "NEEDLE MARKET", Vector3.zero, 220)

	building(folder, "TradingPost", CFrame.new(0, y, -4670) * CFrame.Angles(0, math.pi, 0), 40, 26, 14, { sign = "TRADING POST", prop = "trading_post" })
	building(folder, "Museum", CFrame.new(90, y, -4660) * CFrame.Angles(0, math.pi, 0), 34, 24, 16, { sign = "MUSEUM", prop = "museum", wall = Rustic.PaintCream, roof = Rustic.PaintBlue })
	for i, z in { -4485, -4570, -4610 } do
		building(folder, "Sawmill", CFrame.new(165, y, z) * CFrame.Angles(0, math.pi / 2, 0), 26, 20, 12, { sign = i == 1 and "SAWMILL ROW" or nil, prop = "mill" })
	end
	building(folder, "Workshop", CFrame.new(-150, y, -4680) * CFrame.Angles(0, math.pi * 0.75, 0), 24, 20, 11, { sign = "WORKSHOP", prop = "workshop" })

	-- The bounty board and the well in the middle.
	local board = part(folder, "BountyBoard", Vector3.new(14, 8, 0.6), CFrame.new(0, y + 6, -4560), Rustic.Wood, Enum.Material.WoodPlanks)
	boardText(board, "BOUNTY BOARD\nNew jobs every day")
	for _, x in { -6.5, 6.5 } do
		post(folder, "BoardPost", 10, 0.7, CFrame.new(x, y, -4560), Rustic.WoodDark, Enum.Material.Wood)
	end
	local well = CFrame.new(0, y, -4520)
	post(folder, "Well", 3, 8, well, Rustic.Stone, Enum.Material.Cobblestone)
	part(folder, "WellWater", Vector3.new(0.2, 6.4, 6.4), well * CFrame.new(0, 2.9, 0) * CFrame.Angles(0, 0, math.pi / 2), Rustic.Water, Enum.Material.Glass, Enum.PartType.Cylinder, false)
	for _, x in { -3.6, 3.6 } do
		post(folder, "WellPost", 8, 0.5, well * CFrame.new(x, 0, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	part(folder, "WellRoof", Vector3.new(9, 0.5, 5), well * CFrame.new(0, 8, 0), Rustic.PaintRedDark, Enum.Material.WoodPlanks)

	-- An arch where the Ridge Cut comes in.
	-- On the road's center line, facing along it (the road runs (-15, -4100) -> (0, -4460) here).
	local arch = spot(-6.67, -4300, Vector2.new(15, -360).Unit)
	for _, side in { -1, 1 } do
		post(folder, "ArchPost", 16, 1.6, arch * CFrame.new(side * 11, -1, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	local beam = part(folder, "ArchBeam", Vector3.new(26, 3, 1), arch * CFrame.new(0, 14, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	boardText(beam, "HOMESTEAD VALLEY")

	-- The Homestead branch of the bank (the Economy thread's counter can hook the BankCounter tag), facing the well.
	local bank = building(folder, "HomesteadBank", CFrame.new(95, y, -4570) * CFrame.Angles(0, math.pi / 2, 0), 30, 22, 13, { sign = "SAVINGS & LOAN", wall = Rustic.PaintCream, roof = Rustic.PaintGreen, material = Enum.Material.Brick, prop = "homestead_bank" })
	local counter = part(bank, "Counter", Vector3.new(10, 3.5, 2), CFrame.new(95, y, -4570) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, 2.75, 3), Rustic.WoodDark, Enum.Material.WoodPlanks)
	CollectionService:AddTag(counter, "BankCounter")

	CollectionService:AddTag(board, "BountyBoard")

	-- The people of the hub. The quest system takes them over by their QuestGiver id.
	local people = Instance.new("Folder")
	people.Name = "Townsfolk"
	people.Parent = folder
	local function facing(x, z, tx, tz)
		local p = Vector3.new(x, y, z)
		return CFrame.lookAt(p, Vector3.new(tx, y, tz))
	end
	townsperson(people, "bounty", "Marshal Hettie", facing(10, -4554, 0, -4520), Rustic.PaintBlue, {
		"Jobs go up on the board every morning. Bring the hay, get paid.",
		"Folks out past the Spindle pay double for clean bales.",
	})
	townsperson(people, "trader", "Trader Oskar", facing(-12, -4652, 0, -4520), Rustic.PaintGreen, {
		"I'll trade for anything with a shine on it. Needles most of all.",
		"Pine needles from the west woods? Bring me those.",
	})
	townsperson(people, "elder", "Old Wren", facing(-14, -4516, 0, -4520), Rustic.PaintRedDark, {
		"Twelve shards, they say, and the Spindle door opens.",
		"The tailor down on the south shore knows more than she lets on.",
		"When the gold beam goes up, ride for it. Rich hay never lasts.",
	})
	townsperson(people, "ferrymaster", "Ferrymaster Bo", facing(70, -4480, 80, -4380), IRON, {
		"Ferries leave from Swamp Port and Ash Dock. Trailers ride free.",
		"The Return Ferry runs from Swamp Port back round to Meadow Shore.",
	})
end

function LANDMARKS.spindle(folder)
	-- The sealed door on the Spindle's east face, with a socket for each of the twelve shards of the Master Needle.
	local x, z = 333, -5916
	local base = spot(x, z, Vector2.new(1, 0))
	local stone = Color3.fromRGB(150, 142, 160)
	local frame = part(folder, "DoorFrame", Vector3.new(20, 26, 4), base * CFrame.new(0, 12, 2.5), stone, Enum.Material.Slate)
	local door = part(folder, "SpindleDoor", Vector3.new(14, 20, 1), base * CFrame.new(0, 10, 0.2), Color3.fromRGB(96, 86, 120), Enum.Material.Slate)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local socket = part(folder, "ShardSocket", Vector3.new(0.6, 1, 1), door.CFrame * CFrame.new(math.cos(a) * 5, math.sin(a) * 5 + 2, -0.6) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(242, 183, 5), Enum.Material.Neon, Enum.PartType.Cylinder, false)
		socket.Transparency = 0.6
		socket:SetAttribute("Slot", i + 1) -- SpindleDoor.luau lights it once anyone here holds that shard
		CollectionService:AddTag(socket, "ShardSocket")
	end
	CollectionService:AddTag(door, "SpindleDoor")
	-- The Blender Spindle (Config/Props the_spindle), built round this door: its door (center 11 up, front -Z) on
	-- this one and its twelve sockets on these. Only a look. The part door stays the door (SpindleDoor.client fades
	-- it for a player with all twelve shards) and the part sockets stay the lights, so the mesh drops its own door.
	local spindle = Props.make("the_spindle", base * CFrame.new(0, 10 - 11 + 59.9, 0.2 + 19.45 - 2.65))
	if spindle then
		for _, piece in Props.find(spindle, "Door") do
			piece:Destroy()
		end
		Props.weldTo(spindle, frame, frame)
	end
	billboard(door, "THE SPINDLE\nTwelve shards open this door", Vector3.new(0, 14, 0), 160)

	-- The Observatory up on the bluff above Mirror Lake (meteor showers land here).
	local ox, oz = 1830, -1000
	local oy = ground(ox, oz)
	local obs = Instance.new("Model")
	obs.Name = "Observatory"
	post(obs, "Tower", 18, 16, CFrame.new(ox, oy - 2, oz), Rustic.PaintCream, Enum.Material.Concrete)
	local dome = part(obs, "Dome", Vector3.new(15, 15, 15), CFrame.new(ox, oy + 16, oz), IRON, Enum.Material.Metal, Enum.PartType.Ball)
	part(obs, "Scope", Vector3.new(9, 1.6, 1.6), CFrame.new(ox, oy + 21, oz) * CFrame.Angles(0, 0.6, math.rad(40)), Rustic.Metal, Enum.Material.Metal, Enum.PartType.Cylinder)
	obs.PrimaryPart = dome
	if Props.has("observatory") then
		local mesh = Props.make("observatory", CFrame.new(ox, oy + 12, oz), nil, CFrame.Angles(0, math.pi, 0))
		if mesh then
			Props.restOn(mesh, oy - 1)
			Props.weldTo(mesh, dome, obs)
		end
	end
	obs.Parent = folder

	-- The cave mouth on the west foot: a stone arch and a lantern.
	local mouth = Map.Cave.mouth
	local arch = CFrame.lookAt(mouth, mouth + Vector3.new(-1, 0, 0.1))
	for _, side in { -1, 1 } do
		part(folder, "CavePillar", Vector3.new(3, 16, 3), arch * CFrame.new(side * 9, 2, 0), Rustic.StoneDark, Enum.Material.Slate)
	end
	part(folder, "CaveLintel", Vector3.new(22, 3, 3.4), arch * CFrame.new(0, 11, 0), Rustic.StoneDark, Enum.Material.Slate)
	local lantern = part(folder, "Lantern", Vector3.new(1, 1.4, 1), arch * CFrame.new(-7, 8, -2), Color3.fromRGB(255, 200, 120), Enum.Material.Neon, nil, false)
	light(lantern, Color3.fromRGB(255, 190, 120), 22, 1.2)
	signpost(folder, mouth.X - 18, mouth.Z + 14, Vector2.new(-1, 0), "CRYSTAL CAVE", 9)
end

function LANDMARKS.cave(folder, rng)
	-- Crystals all round the cavern and a field of crystal hay on its floor.
	local c = Map.Cave.chamber
	local floorY = c.center.Y - c.radius * 0.45 + 4
	for i = 1, 26 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(c.radius * 0.35, c.radius * 0.75)
		TREES.crystal(folder, CFrame.new(c.center.X + math.cos(a) * d, floorY - 0.5, c.center.Z + math.sin(a) * d), rng:NextNumber(0.8, 1.6), rng)
	end
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		local p = Map.Cave.mouth:Lerp(c.center, i / 7)
		local lamp = part(folder, "CaveLamp", Vector3.new(0.8, 0.8, 0.8), CFrame.new(p + Vector3.new(math.cos(a) * 2, 4, 0)), Color3.fromRGB(255, 196, 120), Enum.Material.Neon, nil, false)
		CollectionService:AddTag(lamp, "AlwaysLit") -- it's always night in the cave
		light(lamp, Color3.fromRGB(255, 190, 120), 26, 1)
	end
	field("Crystal Cave", Map.Cave.hayType, Vector3.new(c.center.X, floorY, c.center.Z), floorY, 8, rng)
end

function LANDMARKS.valley(folder)
	-- A jetty into Mirror Lake, and the stone ruins of the Sunken Harbor on its bed (Low Tide uncovers them later).
	local lake = Map.Lake
	local shore = Vector2.new(lake.center.X - lake.radius - 20, lake.center.Y)
	local level = lake.level
	for i = 0, 6 do
		local x = shore.X + i * 8
		part(folder, "JettyDeck", Vector3.new(8, 0.6, 10), CFrame.new(x, level + 1.6, shore.Y), Rustic.Wood, Enum.Material.WoodPlanks)
		for _, side in { -1, 1 } do
			post(folder, "JettyPost", 10, 0.7, CFrame.new(x, level - 8, shore.Y + side * 4.5), Rustic.WoodDark, Enum.Material.Wood)
		end
	end
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local p = Vector3.new(lake.center.X + math.cos(a) * 40, level - lake.depth + 6, lake.center.Y + math.sin(a) * 40)
		part(folder, "HarborRuin", Vector3.new(4, 10 + (i % 3) * 3, 4), CFrame.new(p) * CFrame.Angles(0.1 * (i % 2), a, 0), Rustic.StoneDark, Enum.Material.Cobblestone)
	end
	signpost(folder, shore.X - 6, shore.Y + 10, Vector2.new(-1, 0), "MIRROR LAKE", 9)
end

function LANDMARKS.shore(folder)
	-- The lighthouse on the south coast: it flashes at night (its code is a puzzle for later).
	local x, z = 300, 1280
	local y = ground(x, z)
	local tower = Instance.new("Model")
	tower.Name = "Lighthouse"
	for i = 0, 4 do
		local color = i % 2 == 0 and Rustic.PaintCream or Rustic.PaintRed
		post(tower, "Tower", 8, 12 - i * 1.2, CFrame.new(x, y + i * 8, z), color, Enum.Material.Concrete)
	end
	part(tower, "Gallery", Vector3.new(1, 10, 10), CFrame.new(x, y + 40.5, z) * CFrame.Angles(0, 0, math.pi / 2), IRON, Enum.Material.Metal, Enum.PartType.Cylinder)
	local lamp = part(tower, "Lamp", Vector3.new(4, 4, 4), CFrame.new(x, y + 43, z), Color3.fromRGB(255, 236, 190), Enum.Material.Neon, Enum.PartType.Ball, false)
	light(lamp, Color3.fromRGB(255, 230, 180), 60, 2)
	part(tower, "Cap", Vector3.new(6, 2.4, 6), CFrame.new(x, y + 46.5, z), Rustic.PaintRedDark, Enum.Material.Metal)
	tower.PrimaryPart = lamp
	tower.Parent = folder

	-- The Tailor's shack, where the mystery starts.
	building(folder, "TailorShack", spot(-264, 820, Vector2.new(0, 1), 4), 18, 14, 9, { sign = "THE TAILOR", roof = Rustic.PaintGreen })
	signpost(folder, -244, 850, Vector2.new(0, 1), "THE TAILOR'S SHACK", 10)
end

function LANDMARKS.ridge(folder)
	-- The Ridge Tunnel: a stone portal at each end of the bore and lamps along its walls (lit day and night).
	local road
	for _, r in Map.Roads do
		if r.tunnel then
			road = r
		end
	end
	if not road then
		return
	end
	local stone = Color3.fromRGB(120, 114, 108)
	local inside, lamps = false, 0
	for i = 1, #road.points - 1 do
		local a, b = road.points[i], road.points[i + 1]
		local dir = (b - a).Unit
		local n = math.max(1, math.floor((b - a).Magnitude / 6))
		for k = 0, n - 1 do
			local p = a:Lerp(b, k / n)
			local _, _, _, _, tube = WorldShape.column(p.X, p.Y)
			local now = tube ~= nil and tube.land == true
			if now ~= inside then
				-- A portal where the road goes in or comes out: pillars and a lintel outside the lane.
				local _, h = WorldShape.nearestRoad(p.X, p.Y)
				local base = CFrame.lookAt(Vector3.new(p.X, h, p.Y), Vector3.new(p.X + dir.X, h, p.Y + dir.Y))
				for _, side in { -1, 1 } do
					part(folder, "PortalPillar", Vector3.new(4, 24, 5), base * CFrame.new(side * 12.5, 12, 0), stone, Enum.Material.Cobblestone)
				end
				local lintel = part(folder, "PortalLintel", Vector3.new(29, 5, 5), base * CFrame.new(0, 24.5, 0), stone, Enum.Material.Cobblestone)
				boardText(lintel, "RIDGE TUNNEL")
				inside = now
			end
			if now and k % 10 == 0 then
				-- A wall lamp every 60 studs, on alternate walls, well off the lane.
				local _, h = WorldShape.nearestRoad(p.X, p.Y)
				local side = lamps % 2 == 0 and 1 or -1
				local off = Vector2.new(-dir.Y, dir.X) * side * 9.5
				local lamp = part(folder, "TunnelLamp", Vector3.new(0.8, 0.8, 0.8), CFrame.new(p.X + off.X, h + 14, p.Y + off.Y), Color3.fromRGB(255, 214, 150), Enum.Material.Neon, nil, false)
				light(lamp, Color3.fromRGB(255, 200, 140), 28, 1.2)
				CollectionService:AddTag(lamp, "AlwaysLit") -- it's always dark in the tunnel
				lamps += 1
			end
		end
	end
end

function LANDMARKS.pine(folder)
	-- The old mill by the end of the Shore Road, with log piles.
	building(folder, "PineMill", spot(-2010, -780, Vector2.new(1, 0), 18), 30, 22, 14, { sign = "PINE MILL", prop = "mill", roof = Rustic.PaintGreen })
	-- A log pile beside it: three logs on the ground, two on top.
	for layer = 0, 1 do
		for k = 0, 2 - layer do
			local x = -1980 + k * 2.3 + layer * 1.15
			part(folder, "Log", Vector3.new(14, 2.2, 2.2), CFrame.new(x, 18 + 1.1 + layer * 2, -756) * CFrame.Angles(0, math.pi / 2, 0), Rustic.Bark, Enum.Material.Wood, Enum.PartType.Cylinder)
		end
	end
	signpost(folder, -1625, 50, Vector2.new(1, 0.3), "PINE FOREST", 9)
end

function LANDMARKS.haunted(folder, rng)
	-- The Wreck of the Bobbin, half sunk on the west shore. The captain's cabin hides the Moth-Eaten Map.
	local cf = CFrame.new(-3500, -2, -2807) * CFrame.Angles(0, math.rad(20), math.rad(12))
	local hull = Color3.fromRGB(70, 58, 48)
	part(folder, "Hull", Vector3.new(16, 10, 60), cf * CFrame.new(0, 3, 0), hull, Enum.Material.WoodPlanks)
	wedge(folder, "Bow", Vector3.new(16, 10, 14), cf * CFrame.new(0, 3, -37), hull, Enum.Material.WoodPlanks)
	part(folder, "Deck", Vector3.new(15, 1, 58), cf * CFrame.new(0, 8.4, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	building(folder, "CaptainsCabin", cf * CFrame.new(0, 8.4, 18), 12, 12, 7, { roof = hull })
	post(folder, "Mast", 34, 1.4, cf * CFrame.new(0, 8, -6) * CFrame.Angles(0, 0, math.rad(-18)), Rustic.WoodDark, Enum.Material.Wood)
	signpost(folder, -3430, -2790, Vector2.new(-1, 0), "WRECK OF THE BOBBIN", 11)

	-- Graves and lanterns along the grove road.
	for i = 1, 14 do
		local x, z = -2620 + rng:NextNumber(-90, 90), -2960 + rng:NextNumber(-60, 60)
		if buildable(x, z, 4) and not crowded(x, z, 4) then
			local base = spot(x, z, Vector2.new(0, -1))
			part(folder, "Gravestone", Vector3.new(2.4, 3.4, 0.6), base * CFrame.new(0, 1.2, 0) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), Color3.fromRGB(110, 106, 116), Enum.Material.Slate)
			claim(x, z)
		end
	end
	for i = 0, 8 do
		local p = Vector2.new(-2250, -1800):Lerp(Vector2.new(-2350, -2200), i / 8) + Vector2.new(11, 0)
		local lx, lz = offRoad(p.X, p.Y, 1.5) -- the road bends near the end; keep every post out of the lane
		local base = CFrame.new(at(lx, lz))
		post(folder, "LanternPost", 7, 0.4, base, Color3.fromRGB(40, 36, 36), Enum.Material.Metal)
		local glow = part(folder, "Lantern", Vector3.new(1, 1.2, 1), base * CFrame.new(0, 7.4, 0), Color3.fromRGB(150, 210, 190), Enum.Material.Neon, nil, false)
		light(glow, Color3.fromRGB(140, 220, 200), 20, 0.8)
	end
	signpost(folder, -2235, -1780, Vector2.new(0.3, 1), "HAUNTED GROVE\nStay on the road at night", 11)
end

function LANDMARKS.snow(folder)
	-- The ski lodge at the end of the Snow Road.
	building(folder, "SkiLodge", spot(-1665, -5082, Vector2.new(0, 1), 46), 34, 24, 13, { sign = "SNOW PEAK LODGE", roof = SNOW })
	-- The hidden door: a stitched seam in the rock high on the ridge.
	local x, z = -2130, -5180
	local base = spot(x, z, Vector2.new(1, 0.4))
	local seam = part(folder, "HiddenDoor", Vector3.new(8, 12, 1.2), base * CFrame.new(0, 5, 0), Color3.fromRGB(110, 120, 134), Enum.Material.Slate)
	for i = -2, 2 do
		part(folder, "Stitch", Vector3.new(2.4, 0.3, 0.3), seam.CFrame * CFrame.new(0, i * 2, -0.7) * CFrame.Angles(0, 0, math.rad(i % 2 == 0 and 30 or -30)), Color3.fromRGB(170, 220, 240), Enum.Material.Neon, nil, false)
	end
	signpost(folder, -1675, -4870, Vector2.new(0, 1), "SNOW PEAK\nLodge ahead", 9)
end

function LANDMARKS.volcano(folder, rng)
	-- The Magma Spindle stands in the crater over the lava.
	local peak = WorldShape.region("volcano").peak
	local c = peak.center
	local floor = ground(c.X, c.Y)
	local spire = part(folder, "MagmaSpindle", Vector3.new(3, 46, 3), CFrame.new(c.X, floor + 22, c.Y) * CFrame.Angles(0, 0.4, 0.05), Color3.fromRGB(90, 40, 30), Enum.Material.Basalt)
	local glow = part(folder, "LavaGlow", Vector3.new(peak.crater * 1.4, 1, peak.crater * 1.4), CFrame.new(c.X, floor + 1.5, c.Y), Color3.fromRGB(230, 110, 40), Enum.Material.Neon, nil, false)
	glow.Transparency = 0.35
	light(glow, Color3.fromRGB(255, 120, 50), 60, 2)
	billboard(spire, "VOLCANO", Vector3.new(0, 30, 0), 900)

	-- The Old Quarry at the foot: cut stone, a cracked mine cart track and a locked chest.
	local q = CFrame.new(1943, 30, -5759)
	for i = 1, 9 do
		local size = Vector3.new(rng:NextNumber(4, 7), rng:NextNumber(3, 6), rng:NextNumber(4, 7))
		part(folder, "QuarryStone", size, q * CFrame.new(rng:NextNumber(-30, 30), size.Y / 2, rng:NextNumber(-25, 25)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color3.fromRGB(122, 112, 104), Enum.Material.Slate)
	end
	for i = 0, 7 do
		local cf = q * CFrame.new(-20 + i * 6, 0.2, 18)
		for _, side in { -1, 1 } do
			part(folder, "Rail", Vector3.new(6, 0.3, 0.3), cf * CFrame.new(0, 0, side * 1.2), IRON, Enum.Material.Metal)
		end
		part(folder, "Sleeper", Vector3.new(0.6, 0.3, 3.4), cf, Rustic.WoodDark, Enum.Material.Wood)
	end
	local cart = q * CFrame.new(4, 1.6, 18)
	part(folder, "MineCart", Vector3.new(5, 2.6, 3.6), cart, IRON, Enum.Material.Metal)
	part(folder, "Chest", Vector3.new(3, 2, 2), q * CFrame.new(-26, 1, -18), Rustic.WoodDark, Enum.Material.WoodPlanks)
	signpost(folder, 1883, -5734, Vector2.new(-0.6, 0.8), "OLD QUARRY", 8)
end

function LANDMARKS.desert(folder, rng)
	-- The Buried Pyramid: stepped sandstone, half under the dunes.
	local c = Vector3.new(1934, 10, -4355)
	local stone = Color3.fromRGB(190, 160, 112)
	for i = 0, 5 do
		local w = 96 - i * 16
		part(folder, "PyramidStep", Vector3.new(w, 8, w), CFrame.new(c + Vector3.new(0, i * 8 - 2, 0)), stone, Enum.Material.Sandstone)
	end
	local door = part(folder, "PyramidDoor", Vector3.new(8, 10, 1), CFrame.new(c + Vector3.new(0, 7, 48.6)), Color3.fromRGB(60, 50, 40), Enum.Material.Slate)
	billboard(door, "BURIED PYRAMID", Vector3.new(0, 10, 0), 200)

	-- The oasis: palms round the pool, and a camp of tents.
	local o = Map.Oasis
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local x, z = o.center.X + math.cos(a) * (o.radius + 12), o.center.Y + math.sin(a) * (o.radius + 12)
		TREES.palm(folder, CFrame.new(x, ground(x, z) - 1, z), rng:NextNumber(0.9, 1.2), rng)
		claim(x, z)
	end
	for i = 0, 2 do
		local base = spot(1579 + i * 16, -3980, Vector2.new(0, 1))
		wedge(folder, "Tent", Vector3.new(8, 6, 5), base * CFrame.new(0, 3, -2.5), Rustic.Cloth, Enum.Material.Fabric)
		wedge(folder, "Tent", Vector3.new(8, 6, 5), base * CFrame.new(0, 3, 2.5) * CFrame.Angles(0, math.pi, 0), Rustic.Cloth, Enum.Material.Fabric)
	end
	signpost(folder, 2240, -3250, Vector2.new(0, -1), "DESERT DUNES", 9)
end

function LANDMARKS.swamp(folder, rng)
	-- Boardwalks out over the bog, with lily pads in the pools.
	for _, walk in { { Vector2.new(2280, -2325), Vector2.new(2340, -2170) }, { Vector2.new(2720, -2375), Vector2.new(2780, -2510) } } do
		local a, b = walk[1], walk[2]
		local n = math.floor((b - a).Magnitude / 6)
		local along = CFrame.lookAt(Vector3.zero, Vector3.new(b.X - a.X, 0, b.Y - a.Y))
		for i = 0, n do
			local p = a:Lerp(b, i / n)
			local base = along + Vector3.new(p.X, 1.4, p.Y)
			part(folder, "Boardwalk", Vector3.new(6, 0.5, 6.2), base, Rustic.Wood, Enum.Material.WoodPlanks)
			if i % 2 == 0 then
				for _, side in { -1, 1 } do
					post(folder, "BoardwalkPost", 5, 0.5, base * CFrame.new(side * 2.8, -4, 0), Rustic.WoodDark, Enum.Material.Wood)
				end
			end
		end
	end
	for _ = 1, 50 do
		local x, z = 2400 + rng:NextNumber(-700, 700), -2400 + rng:NextNumber(-800, 800)
		local h, water = WorldShape.column(x, z)
		if water and water > SEA and water - h < 3 then
			part(folder, "LilyPad", Vector3.new(0.2, 3, 3), CFrame.new(x, water + 0.1, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(96, 128, 70), Enum.Material.Grass, Enum.PartType.Cylinder, false)
		end
	end
	signpost(folder, 2195, -1830, Vector2.new(0, 1), "THE SWAMP\nMud slows trucks", 10)
end

function LANDMARKS.keys(folder)
	-- A harbor market by the ferry, and tide-pool rocks.
	for i = 0, 2 do
		local base = spot(3990 + i * 16, -2630, Vector2.new(-1, 0), 2)
		part(folder, "Counter", Vector3.new(3, 3.5, 10), base * CFrame.new(0, 1.75, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
		part(folder, "Awning", Vector3.new(7, 0.4, 12), base * CFrame.new(0, 8, 0) * CFrame.Angles(0, 0, math.rad(10)), ({ Rustic.PaintBlue, Rustic.PaintCream, Rustic.PaintGreen })[i + 1], Enum.Material.Fabric)
		for _, z in { -5, 5 } do
			post(folder, "Pole", 8, 0.4, base * CFrame.new(2.5, 0, z), Rustic.Wood, Enum.Material.Wood)
		end
	end
	signpost(folder, 3946, -3192, Vector2.new(-1, 0), "THIMBLE KEYS", 9)
end

function LANDMARKS.bobbin(folder)
	-- The Weaver's lost workshop on top of the rock: broken stone walls and the twelfth shard on a pedestal.
	local zone
	for _, f in Map.Flat do
		if f.name == "Workshop" then
			zone = f
		end
	end
	local mid = (zone.min + zone.max) / 2
	local base = CFrame.new(mid.X, zone.height, mid.Y)
	local stone = Color3.fromRGB(110, 106, 112)
	for i, w in { { Vector3.new(30, 12, 2), CFrame.new(0, 6, -14) }, { Vector3.new(2, 9, 26), CFrame.new(-14, 4.5, 0) }, { Vector3.new(14, 6, 2), CFrame.new(8, 3, 14) } } do
		part(folder, "WorkshopWall" .. i, w[1], base * w[2], stone, Enum.Material.Cobblestone)
	end
	part(folder, "Pedestal", Vector3.new(3, 4, 3), base * CFrame.new(0, 2, 0), stone, Enum.Material.Slate)
	local shard = part(folder, "Shard", Vector3.new(0.6, 3, 0.6), base * CFrame.new(0, 5.6, 0) * CFrame.Angles(0, 0, 0.2), Color3.fromRGB(242, 183, 5), Enum.Material.Neon, nil, false)
	light(shard, Color3.fromRGB(255, 200, 80), 24, 1.5)
	billboard(shard, "THE WEAVER'S WORKSHOP", Vector3.new(0, 6, 0), 200)
end

-- The Graveyard of Ships: wrecks on the reef between the main island and Bobbin Rock, clear of the ferry lane.
local function graveyard(folder, rng)
	local lane = Map.Channels[2]
	local made = 0
	for _ = 1, 60 do
		if made >= 6 then
			break
		end
		local x, z = 3700 + rng:NextNumber(-260, 260), -5560 + rng:NextNumber(-200, 200)
		local d = WorldShape.segment(x, z, lane.from.X, lane.from.Y, lane.to.X, lane.to.Y)
		if d > lane.width / 2 + 70 then
			local cf = CFrame.new(x, SEA - 6, z) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, math.pi * 2), rng:NextNumber(0.2, 0.5))
			part(folder, "Wreck", Vector3.new(12, 9, 44), cf, Color3.fromRGB(64, 54, 46), Enum.Material.WoodPlanks)
			post(folder, "WreckMast", 22, 1.1, cf * CFrame.new(0, 3, -6) * CFrame.Angles(0.3, 0, 0), Rustic.WoodDark, Enum.Material.Wood)
			made += 1
		end
	end
end

-- The sky island's trees and its field of cloud hay.
local function skyIsland(folder, rng)
	local sky = Map.SkyIsland
	if not sky then
		return -- out for now
	end
	for i = 1, 16 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(30, sky.radius * 0.7)
		local x, z = sky.center.X + math.cos(a) * d, sky.center.Y + math.sin(a) * d
		TREES.oak(folder, CFrame.new(x, sky.top - 2, z), rng:NextNumber(0.9, 1.3), rng)
	end
	field("Sky Island", "sky", Vector3.new(sky.center.X, sky.top - 1, sky.center.Y + 40), sky.top - 1.5, 9, rng)
	signpost(folder, sky.center.X + 10, sky.center.Y + 150, Vector2.new(0, 1), "SKY ISLAND", 9)
end

-- Signs where the roads branch, so nobody gets lost.
-- Junction signs: where they stand, which way they face, and the places they point to. Each line is an arrow, a
-- name and a target; the driving distance is worked out from the road graph (RoadGraph.luau) when the map builds, so
-- "HOMESTEAD 880" can never drift from the roads. A line with no target is plain text.
local function regionCenter(id)
	local r = WorldShape.region(id)
	return r and Vector2.new(r.cx, r.cz) or Vector2.zero
end
local HOMESTEAD = Vector2.new(0, -4550)
local ASH_DOCK = Vector2.new(3107, -5627)
local SWAMP_PORT = Vector2.new(3220, -2246)
local MIRROR_LAKE = Map.Lake.center
local JUNCTIONS = {
	{ 150, 600, Vector2.new(0, -1), { { "<", "PINE FOREST", function() return regionCenter("pine") end }, { ">", "MIRROR LAKE", MIRROR_LAKE } } },
	{ -30, -600, Vector2.new(0, 1), { { "^", "HOMESTEAD", HOMESTEAD }, { "", "by the Ridge Cut" } } },
	{ 450, 740, Vector2.new(0, -1), { { "v", "RETURN FERRY", Vector2.new(715, 1195) }, { ">", "MIRROR LAKE", MIRROR_LAKE } } },
	{ -2540, -2880, Vector2.new(0, 1), { { "^", "HOMESTEAD", HOMESTEAD }, { "<", "WRECK", Vector2.new(-3495, -2807) } } },
	{ -1700, -4730, Vector2.new(1, 0), { { "<", "SNOW PEAK LODGE", Vector2.new(-1665, -5057) }, { ">", "HOMESTEAD", HOMESTEAD } } },
	{ 2440, -2330, Vector2.new(0, 1), { { ">", "SWAMP PORT", SWAMP_PORT }, { "", "Ferries to Thimble Keys and Meadow" } } },
	{ 2110, -3570, Vector2.new(0, 1), { { "<", "HIGHWAY", Map.Highway.from }, { "^", "HOMESTEAD", HOMESTEAD } } },
	{ 1510, -4280, Vector2.new(1, 0), { { "v", "VOLCANO", function() return regionCenter("volcano") end }, { ">", "ASH DOCK", ASH_DOCK } } },
	{ 2980, -5520, Vector2.new(-1, 0), { { ">", "ASH DOCK", ASH_DOCK }, { "", "Ferry to Bobbin Rock" } } },
}

-- A junction sign's text: one line per place, "^ HOMESTEAD 880" or "MIRROR LAKE 340 >" (arrows keep their side).
-- Distances are rounded to 10 studs. Returns the text and the distances for the self-tests.
local function junctionText(j)
	local RoadGraph = require(script.Parent.RoadGraph)
	local dist = RoadGraph.distances(Vector2.new(j[1], j[2]))
	local lines, numbers = {}, {}
	for _, line in j[4] do
		local arrow, name, target = line[1], line[2], line[3]
		if type(target) == "function" then
			target = target()
		end
		if not target then
			table.insert(lines, name)
			continue
		end
		local d = dist[RoadGraph.nearest(target)]
		if d == math.huge then
			table.insert(lines, (arrow == ">" and "%s >" or "%s %s"):format(name, arrow))
			continue
		end
		local n = math.max(10, math.floor(d / 10 + 0.5) * 10)
		table.insert(numbers, { name = name, distance = n, target = target })
		if arrow == ">" then
			table.insert(lines, ("%s %d >"):format(name, n))
		else
			table.insert(lines, ("%s %s %d"):format(arrow, name, n))
		end
	end
	return table.concat(lines, "\n"), numbers
end
Regions.junctions = JUNCTIONS
Regions.junctionText = junctionText

-- A sign at the roadside wherever a road crosses into another region: its name and the hay that grows there.
local function borderSigns(folder)
	local placed = {}
	local count = 0
	for _, road in Map.Roads do
		-- A road out of Meadow's gate starts in Meadow, so its first region gets a sign too.
		local start = road.points[1]
		local current = WorldShape.meadowDistance(start.X, start.Y) < 4 and "meadow" or nil
		local candidate, run = nil, 0
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			local dir = (b - a).Unit
			local n = math.max(1, math.ceil((b - a).Magnitude / 8))
			for k = 0, n - 1 do
				local p = a:Lerp(b, k / n)
				local r = WorldShape.inMeadow(p.X, p.Y) and "meadow" or WorldShape.regionAt(p.X, p.Y)
				local id = r and (r == "meadow" and r or r.id)
				if not id or id == current then
					candidate, run = nil, 0
					continue
				end
				if id ~= candidate then
					candidate, run = id, 0
				end
				run += 1
				-- The new region has to hold for 40 studs, so a wobbly border doesn't sprout a row of signs.
				if run < 5 then
					continue
				end
				local first = current == nil
				current, candidate, run = id, nil, 0
				if first or id == "meadow" then
					continue
				end
				local at = p - dir * 16 + Vector2.new(-dir.Y, dir.X) * (Map.RoadWidth / 2 + 4)
				local near = false
				for _, q in placed do
					if (q - at).Magnitude < 80 then
						near = true
						break
					end
				end
				if near then
					continue
				end
				table.insert(placed, at)
				local region = WorldShape.region(id)
				local hay = GloveConfig.HayTypes[region.hayType]
				local text = string.upper(region.name)
				if hay then
					text ..= ("\n%s, tier %d"):format(hay.name, hay.tier)
				end
				signpost(folder, at.X, at.Y, -dir, text, 13)
				count += 1
			end
		end
	end
	return count
end

-- Labels that read from far off, so the big landmarks find you: the Spindle on the skyline, the snow peak, Bobbin.
local function skyline(folder)
	for _, def in {
		{ "spindle", "THE SPINDLE" },
		{ "snow", "SNOW PEAK" },
		{ "bobbin", "BOBBIN ROCK" },
	} do
		local peak = WorldShape.region(def[1]).peak
		local top = WorldShape.heightAt(peak.center.X, peak.center.Y)
		-- A persistent model so the label streams to every client however far away it is.
		local holder = Instance.new("Model")
		holder.Name = def[2]
		holder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		holder.Parent = folder
		local anchor = part(holder, "SkylineLabel", Vector3.new(1, 1, 1), CFrame.new(peak.center.X, top + 30, peak.center.Y), Rustic.Stone, nil, nil, false)
		anchor.Transparency = 1
		anchor.CanQuery = false
		billboard(anchor, def[2], Vector3.zero, 4000)
	end
end

function Regions.build(worldFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Isles"
	folder.Parent = worldFolder
	local rng = Random.new(Map.Seed)
	local trees, made = 0, 0

	for _, r in WorldShape.regions do
		-- A plain Model per region (Default streaming, never Atomic): parts stream one by one, and the region can be
		-- found, pivoted or budgeted as a unit (Config/WorldMap PartBudget).
		local sub = Instance.new("Model")
		sub.Name = r.name
		sub.Parent = folder
		palette = PALETTE[r.id] or {}
		local landmark = LANDMARKS[r.id]
		if landmark then
			-- One broken landmark shouldn't take the rest of the map down with it.
			local ok, err = pcall(landmark, sub, rng)
			if not ok then
				warn(("[Needlewood] %s landmarks failed: %s"):format(r.name, tostring(err)))
			end
			claimParts(sub)
		end
		for _, planting in PLANTING[r.id] or {} do
			trees += plant(sub, r, planting[1], planting[2], rng)
		end
		rocks(sub, r, 18, rng)
		if r.id == "valley" or r.id == "shore" or r.id == "homestead" then
			herd(sub, r, r.id == "homestead" and 6 or 12, rng)
			windmill(sub, r.cx + r.rx * 0.35, r.cz - r.rz * 0.2)
		end
		hayFields(r, rng)
		palette = {}
		made += 1
		task.wait() -- spread the work out so the server keeps ticking
	end

	local cave = Instance.new("Model")
	cave.Name = "Crystal Cave"
	cave.Parent = folder
	LANDMARKS.cave(cave, rng)

	local sea = Instance.new("Model")
	sea.Name = "Graveyard of Ships"
	sea.Parent = folder
	graveyard(sea, rng)

	if Map.SkyIsland then
		local sky = Instance.new("Model")
		sky.Name = "Sky Island"
		sky.Parent = folder
		skyIsland(sky, rng)
	end

	local signs = Instance.new("Model")
	signs.Name = "Signs"
	signs.Parent = folder
	for _, j in JUNCTIONS do
		local ok, text = pcall(junctionText, j)
		if not ok then
			warn("[Needlewood] junction sign distances failed: " .. tostring(text))
			local names = {}
			for _, line in j[4] do
				table.insert(names, line[2])
			end
			text = table.concat(names, "\n")
		end
		signpost(signs, j[1], j[2], j[3], text, 14)
	end
	local ok, borders = pcall(borderSigns, signs)
	if not ok then
		warn("[Needlewood] Region signs failed: " .. tostring(borders))
		borders = 0
	end
	local skyOk, skyErr = pcall(skyline, signs)
	if not skyOk then
		warn("[Needlewood] Skyline labels failed: " .. tostring(skyErr))
	end
	print(("[Needlewood] %d junction signs, %d region signs"):format(#JUNCTIONS, borders))

	print(("[Needlewood] Stitched Isles: %d regions, %d trees, %d hay fields"):format(made, trees, #Regions.fields))
	return folder
end

return Regions
