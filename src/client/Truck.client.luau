--!nonstrict
-- Drives your truck. Runs only while you sit in its driver's seat; the server gave this client the truck's physics.
-- W/S (or the thumbstick) for gas and reverse, A/D to steer, jump to get out. Getting out sets you down beside the
-- driver's door; the Drive button there puts you back in.
-- The truck tilts to follow the ground under its wheels, so hay bales in the bed feel the hills and can shift or
-- spill on rough driving. Speed changes are kept smooth so a careful driver keeps the load.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local ACCEL = 22 -- studs/s² on the gas
local BRAKE = 45 -- studs/s² when pressing against the way you are rolling
local COAST = 10 -- studs/s² when you let go
local REVERSE = 0.4 -- fraction of top speed going backwards
local TURN = 1.4 -- radians per second at speed
local TILT_FOLLOW = 6 -- how fast the truck leans into the slope under it

local active = nil

local function yawOf(cframe)
	local look = cframe.LookVector
	return math.atan2(-look.X, -look.Z)
end

local Kit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Kit"))
local Theme = Kit.Theme
local F = Theme.Fonts

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -90)
hint.Size = UDim2.fromOffset(480, 26)
hint.BackgroundColor3 = Theme.Colors.Wood
hint.BackgroundTransparency = 0.1
hint.Font = F.Bold
hint.TextSize = 15
hint.TextColor3 = Theme.Colors.Cream
local DRIVE_HINT = "W/S drive   A/D steer   Q horn   Space get out   T tow"
hint.Text = DRIVE_HINT
hint.Visible = false
Kit.corner(hint, 8)
Kit.stroke(hint, Theme.Colors.Ink, 1.5)
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "TruckHint"
hintGui.ResetOnSpawn = false
hintGui.Parent = player:WaitForChild("PlayerGui")
hint.Parent = hintGui

local function stop()
	if not active then
		return
	end
	active.connection:Disconnect()
	active.recovered:Disconnect()
	local chassis = active.chassis
	if chassis.Parent then
		active.drive.PlaneVelocity = Vector2.zero
		active.steer.CFrame = CFrame.Angles(0, yawOf(chassis.CFrame), 0)
	end
	active = nil
	hint.Visible = false
end

-- True for things the truck carries or pulls rather than drives on: other vehicles (its own trailer too), hay bales,
-- loose hay and people.
local function isLoose(part)
	if part:HasTag("HayBale") or (part.Parent and part.Parent.Name == "LooseHay") then
		return true
	end
	local node = part.Parent
	while node and node ~= workspace do
		if node:GetAttribute("TruckId") or node:GetAttribute("TrailerId") or node:FindFirstChildOfClass("Humanoid") then
			return true
		end
		node = node.Parent
	end
	return false
end

local function groundBelow(origin, params)
	for _ = 1, 5 do
		local hit = workspace:Raycast(origin, Vector3.new(0, -9, 0), params)
		if not hit or not isLoose(hit.Instance) then
			return hit
		end
		params:AddToFilter(hit.Instance) -- the filter is reset every frame
	end
	return nil
end

-- The ground's up direction under the four corners of the truck, or nil in the air.
local function groundUp(model, chassis, params)
	local length = model:GetAttribute("Length") or 14
	local track = model:GetAttribute("Track") or 2.8
	local corners = {}
	for _, z in { -length / 2 + 2.5, length / 2 - 2.5 } do
		for _, x in { -track, track } do
			local origin = chassis.CFrame * Vector3.new(x, 3, z)
			local hit = groundBelow(origin, params)
			if not hit then
				return nil
			end
			table.insert(corners, hit.Position)
		end
	end
	local front = (corners[1] + corners[2]) / 2
	local back = (corners[3] + corners[4]) / 2
	local left = (corners[1] + corners[3]) / 2
	local right = (corners[2] + corners[4]) / 2
	local forward = front - back
	local side = right - left
	if forward.Magnitude < 0.1 or side.Magnitude < 0.1 then
		return nil
	end
	local up = side.Unit:Cross(forward.Unit)
	if up.Y < 0.6 then
		return nil -- too steep to trust; stay as we are
	end
	return up.Unit
end

local function start(seat)
	stop()
	local model = seat.Parent
	local chassis = model and model.PrimaryPart
	local drive = chassis and chassis:FindFirstChild("Drive")
	local steer = chassis and chassis:FindFirstChild("Steer")
	if not drive or not steer then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local state = {
		chassis = chassis,
		drive = drive,
		steer = steer,
		speed = 0,
		yaw = yawOf(chassis.CFrame),
		up = Vector3.yAxis,
	}
	active = state
	hint.Text = DRIVE_HINT
	hint.Visible = true

	-- Flipped or towed (Vehicles.recover): start again from where the truck now stands, not the old heading.
	state.recovered = model:GetAttributeChangedSignal("RecoveredAt"):Connect(function()
		state.yaw = yawOf(chassis.CFrame)
		state.speed = 0
		state.up = Vector3.yAxis
	end)

	state.connection = RunService.Heartbeat:Connect(function(dt)
		if not seat.Parent or seat.Occupant == nil then
			stop()
			return
		end
		if chassis.Anchored then
			-- Still in the garage scene; the server is moving it.
			state.yaw = yawOf(chassis.CFrame)
			state.speed = 0
			return
		end

		local maxSpeed = model:GetAttribute("MaxSpeed") or 40
		local throttle = seat.ThrottleFloat
		local steerInput = seat.SteerFloat

		local target = throttle >= 0 and throttle * maxSpeed or throttle * maxSpeed * REVERSE
		local rate = COAST
		if throttle ~= 0 then
			rate = (state.speed ~= 0 and math.sign(target) ~= math.sign(state.speed)) and BRAKE or ACCEL
		end
		rate *= game:GetService("Lighting"):GetAttribute("WeatherGrip") or 1 -- wet or snowy roads (Weather.client)
		if state.speed < target then
			state.speed = math.min(state.speed + rate * dt, target)
		else
			state.speed = math.max(state.speed - rate * dt, target)
		end

		-- Blocked by a wall or a steep bank: do not keep winding up speed you are not getting.
		local actual = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
		if math.abs(state.speed) > math.abs(actual) + 10 then
			state.speed = actual + math.sign(state.speed) * 10
		end

		-- Enough push to climb the steepest meadow slope with a full bed, whatever the truck and its load weigh.
		-- PullMass is the load and hitched trailer the server counts for this truck (Vehicles.luau updateCargo).
		local mass = chassis.AssemblyMass + (model:GetAttribute("PullMass") or 0)
		drive.MaxForce = mass * (workspace.Gravity + 80)

		local grip = math.clamp(math.abs(state.speed) / 14, 0, 1)
		state.yaw -= steerInput * TURN * grip * math.sign(state.speed) * dt

		params.FilterDescendantsInstances = { model, player.Character }
		local up = groundUp(model, chassis, params)
		if up then
			state.up = state.up:Lerp(up, math.clamp(dt * TILT_FOLLOW, 0, 1)).Unit
		end
		local heading = Vector3.new(-math.sin(state.yaw), 0, -math.cos(state.yaw))
		local forward = (heading - state.up * heading:Dot(state.up)).Unit
		local right = forward:Cross(state.up)
		steer.CFrame = CFrame.fromMatrix(Vector3.zero, right, state.up, -forward)
		drive.PlaneVelocity = Vector2.new(0, -state.speed)
	end)
end

-- Stand the character on the ground beside the driver's door, facing the way the truck faces.
local function getOut(character, seat)
	local model = seat.Parent
	local chassis = model and model.PrimaryPart
	local exit = seat:GetAttribute("ExitOffset")
	if not chassis or not exit or not character.Parent then
		return
	end
	local spot = (chassis.CFrame * exit).Position
	local look = chassis.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	character:PivotTo(CFrame.lookAt(spot, spot + look.Unit))
end

local function watch(character)
	local humanoid = character:WaitForChild("Humanoid")
	local lastSeat = nil
	humanoid.Seated:Connect(function(isSeated, seatPart)
		if isSeated and seatPart and seatPart:IsA("VehicleSeat") and seatPart:GetAttribute("Truck") then
			lastSeat = seatPart
			start(seatPart)
		else
			stop()
			local seat = lastSeat
			lastSeat = nil
			if seat and humanoid.Health > 0 then
				task.defer(getOut, character, seat)
			end
		end
	end)
	if humanoid.SeatPart and humanoid.SeatPart:GetAttribute("Truck") then
		lastSeat = humanoid.SeatPart
		start(humanoid.SeatPart)
	end
end

player.CharacterAdded:Connect(function(character)
	stop()
	watch(character)
end)
if player.Character then
	task.spawn(watch, player.Character)
end

-- T twice while driving: the tow truck sets your truck (and a hitched trailer) down on the dealer lot. For a truck
-- stuck in a ditch or on a rock; a truck on its roof gets a "Flip upright" button beside it instead.
local towAskedAt = -math.huge
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not active then
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		local horn = ReplicatedStorage:FindFirstChild("TruckHorn")
		if horn then
			horn:FireServer()
		end
		return
	end
	if input.KeyCode ~= Enum.KeyCode.T then
		return
	end
	if os.clock() - towAskedAt > 3 then
		towAskedAt = os.clock()
		hint.Text = "Press T again to tow to Homestead Motors"
		task.delay(3, function()
			if active and os.clock() - towAskedAt >= 3 then
				hint.Text = DRIVE_HINT
			end
		end)
		return
	end
	towAskedAt = -math.huge
	local remote = ReplicatedStorage:FindFirstChild("TruckRecover")
	if not remote then
		return
	end
	local ok, _, message = pcall(function()
		return remote:InvokeServer("tow")
	end)
	hint.Text = ok and (message or "") or "Could not reach the tow truck."
	task.delay(3, function()
		if active then
			hint.Text = DRIVE_HINT
		end
	end)
end)
