--!nonstrict
-- Field bale chutes (V8 plan). A wooden hopper on four posts stands over a lane beside each big hay field, and one
-- on the meadow's trailer road. Park a truck or trailer bed under it and pull the lever: it pours a bale's worth of loose
-- hay into each free spot of the bed, one layer at a time, in about three seconds. Shovelling a bed full by hand was
-- the slow part of a truck trip, so this is what makes a truck beat the wheelbarrow.
--
-- No bales: fields grow loose hay, so the chute pours ordinary loose clumps (Hay.spawnPiece), never welded, that the
-- dock unloads like any other hay. Each chute holds Config/Chutes Stock loads and refills one every RefillSeconds.
--
--   Chutes.build(worldFolder) -- after WorldMap.build, so Regions.fields is filled
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Chutes)
local RateLimit = require(Shared.RateLimit)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local Bales = require(script.Parent.Bales)
local Data = require(script.Parent.Data)
local Feedback = require(script.Parent.Feedback)
local Hay = require(script.Parent.Hay)
local Vehicles = require(script.Parent.Vehicles)
local Props = require(script.Parent.Props)

local Chutes = {}

local BALE = Vector3.new(4.6, 2.6, 3.2) -- Bales.luau SIZE: lying lengthwise in a bed, 3.2 across and 4.6 along
local SLOT_ACROSS, SLOT_ALONG = 3.25, 4.7
local CLUMPS = 3 -- clumps poured per bale slot
local STRANDS = math.floor(require(Shared.Config.Game).FieldPileStrands / CLUMPS) -- a bale's worth across the clumps
local GATE_OPEN = math.rad(70) -- the flap swings out toward the front while bales drop
local LEVER_PULLED = math.rad(45) -- the lever's top swings back toward the hopper
local ROAD_CLEAR = 18 -- from a road's center line to a field chute's center: half a road plus the chute's half width

local chutes = {}
local pullLimit = RateLimit.new("Chutes.Pull", 1, 2)

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
-- `only` limits the search to one model (the SelfTest's truck, which no player owns).
local function bedUnder(chute, only)
	local best, bestD
	for model in if only then { [only] = true } else Vehicles.all() do
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
					if Bales.fromPart(p) or Hay.isPiece(p) then
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

-- Pulls the lever for player (nil in self-tests: the bales then have no owner). Returns how many bales will drop.
function Chutes.pull(chute, player, only)
	if chute.busy then
		return 0
	end
	if chute.stock <= 0 then
		tell(player, "The chute is empty. It refills a bale every few seconds.")
		return 0
	end
	local bed = bedUnder(chute, only)
	if not bed then
		tell(player, "Park a truck or trailer bed under the chute, then pull the lever.")
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
	if chute.swingLever then
		chute.swingLever(LEVER_PULLED, 0.25)
	end
	if chute.swingGate then
		chute.swingGate(GATE_OPEN, 0.4)
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
			-- Fields grow loose hay, never bales, so the chute pours a bale's worth of loose clumps into each slot.
			local at = cf.Position + Vector3.new(0, 1.2, 0)
			local first
			for _ = 1, CLUMPS do
				local spread = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2
				local piece = Hay.spawnPiece(at + spread, Vector3.new(0, -4, 0), player and player.UserId, nil, hayType, STRANDS)
				piece:SetAttribute("HayType", hayType or "meadow")
				if field and field.rich then
					piece:SetAttribute("NeedleBoost", 2)
				end
				first = first or piece
			end
			Feedback.play("BaleLift", first)
			chute.stock -= 1
			dropped += 1
			refreshLabel(chute)
			task.wait(Cfg.DropGap)
		end
		if chute.swingGate then
			chute.swingGate(0, 0.6)
		end
		if chute.swingLever then
			chute.swingLever(0, 0.4)
		end
		chute.busy = false
		if dropped > 0 then
			tell(player, ("%d loads of hay in the bed."):format(dropped))
		end
	end)
	return math.min(#slots, chute.stock)
end

-- The Blender chute (blender/props/hub.py field_bale_chute; rigs.json) in its own units: 14.1 wide, 14.45 tall and
-- 15.95 deep, facing -Z. Legs at x +-6.65 and z +-7 (inner faces at +-6.25), lane beams with their underside at 10,
-- a plank hopper and bin from 11.2 up to 14, the Gate flap across the spout front (hinged at its top edge) and the red
-- Lever on the front-left leg (pivots at its base). Chutes are built at Cfg.Scale, and the collision parts below follow
-- the same numbers, so the posts you bump into are the posts you see.
local MESH = {
	depth = 15.95,
	legX = 6.65,
	legZ = 7.0,
	legTop = 12.8,
	beamY = 10.3,
	binW = 11.6,
	binD = 15.2,
	binY0 = 11.2,
	binY1 = 14.0,
	lever = Vector3.new(-6.66, 4.15, -7.85), -- base of the lever
	leverH = 2.86,
}

-- The box around some parts, in world axes.
local function boxOf(parts)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in parts do
		local half = p.Size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local corner = p.CFrame * Vector3.new(half.X * x, half.Y * y, half.Z * z)
					low, high = low:Min(corner), high:Max(corner)
				end
			end
		end
	end
	return low, high
end

-- Joins a moving piece of the mesh (Gate, Lever) to the hopper through a hinge at hingeAt, across the lane. Returns
-- a function that swings it to an angle in radians.
local function hinge(pieces, anchor, frame, hingeAt)
	local pivot = CFrame.fromMatrix(hingeAt, frame.RightVector, frame.UpVector)
	local welds = {}
	for _, p in pieces do
		local weld = Instance.new("Weld")
		weld.Part0 = anchor
		weld.Part1 = p
		weld.C0 = anchor.CFrame:ToObjectSpace(pivot)
		weld.C1 = p.CFrame:ToObjectSpace(pivot)
		weld.Parent = p
		table.insert(welds, weld)
	end
	local base = anchor.CFrame:ToObjectSpace(pivot)
	return function(angle, seconds)
		for _, weld in welds do
			TweenService:Create(weld, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { C0 = base * CFrame.Angles(angle, 0, 0) }):Play()
		end
	end
end

-- frame: ground CFrame in the middle of the lane, LookVector along the lane.
function Chutes.make(parent, frame, field, name)
	local model = Instance.new("Model")
	model.Name = name or "BaleChute"
	local S = Cfg.Scale
	local look = {} -- the part-built chute each client hides once the mesh has loaded (not the lantern)
	local function add(...)
		local p = part(model, ...)
		table.insert(look, p)
		return p
	end
	local legX, legZ = MESH.legX * S, MESH.legZ * S
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			add("Post", Vector3.new(0.8, MESH.legTop, 0.8) * S, frame * CFrame.new(sx * legX, MESH.legTop * S / 2, sz * legZ), Rustic.WoodDark, Enum.Material.Wood)
		end
		-- The X-braces and low rail stand in the leg plane, outside the lane: one wall each side keeps people out.
		add("SideBrace", Vector3.new(0.4, 8.4 * S, 2 * legZ), frame * CFrame.new(sx * legX, 5.2 * S, 0), Rustic.Wood, Enum.Material.WoodPlanks).Transparency = 0.6
		add("Beam", Vector3.new(14.1 * S, 0.6 * S, 0.7 * S), frame * CFrame.new(0, MESH.beamY * S, sx * legZ), Rustic.WoodDark, Enum.Material.Wood)
	end
	local binH = MESH.binY1 - MESH.binY0
	local hopper = add("Hopper", Vector3.new(MESH.binW, binH, MESH.binD) * S, frame * CFrame.new(0, (MESH.binY0 + binH / 2) * S, 0), Rustic.Wood)
	add("Spout", Vector3.new(3.6, 1.2, 3.6) * S, frame * CFrame.new(0, 10.6 * S, 0), Rustic.Wood, nil, false)
	local leverBase = MESH.lever * S
	local handle = add("Handle", Vector3.new(0.5, MESH.leverH, 0.5) * S, frame * CFrame.new(leverBase + Vector3.new(0, MESH.leverH * S / 2, 0)), Rustic.PaintRed, Enum.Material.Wood, false)
	-- A lantern on the other front leg so the chute is easy to find at night (WorldClock lights anything named Lantern).
	local lantern = part(model, "Lantern", Vector3.new(0.8, 1.2, 0.8), frame * CFrame.new(legX, 9 * S, -legZ - 0.8), Rustic.PaintCream, Enum.Material.Neon, false)
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = 1.4
	light.Color = Color3.fromRGB(255, 214, 150)
	light.Parent = lantern
	model.Parent = parent

	-- The mesh at Cfg.Scale, standing on the ground. Its Gate and Lever stay unwelded so they can swing on a pull.
	local swingGate, swingLever
	local mesh = Props.make("field_bale_chute", frame * CFrame.new(0, MESH.binY1 * S / 2, 0), MESH.depth * S)
	if mesh then
		Props.restOn(mesh, frame.Position.Y)
		local gate, lever = Props.find(mesh, "Gate"), Props.find(mesh, "Lever")
		local loose = table.clone(gate)
		table.move(lever, 1, #lever, #loose + 1, loose)
		Props.weldTo(mesh, hopper, look, loose)
		if #gate > 0 then
			local low, high = boxOf(gate)
			swingGate = hinge(gate, hopper, frame, Vector3.new((low.X + high.X) / 2, high.Y, (low.Z + high.Z) / 2))
		end
		if #lever > 0 then
			local low, high = boxOf(lever)
			-- The prompt sits where the mesh's lever really is, whichever way the import turned it.
			handle.CFrame = CFrame.new((low + high) / 2) * frame.Rotation
			swingLever = hinge(lever, hopper, frame, Vector3.new((low.X + high.X) / 2, low.Y, (low.Z + high.Z) / 2))
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PullPrompt"
	prompt.ActionText = "Pull lever"
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
		swingGate = swingGate,
		swingLever = swingLever,
		label = WorldLabel.billboard(hopper, "", { kind = "sign", offset = Vector3.new(0, 6, 0) }),
	}
	refreshLabel(chute)
	prompt.Triggered:Connect(function(player)
		if not pullLimit:allow(player) then
			return
		end
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
		-- Close to a road so a truck can pull in, but never standing on it.
		local road = WorldShape.nearestRoad(p.X, p.Z)
		if flat and road and road >= ROAD_CLEAR and (not bestRoad or road < bestRoad) then
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

-- SelfTest hook: pull into a truck that isn't in Vehicles.all() (test trucks have no real owner).
Chutes.test = {
	pullInto = function(chute, model)
		return Chutes.pull(chute, nil, model)
	end,
}

return Chutes
