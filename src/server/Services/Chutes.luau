--!nonstrict
-- Field bale chutes (V8 plan). A wooden hopper on four posts stands over a lane beside each big hay field, and one
-- on the meadow's trailer road. Park a truck or trailer bed under it and pull the rope: it drops loose bales into the
-- free spots of the bed, one layer at a time, in about three seconds. Loading 9 bales by hand was the slow part of a
-- truck trip, so this is what makes a truck beat the wheelbarrow.
--
-- The bales are ordinary loose bales (Bales.spawn), never welded: the truck's cargo loop picks them up like any
-- other. Each chute holds Config/Chutes Stock bales and refills one every RefillSeconds.
--
--   Chutes.build(worldFolder) -- after WorldMap.build, so Regions.fields is filled
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Chutes)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local Bales = require(script.Parent.Bales)
local Data = require(script.Parent.Data)
local Feedback = require(script.Parent.Feedback)
local Vehicles = require(script.Parent.Vehicles)

local Chutes = {}

local BALE = Vector3.new(4.6, 2.6, 3.2) -- Bales.luau SIZE: lying lengthwise in a bed, 3.2 across and 4.6 along
local SLOT_ACROSS, SLOT_ALONG = 3.25, 4.7

local chutes = {}

local function part(parent, name, size, cframe, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.WoodPlanks
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- The bed (truck or trailer) whose cargo box is under this chute, nearest the middle of the lane.
local function bedUnder(chute)
	local best, bestD
	for model in Vehicles.all() do
		local chassis = model.PrimaryPart
		local offset, size = model:GetAttribute("CargoOffset"), model:GetAttribute("CargoSize")
		if chassis and offset and size then
			local cargo = chassis.CFrame * offset
			local p = chute.frame:PointToObjectSpace(cargo.Position)
			if math.abs(p.X) < Cfg.LaneWidth / 2 and math.abs(p.Z) < Cfg.LaneLength / 2 + 4 and p.Y > -2 and p.Y < Cfg.Clearance then
				local d = Vector2.new(p.X, p.Z).Magnitude
				if not bestD or d < bestD then
					best, bestD = { model = model, cframe = cargo, size = size }, d
				end
			end
		end
	end
	return best
end

Chutes.BALE = BALE

-- Bale spots in the bed that nothing is in, bottom layer first. Each is the bale's CFrame, long side along the bed.
local function freeSlots(bed)
	local size = bed.size
	local across = math.max(1, math.floor((size.X + 0.3) / BALE.Z))
	local along = math.max(1, math.floor((size.Z + 0.3) / BALE.X))
	local layers = math.clamp(math.floor(size.Y / BALE.Y), 1, 2)
	local stepX = math.min(SLOT_ACROSS, size.X / across)
	local stepZ = math.min(SLOT_ALONG, size.Z / along)
	local floorY = -size.Y / 2
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bed.model }
	local slots = {}
	for layer = 0, layers - 1 do
		for k = 1, along do
			for i = 1, across do
				local local_ = CFrame.new((i - (across + 1) / 2) * stepX, floorY + BALE.Y * (layer + 0.5), (k - (along + 1) / 2) * stepZ)
				local cf = bed.cframe * local_ * CFrame.Angles(0, math.pi / 2, 0)
				local taken = false
				for _, p in Workspace:GetPartBoundsInBox(cf, BALE * 0.85, params) do
					if Bales.fromPart(p) then
						taken = true
						break
					end
				end
				if not taken then
					table.insert(slots, cf)
				end
			end
		end
		-- Fill one layer per pull, so the top layer only starts once the bottom one is full.
		if #slots > 0 then
			break
		end
	end
	return slots
end

local function refreshLabel(chute)
	chute.label.Text = ("BALE CHUTE\n%d bales"):format(chute.stock)
	chute.prompt.ObjectText = ("Bale chute (%d)"):format(chute.stock)
end

local function tell(player, text)
	if player then
		Data.toast(player, text)
	end
end

-- Pulls the rope for player (nil in self-tests: the bales then have no owner). Returns how many bales will drop.
function Chutes.pull(chute, player)
	if chute.busy then
		return 0
	end
	if chute.stock <= 0 then
		tell(player, "The chute is empty. It refills a bale every few seconds.")
		return 0
	end
	local bed = bedUnder(chute)
	if not bed then
		tell(player, "Park a truck or trailer bed under the chute, then pull the rope.")
		return 0
	end
	local slots = freeSlots(bed)
	if #slots == 0 then
		tell(player, "That bed is full. Haul it to the dock!")
		return 0
	end
	chute.busy = true
	local field = chute.field
	local hayType = field and field.hayType or nil
	-- Field bales are tinted by their hay; copy the tint from one still standing in the field.
	local color
	if field then
		for b in field.bales do
			if b.body and b.body.Parent then
				color = b.body.Color
				break
			end
		end
	end
	task.spawn(function()
		local dropped = 0
		for _, slot in slots do
			if chute.stock <= 0 or not bed.model.Parent then
				break
			end
			-- Re-read the bed each time: the driver may roll a little while it fills.
			local chassis = bed.model.PrimaryPart
			local offset = bed.model:GetAttribute("CargoOffset")
			local now = chassis and offset and chassis.CFrame * offset
			local cf = now and now * bed.cframe:ToObjectSpace(slot) or slot
			local b = Bales.spawn(Vector3.zero, false, false, hayType)
			b.ownerId = player and player.UserId
			if color then
				b.body.Color = color
			end
			if field and field.rich then
				b.body:SetAttribute("NeedleBoost", 2)
			end
			b.body.CFrame = cf + Vector3.new(0, 1.2, 0)
			b.body.Anchored = false
			Feedback.play("BaleLift", b.body)
			chute.stock -= 1
			dropped += 1
			refreshLabel(chute)
			task.wait(Cfg.DropGap)
		end
		chute.busy = false
		if dropped > 0 then
			tell(player, ("%d bales in the bed."):format(dropped))
		end
	end)
	return math.min(#slots, chute.stock)
end

-- frame: ground CFrame in the middle of the lane, LookVector along the lane.
function Chutes.make(parent, frame, field, name)
	local model = Instance.new("Model")
	model.Name = name or "BaleChute"
	local W, Lz, H = Cfg.LaneWidth, Cfg.LaneLength, Cfg.Clearance
	local postX, postZ = W / 2 + 0.6, Lz * 0.3
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "Post", Vector3.new(1.2, H + 6, 1.2), frame * CFrame.new(sx * postX, (H + 6) / 2 - 1, sz * postZ), Rustic.WoodDark, Enum.Material.Wood)
		end
		part(model, "Beam", Vector3.new(1, 1, Lz * 0.6 + 2), frame * CFrame.new(sx * postX, H + 0.5, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	local hopper = part(model, "Hopper", Vector3.new(W - 1, 5, Lz * 0.6), frame * CFrame.new(0, H + 3, 0), Rustic.Wood)
	part(model, "Roof", Vector3.new(W + 3, 0.6, Lz * 0.6 + 3), frame * CFrame.new(0, H + 6.2, 0), Rustic.PaintRed, Enum.Material.WoodPlanks)
	part(model, "Spout", Vector3.new(W - 4, 0.4, 4), frame * CFrame.new(0, H - 0.4, 0) * CFrame.Angles(math.rad(-20), 0, 0), Rustic.Wood, nil, false)
	-- The pull rope hangs in the middle of the lane, low enough to reach from a truck's cab.
	local rope = part(model, "PullRope", Vector3.new(0.3, H - 8.5, 0.3), frame * CFrame.new(-2, 8.5 + (H - 8.5) / 2, -Lz * 0.3 + 1), Rustic.Wood, Enum.Material.Fabric, false)
	local handle = part(model, "Handle", Vector3.new(1.2, 0.5, 0.5), frame * CFrame.new(-2, 8.4, -Lz * 0.3 + 1), Rustic.PaintRed, Enum.Material.Wood, false)
	rope.CanQuery = false
	model.Parent = parent

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PullPrompt"
	prompt.ActionText = "Pull rope"
	prompt.ObjectText = "Bale chute"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = handle

	local chute = {
		model = model,
		frame = frame,
		field = field,
		stock = Cfg.Stock,
		busy = false,
		prompt = prompt,
		label = WorldLabel.billboard(hopper, "", { kind = "sign", offset = Vector3.new(0, 6, 0) }),
	}
	refreshLabel(chute)
	prompt.Triggered:Connect(function(player)
		Chutes.pull(chute, player)
	end)
	table.insert(chutes, chute)
	return chute
end

-- A spot beside a field: flat, near a road, clear of the bales (which spread about 11 studs from the center).
local function spotFor(field, WorldShape)
	local c = field.center
	local best, bestRoad
	for i = 0, 11 do
		local a = i * math.pi / 6
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local lane = Vector3.new(-out.Z, 0, out.X)
		local p = c + out * 22
		local h = WorldShape.heightAt(p.X, p.Z)
		local flat = true
		for _, o in { out * 8, -out * 8, lane * 10, -lane * 10 } do
			if math.abs(WorldShape.heightAt(p.X + o.X, p.Z + o.Z) - h) > 2 then
				flat = false
				break
			end
		end
		local road = WorldShape.nearestRoad(p.X, p.Z)
		if flat and road and (not bestRoad or road < bestRoad) then
			best, bestRoad = CFrame.lookAt(Vector3.new(p.X, h, p.Z), Vector3.new(p.X, h, p.Z) + lane), road
		end
	end
	return best
end

function Chutes.build(worldFolder)
	local folder = Instance.new("Folder")
	folder.Name = "BaleChutes"
	folder.Parent = worldFolder or Workspace

	local m = Cfg.Meadow
	local at = Vector3.new(m.at.X, 0, m.at.Y)
	Chutes.make(folder, CFrame.lookAt(at, at + Vector3.new(m.lane.X, 0, m.lane.Y)), nil, "MeadowBaleChute")

	-- The world map's hay fields (Regions.luau), when this place has them.
	local okR, Regions = pcall(require, script.Parent.Regions)
	local okW, WorldShape = pcall(require, script.Parent.WorldShape)
	if okR and okW and Regions.fields then
		for _, field in Regions.fields do
			local frame = spotFor(field, WorldShape)
			if frame then
				Chutes.make(folder, frame, field)
			end
		end
	end

	task.spawn(function()
		while true do
			task.wait(Cfg.RefillSeconds)
			for _, chute in chutes do
				if chute.stock < Cfg.Stock then
					chute.stock += 1
					refreshLabel(chute)
				end
			end
		end
	end)
end

return Chutes
