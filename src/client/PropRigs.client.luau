--!nonstrict
-- Turns the moving pieces of rigged Rustic meshes on this client. The Blender trucks and trailers carry each wheel
-- as its own child mesh (Wheel_L1, Wheel_R2, ...); here every wheel rolls with the speed of the part it is welded
-- to, so a moving truck's wheels turn. Only the look changes: the weld offsets are edited locally, physics and the
-- server never see it.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

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

local function track(model)
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
