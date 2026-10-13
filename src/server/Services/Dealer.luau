--!nonstrict
-- Homestead Motors, the truck dealer at Meadow Farm. Walk in through the front door, step up to the sales counter
-- and a panel shows the trucks for sale. Buy your first truck (the Rusty Pickup) and you are put in the driver's
-- seat in the garage: the roller door goes up and the camera watches you drive it out onto the lot. Then it is
-- yours to drive. Owners can come back to the counter any time to have their truck brought round again.
--
-- The building is part-built for now, laid out around Meadow.DealerCenter with its front facing east (+X).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Meadow = require(Shared.Config.Meadow)
local Rustic = require(Shared.Config.Rustic)
local Trucks = require(Shared.Config.Trucks)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)
local Vehicles = require(script.Parent.Vehicles)

local Dealer = {}

local DOOR_SECONDS = 1.6 -- roller door going up
local DRIVE_SECONDS = 4.4 -- garage to the lot
local COUNTER_REACH = 16
local STUDIO_CASH = 6000

local origin = CFrame.new(Meadow.DealerCenter)
local folder = nil
local trucksFolder = nil
local garageDoor = nil
local doorClosed = nil -- { size, cframe }
local counter = nil
local garageBusy = false
local delivering = {} -- player -> true while their truck is being brought out
local cutsceneRemote = nil

-- Local spots (studs from the dealer's center; +X is the front).
local GARAGE_START = Vector3.new(-6, 0.15, 10.5)
local LOT_STOP = Vector3.new(41, 0.15, 10.5)
local CAMERA_SPOT = Vector3.new(47, 9, 31)
local DOOR_SPOT = Vector3.new(20, 5, 11)

local function world(v)
	return origin * v
end

local function part(parent, name, size, cframe, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- An axis-aligned box from local min/max corners.
local function block(parent, name, x0, x1, y0, y1, z0, z1, color, material)
	local size = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
	local center = Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	return part(parent, name, size, origin * CFrame.new(center), color, material)
end

local function glassBlock(parent, x0, x1, y0, y1, z0, z1)
	local g = block(parent, "Window", x0, x1, y0, y1, z0, z1, Rustic.Glass, Enum.Material.Glass)
	g.Transparency = 0.6
	return g
end

local function board(parent, name, size, cframe, text, faces)
	local p = part(parent, name, size, cframe, Rustic.Wood, Enum.Material.WoodPlanks)
	for _, face in faces or { Enum.NormalId.Front } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(size.X * 40, size.Y * 40)
		gui.LightInfluence = 1
		gui.Parent = p
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(40, 34, 28)
		label.Text = text
		label.Parent = gui
	end
	return p
end

local function lamp(parent, position)
	local shade = part(parent, "Lamp", Vector3.new(2, 0.4, 2), origin * CFrame.new(position), Rustic.PaintCream, Enum.Material.Neon)
	shade.CanCollide = false
	local light = Instance.new("PointLight")
	light.Range = 24
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 226, 180)
	light.Parent = shade
end

-- Hank, who sells trucks. A blocky R6-style figure, just parts.
local function clerk(parent, position)
	local model = Instance.new("Model")
	model.Name = "Hank"
	local base = origin * CFrame.new(position) * CFrame.Angles(0, -math.pi / 2, 0) -- faces +X, over the counter
	local skin = Color3.fromRGB(204, 160, 120)
	part(model, "LeftLeg", Vector3.new(1, 2, 1), base * CFrame.new(-0.5, 1, 0), Rustic.PaintBlue, Enum.Material.Fabric)
	part(model, "RightLeg", Vector3.new(1, 2, 1), base * CFrame.new(0.5, 1, 0), Rustic.PaintBlue, Enum.Material.Fabric)
	part(model, "Torso", Vector3.new(2, 2, 1), base * CFrame.new(0, 3, 0), Rustic.PaintBlue, Enum.Material.Fabric)
	part(model, "Shirt", Vector3.new(2.02, 0.8, 1.02), base * CFrame.new(0, 3.6, 0), Rustic.PaintCream, Enum.Material.Fabric)
	part(model, "LeftArm", Vector3.new(1, 2, 1), base * CFrame.new(-1.5, 3, 0), Rustic.PaintCream, Enum.Material.Fabric)
	part(model, "RightArm", Vector3.new(1, 2, 1), base * CFrame.new(1.5, 3, 0), Rustic.PaintCream, Enum.Material.Fabric)
	local head = part(model, "Head", Vector3.new(1.2, 1.2, 1.2), base * CFrame.new(0, 4.6, 0), skin)
	part(model, "Cap", Vector3.new(1.3, 0.4, 1.3), base * CFrame.new(0, 5.3, 0), Rustic.PaintRed, Enum.Material.Fabric)
	part(model, "Brim", Vector3.new(1.2, 0.15, 0.7), base * CFrame.new(0, 5.15, -0.9), Rustic.PaintRed, Enum.Material.Fabric)
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(200, 40)
	tag.StudsOffset = Vector3.new(0, 2.2, 0)
	tag.MaxDistance = 40
	tag.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = "Hank, truck sales"
	label.Parent = tag
	model.Parent = parent
end

local function buildBuilding()
	local b = Instance.new("Model")
	b.Name = "HomesteadMotors"
	b.Parent = folder
	local wall, trim = Rustic.PaintRed, Rustic.PaintCream
	local planks = Enum.Material.WoodPlanks

	-- Floors: wood in the showroom, concrete in the garage, and a concrete lot out front.
	block(b, "ShowroomFloor", -20, 20, -1, 0.1, -18, 4, Rustic.Wood, planks)
	block(b, "GarageFloor", -20, 20, -1, 0.1, 4, 18, Rustic.Stone, Enum.Material.Concrete)
	block(b, "Lot", 20, 52, -1, 0.06, -42, 24, Rustic.StoneDark, Enum.Material.Concrete)

	-- Outer walls. The east (front) wall has the shop door, a big window and the garage door.
	block(b, "WestWall", -20, -19, 0, 14, -18, 18, wall, planks)
	block(b, "NorthWall", -20, 20, 0, 14, -18, -17, wall, planks)
	block(b, "SouthWall", -20, 20, 0, 14, 17, 18, wall, planks)
	block(b, "FrontWall", 19, 20, 0, 14, -18, -12, wall, planks)
	block(b, "DoorHeader", 19, 20, 10, 14, -12, -4, trim, planks)
	block(b, "WindowSill", 19, 20, 0, 3, -4, 2, wall, planks)
	glassBlock(b, 19.3, 19.7, 3, 11, -4, 2)
	block(b, "WindowHeader", 19, 20, 11, 14, -4, 2, wall, planks)
	block(b, "FrontPillar", 19, 20, 0, 14, 2, 5, trim, planks)
	block(b, "GarageHeader", 19, 20, 10, 14, 5, 17, trim, planks)
	block(b, "CornerPillar", 19, 20, 0, 14, 17, 18, trim, planks)

	-- Inside wall between the showroom and the garage, with a doorway and a window to see the trucks.
	block(b, "DividerA", -19, -18, 0, 14, 3.5, 4.5, wall, planks)
	block(b, "DividerHeader", -18, -12, 9, 14, 3.5, 4.5, wall, planks)
	block(b, "DividerB", -12, 0, 0, 14, 3.5, 4.5, wall, planks)
	block(b, "DividerSill", 0, 12, 0, 3, 3.5, 4.5, wall, planks)
	glassBlock(b, 0, 12, 3, 9, 3.8, 4.2)
	block(b, "DividerTop", 0, 12, 9, 14, 3.5, 4.5, wall, planks)
	block(b, "DividerC", 12, 19, 0, 14, 3.5, 4.5, wall, planks)

	-- Rusty tin roof and the false front with the shop name.
	block(b, "Roof", -21, 21, 14, 14.8, -19, 19, Rustic.Rust, Enum.Material.CorrodedMetal)
	board(
		b,
		"ShopSign",
		Vector3.new(22, 5, 0.6),
		origin * CFrame.new(20.4, 17, -7) * CFrame.Angles(0, -math.pi / 2, 0),
		"HOMESTEAD MOTORS",
		{ Enum.NormalId.Front }
	)
	board(b, "GarageSign", Vector3.new(10, 2.4, 0.3), origin * CFrame.new(20.2, 12, 11) * CFrame.Angles(0, -math.pi / 2, 0), "GARAGE")
	board(b, "OpenSign", Vector3.new(6, 1.6, 0.3), origin * CFrame.new(20.2, 11.2, -8) * CFrame.Angles(0, -math.pi / 2, 0), "COME IN, WE'RE OPEN")

	-- Roller door. Its closed size and spot are kept so it can roll back down.
	garageDoor = block(b, "GarageDoor", 19.3, 19.7, 0.1, 10, 5, 17, Rustic.Metal, Enum.Material.CorrodedMetal)
	doorClosed = { size = garageDoor.Size, cframe = garageDoor.CFrame }

	-- Showroom: the sales counter, Hank, a rug to stand on, the display truck on its platform, a price board.
	block(b, "Counter", -15, -13, 0, 3.6, -14, -2, Rustic.WoodDark, planks)
	block(b, "CounterTop", -15.3, -12.7, 3.6, 4, -14.3, -1.7, trim, planks)
	clerk(b, Vector3.new(-17, 0.1, -8))
	counter = block(b, "SalesRug", -12, -6, 0.1, 0.2, -12, -4, Rustic.PaintRedDark, Enum.Material.Fabric)
	counter.CanCollide = false
	CollectionService:AddTag(counter, "DealerCounter")
	board(b, "SalesSign", Vector3.new(8, 2, 0.3), origin * CFrame.new(-14, 9, -8) * CFrame.Angles(0, -math.pi / 2, 0), "TRUCK SALES", {
		Enum.NormalId.Front,
		Enum.NormalId.Back,
	})

	local lines = {}
	for _, def in Trucks do
		table.insert(lines, ("%s  $%s%s"):format(def.name, tostring(def.price), def.available and "" or "  (soon)"))
	end
	board(b, "PriceBoard", Vector3.new(16, 8, 0.3), origin * CFrame.new(0, 7, -16.7), "TRUCKS\n" .. table.concat(lines, "\n"), {
		Enum.NormalId.Back,
	})

	local platform = part(b, "Platform", Vector3.new(0.4, 17, 17), origin * CFrame.new(6, 0.3, -7) * CFrame.Angles(0, 0, math.pi / 2), Rustic.StoneDark, Enum.Material.Concrete, Enum.PartType.Cylinder)
	platform.CanCollide = true
	Vehicles.build(Vehicles.get("rusty_pickup"), origin * CFrame.new(6, 0.5, -7) * CFrame.Angles(0, math.rad(-35), 0), b)

	-- Garage: a workbench and a stack of tires.
	block(b, "Workbench", -18, -6, 0, 3, 15, 17, Rustic.WoodDark, planks)
	for i = 0, 2 do
		part(b, "Tire", Vector3.new(0.9, 2.8, 2.8), origin * CFrame.new(15, 0.55 + i * 0.95, 15.5) * CFrame.Angles(0, 0, math.pi / 2), Rustic.Tire, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end

	for _, spot in { Vector3.new(-8, 13.4, -10), Vector3.new(8, 13.4, -10), Vector3.new(-6, 13.4, 11), Vector3.new(8, 13.4, 11) } do
		lamp(b, spot)
	end
end

-- The rest of the line-up waits on the lot with COMING SOON boards.
local function buildLot()
	local lot = Instance.new("Folder")
	lot.Name = "Lot"
	lot.Parent = folder
	local x = 23
	for _, def in Trucks do
		if not def.available then
			local pivot = origin * CFrame.new(x, 0.06, -28) * CFrame.Angles(0, math.pi, 0) -- noses face south
			Vehicles.build(def, pivot, lot)
			board(
				lot,
				"PriceTag",
				Vector3.new(6.5, 2.6, 0.3),
				origin * CFrame.new(x, 1.6, -28 + def.length / 2 + 2.5),
				("%s\n$%s  COMING SOON"):format(def.name:upper(), tostring(def.price)),
				{ Enum.NormalId.Front, Enum.NormalId.Back }
			)
			x += 8.5
		end
	end
end

local function tweenDoor(open)
	local size, cframe = doorClosed.size, doorClosed.cframe
	local goal
	if open then
		local rolled = Vector3.new(size.X, 0.6, size.Z)
		goal = { Size = rolled, CFrame = cframe * CFrame.new(0, size.Y / 2 - 0.3, 0) }
	else
		goal = { Size = size, CFrame = cframe }
	end
	garageDoor.CanCollide = not open
	TweenService:Create(garageDoor, TweenInfo.new(DOOR_SECONDS * 0.9, Enum.EasingStyle.Sine), goal):Play()
end

-- Puts the player in their truck in the garage, opens the door and drives it out onto the lot.
local function deliver(player, def)
	delivering[player] = true
	while garageBusy do
		task.wait(0.5)
	end
	garageBusy = true

	local ok, err = pcall(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or not player.Parent then
			return
		end

		local startCF = origin * CFrame.lookAt(GARAGE_START, GARAGE_START + Vector3.xAxis)
		local model = Vehicles.build(def, startCF, trucksFolder)
		model.Name = player.Name .. "'s " .. def.name
		local seat = Vehicles.makeDrivable(model, player)
		Vehicles.setOwned(player, model)
		seat:Sit(humanoid)
		task.wait(0.3)

		cutsceneRemote:FireClient(player, {
			truck = model,
			camera = world(CAMERA_SPOT),
			door = world(DOOR_SPOT),
			stop = world(LOT_STOP),
			doorSeconds = DOOR_SECONDS,
			driveSeconds = DRIVE_SECONDS,
			title = def.name:upper(),
		})

		tweenDoor(true)
		task.wait(DOOR_SECONDS)

		-- Out through the door: slow roll, pick up speed, ease to a stop on the lot.
		local from, to = GARAGE_START, LOT_STOP
		local started = os.clock()
		while model.Parent do
			local alpha = math.min((os.clock() - started) / DRIVE_SECONDS, 1)
			local t = alpha * alpha * (3 - 2 * alpha)
			local at = from:Lerp(to, t)
			Vehicles.place(model, origin * CFrame.lookAt(at, at + Vector3.xAxis))
			if alpha >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		if model.Parent then
			Vehicles.release(model, player)
		end
		task.wait(0.6)
		tweenDoor(false)
		task.wait(DOOR_SECONDS)
	end)
	if not ok then
		warn("[Needlewood] truck delivery failed: " .. tostring(err))
	end
	garageBusy = false
	delivering[player] = nil
end

local function nearCounter(player)
	local root = Avatar.getRoot(player)
	return root and counter and (root.Position - counter.Position).Magnitude <= COUNTER_REACH
end

-- The panel's Buy / Get my truck button. Returns ok and a message for the panel.
local function onBuy(player, id)
	local def = typeof(id) == "string" and Vehicles.get(id)
	if not def then
		return false, "Unknown truck."
	end
	if not def.available then
		return false, def.name .. " is coming soon."
	end
	if not nearCounter(player) then
		return false, "Step up to the counter first."
	end
	local state = Data.get(player)
	if not state then
		return false, "Still loading your save. Try again in a moment."
	end
	if delivering[player] then
		return false, "Your truck is already on its way."
	end
	if state.carryBale then
		return false, "Put the bale down first."
	end

	local owns = table.find(state.trucks, def.id) ~= nil
	if not owns then
		if state.cash < def.price then
			return false, ("You need $%d more for the %s."):format(def.price - state.cash, def.name)
		end
		state.cash -= def.price
		table.insert(state.trucks, def.id)
		Data.sync(player)
		task.spawn(Data.save, player)
	end
	task.spawn(deliver, player, def)
	if owns then
		return true, "Hank is bringing your truck round."
	end
	return true, ("Sold! The %s is yours. Watch the garage door."):format(def.name)
end

function Dealer.build(worldFolder)
	folder = Instance.new("Folder")
	folder.Name = "Dealer"
	folder.Parent = worldFolder
	trucksFolder = Instance.new("Folder")
	trucksFolder.Name = "Trucks"
	trucksFolder.Parent = worldFolder

	local remotes = Instance.new("Folder")
	remotes.Name = "DealerRemotes"
	local buy = Instance.new("RemoteFunction")
	buy.Name = "Buy"
	buy.Parent = remotes
	cutsceneRemote = Instance.new("RemoteEvent")
	cutsceneRemote.Name = "Cutscene"
	cutsceneRemote.Parent = remotes
	local studioCash = Instance.new("RemoteEvent")
	studioCash.Name = "StudioCash"
	studioCash.Parent = remotes
	remotes.Parent = ReplicatedStorage

	buy.OnServerInvoke = function(player, id)
		local ok, result, message = pcall(onBuy, player, id)
		if not ok then
			warn("[Needlewood] dealer error: " .. tostring(result))
			return false, "Something went wrong at the counter."
		end
		return result, message
	end

	-- Testing only: in Studio the panel has a button that adds cash so the purchase can be tried right away.
	studioCash.OnServerEvent:Connect(function(player)
		if not RunService:IsStudio() then
			return
		end
		local state = Data.get(player)
		if state then
			state.cash += STUDIO_CASH
			Data.sync(player)
			Data.toast(player, ("Studio test cash: +$%d"):format(STUDIO_CASH))
		end
	end)

	Vehicles.init()
	buildBuilding()
	buildLot()
end

return Dealer
