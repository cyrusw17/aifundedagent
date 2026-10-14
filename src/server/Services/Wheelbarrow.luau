--!nonstrict
-- The wheelbarrow: bought once at its stand by the sell pad (Prices.Wheelbarrow), then kept in the save slot's gear
-- and handed out as a tool. With it out, a barrow rolls in front of you. Click a bale to load it (up to
-- Config.WheelbarrowBales, stacked), click a truck or trailer to tip the load into its bed, or anywhere else to set it
-- down in front of you. A loaded barrow slows you a little (Config.WheelbarrowLoadFactor of the bales' weight).
--
-- Putting the barrow away parks it where it stands (its bales are set down first). Shovel loads poured into a
-- parked barrow (Tools: click it with hay in your arms) fill it, and every Config.PiecesPerBale strands press into a
-- bale that drops out of the front, ready to lift and throw in the truck (Cyrus, 2026-10-13). Taking the tool out
-- again brings the barrow back to you, hay and all. The hay in a barrow is not saved, like a hopper's.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Prices = require(ReplicatedStorage.Shared.Config.Prices)
local ToolGuide = require(ReplicatedStorage.Shared.ToolGuide)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Avatar = require(script.Parent.Avatar)
local Hay = require(script.Parent.Hay)
local Bales = require(script.Parent.Bales)
local HayMath = require(ReplicatedStorage.Shared.HayMath)
local WorldLabel = require(ReplicatedStorage.Shared.WorldLabel)
local Feedback = require(script.Parent.Feedback)

local Wheelbarrow = {}

local GEAR_ID = "wheelbarrow"
local TOOL_NAME = "Wheelbarrow"
local WOOD = Color3.fromRGB(128, 105, 77)
local METAL = Color3.fromRGB(107, 94, 84)
local TRAY = CFrame.new(0, -2.2, -4) -- the tray floor's center, from the player's root
local BALE_SIZE = Vector3.new(4.6, 2.6, 3.2)

local barrows = {} -- player -> the barrow model while the tool is out
local parked = {} -- player -> their barrow standing in the world while the tool is away
local hayIn = {} -- player -> { strands, wet, hayType } poured into their barrow and not yet pressed
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

-- The loose hay showing in a barrow: a mound in the tray that grows toward a bale's worth, and a count above it.
local function showFill(player)
	local model = barrows[player] or parked[player]
	local tray = model and model:FindFirstChild("Tray")
	if not tray then
		return
	end
	local fill = hayIn[player]
	local strands = fill and fill.strands or 0
	local mound = model:FindFirstChild("HayFill")
	if strands <= 0 then
		if mound then
			mound:Destroy()
		end
		local label = tray:FindFirstChild("WorldLabel")
		if label then
			label:Destroy()
		end
		return
	end
	local share = math.clamp(strands / Config.PiecesPerBale, 0, 1)
	if not mound then
		mound = makePart(model, "HayFill", Vector3.one, tray.CFrame, Color3.fromRGB(196, 170, 104), Enum.Material.Fabric)
		local shape = Instance.new("SpecialMesh")
		shape.MeshType = Enum.MeshType.Sphere
		shape.Parent = mound
		mound.CanQuery = true
		local weld = Instance.new("Weld")
		weld.Part0 = tray
		weld.Part1 = mound
		weld.Parent = mound
	end
	local look = Hay.look(fill.hayType)
	local c = look.colors[1]
	mound.Color = Color3.fromRGB(c[1], c[2], c[3])
	local height = 0.3 + share * 1.4
	mound.Size = Vector3.new(4.6, height, 3.2)
	local weld = mound:FindFirstChildOfClass("Weld")
	if weld then
		weld.C0 = CFrame.new(0, height / 2, 0)
	end
	mound.CFrame = tray.CFrame * CFrame.new(0, height / 2, 0)
	local text = ("Hay %d / %d"):format(strands, Config.PiecesPerBale)
	local label = tray:FindFirstChild("WorldLabel")
	local textLabel = label and label:FindFirstChild("Text")
	if textLabel then
		textLabel.Text = text
	else
		WorldLabel.billboard(tray, text, { offset = Vector3.new(0, 3.5, 0), kind = "status" })
	end
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

-- Parks the rolling barrow where it stands: unwelded from the player, set level on the ground and anchored, so a
-- shovel can fill it (Wheelbarrow.pourIn). Its bales are set down first.
local function park(player)
	local model = barrows[player]
	barrows[player] = nil
	if not model or not model.Parent then
		return
	end
	local tray = model:FindFirstChild("Tray")
	if not tray then
		model:Destroy()
		return
	end
	local look = tray.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, -1)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model, player.Character }
	local hit = workspace:Raycast(tray.Position + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
	local groundY = hit and hit.Position.Y or tray.Position.Y - 1.25
	-- The wheel (1.4 across) sits 0.55 under the tray floor, so the floor rides 1.25 over the ground.
	local level = CFrame.lookAt(Vector3.new(tray.Position.X, groundY + 1.25, tray.Position.Z), Vector3.new(tray.Position.X, groundY + 1.25, tray.Position.Z) + flat)
	local offsets = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			offsets[p] = tray.CFrame:ToObjectSpace(p.CFrame)
		end
	end
	for p, offset in offsets do
		for _, weld in p:GetChildren() do
			if weld:IsA("Weld") and not (weld.Part0 and weld.Part0:IsDescendantOf(model)) then
				weld:Destroy() -- the welds to the player's root; the hay mound's weld to the tray stays
			end
		end
		p.Anchored = true
		p.CanQuery = true -- so a shovel click can find it
		p.CanCollide = p.Name ~= "Handle" and p.Name ~= "HayFill"
		p.CFrame = level * offset
	end
	model.Name = "ParkedBarrow"
	model:SetAttribute("BarrowOwner", player.UserId)
	model.Parent = workspace
	parked[player] = model
	showFill(player)
end

-- Takes the parked barrow away (the rolling one is built fresh in front of the player).
local function unpark(player)
	if parked[player] then
		parked[player]:Destroy()
		parked[player] = nil
	end
end

-- The player whose barrow part belongs to (a parked one, or one being rolled), or nil.
function Wheelbarrow.ownerOf(part)
	local node = part
	while node and node ~= workspace do
		if node:IsA("Model") and (node.Name == "ParkedBarrow" or node.Name == "Barrow") then
			for player, model in parked do
				if model == node then
					return player
				end
			end
			for player, model in barrows do
				if model == node then
					return player
				end
			end
			return nil
		end
		node = node.Parent
	end
	return nil
end

-- Presses a bale's worth of the barrow's hay into a bale, dropped out of the front of the barrow onto the ground.
local function press(owner)
	local fill = hayIn[owner]
	local model = parked[owner] or barrows[owner]
	local tray = model and model:FindFirstChild("Tray")
	if not fill or fill.strands < Config.PiecesPerBale or not tray then
		return nil
	end
	local wetShare = fill.strands > 0 and fill.wet / fill.strands or 0
	fill.wet = math.max(0, fill.wet - math.floor(wetShare * Config.PiecesPerBale + 0.5))
	fill.strands -= Config.PiecesPerBale
	local hayType = fill.hayType
	if fill.strands <= 0 then
		hayIn[owner] = nil
	end
	-- Out over the wheel at the front, a little up, so it tumbles off onto the ground.
	local at = tray.CFrame * CFrame.new(0, BALE_SIZE.Y / 2 + 0.6, -3.6)
	local b = Bales.spawn(at.Position, false, false, hayType)
	b.ownerId = owner.UserId
	b.body.CFrame = at * CFrame.Angles(0, math.pi / 2, 0)
	b.body.Anchored = false
	pcall(function()
		b.body:SetNetworkOwner(nil)
	end)
	if wetShare >= 0.5 then
		Bales.wet(b)
	end
	Feedback.play("BaleSetDown", b.body)
	return b
end

-- Pours all the hay in player's arms into the barrow part belongs to (theirs or a friend's; the bales it presses
-- belong to the barrow's owner). Returns how many strands went in, or 0.
function Wheelbarrow.pourIn(player, part)
	local owner = Wheelbarrow.ownerOf(part)
	local state = Data.get(player)
	if not owner or not state or (state.loadHay or 0) < Config.HayPerPiece then
		return 0
	end
	local held = math.floor(state.loadHay / Config.HayPerPiece)
	local split = HayMath.pourSplit({
		hay = state.loadHay,
		sorted = state.loadSortedHay,
		needles = state.loadNeedles,
		wet = state.loadWetHay,
	}, held, Config.HayPerPiece)
	local n = split.n
	if n <= 0 then
		return 0
	end
	local hayType = state.loadType or "meadow"
	-- The needles rolled when it was scooped go back with the hay: the bale it becomes rolls its own when broken.
	state.loadHay, state.loadSortedHay, state.loadNeedles, state.loadWeight, state.loadTier = 0, 0, 0, 0, 0
	state.loadWetHay = 0
	state.loadType = nil
	Data.sync(player)
	Avatar.refreshSpeed(player)

	local fill = hayIn[owner]
	if not fill then
		fill = { strands = 0, wet = 0, hayType = hayType }
		hayIn[owner] = fill
	end
	-- A barrow presses one kind of hay at a time; the kind poured in first wins (it is the bale's hay type).
	fill.strands += n
	fill.wet += split.wetOut
	local made = 0
	while press(owner) do
		made += 1
	end
	showFill(owner)
	local root = Avatar.getRoot(player)
	if root then
		Feedback.play("Scoop", root, 0.8)
	end
	if made > 0 then
		Data.toast(player, made == 1 and "The barrow is full and pressed a bale. Lift it (F) and throw it in the truck."
			or ("The barrow pressed %d bales. Lift them (F) and throw them in the truck."):format(made))
	else
		Data.toast(player, ("Barrow: %d / %d hay for the next bale."):format(hayIn[owner] and hayIn[owner].strands or 0, Config.PiecesPerBale))
	end
	return n
end

-- How many strands are in player's barrow waiting to be pressed (for the self-tests and the UI).
function Wheelbarrow.hayIn(player)
	return hayIn[player] and hayIn[player].strands or 0
end

-- The parked barrow model of player, or nil (for the self-tests).
function Wheelbarrow.parkedOf(player)
	return parked[player]
end

-- The cargo box (CFrame at its middle, and its size) of the truck or trailer part belongs to, or nil.
Wheelbarrow.cargoOf = cargoOf

-- Tips the barrow's load into the cargo box of the truck or trailer that part belongs to. Returns how many went in.
function Wheelbarrow.tipInto(player, part)
	local box, size = cargoOf(part)
	if not box then
		return 0
	end
	return tipInto(player, box, size)
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
		Data.toast(player, "Click a bale to load it, or put the barrow away to park it and fill it with your shovel.")
	end
end

local function makeTool(player)
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = ToolGuide.tool("Wheelbarrow")
	tool.Equipped:Connect(function()
		local root = Avatar.getRoot(player)
		if root and not barrows[player] then
			unpark(player) -- the parked barrow comes back to you, with its hay
			barrows[player] = buildBarrow(root)
			showFill(player)
		end
	end)
	tool.Unequipped:Connect(function()
		unloadAll(player)
		park(player)
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
	Data.toast(player, ("Bought a wheelbarrow. Park it, fill it with %d hay from your shovel and it presses a bale."):format(Config.PiecesPerBale))
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
	prompt.ObjectText = ("Wheelbarrow (%d bales)"):format(Config.WheelbarrowBales)
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
			park(player) -- it stays where it was, so a respawn does not lose the hay in it
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
		unpark(player)
		hayIn[player] = nil
	end)
end

return Wheelbarrow
