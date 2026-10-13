--!nonstrict
-- Quests, rituals, daily bounties and mystery items. Definitions live in Config/Quests.luau; this service tracks each
-- player's steps (saved in their save slot as `quests`), builds the places quests send you, and hands out rewards.
-- The client only shows the quest log (src/client/Quests.client.luau); every step is decided here.
--
-- Other services report what players do through Events.luau. Ownership steps (truck, plot, gloves, sorter), visits
-- and bale patterns are checked here on a short loop. Quest gear is never sold, only earned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestConfig = require(Shared.Config.Quests)
local GloveConfig = require(Shared.Config.Gloves)
local NeedleTypes = require(Shared.Config.Needles)
local LandConfig = require(Shared.Config.Land)
local Rustic = require(Shared.Config.Rustic)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Events = require(script.Parent.Events)
local DayNight = require(script.Parent.DayNight)
local Bales = require(script.Parent.Bales)
local Needle = require(script.Parent.Needle)
local Gloves = require(script.Parent.Gloves)
local Vehicles = require(script.Parent.Vehicles)

local Quests = {}

local rng = Random.new()
local folder = nil -- Workspace.Needlewood.Quests
local spots = {} -- spotId -> { def, model, base, position, pads }
local reachable = { Meadow = true } -- regions with a built place (Meadow, plus any region a QuestAnchor names)
local wanderIndex = 1
local players = {} -- player -> { lifted = bool, lastPublish }
local changedRemote = nil -- RemoteEvent: tells a client its quest log changed

local questById = {}
for i, q in QuestConfig.List do
	q.order = i
	questById[q.id] = q
end

local pieceKinds = {}
for _, def in LandConfig.Pieces do
	pieceKinds[def.id] = def.kind
end

-- Config/Needles names some regions differently from the map ("Desert" for Desert Dunes).
local REGION_ALIAS = { ["Desert Dunes"] = "Desert" }

local function needleForHay(hayType)
	local hay = GloveConfig.HayTypes[hayType or "meadow"]
	for _, n in NeedleTypes do
		if hay and n.map == hay.map then
			return n.id
		end
	end
	return NeedleTypes[1].id
end

local function isReachable(region)
	return region == nil or reachable[region] == true
end

-- Needle types whose region can be reached right now (the alien offering asks for these).
local function reachableNeedles()
	local list = {}
	for _, n in NeedleTypes do
		for region in reachable do
			if n.map == region or n.map == REGION_ALIAS[region] then
				table.insert(list, n)
				break
			end
		end
	end
	return list
end

local function needleName(id)
	for _, n in NeedleTypes do
		if n.id == id then
			return n.name
		end
	end
	return id
end

-- Saved quest state --------------------------------------------------------------------------------------------------

local function questsOf(player)
	local s = Data.get(player)
	if not s then
		return nil, nil
	end
	local q = s.quests
	if typeof(q) ~= "table" then
		q = {}
		s.quests = q
	end
	q.active = typeof(q.active) == "table" and q.active or {}
	q.done = typeof(q.done) == "table" and q.done or {}
	q.earned = typeof(q.earned) == "table" and q.earned or {}
	q.bounty = typeof(q.bounty) == "table" and q.bounty or {}
	return q, s
end

-- The active quest ids, copied, so steps can finish (and start new quests) while we go through them.
local function activeIds(q)
	local ids = {}
	for id in q.active do
		table.insert(ids, id)
	end
	return ids
end

local function today()
	return os.time() // 86400
end

local function todaysBounties()
	local day = today()
	local pool = table.clone(QuestConfig.Bounties)
	local r = Random.new(day * 7919 + 13)
	for i = #pool, 2, -1 do
		local j = r:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local list = {}
	for i = 1, math.min(QuestConfig.BountiesPerDay, #pool) do
		list[i] = pool[i]
	end
	return list, day
end

local function bountyState(q)
	local _, day = todaysBounties()
	if q.bounty.day ~= day then
		q.bounty = { day = day, n = {}, done = {} }
	end
	q.bounty.n = typeof(q.bounty.n) == "table" and q.bounty.n or {}
	q.bounty.done = typeof(q.bounty.done) == "table" and q.bounty.done or {}
	return q.bounty
end

local function currentStep(q, id)
	local entry = id and q.active[id]
	local def = id and questById[id]
	if not entry or not def then
		return nil, nil, nil
	end
	entry.seen = typeof(entry.seen) == "table" and entry.seen or {}
	entry.step = typeof(entry.step) == "number" and entry.step or 1
	return def.steps[entry.step], entry, def
end

local function waitingOnMap(def)
	return def.region ~= "Meadow" and not isReachable(def.region)
end

local function requirementsMet(q, def)
	for _, need in def.requires or {} do
		if not q.done[need] then
			return false
		end
	end
	return true
end

-- Starts every quest whose requirements are done. Returns true if any started.
local function unlockQuests(q)
	local started = false
	for _, def in QuestConfig.List do
		if not q.done[def.id] and not q.active[def.id] and requirementsMet(q, def) and not waitingOnMap(def) then
			q.active[def.id] = { step = 1, n = 0, seen = {} }
			started = true
		end
	end
	return started
end

-- Rewards and perks --------------------------------------------------------------------------------------------------

local function applyPerks(player, q)
	for id, reward in QuestConfig.Rewards do
		if reward.perk then
			player:SetAttribute(reward.perk, q.earned[id] == true or nil)
		end
	end
	for id, reward in QuestConfig.Rewards do
		if reward.kind == "gloves" and q.earned[id] then
			task.spawn(Gloves.grant, player, id)
		end
	end
end

local function rewardText(reward)
	local parts = {}
	if reward.cash then
		table.insert(parts, ("$%d"):format(reward.cash))
	end
	for _, key in { "gear", "gloves", "truck", "relic", "unlock" } do
		local id = reward[key]
		if id and QuestConfig.Rewards[id] then
			table.insert(parts, QuestConfig.Rewards[id].name)
		end
	end
	return table.concat(parts, ", ")
end

local function giveReward(player, q, reward, name)
	if reward.cash then
		Bank.earn(player, reward.cash, "Quest: " .. name)
	end
	for _, key in { "gear", "gloves", "truck", "relic", "unlock" } do
		local id = reward[key]
		if id then
			q.earned[id] = true
		end
	end
	applyPerks(player, q)
end

local publish -- forward declaration

local function complete(player, q, def)
	q.active[def.id] = nil
	q.done[def.id] = true
	giveReward(player, q, def.reward or {}, def.name)
	local got = rewardText(def.reward or {})
	Data.toast(
		player,
		("%s %s complete! %s"):format(
			def.ritual and "Ritual" or "Quest",
			def.name,
			got ~= "" and ("You got: " .. got) or ""
		)
	)
	if def.ritual then
		for _, other in Players:GetPlayers() do
			if other ~= player then
				Data.toast(other, ('%s finished the ritual "%s".'):format(player.DisplayName, def.name))
			end
		end
	end
	unlockQuests(q)
	task.spawn(Data.save, player)
end

local function advance(player, id)
	local q = questsOf(player)
	if not q then
		return
	end
	local step, entry, def = currentStep(q, id)
	if not step then
		return
	end
	entry.step += 1
	entry.n = 0
	entry.seen = {}
	entry.pity = nil
	entry.last = nil
	if entry.step > #def.steps then
		complete(player, q, def)
	else
		Data.toast(player, ("%s: %s"):format(def.name, def.steps[entry.step].text))
	end
	publish(player)
end

-- Adds to a counted step and moves on when it is full.
local function bump(player, id, amount)
	local q = questsOf(player)
	if not q then
		return
	end
	local step, entry = currentStep(q, id)
	if not step then
		return
	end
	entry.n = (entry.n or 0) + amount
	if entry.n >= (step.count or 1) then
		advance(player, id)
	else
		publish(player)
	end
end

local function matches(filter, info)
	for k, v in filter or {} do
		if info[k] ~= v then
			return false
		end
	end
	return true
end

-- The world ----------------------------------------------------------------------------------------------------------

local function groundAt(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local hit = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), params)
	return hit and hit.Position.Y or 0
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

local function label(parent, text, offset, distance)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(220, 46)
	gui.StudsOffset = offset
	gui.MaxDistance = distance or 70
	gui.Parent = parent
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.Parent = gui
	return t
end

-- Each look is a few parts in the Rustic palette. Returns the part prompts and markers hang on.
local LOOKS = {}

function LOOKS.board(m, cf)
	for _, x in { -2.2, 2.2 } do
		part(m, "Post", Vector3.new(0.5, 6, 0.5), cf * CFrame.new(x, 3, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	local board =
		part(m, "Board", Vector3.new(5.4, 3.4, 0.3), cf * CFrame.new(0, 4.2, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	for i = 0, 2 do
		part(
			m,
			"Note",
			Vector3.new(1.2, 1.4, 0.05),
			cf * CFrame.new(-1.6 + i * 1.6, 4.2, -0.18),
			Rustic.HayLight,
			Enum.Material.SmoothPlastic
		)
	end
	label(board, "QUESTS", Vector3.new(0, 3, 0))
	return board
end

function LOOKS.scarecrow(m, cf)
	part(m, "Pole", Vector3.new(0.4, 7, 0.4), cf * CFrame.new(0, 3.5, 0), Rustic.WoodDark, Enum.Material.Wood)
	part(m, "Arms", Vector3.new(5, 0.35, 0.35), cf * CFrame.new(0, 5, 0), Rustic.WoodDark, Enum.Material.Wood)
	local body =
		part(m, "Coat", Vector3.new(2.2, 2.4, 1), cf * CFrame.new(0, 4.6, 0), Rustic.PaintRedDark, Enum.Material.Fabric)
	part(
		m,
		"Head",
		Vector3.new(1.4, 1.4, 1.4),
		cf * CFrame.new(0, 6.6, 0),
		Rustic.Hay,
		Enum.Material.Fabric,
		Enum.PartType.Ball
	)
	part(
		m,
		"Brim",
		Vector3.new(2.4, 0.15, 2.4),
		cf * CFrame.new(0, 7.3, 0),
		Rustic.BarkDark,
		Enum.Material.Fabric,
		Enum.PartType.Cylinder
	).CFrame = cf
		* CFrame.new(0, 7.3, 0)
		* CFrame.Angles(0, 0, math.pi / 2)
	part(m, "Crown", Vector3.new(1.1, 1, 1.1), cf * CFrame.new(0, 7.8, 0), Rustic.BarkDark, Enum.Material.Fabric)
	for _, x in { -2.6, 2.6 } do
		part(m, "Straw", Vector3.new(0.6, 0.5, 0.5), cf * CFrame.new(x, 5, 0), Rustic.HayLight, Enum.Material.Fabric)
	end
	return body
end

-- The Old Scarecrow in a ring of four flat stones, where the bales go at dusk.
function LOOKS.ring(m, cf, spot)
	local body = LOOKS.scarecrow(m, cf)
	spot.pads = {}
	for i = 0, 3 do
		local a = i * math.pi / 2
		local pcf = cf * CFrame.new(math.sin(a) * 9, 0, math.cos(a) * 9)
		local stone = part(
			m,
			"Stone",
			Vector3.new(5.6, 0.6, 4.2),
			pcf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, a, 0),
			Rustic.Stone,
			Enum.Material.Slate
		)
		table.insert(spot.pads, stone.CFrame * CFrame.new(0, 1.6, 0))
	end
	return body
end

function LOOKS.well(m, cf)
	for i = 0, 7 do
		local a = i * math.pi / 4
		part(
			m,
			"Wall",
			Vector3.new(2.4, 2.6, 0.9),
			cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 1.3, 2.6),
			Rustic.Stone,
			Enum.Material.Cobblestone
		)
	end
	part(
		m,
		"Water",
		Vector3.new(0.2, 4.4, 4.4),
		cf * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Rustic.Water,
		Enum.Material.Glass,
		Enum.PartType.Cylinder
	)
	for _, x in { -2.8, 2.8 } do
		part(m, "Post", Vector3.new(0.45, 6, 0.45), cf * CFrame.new(x, 3, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	part(m, "Roof", Vector3.new(7, 0.4, 4), cf * CFrame.new(0, 6.2, 0), Rustic.BarkDark, Enum.Material.WoodPlanks)
	local crank =
		part(m, "Crank", Vector3.new(5.6, 0.3, 0.3), cf * CFrame.new(0, 4.6, 0), Rustic.Metal, Enum.Material.Metal)
	return crank
end

function LOOKS.barn(m, cf)
	local w, d, h = 26, 30, 12
	part(m, "Floor", Vector3.new(w, 0.6, d), cf * CFrame.new(0, 0.3, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	part(
		m,
		"Back",
		Vector3.new(w, h, 0.8),
		cf * CFrame.new(0, h / 2, d / 2),
		Rustic.PaintRedDark,
		Enum.Material.WoodPlanks
	)
	for _, x in { -1, 1 } do
		part(
			m,
			"Side",
			Vector3.new(0.8, h, d),
			cf * CFrame.new(x * w / 2, h / 2, 0),
			Rustic.PaintRedDark,
			Enum.Material.WoodPlanks
		)
		part(
			m,
			"Front",
			Vector3.new(w / 2 - 6, h, 0.8),
			cf * CFrame.new(x * (w / 4 + 3), h / 2, -d / 2),
			Rustic.PaintRedDark,
			Enum.Material.WoodPlanks
		)
		local roof = part(
			m,
			"Roof",
			Vector3.new(w / 2 + 2, 0.6, d + 2),
			cf * CFrame.new(x * w / 4, h + 3, 0) * CFrame.Angles(0, 0, -x * 0.42),
			Rustic.BarkDark,
			Enum.Material.Slate
		)
		roof.CanCollide = true
	end
	part(
		m,
		"Header",
		Vector3.new(12, 3, 0.8),
		cf * CFrame.new(0, h - 1.5, -d / 2),
		Rustic.PaintRedDark,
		Enum.Material.WoodPlanks
	)
	part(
		m,
		"Loft",
		Vector3.new(w - 1, 0.5, 10),
		cf * CFrame.new(0, 7.5, d / 2 - 5),
		Rustic.Wood,
		Enum.Material.WoodPlanks
	)
	-- Old Bessie under a dusty tarp until she is rebuilt (just a shape; the real truck is called from the quest log).
	local tarp = part(m, "Tarp", Vector3.new(9, 6, 18), cf * CFrame.new(0, 3.6, 2), Rustic.Cloth, Enum.Material.Fabric)
	-- Real bales along the wall (Bales.spawn, the one bale size), free to take like any other.
	for i = 0, 3 do
		local z = -6 + i * 4
		Bales.spawn((cf * CFrame.new(9.5, 0.6, z)).Position, true)
	end
	label(tarp, "THE OLD BARN", Vector3.new(0, 9, 0), 120)
	return tarp
end

function LOOKS.key(m, cf)
	local box = part(
		m,
		"Toolbox",
		Vector3.new(3, 1.6, 1.8),
		cf * CFrame.new(0, 0.8, 0),
		Rustic.WoodDark,
		Enum.Material.WoodPlanks
	)
	local key =
		part(m, "Key", Vector3.new(1.2, 0.2, 0.4), cf * CFrame.new(0, 1.7, 0), Rustic.Metal, Enum.Material.Metal)
	key.CanCollide = false
	part(
		m,
		"Bow",
		Vector3.new(0.2, 0.6, 0.6),
		cf * CFrame.new(-0.7, 1.7, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Rustic.Metal,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	).CanCollide =
		false
	return box
end

function LOOKS.page(m, cf)
	local rock = part(m, "Rock", Vector3.new(2.6, 1.2, 2), cf * CFrame.new(0, 0.6, 0), Rustic.Rock, Enum.Material.Slate)
	local page = part(
		m,
		"Page",
		Vector3.new(1.1, 0.05, 1.4),
		cf * CFrame.new(0, 1.25, 0) * CFrame.Angles(0, 0.4, 0),
		Rustic.HayLight,
		Enum.Material.SmoothPlastic
	)
	page.CanCollide = false
	return rock
end

-- The crop circle: a flattened ring of hay with a 3 x 3 grid of pads and a sign post that shows tonight's pattern.
function LOOKS.circle(m, cf, spot)
	local disc = part(
		m,
		"Flat",
		Vector3.new(0.2, 34, 34),
		cf * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Rustic.HayLight,
		Enum.Material.Fabric,
		Enum.PartType.Cylinder
	)
	disc.CanCollide = false
	part(
		m,
		"Ring",
		Vector3.new(0.25, 26, 26),
		cf * CFrame.new(0, 0.07, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Rustic.Hay,
		Enum.Material.Fabric,
		Enum.PartType.Cylinder
	).CanCollide =
		false
	spot.pads = {}
	for gz = -1, 1 do
		for gx = -1, 1 do
			local pad = part(
				m,
				"Pad",
				Vector3.new(5.4, 0.2, 4.2),
				cf * CFrame.new(gx * 7, 0.15, gz * 6),
				Rustic.Dirt,
				Enum.Material.Ground
			)
			pad.CanCollide = false
			table.insert(spot.pads, pad.CFrame * CFrame.new(0, 1.5, 0))
		end
	end
	local post =
		part(m, "SignPost", Vector3.new(0.5, 6, 0.5), cf * CFrame.new(0, 3, -15), Rustic.WoodDark, Enum.Material.Wood)
	spot.signLabel = label(post, "", Vector3.new(0, 4.5, 0), 60)
	spot.signLabel.Parent.Size = UDim2.fromOffset(150, 110)
	return disc
end

function LOOKS.golden(m, cf)
	local bale = part(
		m,
		"GoldenBale",
		Vector3.new(4.6, 2.6, 3.2),
		cf * CFrame.new(0, 1.3, 0),
		Color3.fromRGB(230, 186, 74),
		Enum.Material.Neon
	)
	bale.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 214, 120)
	light.Range = 18
	light.Parent = bale
	return bale
end

function LOOKS.stone(m, cf)
	local stone = part(
		m,
		"Stone",
		Vector3.new(2.4, 7, 1.6),
		cf * CFrame.new(0, 3.2, 0) * CFrame.Angles(0.05, 0.3, 0.04),
		Rustic.StoneDark,
		Enum.Material.Slate
	)
	part(
		m,
		"Rune",
		Vector3.new(0.9, 0.9, 0.1),
		stone.CFrame * CFrame.new(0, 1, -0.82),
		Color3.fromRGB(120, 210, 255),
		Enum.Material.Neon
	).CanCollide =
		false
	return stone
end

function LOOKS.crate(m, cf)
	local crate =
		part(m, "Crate", Vector3.new(3, 2.4, 2.4), cf * CFrame.new(0, 1.2, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	part(m, "Band", Vector3.new(3.05, 0.25, 2.45), cf * CFrame.new(0, 1.6, 0), Rustic.Metal, Enum.Material.Metal)
	return crate
end

function LOOKS.door(m, cf)
	local frame =
		part(m, "Frame", Vector3.new(6, 8, 1.2), cf * CFrame.new(0, 4, 0), Rustic.StoneDark, Enum.Material.Slate)
	part(m, "Door", Vector3.new(4, 6.6, 0.3), cf * CFrame.new(0, 3.4, -0.7), Rustic.WoodDark, Enum.Material.WoodPlanks)
	return frame
end

function LOOKS.ghost(m, cf)
	local ghost = part(
		m,
		"Ghost",
		Vector3.new(2, 5, 1.4),
		cf * CFrame.new(0, 3, 0),
		Color3.fromRGB(200, 230, 240),
		Enum.Material.ForceField
	)
	ghost.CanCollide = false
	return ghost
end

function LOOKS.lantern(m, cf)
	part(m, "Post", Vector3.new(0.4, 6, 0.4), cf * CFrame.new(0, 3, 0), Rustic.WoodDark, Enum.Material.Wood)
	local lamp = part(m, "Lamp", Vector3.new(1, 1.3, 1), cf * CFrame.new(0, 6.4, 0), Rustic.Metal, Enum.Material.Metal)
	return lamp
end

local function buildSpot(id, position, cframe)
	local spot = spots[id]
	if spot and spot.model then
		spot.model:Destroy()
	end
	spot = spot or { def = QuestConfig.Spots[id] }
	spots[id] = spot
	local def = spot.def
	local cf = cframe or CFrame.new(position.X, groundAt(position.X, position.Z), position.Z)
	local model = Instance.new("Model")
	model.Name = "Quest_" .. id
	local builder = LOOKS[def.look] or LOOKS.stone
	local base = builder(model, cf, spot)
	model.PrimaryPart = base
	model:SetAttribute("SpotId", id)
	model.Parent = folder
	CollectionService:AddTag(base, "QuestSpot")
	base:SetAttribute("SpotId", id)
	spot.model = model
	spot.base = base
	spot.position = cf.Position

	-- The marker over a spot your quest needs. Each client shows it only for its own active spots.
	local marker = label(base, "!", Vector3.new(0, 5, 0), 500)
	marker.Parent.Name = "QuestMarker"
	marker.Parent.Size = UDim2.fromOffset(40, 40)
	marker.Parent.AlwaysOnTop = true
	marker.Parent.Enabled = false
	marker.TextColor3 = Color3.fromRGB(255, 214, 120)

	if spot.prompted then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "QuestPrompt"
		prompt.ObjectText = def.name
		prompt.ActionText = def.item and "Take" or "Use"
		prompt.HoldDuration = def.item and 0 or 0.4
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.ClickablePrompt = true
		-- Each client hides it unless one of its quests needs this spot (src/client/Quests.client.luau).
		prompt.Parent = base
		prompt.Triggered:Connect(function(player)
			Quests.usePrompt(player, id)
		end)
	end
	return spot
end

-- Which spots get a prompt: anything a talk, collect or offer step points at.
local function markPrompted()
	for _, def in QuestConfig.List do
		for _, step in def.steps do
			if step.kind == "talk" or step.kind == "collect" or step.kind == "offer" then
				for _, id in step.spots or { step.spot } do
					spots[id] = spots[id] or { def = QuestConfig.Spots[id] }
					spots[id].prompted = true
				end
			end
		end
	end
end

local function onAnchor(anchor)
	if not anchor:IsA("BasePart") then
		return
	end
	local id = anchor:GetAttribute("SpotId")
	local region = anchor:GetAttribute("Region")
	if typeof(region) == "string" then
		reachable[region] = true
	end
	if typeof(id) == "string" and QuestConfig.Spots[id] then
		local cf = anchor.CFrame * CFrame.new(0, -anchor.Size.Y / 2, 0)
		buildSpot(id, cf.Position, CFrame.new(cf.Position) * cf.Rotation)
		reachable[QuestConfig.Spots[id].region] = true
	end
	for player in players do
		local q = questsOf(player)
		if q and unlockQuests(q) then
			publish(player)
		end
	end
end

-- The wandering scarecrow moves now and then, never to where he already stands.
local function moveScarecrow()
	local list = QuestConfig.WanderSpots
	local nextIndex = wanderIndex
	while #list > 1 and nextIndex == wanderIndex do
		nextIndex = rng:NextInteger(1, #list)
	end
	wanderIndex = nextIndex
	local p = list[wanderIndex]
	local spot = buildSpot("wander_scarecrow", p)
	spot.model:SetAttribute("Location", wanderIndex)
	for player in players do
		publish(player)
	end
end

-- The 3 x 3 sign for today: which pads need a bale. Same for everyone on the same UTC day.
local function dailyPattern()
	local r = Random.new(today() * 104729 + 7)
	local cells = {}
	local count = r:NextInteger(4, 6)
	local order = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
	for i = 9, 2, -1 do
		local j = r:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for i = 1, count do
		cells[order[i]] = true
	end
	return cells
end

local function refreshSign()
	local spot = spots.crop_circle
	if not spot or not spot.signLabel then
		return
	end
	local cells = dailyPattern()
	local rows = { "TONIGHT" }
	for row = 0, 2 do
		local line = ""
		for col = 1, 3 do
			line ..= cells[row * 3 + col] and "■ " or "□ "
		end
		table.insert(rows, line)
	end
	spot.signLabel.Text = table.concat(rows, "\n")
end

-- Bales standing on a pad (none carried or breaking).
local function balesOn(padCFrame)
	local found = {}
	-- A small box at the pad's middle, so a bale only counts for the pad it sits on, not its neighbor.
	for _, p in Workspace:GetPartBoundsInBox(padCFrame, Vector3.new(2.4, 3, 2.4)) do
		local b = Bales.fromPart(p)
		if b and not b.gone and not b.carriedBy and not b.breaking and p == b.body then
			found[b] = true
		end
	end
	return found
end

-- Steps --------------------------------------------------------------------------------------------------------------

local function stepWhenOk(step)
	return DayNight.is(step.when)
end

local function ownCheck(player, s, step)
	if step.what == "truck" then
		return #(s.trucks or {}) > 0
	elseif step.what == "plot" then
		return s.land ~= nil and s.land.owned == true
	elseif step.what == "gloves_tier" then
		return (player:GetAttribute("GloveTier") or 0) >= (step.value or 1)
	elseif step.what == "piece_kind" then
		for _, item in (s.land and s.land.items) or {} do
			if typeof(item) == "table" and pieceKinds[item.id] == step.value then
				return true
			end
		end
	end
	return false
end

local function spotIds(step)
	return step.spots or (step.spot and { step.spot }) or {}
end

local function near(player, spot, radius)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not spot or not spot.position then
		return false
	end
	local flat = Vector3.new(root.Position.X - spot.position.X, 0, root.Position.Z - spot.position.Z)
	return flat.Magnitude <= radius and math.abs(root.Position.Y - spot.position.Y) < 30
end

-- Pattern steps: four bales on the stones, or bales on exactly tonight's pads. Takes the bales when it works.
local function checkPattern(player, step)
	local spot = spots[step.spot]
	if not spot or not spot.pads or not stepWhenOk(step) or not near(player, spot, (spot.def.radius or 14) + 12) then
		return false
	end
	local want = step.pads == "daily" and dailyPattern() or nil
	local used = {}
	for i, pad in spot.pads do
		local on = balesOn(pad)
		local has = next(on) ~= nil
		local needed = want == nil or want[i] == true
		if has ~= needed then
			return false
		end
		for b in on do
			table.insert(used, b)
		end
	end
	for _, b in used do
		Bales.consume(b)
	end
	return true
end

local function pollPlayer(player)
	local q, s = questsOf(player)
	if not q then
		return
	end
	local info = players[player]
	local lifted = s.carryBale ~= nil
	if lifted and not info.lifted then
		Events.fire(player, "bale_lifted", 1, {})
	end
	info.lifted = lifted

	for _, id in activeIds(q) do
		local step, entry = currentStep(q, id)
		if not step then
			q.active[id] = nil
			continue
		end
		if step.kind == "own" then
			if ownCheck(player, s, step) then
				advance(player, id)
			end
		elseif step.kind == "visit" and stepWhenOk(step) then
			local ids = spotIds(step)
			local changed = false
			for _, spotId in ids do
				local spot = spots[spotId]
				if not entry.seen[spotId] and spot and near(player, spot, spot.def.radius or 12) then
					entry.seen[spotId] = true
					changed = true
					if #ids > 1 then
						Data.toast(player, ("%s touched."):format(spot.def.name))
					end
				end
			end
			if changed then
				local n = 0
				for _ in entry.seen do
					n += 1
				end
				entry.n = n
				if n >= #ids then
					advance(player, id)
				else
					publish(player)
				end
			end
		elseif step.kind == "pattern" then
			if checkPattern(player, step) then
				Data.toast(player, "The hay settles into place. Something answers.")
				advance(player, id)
			end
		end
	end
end

-- A rare find pops out of a broken bale. Only its finder can take it.
local function dropFind(player, questId, step, position)
	local find = QuestConfig.Finds[step.item] or { name = step.item, color = { 255, 255, 255 } }
	local orb = part(
		folder,
		"QuestFind",
		Vector3.new(1.4, 1.4, 1.4),
		CFrame.new(position + Vector3.new(0, 2.5, 0)),
		Color3.fromRGB(find.color[1], find.color[2], find.color[3]),
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	orb.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = orb.Color
	light.Range = 12
	light.Parent = orb
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take"
	prompt.ObjectText = find.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.Parent = orb
	local taken = false
	prompt.Triggered:Connect(function(who)
		if who ~= player then
			Data.toast(who, ("That %s is %s's."):format(find.name:lower(), player.DisplayName))
			return
		end
		if taken then
			return
		end
		taken = true
		orb:Destroy()
		local q = questsOf(player)
		local now = q and currentStep(q, questId)
		if now == step then
			Data.toast(player, ("You found a %s!"):format(find.name:lower()))
			bump(player, questId, 1)
		end
	end)
	task.delay(QuestConfig.FindSeconds, function()
		if not taken and orb.Parent then
			orb:Destroy()
			-- Missed it: the next bale is a sure thing, so it isn't lost.
			local q = questsOf(player)
			local entry = q and q.active[questId]
			if entry and q and currentStep(q, questId) == step then
				entry.pity = step.pity
			end
		end
	end)
	Data.toast(player, ("Something glows in the hay: a %s!"):format(find.name:lower()))
end

local function onEvent(player, kind, amount, info)
	local q = questsOf(player)
	if not q then
		return
	end
	for _, id in activeIds(q) do
		local step, entry = currentStep(q, id)
		if not step or not stepWhenOk(step) then
			continue
		end
		if step.kind == "event" and step.event == kind and matches(step.filter, info) then
			bump(player, id, amount)
		elseif step.kind == "find" and kind == "bale_broken" and matches(step.filter, info) and info.position then
			entry.pity = (entry.pity or 0) + 1
			if rng:NextNumber() < (step.chance or 0.01) or entry.pity >= (step.pity or math.huge) then
				entry.pity = 0
				dropFind(player, id, step, info.position)
			end
		end
	end

	local bounty = bountyState(q)
	for _, def in (todaysBounties()) do
		if def.event == kind and not bounty.done[def.id] then
			bounty.n[def.id] = (bounty.n[def.id] or 0) + amount
			if bounty.n[def.id] >= def.count then
				bounty.done[def.id] = true
				Bank.earn(player, def.cash, "Bounty: " .. def.text)
				Data.toast(player, ("Bounty done: %s. +$%d"):format(def.text, def.cash))
			end
			publish(player)
		end
	end

	-- Perks from quest rewards.
	if kind == "bale_broken" and q.earned.lucky_thimble and info.position and rng:NextNumber() < 0.3 then
		local jitter = Vector3.new(rng:NextNumber(-1.5, 1.5), 2.5, rng:NextNumber(-1.5, 1.5))
		Needle.spawn(info.position + jitter, player.UserId, needleForHay(info.hayType))
	elseif kind == "raked" and q.earned.thread_rake and info.center then
		local pulled = 0
		for _, n in Needle.inBox(CFrame.new(info.center), Vector3.new(16, 8, 16)) do
			-- Only loose needles that are yours or nobody's: never ones sitting in someone else's bin.
			local owner = n:GetAttribute("OwnerId")
			if (owner == nil or owner == player.UserId) and Needle.collect(player, n) then
				pulled += 1
			end
		end
		if pulled > 0 then
			Data.toast(player, ("The Thread Rake pulled in %d needle%s."):format(pulled, pulled == 1 and "" or "s"))
		end
	end
end

-- Prompts: talk, collect and offer steps.
function Quests.usePrompt(player, spotId)
	local q, s = questsOf(player)
	if not q then
		return
	end
	local spot = spots[spotId]
	if not spot or not near(player, spot, 14) then
		return
	end
	for _, id in activeIds(q) do
		local step, entry = currentStep(q, id)
		if not step or not table.find(spotIds(step), spotId) then
			continue
		end
		if step.kind ~= "talk" and step.kind ~= "collect" and step.kind ~= "offer" then
			continue
		end
		if not stepWhenOk(step) then
			Data.toast(player, ("Not now. Come back %s."):format(QuestConfig.WhenText[step.when] or "later"))
			return
		end
		if step.kind == "talk" then
			if step.distinct then
				-- Counts once each time he has moved since you last found him.
				local here = tostring(spot.model and spot.model:GetAttribute("Location") or 0)
				if entry.last == here then
					Data.toast(player, "You already found him here. He moves every few minutes.")
					return
				end
				entry.last = here
			elseif entry.seen[spotId] then
				Data.toast(player, "Nothing new here.")
				return
			else
				entry.seen[spotId] = true
			end
			if (step.count or 1) > 1 then
				Data.toast(player, ("%s (%d / %d)"):format(spot.def.name, (entry.n or 0) + 1, step.count))
			end
			bump(player, id, 1)
		elseif step.kind == "collect" then
			if entry.seen[spotId] then
				return
			end
			entry.seen[spotId] = true
			Data.toast(player, ("Took the %s."):format(spot.def.name:lower()))
			local ids = spotIds(step)
			entry.n = (entry.n or 0) + 1
			if entry.n >= #ids then
				advance(player, id)
			else
				publish(player)
			end
		elseif step.kind == "offer" then
			-- Check everything first, then take it all, so a short offer takes nothing.
			local want = {}
			for needleId, count in step.needles or {} do
				want[needleId] = count
			end
			if step.needlesEach then
				for _, n in reachableNeedles() do
					want[n.id] = step.needlesEach
				end
			end
			local pocket = Needle.held(player)
			local missing = {}
			for needleId, count in want do
				local have = pocket[needleId] or 0
				if have < count then
					table.insert(missing, ("%d more %s"):format(count - have, needleName(needleId):lower()))
				end
			end
			if step.cash and not Bank.canAfford(player, step.cash) then
				table.insert(missing, ("%s more"):format(Bank.money(step.cash - Bank.spendable(s))))
			end
			if #missing > 0 then
				Data.toast(
					player,
					("You need %s. Needles must be in your pocket (click them to pick up)."):format(
						table.concat(missing, ", ")
					)
				)
				return
			end
			if step.cash and not Bank.charge(player, step.cash, spot.def.name .. ": " .. step.text) then
				return
			end
			for needleId, count in want do
				Needle.take(player, needleId, count)
			end
			Data.toast(player, ("%s accepts your offering."):format(spot.def.name))
			advance(player, id)
		end
		return
	end
	-- Nobody's quest needs this spot right now.
	if spot.def.item then
		Data.toast(player, "Not yours to take yet.")
	end
end

-- Quest trucks -------------------------------------------------------------------------------------------------------

local function clearSpotFor(player, size)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local side = flat:Cross(Vector3.yAxis)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Workspace.Terrain, character }
	for _, offset in { flat * 18, flat * 18 + side * 14, flat * 18 - side * 14, -flat * 18, side * 16, -side * 16 } do
		local p = root.Position + offset
		local ground = Vector3.new(p.X, groundAt(p.X, p.Z), p.Z)
		local cf = CFrame.lookAt(ground, ground + side)
		if #Workspace:GetPartBoundsInBox(cf * CFrame.new(0, size.Y / 2 + 0.5, 0), size, params) == 0 then
			return cf
		end
	end
	return nil
end

function Quests.callTruck(player, truckId)
	local q = questsOf(player)
	local def = QuestConfig.Trucks[truckId]
	if not q or not def or not q.earned[truckId] then
		return false, "You haven't earned that truck."
	end
	if def.when and not DayNight.is(def.when) then
		return false, ("%s only comes out %s."):format(def.name, QuestConfig.WhenText[def.when] or "later")
	end
	local s = Data.get(player)
	if s and s.carryBale then
		return false, "Put the bale down first."
	end
	local base = Vehicles.get(def.base)
	if not base then
		return false, "That truck can't be built right now."
	end
	local cf = clearSpotFor(player, Vector3.new(12, 9, base.length + 2))
	if not cf then
		return false, "Find an open patch of ground first."
	end
	local truckDef = table.clone(base)
	truckDef.name = def.name
	truckDef.paint = def.paint or base.paint
	local parent = Workspace:FindFirstChild("Needlewood") or Workspace
	local truck = Vehicles.build(truckDef, cf, parent)
	truck.Name = player.Name .. "'s " .. def.name
	truck:SetAttribute("QuestTruck", truckId)
	Vehicles.makeDrivable(truck, player)
	truck:SetAttribute("MaxSpeed", def.maxSpeed or base.maxSpeed)
	if def.glow and truck.PrimaryPart then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(150, 200, 255)
		light.Range = 24
		light.Brightness = 2
		light.Parent = truck.PrimaryPart
		local glow = Instance.new("Highlight")
		glow.FillTransparency = 0.85
		glow.OutlineColor = Color3.fromRGB(150, 200, 255)
		glow.FillColor = Color3.fromRGB(150, 200, 255)
		glow.Parent = truck
	end
	local seat = truck:FindFirstChild("DriverSeat")
	if seat then
		label(seat, def.name, Vector3.new(0, 8, 0), 80)
	end
	Vehicles.setOwned(player, truck)
	Vehicles.release(truck, player)
	local prompt = seat and seat:FindFirstChild("DrivePrompt")
	if prompt then
		prompt.Enabled = true
	end
	return true, ("%s pulls up next to you."):format(def.name)
end

-- The quest log ------------------------------------------------------------------------------------------------------

local function stepProgress(step, entry)
	if step.kind == "visit" or step.kind == "collect" then
		local ids = spotIds(step)
		if #ids > 1 then
			return entry.n or 0, #ids
		end
	end
	if step.kind == "event" or step.kind == "find" or (step.kind == "talk" and (step.count or 1) > 1) then
		return entry.n or 0, step.count or 1
	end
	return nil, nil
end

-- Where a quest's current step sends you: { { name, position } } for each place still to visit.
local function targetsOf(q, id)
	local step, entry = currentStep(q, id)
	local list = {}
	if step and step.kind ~= "own" and step.kind ~= "event" and step.kind ~= "find" then
		for _, spotId in spotIds(step) do
			local spot = spots[spotId]
			if not entry.seen[spotId] and spot and spot.position then
				table.insert(list, { name = spot.def.name, position = spot.position })
			end
		end
	end
	return list
end

local function snapshot(player)
	local q, s = questsOf(player)
	if not q then
		return nil
	end
	local list = {}
	for _, def in QuestConfig.List do
		local entry = q.active[def.id]
		local status = q.done[def.id] and "done" or entry and "active" or waitingOnMap(def) and "waiting" or "locked"
		local steps = {}
		for i, step in def.steps do
			local n, count
			local isCurrent = entry ~= nil and entry.step == i
			if isCurrent then
				n, count = stepProgress(step, entry)
			end
			table.insert(steps, {
				text = step.text,
				done = q.done[def.id] or (entry ~= nil and entry.step > i),
				current = isCurrent,
				n = n,
				count = count,
				when = step.when and QuestConfig.WhenText[step.when] or nil,
			})
		end
		local needs = {}
		for _, need in def.requires or {} do
			if not q.done[need] and questById[need] then
				table.insert(needs, questById[need].name)
			end
		end
		table.insert(list, {
			id = def.id,
			name = def.name,
			giver = def.giver,
			blurb = def.blurb,
			region = def.region,
			ritual = def.ritual == true,
			status = status,
			needs = needs,
			steps = steps,
			reward = rewardText(def.reward or {}),
			targets = entry and targetsOf(q, def.id) or {},
		})
	end

	local bounty = bountyState(q)
	local bounties = {}
	for _, def in (todaysBounties()) do
		table.insert(bounties, {
			id = def.id,
			text = def.text,
			n = math.min(bounty.n[def.id] or 0, def.count),
			count = def.count,
			cash = def.cash,
			done = bounty.done[def.id] == true,
		})
	end

	local relics = {}
	for _, entry in QuestConfig.Collection do
		local r = QuestConfig.Rewards[entry.id]
		local found = q.earned[entry.id] == true
		table.insert(
			relics,
			{ id = entry.id, name = found and r.name or "???", blurb = found and r.blurb or entry.hint, found = found }
		)
	end

	local gear = {}
	for id, r in QuestConfig.Rewards do
		if q.earned[id] and r.kind ~= "relic" then
			table.insert(gear, {
				id = id,
				kind = r.kind,
				name = r.name,
				blurb = r.blurb,
				wearing = r.kind == "gloves" and player:GetAttribute("GloveId") == id or nil,
			})
		end
	end
	table.sort(gear, function(a, b)
		return a.name < b.name
	end)

	return {
		quests = list,
		bounties = bounties,
		relics = relics,
		gear = gear,
		cash = s.cash,
	}
end

-- Which spots this player's quests point at right now (for the client's markers and prompts).
local function activeSpots(q)
	local ids = {}
	for id in q.active do
		local step, entry = currentStep(q, id)
		if step and step.kind ~= "own" and step.kind ~= "event" and step.kind ~= "find" then
			for _, spotId in spotIds(step) do
				if not entry.seen[spotId] and spots[spotId] and spots[spotId].model then
					table.insert(ids, spotId)
				end
			end
		end
	end
	return ids
end

publish = function(player)
	local q = questsOf(player)
	if not q or not players[player] then
		return
	end
	player:SetAttribute("QuestSpots", table.concat(activeSpots(q), ","))
	-- The HUD tracker: the first active quest's current step.
	local best = players[player].tracked
	if not (best and q.active[best]) then
		best = nil
		for id in q.active do
			local def = questById[id]
			if def and (best == nil or def.order < questById[best].order) then
				best = id
			end
		end
	end
	local step, entry, def = currentStep(q, best)
	if step then
		local n, count = stepProgress(step, entry)
		local text = step.text .. (n and (" (%d/%d)"):format(n, count) or "")
		if step.when then
			text ..= " · " .. QuestConfig.WhenText[step.when]
		end
		player:SetAttribute("QuestTrackName", def.name)
		player:SetAttribute("QuestTrackStep", text)
	else
		player:SetAttribute("QuestTrackName", nil)
		player:SetAttribute("QuestTrackStep", nil)
	end
	-- Where the tracked step sends you, for the tracker's GO button (a waypoint).
	local target = best and targetsOf(q, best)[1]
	player:SetAttribute("QuestTrackTarget", target and target.position or nil)
	player:SetAttribute("QuestTrackTargetName", target and target.name or nil)
	if changedRemote then
		changedRemote:FireClient(player)
	end
end

local function onAction(player, kind, id)
	local q = questsOf(player)
	if not q then
		return false, "Pick a save first."
	end
	if kind == "wear" then
		local reward = typeof(id) == "string" and QuestConfig.Rewards[id]
		if not reward or reward.kind ~= "gloves" or not q.earned[id] then
			return false, "You haven't earned those gloves."
		end
		Gloves.grant(player, id)
		Gloves.buyOrWear(player, id) -- toasts "Put on your ..."
		publish(player)
		return true, nil
	elseif kind == "truck" then
		if typeof(id) ~= "string" then
			return false, nil
		end
		local info = players[player]
		if info and os.clock() - (info.lastTruck or 0) < 5 then
			return false, "Your truck is on its way."
		end
		local ok, message = Quests.callTruck(player, id)
		if ok and info then
			info.lastTruck = os.clock()
		end
		return ok, message
	elseif kind == "track" then
		if typeof(id) == "string" and q.active[id] then
			players[player].tracked = id
			publish(player)
			return true, nil
		end
		return false, nil
	end
	return false, nil
end

-- Golden Shovel: a glint on the shovel blade.
local function dressTools(player)
	local function dress(tool)
		if tool:IsA("Tool") and tool.Name == "Shovel" and player:GetAttribute("GoldenShovel") then
			local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart", true)
			if handle and not handle:FindFirstChild("GoldenGlint") then
				local glint = Instance.new("Sparkles")
				glint.Name = "GoldenGlint"
				glint.SparkleColor = Color3.fromRGB(255, 214, 120)
				glint.Parent = handle
			end
		end
	end
	local function dressAll()
		for _, container in { player.Character, player:FindFirstChild("Backpack") } do
			for _, child in container and container:GetChildren() or {} do
				dress(child)
			end
		end
	end
	local function watch(character)
		character.ChildAdded:Connect(dress)
		local backpack = player:WaitForChild("Backpack", 10)
		if backpack then
			backpack.ChildAdded:Connect(dress)
		end
		dressAll()
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
	player:GetAttributeChangedSignal("GoldenShovel"):Connect(dressAll)
end

local function onLoaded(player)
	local q = questsOf(player)
	if not q then
		return
	end
	players[player] = players[player] or { lifted = false }
	unlockQuests(q)
	applyPerks(player, q)
	publish(player)
end

function Quests.has(player, rewardId)
	local q = questsOf(player)
	return q ~= nil and q.earned[rewardId] == true
end

function Quests.build(worldFolder)
	DayNight.start()

	folder = Instance.new("Folder")
	folder.Name = "Quests"
	folder.Parent = worldFolder

	local remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "Quests"
	local get = Instance.new("RemoteFunction")
	get.Name = "Get"
	get.Parent = remoteFolder
	local action = Instance.new("RemoteFunction")
	action.Name = "Action"
	action.Parent = remoteFolder
	changedRemote = Instance.new("RemoteEvent")
	changedRemote.Name = "Changed"
	changedRemote.Parent = remoteFolder
	remoteFolder.Parent = ReplicatedStorage
	get.OnServerInvoke = function(player)
		local ok, result = pcall(snapshot, player)
		if not ok then
			warn("[Needlewood] quest log failed: " .. tostring(result))
			return nil
		end
		return result
	end
	action.OnServerInvoke = function(player, kind, id)
		local ok, result, message = pcall(onAction, player, kind, id)
		if not ok then
			warn("[Needlewood] quest action failed: " .. tostring(result))
			return false, "Something went wrong."
		end
		return result, message
	end

	Events.on(onEvent)
	Data.loaded.Event:Connect(onLoaded)
	Players.PlayerAdded:Connect(dressTools)
	for _, player in Players:GetPlayers() do
		dressTools(player)
		if Data.get(player) then
			task.spawn(onLoaded, player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		players[player] = nil
	end)

	-- Build the places once the terrain is in, so they sit on the ground.
	task.spawn(function()
		markPrompted()
		for id, def in QuestConfig.Spots do
			local p = def.pos or def.fallback
			if p and not def.wander then
				buildSpot(id, p)
			end
		end
		moveScarecrow()
		refreshSign()
		CollectionService:GetInstanceAddedSignal("QuestAnchor"):Connect(onAnchor)
		for _, anchor in CollectionService:GetTagged("QuestAnchor") do
			onAnchor(anchor)
		end
		for player in players do
			publish(player)
		end
	end)

	task.spawn(function()
		local lastWander, lastDay = os.clock(), today()
		while true do
			task.wait(0.5)
			for player in players do
				local ok, err = pcall(pollPlayer, player)
				if not ok then
					warn("[Needlewood] quest check failed: " .. tostring(err))
				end
			end
			if os.clock() - lastWander > QuestConfig.WanderMinutes * 60 then
				lastWander = os.clock()
				moveScarecrow()
			end
			if today() ~= lastDay then
				lastDay = today()
				refreshSign()
				for player in players do
					publish(player)
				end
			end
			-- The golden bale only shows at midnight.
			local golden = spots.golden_bale
			if golden and golden.model then
				local show = DayNight.is("midnight")
				for _, p in golden.model:GetDescendants() do
					if p:IsA("BasePart") then
						p.Transparency = show and 0 or 1
					elseif p:IsA("PointLight") then
						p.Enabled = show
					end
				end
			end
		end
	end)
end

return Quests
