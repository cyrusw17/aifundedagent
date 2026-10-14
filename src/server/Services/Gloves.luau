--!nonstrict
-- Shovels (this was gloves until Cyrus swapped them on 2026-10-13; the module and ids keep the old names so saves
-- carry over): which shovel each player owns and uses, what carried hay weighs, and how much it slows them down.
-- Numbers live in Config/Gloves. A shovel rack by the sell pad sells and swaps them. Owned and used shovels save
-- with the save slot (Data state.gloves). Gloves bought before that were kept in their own DataStore,
-- NeedlewoodGlovesV1; a used slot with nothing saved yet picks those up once, as the shovels of the same tiers.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local GloveConfig = require(ReplicatedStorage.Shared.Config.Gloves)
local HayMath = require(ReplicatedStorage.Shared.HayMath)
local WorldLabel = require(ReplicatedStorage.Shared.WorldLabel)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)

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
local brokeFirstBale = {} -- player -> true once their first bale has been broken (it always spills a needle)
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

-- The shovel a player uses (the starter Old Shovel when none).
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
	return HayMath.pieceWeight(hay, piece:GetAttribute("Wet") == true, Config), hay.tier
end

-- Weight and tier of a whole bale (a rain-soaked one is heavier).
function Gloves.baleWeight(body)
	local hay = Gloves.hayType(body:GetAttribute("HayType"))
	return HayMath.baleWeight(hay, body:GetAttribute("Wet") == true, Config, GloveConfig), hay.tier
end

-- How many tiers the player's shovel falls short of hay of the given tier.
function Gloves.shortBy(player, hayTier)
	return math.max(0, (hayTier or 0) - Gloves.get(player).tier)
end

function Gloves.carryCapacity(player)
	return Config.CarryCapacity + Gloves.get(player).carryBonus
end

-- Strands per shovel scoop for hay of the given tier.
function Gloves.scoopSize(player, hayTier)
	return HayMath.scoopSize(Gloves.get(player), hayTier, Config, GloveConfig)
end

-- Walk speed using shovel glove (a Config/Gloves tier) carrying weight of hay whose hardest tier is hayTier (HayMath.speed).
function Gloves.speedFor(glove, baseSpeed, weight, hayTier)
	return HayMath.speed(glove, baseSpeed, weight, hayTier, GloveConfig)
end

-- Walk speed for this player carrying weight of hay whose hardest tier is hayTier.
function Gloves.walkSpeed(player, baseSpeed, weight, hayTier)
	return Gloves.speedFor(Gloves.get(player), baseSpeed, weight, hayTier)
end

local function publish(player)
	local glove = Gloves.get(player)
	player:SetAttribute("GloveName", glove.name)
	player:SetAttribute("ShovelName", glove.name) -- the same, under the name the UI should move to
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

-- Set by Avatar so walk speed updates the moment the shovel changes.
Gloves.changed = function(_player) end

-- Copies owned and used shovels into the save slot; Data.luau writes them with the rest of the slot.
local function save(player)
	local state = Data.get(player)
	if not state or not owned[player] then
		return
	end
	local list = {}
	for id in owned[player] do
		table.insert(list, id)
	end
	state.gloves = { owned = list, worn = worn[player], brokeFirstBale = brokeFirstBale[player] }
end

local function legacyGloves(player)
	if not store then
		return nil
	end
	local ok, saved = pcall(function()
		return store:GetAsync(keyFor(player))
	end)
	return ok and typeof(saved) == "table" and saved or nil
end

-- The Old Shovel until a save slot is picked.
local function reset(player)
	owned[player] = nil
	worn[player] = "bare"
	publish(player)
end

-- Runs when a save slot loads (Data.loaded).
local function load(player)
	local state = Data.get(player)
	if not state then
		return
	end
	local saved = state.gloves
	if saved == nil and not state.fresh then
		saved = legacyGloves(player)
	end
	owned[player] = { bare = true }
	worn[player] = "bare"
	brokeFirstBale[player] = nil
	if typeof(saved) == "table" then
		brokeFirstBale[player] = saved.brokeFirstBale == true or nil
		for _, id in (typeof(saved.owned) == "table" and saved.owned or {}) do
			if byId[id] then
				owned[player][id] = true
			end
		end
		if byId[saved.worn] and owned[player][saved.worn] then
			worn[player] = saved.worn
		end
	end
	if not player.Parent then
		return
	end
	save(player)
	publish(player)
end

-- Buy a shovel if needed, then use it.
function Gloves.buyOrWear(player, id)
	local def = byId[id]
	local state = Data.get(player)
	if not def or not state or not owned[player] then
		return
	end
	if not owned[player][id] then
		if def.quest then
			return -- quest shovels are earned (Gloves.grant), never bought
		end
		local paid = Bank.charge(player, def.price, def.name)
		if not paid then
			Data.toast(player, ("%s cost $%d. You have $%d."):format(def.name, def.price, Bank.spendable(state)))
			return
		end
		owned[player][id] = true
		Data.toast(player, ("Bought the %s. Each load carries more hay, and heavy hay slows you less."):format(def.name))
	elseif worn[player] == id then
		return
	else
		Data.toast(player, ("Switched to your %s."):format(def.name))
	end
	worn[player] = id
	publish(player)
	save(player)
end

-- Gives a player a shovel for free (quest rewards). Waits for their save slot's shovels to load. Safe to call again.
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

-- True the first time a player ever breaks a bale, so that bale can promise them a needle. Kept with the gloves
-- record (state.gloves) so it survives leaving.
function Gloves.firstBaleBreak(player)
	if brokeFirstBale[player] or not owned[player] then
		return false
	end
	brokeFirstBale[player] = true
	task.spawn(save, player)
	return true
end

-- For the self-test: read or set the first-bale flag, so a test can check the promised needle and then put the
-- player's real flag back.
function Gloves.firstBaleBroken(player)
	return brokeFirstBale[player] == true
end

function Gloves.setFirstBaleBroken(player, value)
	brokeFirstBale[player] = value == true or nil
	save(player)
end

function Gloves.owns(player, id)
	return owned[player] ~= nil and owned[player][id] == true
end

-- A shovel for the rack in its tier's colors: a wooden shaft, the band and the blade, leaning blade-down. Returns
-- the blade, which carries the Buy / Use button.
local function rackShovel(def, cframe, parent)
	local color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	local okMaterial, material = pcall(function()
		return Enum.Material[def.material]
	end)
	local model = Instance.new("Model")
	model.Name = def.id
	local function part(name, size, offset, partColor, partMaterial)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cframe * offset
		p.Color = partColor
		p.Material = partMaterial
		p.Anchored = true
		p.CanCollide = false
		p.Parent = model
		return p
	end
	local lean = CFrame.Angles(math.rad(-12), 0, 0)
	part("Shaft", Vector3.new(0.22, 3.2, 0.22), lean * CFrame.new(0, 1.9, 0), Color3.fromRGB(128, 105, 77), Enum.Material.Wood)
	part("Band", Vector3.new(0.34, 0.2, 0.34), lean * CFrame.new(0, 0.32, 0), color, okMaterial and material or Enum.Material.Metal)
	local blade = part("Blade", Vector3.new(0.9, 1.1, 0.1), lean * CFrame.new(0, -0.3, 0), color, okMaterial and material or Enum.Material.Metal)
	if def.tier >= 5 then
		local glow = Instance.new("PointLight")
		glow.Color = color:Lerp(Color3.new(1, 1, 1), 0.4)
		glow.Brightness = 0.8
		glow.Range = 5
		glow.Parent = blade
	end
	model.PrimaryPart = blade
	model.Parent = parent
	return blade
end

-- The shovel rack: a rustic rail with one shovel per tier leaning on it, blade down. Each has its own Buy / Use button.
function Gloves.buildStand(parent, cframe)
	local stand = Instance.new("Model")
	stand.Name = "GloveStand" -- kept: the tutorial, the map and the self-tests find the rack by this name
	stand:SetAttribute("Sells", "Shovels")
	stand.Parent = parent

	local count = #GloveConfig.Tiers - 1 -- the starter Old Shovel is not for sale
	local length = count * 1.6 + 1
	local wood, dark = Color3.fromRGB(128, 105, 77), Color3.fromRGB(92, 74, 54)
	local top = Instance.new("Part")
	top.Name = "Table" -- the rail
	top.Size = Vector3.new(0.5, 0.4, length)
	top.CFrame = cframe * CFrame.new(0.9, 3.4, 0)
	top.Color = wood
	top.Material = Enum.Material.WoodPlanks
	top.Anchored = true
	top.Parent = stand
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(2.4, 0.3, length)
	base.CFrame = cframe * CFrame.new(0, 0.15, 0)
	base.Color = dark
	base.Material = Enum.Material.Wood
	base.Anchored = true
	base.Parent = stand
	for _, z in { -length / 2 + 0.2, length / 2 - 0.2 } do
		local post = Instance.new("Part")
		post.Size = Vector3.new(0.4, 3.4, 0.4)
		post.CFrame = cframe * CFrame.new(0.9, 1.7, z)
		post.Color = dark
		post.Material = Enum.Material.Wood
		post.Anchored = true
		post.Parent = stand
	end

	WorldLabel.billboard(top, "SHOVELS", { offset = Vector3.new(0, 3, 0), kind = "status" })

	local slot = 0
	for _, def in GloveConfig.Tiers do
		if def.price > 0 then
			local z = -length / 2 + 1 + slot * 1.6
			slot += 1
			local blade = rackShovel(def, cframe * CFrame.new(0.3, 0.9, z), stand)
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
			prompt.Parent = blade
			prompt.Triggered:Connect(function(player)
				Gloves.buyOrWear(player, def.id)
			end)
		end
	end
	return stand
end

function Gloves.init()
	Players.PlayerAdded:Connect(reset)
	Data.loaded.Event:Connect(load)
	for _, player in Players:GetPlayers() do
		if Data.get(player) then
			task.spawn(load, player)
		else
			task.spawn(reset, player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		worn[player] = nil
		brokeFirstBale[player] = nil
	end)
end

return Gloves
