--!nonstrict
-- The Hay Wagon: a free, slow ride for players (no cargo) on a loop from base camp up the North Road to Homestead,
-- back to camp, then down the South road and the Swamp Road to Swamp Port and back. New players see the isles
-- before they own a truck; trucks stay the way to haul. A little tractor pulls it.
--
-- It is anchored and moved along the road every frame, and nothing on it collides, so it never blocks a lane or
-- shoves a truck: riders sit in its seats (a Ride prompt seats you; jump to get off). It waits STOP_SECONDS at each
-- stop, where a signpost lists the stops.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)
local Rustic = require(Shared.Config.Rustic)
local WorldShape = require(script.Parent.WorldShape)
local Regions = require(script.Parent.Regions)

local HayWagon = {}

local SPEED = 14 -- studs per second
local STOP_SECONDS = 20
local STEP = 4 -- studs between route samples
local SEATS = 6
local LANE_OFFSET = 4 -- keeps to the right-hand side of the road

local function roadPoints(list, name)
	for _, road in list do
		if road.name == name then
			return road.points
		end
	end
	error("no road " .. name)
end

local function concat(...)
	local out = {}
	for _, list in { ... } do
		for _, p in list do
			if #out == 0 or (out[#out] - p).Magnitude > 0.5 then
				table.insert(out, p)
			end
		end
	end
	return out
end

local function reversed(list)
	local out = {}
	for i = #list, 1, -1 do
		table.insert(out, list[i])
	end
	return out
end

-- The loop as legs: { stop name at the end, polyline }.
local function legs()
	local camp = Vector2.new(0, 26)
	local north = concat({ camp }, roadPoints(Meadow.Roads, "North"), roadPoints(Map.Roads, "North Road"))
	local south = concat({ camp, Vector2.new(120, 26) }, roadPoints(Meadow.Roads, "South"), { Vector2.new(150, 640) }, roadPoints(Map.Roads, "Swamp Road"))
	return {
		{ stop = "Homestead", line = north },
		{ stop = "Base Camp", line = reversed(north) },
		{ stop = "Swamp Port", line = south },
		{ stop = "Base Camp", line = reversed(south) },
	}
end

-- Dense samples along a polyline at road height, kept to the right of the center line.
local function sample(line)
	local out = {}
	for i = 1, #line - 1 do
		local a, b = line[i], line[i + 1]
		local dir = (b - a).Unit
		local right = Vector2.new(-dir.Y, dir.X)
		local n = math.max(1, math.floor((b - a).Magnitude / STEP))
		for k = 0, n - 1 do
			local p = a:Lerp(b, k / n) + right * LANE_OFFSET
			table.insert(out, Vector3.new(p.X, WorldShape.heightAt(p.X, p.Y), p.Y))
		end
	end
	local last = line[#line]
	table.insert(out, Vector3.new(last.X, WorldShape.heightAt(last.X, last.Y), last.Y))
	-- Smooth the heights so terrain noise doesn't make it hop.
	for _ = 1, 2 do
		for i = 2, #out - 1 do
			local y = (out[i - 1].Y + out[i].Y * 2 + out[i + 1].Y) / 4
			out[i] = Vector3.new(out[i].X, y, out[i].Z)
		end
	end
	return out
end

local function part(parent, name, size, cframe, color, material, shape)
	local p = Instance.new(name == "Seat" and "Seat" or "Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Wood
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = name == "Seat"
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Builds the wagon at the origin, facing -Z; returns the model and its seats.
local function buildWagon(parent)
	local model = Instance.new("Model")
	model.Name = "HayWagon"
	local origin = CFrame.new()
	local bed = part(model, "Bed", Vector3.new(8, 0.8, 14), origin * CFrame.new(0, 2.4, 2), Rustic.Wood, Enum.Material.WoodPlanks)
	model.PrimaryPart = bed
	for _, side in { -1, 1 } do
		part(model, "Rail", Vector3.new(0.4, 1.4, 14), origin * CFrame.new(side * 3.9, 3.5, 2), Rustic.WoodDark)
		for _, z in { -3, 7 } do
			part(model, "Wheel", Vector3.new(0.6, 3.2, 3.2), origin * CFrame.new(side * 4.3, 1.6, z), Rustic.WoodDark, Enum.Material.Wood, Enum.PartType.Cylinder)
		end
	end
	-- A heap of hay down the middle to lean on, and benches facing out.
	part(model, "HayHeap", Vector3.new(2.4, 1.6, 12), origin * CFrame.new(0, 3.6, 2), Color3.fromRGB(189, 168, 112), Enum.Material.Grass)
	local seats = {}
	for i = 0, SEATS - 1 do
		local side = i % 2 == 0 and -1 or 1
		local z = -2 + math.floor(i / 2) * 4
		local seat = part(model, "Seat", Vector3.new(2, 0.6, 2), origin * CFrame.new(side * 2.5, 3.1, z) * CFrame.Angles(0, side * math.pi / 2, 0), Rustic.PaintRed, Enum.Material.Fabric)
		seat.CanTouch = true
		table.insert(seats, seat)
	end
	-- The tractor in front.
	local t = origin * CFrame.new(0, 0, -9)
	part(model, "TractorBody", Vector3.new(4, 3, 6), t * CFrame.new(0, 3, 0), Rustic.PaintGreen, Enum.Material.Metal)
	part(model, "TractorHood", Vector3.new(3, 2, 3), t * CFrame.new(0, 3.5, -3.5), Rustic.PaintGreen, Enum.Material.Metal)
	part(model, "TractorStack", Vector3.new(0.5, 3, 0.5), t * CFrame.new(1, 6, -3), Color3.fromRGB(60, 58, 56), Enum.Material.Metal)
	for _, side in { -1, 1 } do
		part(model, "TractorWheel", Vector3.new(1.2, 4.4, 4.4), t * CFrame.new(side * 2.6, 2.2, 1.5), Color3.fromRGB(40, 38, 36), Enum.Material.Rubber, Enum.PartType.Cylinder)
		part(model, "TractorFront", Vector3.new(0.8, 2.4, 2.4), t * CFrame.new(side * 1.8, 1.2, -3.5), Color3.fromRGB(40, 38, 36), Enum.Material.Rubber, Enum.PartType.Cylinder)
	end
	part(model, "Driver", Vector3.new(1.6, 2.6, 1), t * CFrame.new(0, 5.6, 1.5), Color3.fromRGB(120, 92, 70), Enum.Material.Fabric)
	part(model, "DriverHat", Vector3.new(2.2, 0.5, 2.2), t * CFrame.new(0, 7.2, 1.5), Color3.fromRGB(189, 168, 112), Enum.Material.Fabric)
	local board = part(model, "WagonBoard", Vector3.new(6, 1.4, 0.3), origin * CFrame.new(0, 5.2, 9.2), Rustic.PaintCream, Enum.Material.WoodPlanks)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(300, 70)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Merriweather
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(40, 32, 26)
	label.Text = "FREE HAY WAGON"
	label.Parent = gui
	gui.Parent = board

	-- Ride: seats you in a free seat (riders only, no cargo).
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ride"
	prompt.ObjectText = "Free hay wagon"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = bed
	prompt.Triggered:Connect(function(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.SeatPart then
			return
		end
		for _, seat in seats do
			if not seat.Occupant then
				seat:Sit(humanoid)
				return
			end
		end
	end)
	model.Parent = parent
	return model, seats, label
end

HayWagon.legs = {} -- { stop, samples }

function HayWagon.build(parent)
	local folder = Instance.new("Folder")
	folder.Name = "HayWagon"
	folder.Parent = parent
	for _, leg in legs() do
		table.insert(HayWagon.legs, { stop = leg.stop, samples = sample(leg.line) })
	end
	-- A stop sign at each stop.
	local seen = {}
	for _, leg in HayWagon.legs do
		if not seen[leg.stop] then
			seen[leg.stop] = true
			local at = leg.samples[#leg.samples]
			local text = ("HAY WAGON STOP\n%s\nFree: Camp, Homestead, Swamp Port"):format(leg.stop:upper())
			if Regions.signpost then
				pcall(Regions.signpost, folder, at.X + 12, at.Z, Vector2.new(-1, 0), text, 12)
			end
		end
	end

	local model, seats, label = buildWagon(folder)
	HayWagon.model, HayWagon.seats = model, seats
	local state = { leg = 1, i = 1, along = 0, wait = STOP_SECONDS }
	HayWagon.state = state

	local function place()
		local samples = HayWagon.legs[state.leg].samples
		local a = samples[state.i]
		local b = samples[math.min(state.i + 1, #samples)]
		local p = a:Lerp(b, state.along)
		local ahead = samples[math.min(state.i + 3, #samples)]
		local dir = Vector3.new(ahead.X - p.X, 0, ahead.Z - p.Z)
		if dir.Magnitude < 0.1 then
			dir = model:GetPivot().LookVector
		end
		model:PivotTo(CFrame.lookAt(p, p + dir.Unit))
	end

	-- Moves the wagon dt seconds along the loop (tests call this directly).
	function HayWagon.step(dt)
		if state.wait > 0 then
			state.wait -= dt
			label.Text = ("FREE HAY WAGON\nnext: %s"):format(HayWagon.legs[state.leg].stop)
			return
		end
		local samples = HayWagon.legs[state.leg].samples
		local move = SPEED * dt
		while move > 0 do
			local a, b = samples[state.i], samples[state.i + 1]
			if not b then
				-- End of the leg: a stop, then the next leg.
				state.leg = state.leg % #HayWagon.legs + 1
				state.i, state.along, state.wait = 1, 0, STOP_SECONDS
				break
			end
			local length = math.max(0.01, (b - a).Magnitude)
			local left = (1 - state.along) * length
			if move < left then
				state.along += move / length
				move = 0
			else
				move -= left
				state.i += 1
				state.along = 0
			end
		end
		place()
	end

	place()
	RunService.Heartbeat:Connect(function(dt)
		if model.Parent then
			HayWagon.step(math.min(dt, 0.1))
		end
	end)
end

return HayWagon
