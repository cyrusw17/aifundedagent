--!nonstrict
-- Gloves: which pair each player owns and wears, what carried hay weighs, and how much it slows them down.
-- Numbers live in Config/Gloves. A glove stand by the sell pad sells and swaps them. Owned gloves save in their
-- own DataStore so this never has to touch the main save.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local GloveConfig = require(ReplicatedStorage.Shared.Config.Gloves)
local Data = require(script.Parent.Data)
local GloveLooks = require(script.Parent.GloveLooks)

local Gloves = {}

local byId = {}
for _, def in GloveConfig.Tiers do
	byId[def.id] = def
end
for _, def in GloveConfig.QuestTiers do
	byId[def.id] = def
end

local owned = {} -- player -> { [gloveId] = true }
local worn = {} -- player -> gloveId
local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("NeedlewoodGlovesV1")
	end)
	if ok then
		store = result
	end
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

-- The pair a player has on (bare hands when none).
function Gloves.get(player)
	return byId[worn[player] or "bare"] or GloveConfig.Tiers[1]
end

function Gloves.hayType(id)
	return GloveConfig.HayTypes[id or GloveConfig.DefaultHayType]
		or GloveConfig.HayTypes[GloveConfig.DefaultHayType]
end

-- Weight and tier of one loose piece, from its HayType attribute.
function Gloves.pieceWeight(piece)
	local hay = Gloves.hayType(piece:GetAttribute("HayType"))
	return hay.weight * Config.HayPerPiece, hay.tier
end

-- Weight and tier of a whole bale.
function Gloves.baleWeight(body)
	local hay = Gloves.hayType(body:GetAttribute("HayType"))
	return Config.PiecesPerBale * Config.HayPerPiece * hay.weight * GloveConfig.BaleWeightFactor, hay.tier
end

-- How many tiers the player's gloves fall short of hay of the given tier.
function Gloves.shortBy(player, hayTier)
	return math.max(0, (hayTier or 0) - Gloves.get(player).tier)
end

function Gloves.carryCapacity(player)
	return Config.CarryCapacity + Gloves.get(player).carryBonus
end

-- Strands per shovel scoop for hay of the given tier.
function Gloves.scoopSize(player, hayTier)
	local base = Config.ShovelPieces + Gloves.get(player).scoopBonus
	if player:GetAttribute("GoldenShovel") then
		base *= 2 -- the Golden Shovel, a quest reward (Quests.luau)
	end
	local short = Gloves.shortBy(player, hayTier)
	return math.max(2, math.floor(base * (1 - GloveConfig.UnderGearedScoop * short) + 0.5))
end

-- Walk speed carrying weight of hay whose hardest tier is hayTier.
function Gloves.walkSpeed(player, baseSpeed, weight, hayTier)
	if weight <= 0 then
		return baseSpeed
	end
	local glove = Gloves.get(player)
	local short = Gloves.shortBy(player, hayTier)
	local slow = weight * GloveConfig.SlowPerWeight * (1 - glove.relief) * (1 + GloveConfig.UnderGearedSlow * short)
	return math.max(GloveConfig.MinWalkSpeed, baseSpeed - slow)
end

local function publish(player)
	local glove = Gloves.get(player)
	player:SetAttribute("GloveName", glove.name)
	player:SetAttribute("GloveTier", glove.tier)
	player:SetAttribute("LoadCapBonus", glove.carryBonus)
	local list = {}
	for id in owned[player] or {} do
		table.insert(list, id)
	end
	player:SetAttribute("GlovesOwned", table.concat(list, ","))
	player:SetAttribute("GloveId", glove.id)
	Gloves.changed(player)
end

-- Set by Avatar so walk speed updates the moment gloves change.
Gloves.changed = function(_player) end

local function save(player)
	if not store or not owned[player] then
		return
	end
	local list = {}
	for id in owned[player] do
		table.insert(list, id)
	end
	pcall(function()
		store:SetAsync(keyFor(player), { owned = list, worn = worn[player] })
	end)
end

local function load(player)
	owned[player] = { bare = true }
	worn[player] = "bare"
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok and typeof(saved) == "table" then
			for _, id in (typeof(saved.owned) == "table" and saved.owned or {}) do
				if byId[id] then
					owned[player][id] = true
				end
			end
			if byId[saved.worn] and owned[player][saved.worn] then
				worn[player] = saved.worn
			end
		end
	end
	publish(player)
end

-- Buy a pair if needed, then put it on.
function Gloves.buyOrWear(player, id)
	local def = byId[id]
	local state = Data.get(player)
	if not def or not state or not owned[player] then
		return
	end
	if not owned[player][id] then
		if def.quest then
			return -- quest gloves are earned (Gloves.grant), never bought
		end
		if state.cash < def.price then
			Data.toast(player, ("%s cost $%d. You have $%d."):format(def.name, def.price, state.cash))
			return
		end
		state.cash -= def.price
		owned[player][id] = true
		Data.sync(player)
		Data.toast(player, ("Bought %s. Heavier hay slows you less and you scoop more."):format(def.name))
	elseif worn[player] == id then
		return
	else
		Data.toast(player, ("Put on your %s."):format(def.name))
	end
	worn[player] = id
	publish(player)
	save(player)
end

-- Gives a player a pair for free (quest rewards). Waits for their gloves to load. Safe to call again.
function Gloves.grant(player, id)
	if not byId[id] then
		return
	end
	local started = os.clock()
	while not owned[player] and player.Parent and os.clock() - started < 30 do
		task.wait(0.2)
	end
	if not owned[player] or owned[player][id] then
		return
	end
	owned[player][id] = true
	publish(player)
	save(player)
end

function Gloves.owns(player, id)
	return owned[player] ~= nil and owned[player][id] == true
end

-- A simple glove for the stand until the Blender gloves are in: a palm block and four finger stubs.
local function placeholderGlove(def, cframe, parent)
	local color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	local model = Instance.new("Model")
	model.Name = def.id
	local function part(name, size, offset)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cframe * offset
		p.Color = color
		p.Material = Enum.Material.Fabric
		p.Anchored = true
		p.CanCollide = false
		p.Parent = model
		return p
	end
	local palm = part("Palm", Vector3.new(0.7, 0.25, 0.8), CFrame.new())
	for i = 0, 3 do
		part("Finger" .. i, Vector3.new(0.14, 0.18, 0.45), CFrame.new(-0.26 + i * 0.17, 0, -0.6))
	end
	part("Thumb", Vector3.new(0.14, 0.18, 0.4), CFrame.new(0.42, 0, -0.15) * CFrame.Angles(0, math.rad(-35), 0))
	model.PrimaryPart = palm
	model.Parent = parent
	return palm
end

-- The glove stand: a rustic table with one pair per tier. Each pair has its own Buy / Wear button.
function Gloves.buildStand(parent, cframe)
	local stand = Instance.new("Model")
	stand.Name = "GloveStand"
	stand.Parent = parent

	local count = #GloveConfig.Tiers - 1 -- bare hands are not on the table
	local length = count * 1.6 + 1
	local top = Instance.new("Part")
	top.Name = "Table"
	top.Size = Vector3.new(2.6, 0.4, length)
	top.CFrame = cframe * CFrame.new(0, 2.8, 0)
	top.Color = Color3.fromRGB(128, 105, 77)
	top.Material = Enum.Material.WoodPlanks
	top.Anchored = true
	top.Parent = stand
	for _, z in { -length / 2 + 0.4, length / 2 - 0.4 } do
		local leg = Instance.new("Part")
		leg.Size = Vector3.new(2.2, 2.6, 0.4)
		leg.CFrame = cframe * CFrame.new(0, 1.3, z)
		leg.Color = Color3.fromRGB(92, 74, 54)
		leg.Material = Enum.Material.Wood
		leg.Anchored = true
		leg.Parent = stand
	end

	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(200, 40)
	sign.StudsOffset = Vector3.new(0, 3, 0)
	sign.MaxDistance = 60
	sign.Parent = top
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "GLOVES"
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = sign

	local slot = 0
	for _, def in GloveConfig.Tiers do
		if def.price > 0 then
			local z = -length / 2 + 1 + slot * 1.6
			slot += 1
			local palm = placeholderGlove(def, cframe * CFrame.new(0, 3.15, z), stand)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "GlovePrompt"
			prompt.ObjectText = ("%s (tier %d)"):format(def.name, def.tier)
			prompt.ActionText = ("Buy $%d"):format(def.price)
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 7
			prompt.RequiresLineOfSight = false
			prompt.ClickablePrompt = true
			prompt:SetAttribute("GloveId", def.id)
			prompt:SetAttribute("Price", def.price)
			prompt.Parent = palm
			prompt.Triggered:Connect(function(player)
				Gloves.buyOrWear(player, def.id)
			end)
		end
	end
	GloveLooks.dressStand(stand) -- the Rustic glove meshes, when imported
	return stand
end

function Gloves.init()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		owned[player] = nil
		worn[player] = nil
	end)
	game:BindToClose(function()
		for player in owned do
			save(player)
		end
	end)
end

return Gloves
