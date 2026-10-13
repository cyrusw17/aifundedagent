--!nonstrict
-- The needle object. Every needle found in hay is a real physical part (tag "Needle") that stays in the world:
-- sorters throw them into bins, and anyone can click one to pick it up into their pocket. SELL NEEDLES pads pay for
-- the needles in their bin plus the ones in your pocket. Other services (sorters, spilled hay) make needles here.
--
-- Each needle type has its own color (rarer types glow). About 1 in 500 found needles is MUTATED: bigger, glowing,
-- worth 3x to 25x, and announced to the whole server.
--
-- To keep part counts down, every 10 plain needles of one type and owner resting in a bin are tied into a BUNDLE:
-- one needle part with a "Count" attribute of 10 and a twine band. A bundle sells and picks up as 10 needles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Factory = require(ReplicatedStorage.Shared.Config.Factory)
local Needles = require(ReplicatedStorage.Shared.Config.Needles)
local HayTypes = require(ReplicatedStorage.Shared.Config.Gloves).HayTypes
local Data = require(script.Parent.Data)
local Announce = require(script.Parent.Announce)
local Groups = require(script.Parent.Groups)
local Feedback = require(script.Parent.Feedback)
local Events = require(script.Parent.Events)
local Market = require(script.Parent.Market)
local Prices = require(ReplicatedStorage.Shared.Config.Prices)

local Needle = {}

local SIZE = Vector3.new(1.2, 0.15, 0.15)
local PICKUP_REACH = 10
local MUTATION_CHANCE = 1 / 500
local MUTATION_MIN, MUTATION_MAX = 3, 25
local FANFARE = "rbxasset://sounds/victory.wav"

-- Color per needle type, and whether it glows. Common types are plain metal; the rare maps glow.
local LOOKS = {
	steel = { Color3.fromRGB(150, 158, 166), false },
	pine = { Color3.fromRGB(96, 140, 84), false },
	sand = { Color3.fromRGB(214, 186, 120), false },
	ice = { Color3.fromRGB(170, 220, 240), true },
	bog = { Color3.fromRGB(110, 128, 70), false },
	obsidian = { Color3.fromRGB(60, 40, 70), true },
	geode = { Color3.fromRGB(170, 110, 220), true },
	cloud = { Color3.fromRGB(240, 244, 255), true },
	phantom = { Color3.fromRGB(120, 230, 210), true },
	cosmic = { Color3.fromRGB(80, 70, 220), true },
}
local MUTATED_COLOR = Color3.fromRGB(255, 210, 60)
local BUNDLE = 10
local BUNDLE_SIZE = Vector3.new(1.3, 0.55, 0.55)
local TWINE = Color3.fromRGB(97, 84, 69)

local rng = Random.new()

local types = {}
for _, n in Needles do
	types[n.id] = n
end
Needle.default = types[Factory.NeedleId] or Needles[1]

local folder = Instance.new("Folder")
folder.Name = "Needles"
folder.Parent = Workspace

local held = {} -- player -> { [key] = count }, only until a save slot is loaded (then Data state.pocket)

-- The needle type hidden in a hay type (Config/Gloves HayTypes): the one from the same map, so Pine straw holds Pine
-- needles and Star hay holds Cosmic ones.
local byMap = {}
for _, n in Needles do
	byMap[n.map] = n.id
end
function Needle.forHay(hayType)
	local hay = HayTypes[hayType or "meadow"]
	return hay and byMap[hay.map] or Needle.default.id
end

function Needle.info(id)
	return types[id] or Needle.default
end

-- Dollars one needle of this type and multiplier sells for at a SELL NEEDLES pad.
-- Follows this server's needle market (Market.luau), so it can drift 20% either side of the list price. A polished
-- needle (needle polisher) is worth Prices.PolishBonus more.
function Needle.priceOf(id, mult, polished)
	local polish = polished and 1 + Prices.PolishBonus or 1
	return math.floor(Needle.info(id).sortedValue * (mult or 1) * polish * Market.multiplier(id) + 0.5)
end

-- The pocket lives in the player's save slot (Data state.pocket) so it saves and loads with the slot. It counts
-- needles by key: the needle id, or "id*mult" for a mutated one, so mutations survive a save.
local function pocketOf(player)
	local state = Data.get(player)
	if state then
		state.pocket = state.pocket or {}
		-- Needles picked up before a save slot was chosen join the slot's pocket the first time it is there.
		local early = held[player]
		if early then
			held[player] = nil
			for key, count in early do
				state.pocket[key] = (state.pocket[key] or 0) + count
			end
		end
		return state.pocket
	end
	held[player] = held[player] or {}
	return held[player]
end

-- Pocket and save key for a needle: its id, or "id*mult" when mutated, with a trailing "!" when polished.
function Needle.keyOf(id, mult, polished)
	local key = (mult and mult > 1) and ("%s*%d"):format(id, mult) or id
	return polished and key .. "!" or key
end

-- The id, multiplier and polish of a key from keyOf.
function Needle.parseKey(key)
	local polished = string.sub(key, -1) == "!"
	if polished then
		key = string.sub(key, 1, -2)
	end
	local id, mult = string.match(key, "^(.-)%*(%d+)$")
	if id then
		return id, tonumber(mult), polished
	end
	return key, 1, polished
end

-- Needles in this player's pocket, as { [key] = count } (see keyOf).
function Needle.held(player)
	return pocketOf(player)
end

-- How many needles a needle part is: 1, or 10 for a bundle.
function Needle.count(part)
	return part:GetAttribute("Count") or 1
end

-- Dollars a needle part sells for (a bundle counts all its needles).
function Needle.value(part)
	return Needle.priceOf(part:GetAttribute("NeedleId"), part:GetAttribute("Mutation"), part:GetAttribute("Polished"))
		* Needle.count(part)
end

function Needle.isNeedle(part)
	return CollectionService:HasTag(part, "Needle")
end

-- Rolls whether a freshly found needle is mutated. Returns its multiplier (1 when it is a normal needle).
function Needle.rollMutation()
	if rng:NextNumber() < MUTATION_CHANCE then
		return rng:NextInteger(MUTATION_MIN, MUTATION_MAX)
	end
	return 1
end

-- How many needles are in this player's pocket.
function Needle.heldCount(player)
	local total = 0
	for _, count in pocketOf(player) do
		total += count
	end
	return total
end

-- Empties the player's pocket and returns what was in it, as a list of { id = needleId, mult = multiplier, polished }.
function Needle.takeHeld(player)
	local list = {}
	for key, count in pocketOf(player) do
		local id, mult, polished = Needle.parseKey(key)
		for _ = 1, count do
			table.insert(list, { id = id, mult = mult, polished = polished })
		end
	end
	local state = Data.get(player)
	if state then
		state.pocket = {}
	end
	held[player] = nil
	player:SetAttribute("NeedlesHeld", 0)
	return list
end

-- Sells everything in the player's pocket. Returns how many needles and how many dollars (the caller pays).
function Needle.sellHeld(player)
	local count, value = 0, 0
	for _, n in Needle.takeHeld(player) do
		count += 1
		value += Needle.priceOf(n.id, n.mult, n.polished)
		Market.sold(n.id, 1)
	end
	return count, value
end

-- Takes the most valuable needle out of the player's pocket, for putting it on show. Returns { id, mult } or nil.
function Needle.takeBest(player)
	local pocket = pocketOf(player)
	local bestKey, bestValue = nil, -1
	for key, count in pocket do
		local id, mult, polished = Needle.parseKey(key)
		if count > 0 and Needle.priceOf(id, mult, polished) > bestValue then
			bestKey, bestValue = key, Needle.priceOf(id, mult, polished)
		end
	end
	if not bestKey then
		return nil
	end
	pocket[bestKey] -= 1
	if pocket[bestKey] <= 0 then
		pocket[bestKey] = nil
	end
	player:SetAttribute("NeedlesHeld", Needle.heldCount(player))
	local id, mult, polished = Needle.parseKey(bestKey)
	return { id = id, mult = mult, polished = polished }
end

-- Takes count plain needles of one type out of the player's pocket (an offering, a recipe). All or nothing: returns
-- false and takes none when they have too few.
function Needle.takeFromPocket(player, needleId, count)
	local pocket = pocketOf(player)
	local have = pocket[needleId] or 0
	if have < count then
		return false
	end
	pocket[needleId] = have - count > 0 and have - count or nil
	player:SetAttribute("NeedlesHeld", Needle.heldCount(player))
	return true
end

-- Puts a needle ({ id, mult }) into the player's pocket.
function Needle.give(player, n)
	local pocket = pocketOf(player)
	local key = Needle.keyOf(n.id, n.mult, n.polished)
	pocket[key] = (pocket[key] or 0) + 1
	player:SetAttribute("NeedlesHeld", Needle.heldCount(player))
end

-- How a needle of this type looks: its color and material (mutated needles are gold and glow).
function Needle.look(id, mult)
	local look = LOOKS[id] or LOOKS.steel
	if (mult or 1) > 1 then
		return MUTATED_COLOR, Enum.Material.Neon
	end
	return look[1], look[2] and Enum.Material.Neon or Enum.Material.Metal
end

local function sound(parent, id, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMaxDistance = 80
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 4)
end

-- A burst of glints at a needle.
local function glint(n, amount)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.3, 0.6)
	e.Speed = NumberRange.new(2, 6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 1
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), n.Color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Parent = n
	e:Emit(amount)
	Debris:AddItem(e, 1)
end

-- anyReach: from wherever it lies (the Thread Rake). quiet: the caller tells the player. Returns true if picked up.
local function pickUp(player, n, anyReach, quiet)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not n.Parent or (not anyReach and (n.Position - root.Position).Magnitude > PICKUP_REACH + 2) then
		return false
	end
	local id = n:GetAttribute("NeedleId") or Needle.default.id
	local mult = n:GetAttribute("Mutation") or 1
	local count = Needle.count(n)
	local value = Needle.value(n)
	local pocket = pocketOf(player)
	local polished = n:GetAttribute("Polished") == true
	local key = Needle.keyOf(id, mult, polished)
	pocket[key] = (pocket[key] or 0) + count
	player:SetAttribute("NeedlesHeld", Needle.heldCount(player))
	n:Destroy()
	local name = (polished and "polished " or "") .. Needle.info(id).name:lower()
	local what = count > 1 and ("a bundle of %d %s needles"):format(count, name)
		or ("a %s%s needle"):format(mult > 1 and ("x%d MUTATED "):format(mult) or "", name)
	if not quiet then
		Data.toast(player, ("Picked up %s ($%d). Any sell pad buys it."):format(what, value))
	end
	Events.fire(player, "needle_found", count, { needleId = id })
	return true
end

-- Puts a loose needle straight into a player's pocket (the Thread Rake, a quest reward). Quiet. True if it worked.
function Needle.collect(player, n)
	return pickUp(player, n, true, true)
end

-- How many unmutated needles of one type are in the pocket, polished or not (what quest offerings take).
function Needle.plainCount(player, id)
	local pocket = pocketOf(player)
	return (pocket[id] or 0) + (pocket[Needle.keyOf(id, 1, true)] or 0)
end

-- Takes count unmutated needles of one type out of the pocket for a quest offering, plain ones before polished.
-- Takes none and returns false if there aren't enough.
function Needle.take(player, id, count)
	if Needle.plainCount(player, id) < count then
		return false
	end
	local pocket = pocketOf(player)
	for _, key in { id, Needle.keyOf(id, 1, true) } do
		local used = math.min(pocket[key] or 0, count)
		count -= used
		pocket[key] = (pocket[key] or 0) - used
		if pocket[key] <= 0 then
			pocket[key] = nil
		end
	end
	player:SetAttribute("NeedlesHeld", Needle.heldCount(player))
	return true
end

-- Polishes a needle part (or bundle): worth Prices.PolishBonus more, and it shines.
function Needle.polish(n)
	if n:GetAttribute("Polished") then
		return
	end
	n:SetAttribute("Polished", true)
	n.Reflectance = 0.45
	n.Color = n.Color:Lerp(Color3.new(1, 1, 1), 0.25)
end

-- Makes a needle at position. ownerId is who it belongs to while it sits in a bin. mult > 1 makes it mutated.
function Needle.spawn(position, ownerId, needleId, mult, polished)
	needleId = needleId or Needle.default.id
	mult = mult or 1
	local n = Instance.new("Part")
	n.Name = "Needle"
	n.Shape = Enum.PartType.Cylinder
	n.Size = mult > 1 and SIZE * 1.6 or SIZE
	n.CFrame = CFrame.new(position)
	n.Color, n.Material = Needle.look(needleId, mult)
	n.CollisionGroup = Groups.Loose
	n:SetAttribute("OwnerId", ownerId)
	n:SetAttribute("NeedleId", needleId)
	if mult > 1 then
		n:SetAttribute("Mutation", mult)
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = MUTATED_COLOR
		sparkle.Parent = n
		local light = Instance.new("PointLight")
		light.Color = MUTATED_COLOR
		light.Range = 8
		light.Brightness = 2
		light.Parent = n
	end
	CollectionService:AddTag(n, "Needle")

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = PICKUP_REACH
	click.MouseClick:Connect(function(player)
		pickUp(player, n)
	end)
	click.Parent = n

	if polished then
		Needle.polish(n)
	end
	n.Parent = folder
	pcall(function()
		n:SetNetworkOwner(nil)
	end)
	return n
end

-- Same as spawn, at a CFrame (for code that already has one, like spilled hay).
function Needle.make(cframe, ownerId, needleId, mult, polished)
	local n = Needle.spawn(cframe.Position, ownerId, needleId, mult, polished)
	n.CFrame = cframe
	return n
end

local function announce(ownerId, needleId, mult)
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	local text = ("%s found a x%d MUTATED %s needle worth $%d!"):format(
		owner and owner.DisplayName or "Someone",
		mult,
		Needle.info(needleId).name:lower(),
		Needle.priceOf(needleId, mult)
	)
	Announce.say(text, "gold")
end

-- The reveal: a freshly found needle pops up at `from` with a flash and hangs there for a moment, spinning, then
-- arcs to land at `to`, where it glints and dings and settles with physics. Rolls the mutation chance.
function Needle.throw(from, to, ownerId, needleId)
	needleId = needleId or Needle.default.id
	local mult = Needle.rollMutation()
	local n = Needle.spawn(from, ownerId, needleId, mult)
	n.Anchored = true
	n.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = n.Color
	light.Range = 6
	light.Brightness = 3
	light.Parent = n
	glint(n, mult > 1 and 30 or 8)
	if mult > 1 then
		sound(n, FANFARE, 1)
		announce(ownerId, needleId, mult)
	end

	task.spawn(function()
		local hover = mult > 1 and 1.5 or 0.35
		local lift = from + Vector3.new(0, 1.5, 0)
		local started = os.clock()
		while n.Parent and os.clock() - started < hover do
			local t = (os.clock() - started) / hover
			n.CFrame = CFrame.new(from:Lerp(lift, math.sin(t * math.pi / 2))) * CFrame.Angles(0, t * 12, math.rad(30))
			RunService.Heartbeat:Wait()
		end
		light:Destroy()

		started = os.clock()
		local control = (lift + to) / 2 + Vector3.new(0, 4, 0)
		while n.Parent do
			local alpha = math.min((os.clock() - started) / 0.6, 1)
			local inv = 1 - alpha
			n.CFrame = CFrame.new(inv * inv * lift + 2 * inv * alpha * control + alpha * alpha * to)
				* CFrame.Angles(alpha * 9, alpha * 5, 0)
			if alpha >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		if n.Parent then
			n.Anchored = false
			n.CanCollide = true
			pcall(function()
				n:SetNetworkOwner(nil)
			end)
			glint(n, 6)
			Feedback.needle(n, Needle.value(n)) -- a ding pitched by what the needle is worth
		end
	end)
	return n
end

-- Needle parts inside a box.
function Needle.inBox(cframe, size)
	local found = {}
	for _, p in Workspace:GetPartBoundsInBox(cframe, size) do
		if CollectionService:HasTag(p, "Needle") then
			table.insert(found, p)
		end
	end
	return found
end

-- A bundle of 10 plain needles of one type at cframe.
function Needle.bundle(cframe, ownerId, needleId, polished)
	local b = Needle.spawn(cframe.Position, ownerId, needleId, 1, polished)
	b.Name = "NeedleBundle"
	b.Size = BUNDLE_SIZE
	b.CFrame = cframe
	b:SetAttribute("Count", BUNDLE)
	local band = Instance.new("Part")
	band.Name = "Twine"
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(0.2, BUNDLE_SIZE.Y + 0.08, BUNDLE_SIZE.Z + 0.08)
	band.CFrame = b.CFrame
	band.Color = TWINE
	band.Material = Enum.Material.Fabric
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = b
	weld.Part1 = band
	weld.Parent = band
	band.Parent = b
	return b
end
Needle.BUNDLE = BUNDLE

-- Ties every 10 plain needles of one type and owner resting in a box into one bundle. Needles still flying in
-- (anchored), mutated needles and bundles are left alone. Returns how many bundles it tied.
function Needle.bundleIn(cframe, size)
	local groups = {}
	for _, n in Needle.inBox(cframe, size) do
		if not n.Anchored and Needle.count(n) == 1 and not n:GetAttribute("Mutation") then
			local k = ("%s|%s|%s"):format(
				tostring(n:GetAttribute("OwnerId")),
				n:GetAttribute("NeedleId") or Needle.default.id,
				tostring(n:GetAttribute("Polished") == true)
			)
			groups[k] = groups[k] or {}
			table.insert(groups[k], n)
		end
	end
	local tied = 0
	for _, list in groups do
		while #list >= BUNDLE do
			local center = Vector3.zero
			local first = list[1]
			for i = 1, BUNDLE do
				center += list[i].Position / BUNDLE
			end
			local ownerId, needleId = first:GetAttribute("OwnerId"), first:GetAttribute("NeedleId")
			local polished = first:GetAttribute("Polished") == true
			for _ = 1, BUNDLE do
				(table.remove(list, 1) :: BasePart):Destroy()
			end
			local b = Needle.bundle(CFrame.new(center + Vector3.new(0, 0.3, 0)), ownerId, needleId, polished)
			glint(b, 10)
			tied += 1
		end
	end
	return tied
end

Players.PlayerRemoving:Connect(function(player)
	held[player] = nil
end)

return Needle
