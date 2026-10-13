--!nonstrict
-- The wheelbarrow: bought once at its stand by the sell pad (Prices.Wheelbarrow), then kept in the save slot's gear
-- and handed out as a tool. With it out, a barrow rolls in front of you. Click a bale to load it (up to
-- Config.WheelbarrowBales, stacked), click a truck or trailer to tip the load into its bed, or anywhere else to set it
-- down in front of you. A loaded barrow slows you a little (Config.WheelbarrowLoadFactor of the bales' weight).
-- Putting the barrow away sets its load down.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Prices = require(ReplicatedStorage.Shared.Config.Prices)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Avatar = require(script.Parent.Avatar)
local Bales = require(script.Parent.Bales)

local Wheelbarrow = {}

local GEAR_ID = "wheelbarrow"
local TOOL_NAME = "Wheelbarrow"
local WOOD = Color3.fromRGB(128, 105, 77)
local METAL = Color3.fromRGB(107, 94, 84)
local TRAY = CFrame.new(0, -2.2, -4) -- the tray floor's center, from the player's root
local BALE_SIZE = Vector3.new(4.6, 2.6, 3.2)

local barrows = {} -- player -> the barrow model while the tool is out
local currentAim = nil -- set by init: function(player, root) -> aim or nil

local function owns(player)
	local state = Data.get(player)
	return state ~= nil and table.find(state.gear or {}, GEAR_ID) ~= nil
end

local function makePart(model, name, size, cframe, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Shape = shape or Enum.PartType.Block
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = model
	return p
end

-- The barrow, welded in front of the player's root: a tray with low sides, a wheel at the front, two handles back to
-- the hands. Parented to the character so it moves (and is cleaned up) with it.
local function buildBarrow(root)
	local model = Instance.new("Model")
	model.Name = "Barrow"
	local base = root.CFrame * TRAY
	local floor = makePart(model, "Tray", Vector3.new(5, 0.25, 3.6), base, METAL, Enum.Material.Metal)
	makePart(model, "SideL", Vector3.new(0.2, 0.8, 3.6), base * CFrame.new(-2.5, 0.4, 0), METAL, Enum.Material.Metal)
	makePart(model, "SideR", Vector3.new(0.2, 0.8, 3.6), base * CFrame.new(2.5, 0.4, 0), METAL, Enum.Material.Metal)
	makePart(model, "Front", Vector3.new(5, 0.8, 0.2), base * CFrame.new(0, 0.4, -1.8), METAL, Enum.Material.Metal)
	makePart(
		model,
		"Wheel",
		Vector3.new(0.4, 1.4, 1.4),
		base * CFrame.new(0, -0.55, -2.2),
		Color3.fromRGB(60, 52, 44),
		Enum.Material.Fabric,
		Enum.PartType.Cylinder
	)
	for _, x in { -1, 1 } do
		makePart(model, "Handle", Vector3.new(0.2, 0.2, 3.2), base * CFrame.new(x * 1.2, 0.9, 2.8) * CFrame.Angles(math.rad(12), 0, 0), WOOD, Enum.Material.Wood)
	end
	for _, p in model:GetChildren() do
		local weld = Instance.new("Weld")
		weld.Part0 = root
		weld.Part1 = p
		weld.C0 = root.CFrame:ToObjectSpace(p.CFrame)
		weld.Parent = p
	end
	model.PrimaryPart = floor
	model.Parent = root.Parent
	return model
end

-- Where the nth bale (1-based) sits: stacked on the tray.
local function slot(n)
	return TRAY * CFrame.new(0, 0.125 + BALE_SIZE.Y * (n - 0.5) + 0.05, 0)
end

-- The cargo box of the truck or trailer a part belongs to (Vehicles sets CargoOffset/CargoSize on the model), as
-- its center CFrame and size, or nil.
local function cargoOf(part)
	local node = part
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("CargoOffset") and node.PrimaryPart then
			return node.PrimaryPart.CFrame * node:GetAttribute("CargoOffset"), node:GetAttribute("CargoSize")
		end
		node = node.Parent
	end
	return nil
end

-- Tips the whole load into a truck bed in one go: the bales drop in side by side, loose, and settle with physics.
local function tipInto(player, box, size)
	local state = Data.get(player)
	local load = state and state.barrow
	if not load or #load == 0 then
		return 0
	end
	state.barrow = {}
	-- Lay them flat across the bed from the back of the box, wrapping to a second row (and up a layer) as needed.
	local across = math.max(1, math.floor(size.X / (BALE_SIZE.Z + 0.2)))
	local rows = math.max(1, math.floor(size.Z / (BALE_SIZE.X + 0.2)))
	local floorY = -size.Y / 2 + BALE_SIZE.Y / 2 + 0.3
	for i, b in load do
		local n = i - 1
		local col, row, layer = n % across, math.floor(n / across) % rows, math.floor(n / (across * rows))
		local x = -size.X / 2 + (BALE_SIZE.Z + 0.2) * (col + 0.5)
		local z = size.Z / 2 - (BALE_SIZE.X + 0.2) * (row + 0.5)
		local y = floorY + layer * (BALE_SIZE.Y + 0.1)
		Bales.releaseAt(b, box * CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0))
	end
	Avatar.refreshSpeed(player)
	return #load
end

local function unloadAll(player)
	local state = Data.get(player)
	local load = state and state.barrow
	if not load or #load == 0 then
		return 0
	end
	state.barrow = {}
	local root = Avatar.getRoot(player)
	-- Top bale first, so each one lands on the ground in front and the next stacks on it.
	for i = #load, 1, -1 do
		Bales.release(load[i], root)
	end
	Avatar.refreshSpeed(player)
	return #load
end

-- Loads a bale into the player's barrow (it must be out and have room). Returns true if it went in.
function Wheelbarrow.load(player, bale)
	local state = Data.get(player)
	local root = Avatar.getRoot(player)
	if not state or not root or not barrows[player] or bale.carriedBy then
		return false
	end
	state.barrow = state.barrow or {}
	if #state.barrow >= Config.WheelbarrowBales then
		return false
	end
	if Bales.stow(player, bale, root, slot(#state.barrow + 1)) then
		table.insert(state.barrow, bale)
		Avatar.refreshSpeed(player)
		return true
	end
	return false
end

-- Sets the whole load down in front of the player. Returns how many bales came out.
function Wheelbarrow.unload(player)
	return unloadAll(player)
end

-- True while the player has the barrow out.
function Wheelbarrow.isOut(player)
	return barrows[player] ~= nil
end

local function use(player)
	local state = Data.get(player)
	local root = Avatar.getRoot(player)
	if not state or not root or not barrows[player] then
		return
	end
	state.barrow = state.barrow or {}
	local aim = currentAim and currentAim(player, root)
	local bale = aim and aim.part and Bales.fromPart(aim.part)
	if bale and (bale.body.Position - root.Position).Magnitude > Config.ToolReach then
		bale = nil
	end
	if bale and not bale.carriedBy then
		if not Wheelbarrow.load(player, bale) and #state.barrow >= Config.WheelbarrowBales then
			Data.toast(player, "The barrow is full. Click the ground to set the load down.")
		end
		return
	end
	-- Clicking a truck or trailer close by tips the load straight into its bed.
	if #state.barrow > 0 and aim and aim.part then
		local box, size = cargoOf(aim.part)
		if box and (box.Position - root.Position).Magnitude <= Config.ToolReach + size.Magnitude / 2 then
			tipInto(player, box, size)
			Data.toast(player, "Tipped the load into the bed.")
			return
		end
	end
	if unloadAll(player) == 0 then
		Data.toast(player, "Click a bale to load it into the barrow.")
	end
end

local function makeTool(player)
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = "Click a bale to load it (3 max). Click a truck bed to tip the load in, or the ground to set it down."
	tool.Equipped:Connect(function()
		local root = Avatar.getRoot(player)
		if root and not barrows[player] then
			barrows[player] = buildBarrow(root)
		end
	end)
	tool.Unequipped:Connect(function()
		unloadAll(player)
		if barrows[player] then
			barrows[player]:Destroy()
			barrows[player] = nil
		end
	end)
	tool.Activated:Connect(function()
		use(player)
	end)
	return tool
end

-- Hands the tool over if the player owns a barrow and does not have it yet.
local function give(player)
	if not owns(player) then
		return
	end
	local backpack = player:FindFirstChild("Backpack")
	local character = player.Character
	if not backpack or backpack:FindFirstChild(TOOL_NAME) or (character and character:FindFirstChild(TOOL_NAME)) then
		return
	end
	makeTool(player).Parent = backpack
end

-- Gives the tool to a player who owns a barrow (for after a purchase, or the self-test).
function Wheelbarrow.give(player)
	give(player)
end

local function buy(player)
	local state = Data.get(player)
	if not state then
		Data.toast(player, "Pick a save first.")
		return
	end
	if owns(player) then
		give(player)
		Data.toast(player, "You already own a wheelbarrow. It is in your tools.")
		return
	end
	local ok, why = Bank.charge(player, Prices.Wheelbarrow, "Wheelbarrow")
	if not ok then
		Data.toast(player, why or "Not enough money.")
		return
	end
	state.gear = state.gear or {}
	table.insert(state.gear, GEAR_ID)
	Data.sync(player) -- publishes the "Gear" attribute the goal bar reads
	give(player)
	Data.toast(player, "Bought a wheelbarrow. Hauls 3 bales at a time.")
end

-- A barrow on show with a Buy button.
function Wheelbarrow.buildStand(parent, cframe)
	local model = Instance.new("Model")
	model.Name = "WheelbarrowStand"
	local base = cframe * CFrame.new(0, 1.2, 0)
	local tray = makePart(model, "Tray", Vector3.new(4, 0.25, 3), base, METAL, Enum.Material.Metal)
	makePart(model, "Wheel", Vector3.new(0.4, 1.4, 1.4), base * CFrame.new(0, -0.5, -1.8), Color3.fromRGB(60, 52, 44), Enum.Material.Fabric, Enum.PartType.Cylinder)
	for _, x in { -1, 1 } do
		makePart(model, "Leg", Vector3.new(0.25, 1, 0.25), base * CFrame.new(x * 1.2, -0.6, 1.2), WOOD, Enum.Material.Wood)
		makePart(model, "Handle", Vector3.new(0.2, 0.2, 3), base * CFrame.new(x * 1.2, 0.4, 2.6), WOOD, Enum.Material.Wood)
	end
	for _, p in model:GetChildren() do
		p.Anchored = true
		p.CanQuery = true
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WheelbarrowPrompt"
	prompt.ObjectText = "Wheelbarrow (3 bales)"
	prompt.ActionText = ("Buy $%d"):format(Prices.Wheelbarrow)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = tray
	prompt.Triggered:Connect(buy)
	model.Parent = parent
	return model
end

function Wheelbarrow.init(aimFn)
	currentAim = aimFn
	Data.loaded.Event:Connect(give)
	local function watch(player)
		-- Set the load down while the old character still stands there, before it is gone.
		player.CharacterRemoving:Connect(function()
			unloadAll(player)
			barrows[player] = nil
		end)
		player.CharacterAdded:Connect(function()
			task.wait(1) -- after Avatar has handed out the shovel and rake
			give(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
		task.spawn(give, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		unloadAll(player)
		barrows[player] = nil
	end)
end

return Wheelbarrow
