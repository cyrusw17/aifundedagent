--!nonstrict
-- Turns the moving pieces of rigged Rustic meshes on this client. The Blender trucks and trailers carry each wheel
-- as its own child mesh (Wheel_L1, Wheel_R2, ...); here every wheel rolls with the speed of the part it is welded
-- to, so a moving truck's wheels turn. Only the look changes: the weld offsets are edited locally, physics and the
-- server never see it.
-- Truck doors (Door_L / Door_R child meshes, hinged at their front edge, MODEL_SPECS.md) open and shut here too:
-- press F by a door and it swings 70 degrees out about its hinge on this client. A truck without them is untouched.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DOOR_ANGLE = math.rad(70)
local DOOR_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local wheels = {} -- wheel part -> { weld, base, axis, radius, angle }

-- The wheel's axle is its thinnest side; its radius is half of the others.
local function axleOf(part)
	local size = part.Size
	if size.X <= size.Y and size.X <= size.Z then
		return Vector3.xAxis, math.max(size.Y, size.Z) / 2
	elseif size.Y <= size.Z then
		return Vector3.yAxis, math.max(size.X, size.Z) / 2
	end
	return Vector3.zAxis, math.max(size.X, size.Y) / 2
end

-- The wheel itself, or the model the importer wrapped it in, is named Wheel_<side><number>.
local function isWheel(part, model)
	local node = part
	while node and node ~= model do
		if string.match(node.Name, "^Wheel_") then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Which door a piece belongs to (Door_L is the driver's, Door_R the other; Glass_L / Glass_R ride with them), from
-- the part or the model the importer wrapped it in.
local function doorSide(part, model)
	local node = part
	while node and node ~= model do
		local side = string.match(node.Name, "^Door_([LR])") or string.match(node.Name, "^Glass_([LR])")
		if side then
			return side
		end
		node = node.Parent
	end
	return nil
end

local doors = {} -- door part -> true once it has its prompt

-- A door swings about a vertical hinge at its front edge (the truck faces -Z of the part it is welded to): the left
-- door out to -X, the right one out to +X. Every piece of one door (split by material) turns together.
local function rigDoor(model, side)
	local pieces = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not doors[part] and doorSide(part, model) == side then
			local weld = part:FindFirstChildOfClass("Weld")
			if weld and weld.Part0 then
				table.insert(pieces, { part = part, weld = weld, base = weld.C0 })
			end
		end
	end
	if #pieces == 0 then
		return
	end
	-- The hinge: the front edge of all the pieces together, in the space of the part they are welded to.
	local front, x, y = math.huge, 0, 0
	for _, piece in pieces do
		doors[piece.part] = true
		local half = piece.part.Size / 2
		for _, cx in { -1, 1 } do
			for _, cy in { -1, 1 } do
				for _, cz in { -1, 1 } do
					front = math.min(front, (piece.base * (half * Vector3.new(cx, cy, cz))).Z)
				end
			end
		end
		x += piece.base.Position.X / #pieces
		y += piece.base.Position.Y / #pieces
	end
	local hinge = CFrame.new(x, y, front)
	local angle = Instance.new("NumberValue")
	local function swing()
		local turn = hinge * CFrame.Angles(0, (side == "L" and -1 or 1) * angle.Value, 0) * hinge:Inverse()
		for _, piece in pieces do
			if piece.weld.Parent then
				piece.weld.C0 = turn * piece.base
			end
		end
	end
	angle.Changed:Connect(swing)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open door"
	prompt.ObjectText = side == "L" and "Left door" or "Right door"
	prompt.KeyboardKeyCode = Enum.KeyCode.F -- E is the seat's, and only the nearest prompt per key shows
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = pieces[1].part
	local open = false
	prompt.Triggered:Connect(function()
		open = not open
		prompt.ActionText = open and "Close door" or "Open door"
		TweenService:Create(angle, DOOR_TWEEN, { Value = open and DOOR_ANGLE or 0 }):Play()
	end)
end

local function track(model)
	for _, side in { "L", "R" } do
		rigDoor(model, side)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not wheels[part] and isWheel(part, model) then
			local weld = part:FindFirstChildOfClass("Weld")
			if weld then
				local axis, radius = axleOf(part)
				wheels[part] = { weld = weld, base = weld.C0, axis = axis, radius = math.max(radius, 0.1), angle = 0 }
			end
		end
	end
end

local function watch(model)
	task.delay(1, track, model) -- give the wheel parts and their welds a moment to replicate
	model.DescendantAdded:Connect(function()
		task.defer(track, model)
	end)
end

CollectionService:GetInstanceAddedSignal("PropMesh"):Connect(watch)
for _, model in CollectionService:GetTagged("PropMesh") do
	watch(model)
end

RunService.RenderStepped:Connect(function(dt)
	for part, wheel in wheels do
		local weld = wheel.weld
		local body = weld.Part0
		if not part.Parent or not weld.Parent or not body then
			wheels[part] = nil
		else
			-- Rolling without slipping: the wheel spins about up x velocity, at speed / radius.
			local velocity = body.AssemblyLinearVelocity
			local spin = body.CFrame.UpVector:Cross(velocity) / wheel.radius
			local axle = part.CFrame:VectorToWorldSpace(wheel.axis)
			wheel.angle = (wheel.angle + spin:Dot(axle) * dt) % (math.pi * 2)
			weld.C0 = wheel.base * CFrame.fromAxisAngle(wheel.axis, wheel.angle)
		end
	end
end)
