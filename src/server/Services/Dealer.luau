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
local WorldLabel = require(Shared.WorldLabel)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)
local Vehicles = require(script.Parent.Vehicles)

local Dealer = {}

local DOOR_SECONDS = 1.6 -- roller door going up
local DRIVE_SECONDS = 5 -- garage to the lot
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
local GARAGE_START = Vector3.new(-10, 0.15, 14)
local LOT_STOP = Vector3.new(50, 0.15, 14)
local CAMERA_SPOT = Vector3.new(66, 12, 46)
local DOOR_SPOT = Vector3.new(30, 6, 14)

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
	WorldLabel.surface(p, text, faces)
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
	WorldLabel.billboard(head, "Hank, truck sales", { offset = Vector3.new(0, 2, 0), kind = "tag" })
	model.Parent = parent
end

-- Layout, in studs from the dealer's center (+X is the front, facing base camp):
--   showroom  x -30..30, z -26..2   front door at z -9..-1, the display truck along the north wall
--   garage    x -30..30, z 2..26    roller door at z 5..23, 13 tall
--   lot       x 30..88,  z -66..34  coming-soon trucks in a row at z -44
-- The walk from the front door to the counter runs straight west along z -5, clear of the display truck.
local function buildBuilding()
	local b = Instance.new("Model")
	b.Name = "HomesteadMotors"
	b.Parent = folder
	local wall, trim = Rustic.PaintRed, Rustic.PaintCream
	local planks = Enum.Material.WoodPlanks
	local H = 18 -- wall height

	-- Floors: wood in the showroom, concrete in the garage, and a concrete lot out front.
	block(b, "ShowroomFloor", -30, 30, -1, 0.1, -26, 2, Rustic.Wood, planks)
	block(b, "GarageFloor", -30, 30, -1, 0.1, 2, 26, Rustic.Stone, Enum.Material.Concrete)
	block(b, "Lot", 30, 88, -1, 0.06, -66, 34, Rustic.StoneDark, Enum.Material.Concrete)

	-- Outer walls. The east (front) wall has a big window, the shop door and the garage door.
	block(b, "WestWall", -30, -29, 0, H, -26, 26, wall, planks)
	block(b, "NorthWall", -30, 30, 0, H, -26, -25, wall, planks)
	block(b, "SouthWall", -30, 30, 0, H, 25, 26, wall, planks)
	block(b, "FrontCorner", 29, 30, 0, H, -26, -24, trim, planks)
	block(b, "WindowSill", 29, 30, 0, 3, -24, -11, wall, planks)
	glassBlock(b, 29.3, 29.7, 3, 13, -24, -11)
	block(b, "WindowHeader", 29, 30, 13, H, -24, -11, wall, planks)
	block(b, "DoorPillar", 29, 30, 0, H, -11, -9, trim, planks)
	block(b, "DoorHeader", 29, 30, 12, H, -9, -1, trim, planks)
	block(b, "FrontPillar", 29, 30, 0, H, -1, 5, wall, planks)
	block(b, "GarageHeader", 29, 30, 13, H, 5, 23, trim, planks)
	block(b, "CornerPillar", 29, 30, 0, H, 23, 26, trim, planks)

	-- Inside wall between the showroom and the garage, with a doorway and a window to see the trucks.
	block(b, "DividerA", -29, -28, 0, H, 1.5, 2.5, wall, planks)
	block(b, "DividerHeader", -28, -20, 10, H, 1.5, 2.5, wall, planks)
	block(b, "DividerB", -20, -4, 0, H, 1.5, 2.5, wall, planks)
	block(b, "DividerSill", -4, 16, 0, 3, 1.5, 2.5, wall, planks)
	glassBlock(b, -4, 16, 3, 11, 1.8, 2.2)
	block(b, "DividerTop", -4, 16, 11, H, 1.5, 2.5, wall, planks)
	block(b, "DividerC", 16, 29, 0, H, 1.5, 2.5, wall, planks)

	-- Weathered tin roof and the false front with the shop name.
	block(b, "Roof", -31, 31, H, H + 0.8, -27, 27, Rustic.Metal, Enum.Material.Metal)
	board(
		b,
		"ShopSign",
		Vector3.new(30, 6, 0.6),
		origin * CFrame.new(30.4, H + 3.4, -12) * CFrame.Angles(0, -math.pi / 2, 0),
		"HOMESTEAD MOTORS",
		{ Enum.NormalId.Front }
	)
	board(b, "GarageSign", Vector3.new(14, 3, 0.3), origin * CFrame.new(30.2, 15.5, 14) * CFrame.Angles(0, -math.pi / 2, 0), "GARAGE")
	board(b, "OpenSign", Vector3.new(7, 1.8, 0.3), origin * CFrame.new(30.2, 13.6, -5) * CFrame.Angles(0, -math.pi / 2, 0), "COME IN, WE'RE OPEN")

	-- Roller door. Its closed size and spot are kept so it can roll back down.
	garageDoor = block(b, "GarageDoor", 29.3, 29.7, 0.1, 13, 5, 23, Rustic.Metal, Enum.Material.Metal)
	doorClosed = { size = garageDoor.Size, cframe = garageDoor.CFrame }

	-- Showroom: the sales counter by the west wall with Hank behind it, a rug to stand on in front.
	block(b, "Counter", -24, -21, 0, 3.6, -13, 1, Rustic.WoodDark, planks)
	block(b, "CounterTop", -24.3, -20.7, 3.6, 4, -13.3, 1.3, trim, planks)
	clerk(b, Vector3.new(-26.5, 0.1, -5))
	counter = block(b, "SalesRug", -20, -12, 0.1, 0.2, -9, -1, Rustic.PaintRedDark, Enum.Material.Fabric)
	counter.CanCollide = false
	CollectionService:AddTag(counter, "DealerCounter")
	board(b, "SalesSign", Vector3.new(10, 2.4, 0.3), origin * CFrame.new(-22.5, 10, -5) * CFrame.Angles(0, -math.pi / 2, 0), "TRUCK SALES", {
		Enum.NormalId.Front,
		Enum.NormalId.Back,
	})

	-- The display truck on a low stage along the north wall, nose to the front window, with prices above it.
	local lines = {}
	for _, def in Trucks do
		table.insert(lines, ("%s  $%s%s"):format(def.name, tostring(def.price), def.available and "" or "  (soon)"))
	end
	board(b, "PriceBoard", Vector3.new(22, 5.5, 0.3), origin * CFrame.new(4, 13.6, -24.7), "TRUCKS\n" .. table.concat(lines, "\n"), {
		Enum.NormalId.Back,
	})
	block(b, "Stage", -10, 24, 0, 0.5, -25, -11, Rustic.StoneDark, Enum.Material.Concrete)
	Vehicles.build(Vehicles.get("rusty_pickup"), origin * CFrame.new(7, 0.5, -18) * CFrame.Angles(0, -math.pi / 2, 0), b)

	-- Garage: a workbench along the back and a stack of tires in the corner.
	block(b, "Workbench", -28, -12, 0, 3, 23, 25, Rustic.WoodDark, planks)
	for i = 0, 2 do
		part(b, "Tire", Vector3.new(0.9, 2.8, 2.8), origin * CFrame.new(-27, 0.55 + i * 0.95, 5) * CFrame.Angles(0, 0, math.pi / 2), Rustic.Tire, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end

	for _, spot in { Vector3.new(-14, H - 0.6, -12), Vector3.new(14, H - 0.6, -12), Vector3.new(-10, H - 0.6, 14), Vector3.new(14, H - 0.6, 14) } do
		lamp(b, spot)
	end
end

-- The rest of the line-up waits on the lot with COMING SOON boards.
local function buildLot()
	local lot = Instance.new("Folder")
	lot.Name = "Lot"
	lot.Parent = folder
	local x = 38
	for _, def in Trucks do
		if not def.available then
			local pivot = origin * CFrame.new(x, 0.06, -44) * CFrame.Angles(0, math.pi, 0) -- noses face south
			Vehicles.build(def, pivot, lot)
			board(
				lot,
				"PriceTag",
				Vector3.new(9, 3.2, 0.3),
				origin * CFrame.new(x, 1.9, -44 + def.length / 2 + 3),
				("%s\n$%s  COMING SOON"):format(def.name:upper(), tostring(def.price)),
				{ Enum.NormalId.Front, Enum.NormalId.Back }
			)
			x += 14
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

	Vehicles.init(trucksFolder)
	buildBuilding()
	buildLot()
end

return Dealer
