--!nonstrict
-- The far regions' dangers and secrets (backlog Map #9):
--   * Volcano heat: the crater is too hot to stand in without tier 4 gloves (Iron Gauntlets or Magma Grips). Anyone
--     else is pushed back over the rim with a warning. In the crater: the Ember Cache.
--   * The Ghost Road: a causeway of pale planks from the Wreck of the Bobbin out to Ghost Isle, solid only at night
--     (WorldClock.isNight). At dawn it fades over FADE seconds, then lets go. On Ghost Isle: the Captain's Lantern.
--   * Crystal Cave: the Geode Heart, hidden behind the crystals on the far wall.
--   * Sky Island: the Lost Kite, on a ledge just under the island's west rim.
-- Each secret pays once per save slot (Prices.Secrets) and is kept in state.secrets.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Prices = require(Shared.Config.Prices)
local WorldShape = require(script.Parent.WorldShape)
local WorldClock = require(script.Parent.WorldClock)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Announce = require(script.Parent.Announce)
local Discoveries = require(script.Parent.Discoveries)
local Regions = require(script.Parent.Regions)

local Wilds = {}

local HEAT_TIER = 4 -- gloves at or above this tier shrug off the crater's heat
local HEAT_RADIUS = 105 -- studs from the volcano's peak center, inside the rim
local HEAT_FLOOR = 40 -- studs below the rim top that count as "in the crater" (the outer slopes are fine)
local FADE = 20 -- seconds the Ghost Road takes to fade at dawn

local GHOST = Color3.fromRGB(170, 230, 210)
local GHOST_ROAD = { from = Vector2.new(-1735, -780), to = Vector2.new(-2030, -780), y = 4, width = 16 }
local GHOST_ISLE = { center = Vector2.new(-2075, -780), radius = 42, top = 4 }

local function part(parent, name, size, cframe, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function glow(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
	return l
end

-- Secrets ------------------------------------------------------------------------------------------------------

Wilds.Secrets = {} -- id -> { name, part }

local function found(player, id)
	local state = Data.get(player)
	return state and state.secrets and state.secrets[id] ~= nil
end

local function claimSecret(player, id, name)
	local state = Data.get(player)
	if not state then
		return false
	end
	state.secrets = state.secrets or {}
	-- A secret inside the crater's heat (the Ember Cache) needs the same heat-proof gloves as getting there.
	local spot = Wilds.Secrets[id]
	local hot = id == "ember_cache" or (spot and spot.part and Wilds.inHeat(spot.part.Position))
	if hot and not Wilds.heatProof(player) then
		Data.toast(player, "Too hot to search! Tier 4 gloves (Iron Gauntlets or Magma Grips) handle the crater's heat.")
		return false
	end
	if state.secrets[id] then
		Data.toast(player, ("You already found the %s."):format(name))
		return false
	end
	state.secrets[id] = 1
	local reward = Prices.Secrets[id] or (string.sub(id, 1, 7) == "hidden_" and Prices.Secrets.hidden) or 0
	if reward > 0 then
		Bank.earn(player, reward, "Secret: " .. name)
	end
	Data.toast(player, ("Secret found: the %s! +$%d"):format(name, reward))
	if Discoveries.info(id) then
		Discoveries.discover(player, id) -- stamps it on the map
	end
	Announce.say(("%s found a secret: the %s!"):format(player.DisplayName, name), "gold")
	return true
end
Wilds.claimSecret = claimSecret
Wilds.found = found

local function secret(parent, id, name, cframe, size, color, material)
	local p = part(parent, "Secret_" .. id, size, cframe, color, material)
	p:SetAttribute("SecretId", id)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Search"
	prompt.ObjectText = "?"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	prompt.Triggered:Connect(function(player)
		claimSecret(player, id, name)
	end)
	Wilds.Secrets[id] = { name = name, part = p, prompt = prompt }
	return p
end

-- Volcano heat ---------------------------------------------------------------------------------------------------

local peak = nil
local rimTop = 0

-- True where the crater's heat reaches (inside the rim, below its top).
function Wilds.inHeat(position)
	if not peak then
		return false
	end
	local d = (Vector2.new(position.X, position.Z) - peak.center).Magnitude
	return d < HEAT_RADIUS and position.Y < rimTop + 8 and position.Y > rimTop - HEAT_FLOOR - 120
end

function Wilds.heatProof(player)
	return (player:GetAttribute("GloveTier") or 0) >= HEAT_TIER
end

local warned = {}
local function heatLoop()
	while true do
		task.wait(0.5)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and not humanoid.SeatPart and Wilds.inHeat(root.Position) and not Wilds.heatProof(player) then
				local out = Vector2.new(root.Position.X, root.Position.Z) - peak.center
				out = out.Magnitude > 0.1 and out.Unit or Vector2.new(1, 0)
				-- The client owns its character's physics, so a server velocity alone can be lost: step it back
				-- out of the heat as well, then push.
				character:PivotTo(root.CFrame + Vector3.new(out.X * 6, 3, out.Y * 6))
				root.AssemblyLinearVelocity = Vector3.new(out.X * 55, 45, out.Y * 55)
				if not warned[player] or os.clock() - warned[player] > 8 then
					warned[player] = os.clock()
					Data.toast(player, "Too hot! Tier 4 gloves (Iron Gauntlets or Magma Grips) let you into the crater.")
				end
			end
		end
	end
end

local function volcano(folder)
	local region = WorldShape.region("volcano")
	peak = region and region.peak
	if not peak then
		return
	end
	-- The rim's top: the highest ground on a ring just inside HEAT_RADIUS.
	for a = 0, 7 do
		local p = peak.center + Vector2.new(math.cos(a / 8 * math.pi * 2), math.sin(a / 8 * math.pi * 2)) * (HEAT_RADIUS - 10)
		rimTop = math.max(rimTop, WorldShape.heightAt(p.X, p.Y))
	end
	-- The Ember Cache: an obsidian chest on the crater floor beside the Magma Spindle.
	local x, z = peak.center.X + 34, peak.center.Y - 14
	local y = WorldShape.heightAt(x, z)
	local chest = secret(folder, "ember_cache", "Ember Cache", CFrame.new(x, y + 1.2, z) * CFrame.Angles(0, 0.6, 0), Vector3.new(4, 2.4, 2.6), Color3.fromRGB(30, 24, 28), Enum.Material.Basalt)
	part(folder, "EmberLid", Vector3.new(4.2, 0.5, 2.8), chest.CFrame * CFrame.new(0, 1.45, 0), Color3.fromRGB(230, 110, 40), Enum.Material.Neon, false)
	glow(chest, Color3.fromRGB(255, 130, 60), 16, 1.5)
	task.spawn(heatLoop)
end

-- The Ghost Road -------------------------------------------------------------------------------------------------

local planks = {}
local ghostNight = nil

local function setGhost(solid, seconds)
	for _, p in planks do
		local shown = p:GetAttribute("Shown")
		if solid then
			p.CanCollide = p:GetAttribute("Solid") == true
			TweenService:Create(p, TweenInfo.new(seconds), { Transparency = shown }):Play()
		else
			TweenService:Create(p, TweenInfo.new(seconds), { Transparency = 1 }):Play()
		end
		for _, l in p:GetChildren() do
			if l:IsA("PointLight") then
				l.Enabled = solid
			end
		end
	end
	if not solid then
		task.delay(seconds, function()
			if not WorldClock.isNight() then
				for _, p in planks do
					p.CanCollide = false
				end
			end
		end)
	end
end

local function ghostRoad(folder)
	local road = Instance.new("Folder")
	road.Name = "GhostRoad"
	road.Parent = folder
	local a, b = GHOST_ROAD.from, GHOST_ROAD.to
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local yaw = math.atan2(-dir.X, -dir.Y)
	local segments = math.ceil(length / 30)
	for i = 0, segments - 1 do
		local mid = a + dir * ((i + 0.5) * length / segments)
		local cf = CFrame.new(mid.X, GHOST_ROAD.y - 0.6, mid.Y) * CFrame.Angles(0, yaw, 0)
		local deck = part(road, "GhostPlanks", Vector3.new(GHOST_ROAD.width, 1.2, length / segments + 0.2), cf, GHOST, Enum.Material.Neon)
		deck:SetAttribute("Solid", true)
		deck:SetAttribute("Shown", 0.55)
		table.insert(planks, deck)
		for _, side in { -1, 1 } do
			local post = part(road, "GhostPost", Vector3.new(0.6, 5, 0.6), cf * CFrame.new(side * (GHOST_ROAD.width / 2 + 0.4), 2.5, 0), GHOST, Enum.Material.Neon, false)
			post:SetAttribute("Shown", 0.3)
			table.insert(planks, post)
			if i % 2 == 0 and side == 1 then
				glow(post, GHOST, 22, 0.8)
			end
		end
	end

	-- Ghost Isle: a basalt islet with a drowned lighthouse stump and the Captain's Lantern.
	local isle = GHOST_ISLE
	local rock = part(folder, "GhostIsle", Vector3.new(36, isle.radius * 2, isle.radius * 2), CFrame.new(isle.center.X, isle.top - 18, isle.center.Y) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(58, 56, 64), Enum.Material.Basalt)
	rock.Shape = Enum.PartType.Cylinder
	part(folder, "GhostIsleLanding", Vector3.new(GHOST_ROAD.width, 1, 14), CFrame.new(b.X - dir.X * 2, isle.top - 0.5, b.Y - dir.Y * 2) * CFrame.Angles(0, yaw, 0), Color3.fromRGB(70, 58, 48), Enum.Material.WoodPlanks)
	local stump = part(folder, "LighthouseStump", Vector3.new(16, 12, 12), CFrame.new(isle.center.X - 12, isle.top + 8, isle.center.Y + 8), Color3.fromRGB(150, 146, 150), Enum.Material.Brick)
	stump.Shape = Enum.PartType.Cylinder
	stump.CFrame = stump.CFrame * CFrame.Angles(0, 0, math.rad(90))
	local lantern = secret(folder, "captains_lantern", "Captain's Lantern", CFrame.new(isle.center.X + 10, isle.top + 1, isle.center.Y - 6), Vector3.new(1.4, 2, 1.4), Color3.fromRGB(150, 230, 200), Enum.Material.Neon)
	glow(lantern, GHOST, 18, 1.2)

	ghostNight = WorldClock.isNight()
	setGhost(ghostNight, 0)
	task.spawn(function()
		while road.Parent do
			task.wait(1)
			Wilds.refreshGhost()
		end
	end)
end

-- Brings the Ghost Road in line with the clock now (the loop above does this every second).
function Wilds.refreshGhost()
	local now = WorldClock.isNight()
	if now ~= ghostNight then
		ghostNight = now
		setGhost(now, now and 3 or FADE)
	end
end

function Wilds.ghostSolid()
	return planks[1] ~= nil and planks[1].CanCollide
end

-- Cave and sky ---------------------------------------------------------------------------------------------------

local function cave(folder)
	local c = Map.Cave.chamber
	local floorY = c.center.Y - c.radius * 0.45 + 4
	local x, z = c.center.X + c.radius * 0.78, c.center.Z + c.radius * 0.3
	local geode = secret(folder, "geode_heart", "Geode Heart", CFrame.new(x, floorY + 1.6, z), Vector3.new(3.2, 3.2, 3.2), Color3.fromRGB(150, 110, 200), Enum.Material.Glass)
	geode.Shape = Enum.PartType.Ball
	glow(geode, Color3.fromRGB(180, 140, 255), 12, 1)
end

local function sky(folder)
	local s = Map.SkyIsland
	-- A stone ledge jutting out just under the west rim; drop off the edge to land on it.
	local x, z = s.center.X - s.radius - 2, s.center.Y
	local ledge = part(folder, "KiteLedge", Vector3.new(18, 2, 14), CFrame.new(x, s.top - 16, z), Color3.fromRGB(150, 146, 140), Enum.Material.Slate)
	local kite = secret(folder, "lost_kite", "Lost Kite", ledge.CFrame * CFrame.new(-3, 2.4, 0) * CFrame.Angles(0.5, 0.3, 0.2), Vector3.new(3.4, 0.2, 4.4), Color3.fromRGB(200, 70, 60), Enum.Material.Fabric)
	part(folder, "KiteTail", Vector3.new(0.2, 0.2, 6), kite.CFrame * CFrame.new(0, 0, 4.6), Color3.fromRGB(240, 220, 160), Enum.Material.Fabric, false)
end

-- Hidden spots -------------------------------------------------------------------------------------------------
-- One per region: a hollow tree, a buried shed, a stone cairn or a sunken chest, a short walk off one of the region's
-- roads. No marker points at it. An Old Sign at the roadside gives the clue in paces and a compass direction
-- ("north" is -Z). Finding it pays Prices.Secrets.hidden once per slot and stamps it as a discovery.

local HIDDEN = {
	shore = { kind = "tree", name = "Hollow Driftwood Oak", riddle = "the old oak is hollow" },
	valley = { kind = "tree", name = "Hollow Willow", riddle = "a willow keeps a secret" },
	homestead = { kind = "cairn", name = "Founders' Cairn", riddle = "the first settlers stacked their stones" },
	spindle = { kind = "cairn", name = "Echo Cairn", riddle = "stones that listen" },
	pine = { kind = "tree", name = "Hollow Pine", riddle = "one pine is empty inside" },
	haunted = { kind = "tree", name = "Whispering Oak", riddle = "the dead tree whispers" },
	snow = { kind = "shed", name = "Buried Ski Shed", riddle = "a roof pokes out of the snow" },
	volcano = { kind = "cairn", name = "Ash Cairn", riddle = "stones the ash forgot" },
	desert = { kind = "shed", name = "Buried Prospector's Shed", riddle = "the sand swallowed a shed" },
	swamp = { kind = "chest", name = "Sunken Bog Chest", riddle = "a chest sinks in the mud" },
	keys = { kind = "chest", name = "Castaway's Chest", riddle = "a castaway buried his chest" },
	bobbin = { kind = "shed", name = "Spool Shed", riddle = "a shed full of thread, half buried" },
}
Wilds.Hidden = {} -- region id -> { id, name, part, sign = Vector3, spot = Vector3 }

local DIRECTIONS = { "east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east" }
local function compass(dx, dz)
	-- +X east, +Z south.
	local a = math.atan2(dz, dx)
	return DIRECTIONS[(math.floor(a / (math.pi / 4) + 0.5) % 8) + 1]
end

-- A spot in this region 50 to 120 studs off one of its roads: dry, fairly level, away from fields.
local function hiddenSpot(region, rng)
	local pieces = {}
	for _, road in Map.Roads do
		for k = 1, #road.points - 1 do
			local a, b = road.points[k], road.points[k + 1]
			for t = 0.2, 0.8, 0.2 do
				local p = a:Lerp(b, t)
				local reach = math.max(region.radius.X, region.radius.Y) + 150
				if (p - region.center).Magnitude < reach and not WorldShape.inMeadow(p.X, p.Y) then
					local dir = (b - a).Unit
					table.insert(pieces, { p = p, n = Vector2.new(-dir.Y, dir.X) })
				end
			end
		end
	end
	for _ = 1, 200 do
		if #pieces == 0 then
			return nil
		end
		local piece = pieces[rng:NextInteger(1, #pieces)]
		local side = rng:NextInteger(0, 1) * 2 - 1
		local spot = piece.p + piece.n * side * rng:NextNumber(50, 120) + Vector2.new(rng:NextNumber(-20, 20), rng:NextNumber(-20, 20))
		local d = WorldShape.nearestRoad(spot.X, spot.Y)
		local h, water = WorldShape.column(spot.X, spot.Y)
		local level = true
		for _, o in { Vector2.new(4, 0), Vector2.new(-4, 0), Vector2.new(0, 4), Vector2.new(0, -4) } do
			local h2, w2 = WorldShape.column(spot.X + o.X, spot.Y + o.Y)
			if w2 or math.abs(h2 - h) > 2.5 then
				level = false
			end
		end
		local clear = WorldShape.regionAt(spot.X, spot.Y) == region and not water and level and (not d or d > 30)
		for _, entry in Regions.fields do
			if clear and (Vector2.new(entry.center.X, entry.center.Z) - spot).Magnitude < 40 then
				clear = false
			end
		end
		if clear then
			return Vector3.new(spot.X, h, spot.Y), piece.p
		end
	end
	return nil
end

local function hiddenLook(parent, kind, at, rng)
	local cf = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	if kind == "tree" then
		local trunk = part(parent, "HollowTrunk", Vector3.new(5, 14, 5), cf * CFrame.new(0, 6.5, 0), Color3.fromRGB(92, 74, 54), Enum.Material.Wood)
		trunk.Shape = Enum.PartType.Cylinder
		trunk.CFrame = trunk.CFrame * CFrame.Angles(0, 0, math.rad(90))
		part(parent, "HollowCanopy", Vector3.new(14, 9, 14), cf * CFrame.new(0, 16, 0), Color3.fromRGB(86, 110, 62), Enum.Material.Grass, false)
		part(parent, "Hollow", Vector3.new(2.4, 3.2, 0.4), cf * CFrame.new(0, 2.2, -2.45), Color3.fromRGB(28, 22, 18), Enum.Material.SmoothPlastic, false)
		return cf * CFrame.new(0, 2.2, -3)
	elseif kind == "shed" then
		part(parent, "BuriedRoofL", Vector3.new(7, 0.5, 9), cf * CFrame.new(-1.9, 1.3, 0) * CFrame.Angles(0, 0, math.rad(30)), Color3.fromRGB(110, 80, 60), Enum.Material.WoodPlanks)
		part(parent, "BuriedRoofR", Vector3.new(7, 0.5, 9), cf * CFrame.new(1.9, 1.3, 0) * CFrame.Angles(0, 0, math.rad(-30)), Color3.fromRGB(110, 80, 60), Enum.Material.WoodPlanks)
		part(parent, "ShedChimney", Vector3.new(1, 2.4, 1), cf * CFrame.new(2, 2.4, 2.5), Color3.fromRGB(120, 110, 104), Enum.Material.Brick)
		return cf * CFrame.new(0, 1.2, -5)
	elseif kind == "chest" then
		part(parent, "SunkChest", Vector3.new(3.6, 1.6, 2.4), cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0.15, 0, 0.1), Color3.fromRGB(80, 60, 44), Enum.Material.WoodPlanks)
		part(parent, "SunkChestBand", Vector3.new(3.7, 0.3, 2.5), cf * CFrame.new(0, 0.9, 0) * CFrame.Angles(0.15, 0, 0.1), Color3.fromRGB(120, 110, 100), Enum.Material.Metal)
		return cf * CFrame.new(0, 0.8, 0)
	end
	-- cairn
	for i = 0, 3 do
		local r = 2.6 - i * 0.5
		local stone = part(parent, "CairnStone", Vector3.new(r, 1.2, r * 0.9), cf * CFrame.new(0, 0.6 + i * 1.1, 0) * CFrame.Angles(0, i * 0.7, 0), Color3.fromRGB(128, 122, 116), Enum.Material.Slate)
		stone.Shape = Enum.PartType.Block
	end
	return cf * CFrame.new(0, 1, -1.8)
end

local function hiddenSpots(folder)
	local signpost = Regions.signpost
	for _, r in Map.Regions do
		local def = HIDDEN[r.id]
		local region = WorldShape.region(r.id)
		if def and region then
			local rng = Random.new(Map.Seed * 31 + #r.id * 7 + string.byte(r.id, 1))
			local at, roadPoint = hiddenSpot(region, rng)
			if at then
				local id = "hidden_" .. r.id
				local holder = Instance.new("Model")
				holder.Name = "Hidden_" .. r.id
				holder.Parent = folder
				local findAt = hiddenLook(holder, def.kind, at, rng)
				local ground = WorldShape.column(findAt.X, findAt.Z)
				if findAt.Y < ground + 0.6 then
					findAt = findAt + Vector3.new(0, ground + 0.6 - findAt.Y, 0) -- never inside a slope
				end
				-- The find itself: a small dark bundle you search in the hollow, under the roof, in the chest.
				local find = secret(holder, id, def.name, findAt, Vector3.new(1.2, 0.8, 1.2), Color3.fromRGB(70, 56, 44), Enum.Material.Fabric)
				find.CanCollide = false
				Discoveries.addHidden(id, def.name)
				local offset = Vector2.new(at.X, at.Z) - roadPoint
				local paces = math.floor(offset.Magnitude / 2.5 / 5 + 0.5) * 5
				local text = ("OLD SIGN\n%d paces %s,\n%s"):format(paces, compass(offset.X, offset.Y), def.riddle)
				if signpost then
					signpost(holder, roadPoint.X, roadPoint.Y, offset.Unit, text, 12)
				end
				Wilds.Hidden[r.id] = { id = id, name = def.name, part = find, spot = at, sign = roadPoint }
			else
				warn("[Needlewood] no hidden spot found in " .. r.name)
			end
		end
	end
end

function Wilds.build(folder)
	local wilds = Instance.new("Folder")
	wilds.Name = "Wilds"
	wilds.Parent = folder
	for _, step in { { "volcano", volcano }, { "ghost road", ghostRoad }, { "cave", cave }, { "sky", sky }, { "hidden spots", hiddenSpots } } do
		local ok, err = pcall(step[2], wilds)
		if not ok then
			warn(("[Needlewood] Wilds %s failed: %s"):format(step[1], tostring(err)))
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		warned[player] = nil
	end)
end

return Wilds
