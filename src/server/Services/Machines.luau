--!nonstrict
-- Pieces that go on a conveyor line: needle sorters (one per tier in Sorters.luau), needle bins and hay buyers.
-- The public sell shop uses them, and player plots can place the same pieces on their own conveyor grid.
--
-- Every piece is placed with a ground-level "frame": a CFrame at the middle of its grid cell whose LookVector is the
-- way the belt flows. Conveyors.frame(grid, gx, gz, dir) gives one.
--
--   local bin = Machines.needleBin(parent, frame)                          -- 1 cell, open top
--   Machines.sorter(parent, frame, "conveyor_sorter", bin)                 -- covers this cell and the next one along
--   Machines.hayBuyer(parent, frame, "HAY BUYER")                          -- end-of-line hopper, pays on drop
--   Machines.stepPad(parent, position, color, text, function(player) end)  -- tycoon floor button
--   Machines.splitter(grid, gx, gz, dir, "alternate" | "sorted")           -- a belt tile with two ways out (before finish)
-- A merger needs no piece: a belt tile fed from both sides merges them (and wears the merger mesh).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LineMath = require(Shared.LineMath)
local LineRate = require(Shared.LineRate)
local Pity = require(Shared.Pity)
local Boosts = require(Shared.Boosts)
local LandConfig = require(Shared.Config.Land)
local RateLimit = require(Shared.RateLimit)
local Factory = require(Shared.Config.Factory)
local Config = require(Shared.Config.Game)
local Needles = require(Shared.Config.Needles)
local Sorters = require(Shared.Config.Sorters)
local Economy = require(Shared.Economy)
local WorldLabel = require(Shared.WorldLabel)
local Data = require(script.Parent.Data)
local Tutorial = require(script.Parent.Tutorial)
local Bank = require(script.Parent.Bank)
local Prices = require(Shared.Config.Prices)
local Oil = Prices.SorterOil
local Bales = require(script.Parent.Bales)
local Hay = require(script.Parent.Hay)
local Needle = require(script.Parent.Needle)
local LineStats = require(script.Parent.LineStats)
local Jams = require(script.Parent.Jams) -- watches belts for stuck bales; the sorter lamp asks it
local Skins = require(script.Parent.Skins)
local Conveyors = require(script.Parent.Conveyors)
local Feedback = require(script.Parent.Feedback)
local Events = require(script.Parent.Events)
local Market = require(script.Parent.Market)

local Machines = {}

local T = Factory.TileSize
local TOP = Factory.BeltTop

-- Rustic palette (blender/lib/style.py): weathered wood and plain weathered metal, no rust.
Machines.Colors = {
	planks = Color3.fromRGB(179, 153, 115),
	wood = Color3.fromRGB(133, 110, 82),
	metal = Color3.fromRGB(128, 117, 105),
	darkMetal = Color3.fromRGB(107, 94, 84),
	rubber = Color3.fromRGB(41, 33, 26),
	cleanHay = Color3.fromRGB(219, 204, 153),
	twine = Color3.fromRGB(97, 84, 69),
	pad = Color3.fromRGB(180, 150, 110),
	go = Color3.fromRGB(150, 170, 100),
}
local C = Machines.Colors

local rng = Random.new()
-- Pity (Prices.Pity): each owner's run of sorted bales that found needles but no mutated one, across all their
-- sorters. Kept for the server session only; a rejoin starts the count again.
local dryRun = {}
Players.PlayerRemoving:Connect(function(player)
	dryRun[player.UserId] = nil
end)
local alienUsedDay = {} -- UserId -> UTC day the Alien collector beam was last used (per server)

local needle = Needles[1]
for _, n in Needles do
	if n.id == Factory.NeedleId then
		needle = n
	end
end
Machines.needle = needle

local tiers = {}
for _, tier in Sorters do
	tiers[tier.id] = tier
end

function Machines.part(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local part = Machines.part

-- A floating label (shared WorldLabel helper). kind is "status" unless given ("sign" for place names).
function Machines.sign(parent, text, offset, kind)
	return WorldLabel.billboard(parent, text, { offset = offset, kind = kind or "status" })
end
local sign = Machines.sign

-- note is the short line for the bank history (Bank.luau); text is the toast.
function Machines.pay(ownerId, amount, text, note)
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	local state = owner and Data.get(owner)
	if not state then
		return
	end
	Bank.earn(owner, amount, note or "Farm sale")
	LineStats.record(ownerId, "cash", amount)
	Tutorial.mark(owner, "sold")
	Tutorial.earned(owner, amount)
	Data.toast(owner, text)
	Feedback.sale(owner, amount)
end

-- A tycoon button: a round pad on the ground that fires once each time a player steps onto it.
function Machines.stepPad(parent, position, color, text, onStep)
	local pad = part(parent, "StepPad", Vector3.new(0.4, 5, 5), CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Neon)
	pad.Shape = Enum.PartType.Cylinder
	pad.CanCollide = false
	local label = sign(pad, text, Vector3.new(0, 4, 0))
	local standing = {}
	task.spawn(function()
		while pad.Parent do
			task.wait(0.2)
			local now = {}
			for _, p in Workspace:GetPartBoundsInBox(CFrame.new(position + Vector3.new(0, 2.5, 0)), Vector3.new(4.6, 5, 4.6)) do
				local player = p.Parent and Players:GetPlayerFromCharacter(p.Parent)
				if player and not now[player] then
					now[player] = true
					if not standing[player] then
						task.spawn(onStep, player)
					end
				end
			end
			standing = now
		end
	end)
	return pad, label
end

-- Sorted bales come out of a sorter with their needles taken out. They are ordinary bales (Bales.spawn, same size
-- and look as every other bale), marked sorted so no sorter takes them twice and buyers pay only for the hay.
-- Hay type of a bale body or hay piece (Config/Gloves HayTypes), and the chance of a needle per strand of it.
local function hayTypeOf(p)
	return p:GetAttribute("HayType") or "meadow"
end
local function needleChance(hayType)
	return Prices.needleChance(hayType)
end

-- A bale's or strand's boost attribute (NeedleBoost, MutationBoost): a positive number, else 1.
local function boostOf(inst, name)
	local v = inst:GetAttribute(name)
	return (typeof(v) == "number" and v > 0 and v == v) and v or 1
end

-- A bale's needle and mutation boosts at the sorter, with the extras it picked up (play-together needles, storm odds)
-- stacked under Prices.Boosts.Cap (Boosts.fit, CEO H13). The mutation boost comes back without the storm's odds,
-- because bin.add multiplies those in where the needles come out.
local BOOST_TERMS = Boosts.terms(Prices)
local function baleBoosts(body)
	local own, together = boostOf(body, "NeedleBoost"), 1
	if body:GetAttribute("TogetherBoost") == true then
		together = LandConfig.TogetherBonus or 1
		own /= together
	end
	if body:GetAttribute("GoldenField") == true then
		own *= Config.GoldenBaleNeedles
	end
	local odds = Needle.weatherAt(body.Position)
	odds = (typeof(odds) == "number" and odds > 0) and odds or 1
	local needles, mutation = Boosts.fit(BOOST_TERMS, own, boostOf(body, "MutationBoost"), together, odds)
	return needles, mutation / odds
end

local function spawnSortedBale(cframe, ownerId, hay, hayType)
	local b = Bales.spawn(Vector3.zero, false, false)
	b.body:SetAttribute("HayType", hayType or "meadow")
	b.sorted = true
	b.sortedHay = hay
	b.ownerId = ownerId
	b.body:SetAttribute("Sorted", true)
	b.body.CFrame = cframe
	b.body.Anchored = false
	pcall(function()
		b.body:SetNetworkOwner(nil)
	end)
	local token = b.dropToken
	task.delay(Factory.LooseBaleSeconds, function()
		if not b.gone and not b.carriedBy and b.dropToken == token and not Bales.isAtDropOff(b) then
			Bales.consume(b)
		end
	end)
	return b
end
Machines.spawnSortedBale = spawnSortedBale

-- Price holds (CEO #26): a player can tell their needle bins to keep their needles until this server's market pays a
-- share of list price. state.needleHold is an index into HOLD_STEPS (nil or 0 is off, sell at any price).
local holdLimit = RateLimit.new("NeedleBin.PriceHold", 3, 4)
local HOLD_STEPS = { 1, 1.05, 1.1, 1.15 } -- the market swings 0.8 to 1.2 of list (Prices.Market.Swing)

local function holdOf(player)
	local state = Data.get(player)
	local i = state and state.needleHold
	return typeof(i) == "number" and HOLD_STEPS[i] or nil
end

-- Today's price of a plain B-grade needle of each type in byType, the market's arrow, as lines for a sign.
local function priceLines(byType)
	local ids = {}
	for id in byType do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return byType[a] > byType[b]
	end)
	local lines = ""
	for i = 1, math.min(#ids, 4) do
		local id = ids[i]
		local m = Market.multiplier(id)
		local arrow = m > 1.02 and "▲" or m < 0.98 and "▼" or "•"
		lines ..= ("\n%s $%d %s%d%%"):format(Needle.info(id).name, math.floor(Needle.priceOf(id) + 0.5), arrow, math.round((m - 1) * 100))
	end
	return lines
end

-- "30 Steel until $55 (now $48)" for each type a hold kept back.
local function heldText(held, hold)
	local parts = {}
	for id, count in held do
		local info = Needle.info(id)
		table.insert(parts, ("%d %s until $%d (now $%d)"):format(count, info.name, math.ceil(info.sortedValue * hold), math.floor(Needle.priceOf(id) + 0.5)))
	end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

-- Needle bin: one cell, open on top. Sorters throw real needles into it (Needle.luau) and they pile up.
-- It comes with a SELL NEEDLES pad in front (local +Z side) that pays the full sorted price for your needles in the
-- bin and any you picked up and carry.
function Machines.needleBin(parent, frame)
	local bin = {}
	local model = Instance.new("Model")
	model.Name = "NeedleBin"
	model.Parent = parent
	part(model, "Floor", Vector3.new(T, 0.4, T), frame * CFrame.new(0, 0.2, 0), C.planks, Enum.Material.WoodPlanks)
	for _, sx in { -1, 1 } do
		part(model, "Wall", Vector3.new(0.4, 3, T), frame * CFrame.new(sx * (T / 2 - 0.2), 1.5, 0), C.wood, Enum.Material.WoodPlanks)
		part(model, "Wall", Vector3.new(T, 3, 0.4), frame * CFrame.new(0, 1.5, sx * (T / 2 - 0.2)), C.wood, Enum.Material.WoodPlanks)
	end
	local floor = frame * CFrame.new(0, 0.4, 0)
	local inside = frame * CFrame.new(0, 2, 0)
	local insideSize = Vector3.new(T - 0.8, 3.4, T - 0.8)
	local label = sign(model.Floor, "", Vector3.new(0, 6, 0))

	local corners = nil -- needleId -> corner index, once the needle-type splitter is fitted
	local padLabel = nil -- the SELL NEEDLES pad's sign, set once the pad is built below
	local function refresh()
		Needle.bundleIn(inside, insideSize)
		local count = 0
		local byType = {}
		for _, n in Needle.inBox(inside, insideSize) do
			n:SetAttribute("Binned", true) -- only its owner can pick it up (Needle.pickUp)
			count += Needle.count(n)
			local id = n:GetAttribute("NeedleId") or Needle.default.id
			byType[id] = (byType[id] or 0) + Needle.count(n)
		end
		label.Text = ("NEEDLE BIN\n%d needles%s"):format(count, corners and ", by type" or "")
		if padLabel then
			padLabel.Text = "SELL NEEDLES\nbin and pocket" .. priceLines(byType)
		end
	end
	refresh()
	task.spawn(function()
		while model.Parent do
			task.wait(1)
			refresh()
		end
	end)

	-- The needle-type splitter upgrade: a cross of dividers makes four corners, and each needle type gets its own
	-- corner (in the order the types first arrive; a fifth type shares with the first). Plots can sell it as an
	-- upgrade; the SELL NEEDLES pad works the same.
	local cornerLabels = {}
	local CORNER = { Vector3.new(-1.3, 0, -1.3), Vector3.new(1.3, 0, -1.3), Vector3.new(-1.3, 0, 1.3), Vector3.new(1.3, 0, 1.3) }
	local nextCorner = 0
	local function cornerFor(needleId)
		if not corners then
			return nil
		end
		if not corners[needleId] then
			nextCorner += 1
			local i = (nextCorner - 1) % 4 + 1
			corners[needleId] = i
			cornerLabels[i].Text = Needle.info(needleId).name:upper()
			cornerLabels[i].TextColor3 = (Needle.look(needleId))
		end
		return CORNER[corners[needleId]]
	end

	-- The needle polisher upgrade: a polishing wheel on the bin's side that polishes needles resting in the bin, up to
	-- Prices.PolishPerMinute a minute (a bundle counts as 10). Polished needles sell for Prices.PolishBonus more.
	local polisher = nil
	function bin.fitPolisher()
		if polisher then
			return
		end
		model:SetAttribute("Polisher", true)
		local side = frame * CFrame.new(T / 2 + 0.9, 0, 0)
		polisher = Instance.new("Model")
		polisher.Name = "NeedlePolisher"
		polisher:SetAttribute("Running", false)
		polisher.Parent = model
		local base = part(polisher, "Base", Vector3.new(1.4, 2.4, 2.4), side * CFrame.new(0, 1.2, 0), C.wood, Enum.Material.WoodPlanks)
		local wheel = part(polisher, "Wheel", Vector3.new(0.5, 2, 2), side * CFrame.new(0, 3.2, 0), C.metal, Enum.Material.Metal)
		wheel.Shape = Enum.PartType.Cylinder
		wheel:SetAttribute("Motion", "Spin")
		CollectionService:AddTag(wheel, "PropMotion")
		Skins.dress("needle_polisher", base, polisher, side)
		local spark = Instance.new("ParticleEmitter")
		spark.Rate = 0
		spark.Lifetime = NumberRange.new(0.2, 0.4)
		spark.Speed = NumberRange.new(4, 8)
		spark.LightEmission = 1
		spark.Size = NumberSequence.new(0.15, 0)
		spark.Parent = wheel
		task.spawn(function()
			local budget = 0
			while polisher.Parent do
				task.wait(1)
				budget = math.min(budget + Prices.PolishPerMinute / 60, Prices.PolishPerMinute)
				local worked = false
				for _, n in Needle.inBox(inside, insideSize) do
					local count = Needle.count(n)
					if not n:GetAttribute("Polished") and budget >= count then
						Needle.polish(n)
						budget -= count
						worked = true
					end
				end
				polisher:SetAttribute("Running", worked)
				spark.Rate = worked and 40 or 0
			end
		end)
	end

	function bin.splitByType()
		if corners then
			return
		end
		corners = {}
		model:SetAttribute("SplitByType", true)
		local h = 1.4
		part(model, "Divider", Vector3.new(T - 0.8, h, 0.2), floor * CFrame.new(0, h / 2, 0), C.metal, Enum.Material.Metal)
		part(model, "Divider", Vector3.new(0.2, h, T - 0.8), floor * CFrame.new(0, h / 2, 0), C.metal, Enum.Material.Metal)
		for i, at in CORNER do
			local tag = part(model, "CornerTag", Vector3.new(0.6, 0.1, 0.6), floor * CFrame.new(at + Vector3.new(0, 0.05, 0)), C.pad)
			tag.CanCollide = false
			local l = sign(tag, "", Vector3.new(0, 2, 0))
			l.Parent.Size = UDim2.fromOffset(110, 26)
			l.Parent.MaxDistance = 40
			cornerLabels[i] = l
		end
		label.Text = "NEEDLE BIN\nsorted by type"
		-- Needles already in the bin move to their corners.
		for _, n in Needle.inBox(inside, insideSize) do
			local at = cornerFor(n:GetAttribute("NeedleId") or Needle.default.id)
			n.CFrame = floor * CFrame.new(at + Vector3.new(rng:NextNumber(-0.6, 0.6), 0.4, rng:NextNumber(-0.6, 0.6)))
		end
	end

	-- Needles on their way into the bin (waiting to be thrown, or in the air), so a save taken mid-throw keeps them.
	-- clear() bumps generation, so throws queued before it never land in an emptied bin.
	local flying = {}
	local generation = 0

	-- Throws count needles from `from` into the bin, owned by ownerId, graded grade (nil is B). The bale's needles roll
	-- their mutations here, up front, so the pity rule can see them: with dry (the owner's run of bales without a
	-- mutation, Pity.apply) it returns the new dry count. Without dry, no pity. boost multiplies the mutation chance
	-- (a Hay Market bale's MutationBoost), on top of the weather where the needles come out (Needle.weatherAt).
	function bin.add(from, ownerId, count, needleId, grade, dry, boost)
		local gen = generation
		local mults, nears = {}, {}
		local odds, wet = Needle.weatherAt(from)
		for i = 1, count do
			mults[i], nears[i] = Needle.rollMutation((boost or 1) * odds, wet)
		end
		if dry then
			dry = Pity.apply(dry, mults, Prices.Pity)
		end
		for i = 1, count do
			local token = { ownerId = ownerId, id = needleId or Needle.default.id, grade = grade }
			flying[token] = true
			task.delay(i * 0.08, function()
				if gen ~= generation or not model.Parent then
					flying[token] = nil
					return
				end
				local at = cornerFor(needleId or Needle.default.id)
				local spread = at and 0.7 or 2
				local to = (floor * CFrame.new((at or Vector3.zero) + Vector3.new(rng:NextNumber(-spread, spread), 0.3, rng:NextNumber(-spread, spread)))).Position
				token.part = Needle.throw(from, to, ownerId, needleId, grade, mults[i], nears[i])
				if token.part then
					token.part:SetAttribute("Binned", true)
				end
				task.delay(2.5, function()
					flying[token] = nil -- landed (the longest hover plus flight is 2.1 seconds)
				end)
			end)
		end
		return dry
	end

	-- Sells the player's needles in the bin, except types their price hold keeps back. Each sale lowers the market as
	-- it goes, so a big pile can stop partway once the price drops under the hold. Returns count, value, { [id] = held }.
	local function sellFromBin(player)
		local hold = holdOf(player)
		local count, value, held = 0, 0, {}
		for _, n in Needle.inBox(inside, insideSize) do
			if n:GetAttribute("OwnerId") == player.UserId then
				local id = n:GetAttribute("NeedleId") or Needle.default.id
				if hold and Market.multiplier(id) < hold then
					held[id] = (held[id] or 0) + Needle.count(n)
				else
					count += Needle.count(n)
					value += Needle.value(n)
					Market.sold(id, Needle.count(n))
					n:Destroy()
				end
			end
		end
		return count, value, held
	end

	function bin.sell(player)
		if not Data.get(player) then
			return -- save still loading: selling now would take needles it can't pay for
		end
		local count, value = Needle.sellHeld(player)
		local inBin, binValue, held = sellFromBin(player)
		count += inBin
		value += binValue
		refresh()
		local holding = heldText(held, holdOf(player) or 1)
		if count == 0 then
			Data.toast(player, holding and ("Holding %s. Change the hold at the bin to sell now."):format(holding)
				or "You have no needles in this bin or your pocket. Run some hay through a sorter.")
			return
		end
		Machines.pay(player.UserId, value, ("Sold %d sorted needles for $%d.%s"):format(count, value, holding and (" Holding " .. holding .. ".") or ""), "Sorted needles")
		Events.fire(player, "needles_sold", count)
	end

	-- Held needles sell by themselves once the market reaches the hold (only while their owner is in the game).
	task.spawn(function()
		while model.Parent do
			task.wait(5)
			for _, player in Players:GetPlayers() do
				local hold = holdOf(player)
				if not hold then
					continue
				end
				local ready = false
				for _, n in Needle.inBox(inside, insideSize) do
					if n:GetAttribute("OwnerId") == player.UserId and Market.multiplier(n:GetAttribute("NeedleId") or Needle.default.id) >= hold then
						ready = true
						break
					end
				end
				if ready then
					local count, value = sellFromBin(player)
					if count > 0 then
						refresh()
						Machines.pay(player.UserId, value, ("The market hit your price: your bin sold %d needles for $%d."):format(count, value), "Sorted needles")
						Events.fire(player, "needles_sold", count)
					end
				end
			end
		end
	end)

	-- Take all (CEO #33): every needle of yours in the bin goes into your pocket in one go, to carry to a vault, the
	-- trading post or an order board. The SELL NEEDLES pad already sells the bin where it stands, so this is the trip.
	local takePrompt = Instance.new("ProximityPrompt")
	takePrompt.Name = "TakeAll"
	takePrompt.ActionText = "Take your needles"
	takePrompt.ObjectText = "Needle bin"
	takePrompt.KeyboardKeyCode = Enum.KeyCode.T
	takePrompt.HoldDuration = 0.6
	takePrompt.MaxActivationDistance = 9
	takePrompt.RequiresLineOfSight = false
	takePrompt.UIOffset = Vector2.new(0, 60) -- below the price hold prompt
	takePrompt.Parent = model.Floor
	takePrompt.Triggered:Connect(function(player)
		if not holdLimit:allow(player) or not Data.get(player) then
			return
		end
		local taken = 0
		for _, n in Needle.inBox(inside, insideSize) do
			if n:GetAttribute("OwnerId") == player.UserId then
				local count = Needle.count(n)
				Needle.giveKey(player, Needle.keyOfPart(n), count)
				taken += count
				n:Destroy()
			end
		end
		refresh()
		if taken == 0 then
			Data.toast(player, "None of the needles in this bin are yours.")
			return
		end
		Data.toast(player, ("Took %d needles out of the bin. Any SELL pad, vault or order board takes them from your pocket."):format(taken))
	end)

	-- Cycles the player's price hold: off, then at list price, then 5%, 10% and 15% over it.
	local holdPrompt = Instance.new("ProximityPrompt")
	holdPrompt.Name = "PriceHold"
	holdPrompt.ActionText = "Change price hold"
	holdPrompt.ObjectText = "Needle bin"
	holdPrompt.HoldDuration = 0.2
	holdPrompt.MaxActivationDistance = 9
	holdPrompt.RequiresLineOfSight = false
	holdPrompt.Parent = model.Floor
	holdPrompt.Triggered:Connect(function(player)
		if not holdLimit:allow(player) then
			return
		end
		local state = Data.get(player)
		if not state then
			return
		end
		local i = typeof(state.needleHold) == "number" and state.needleHold or 0
		i = (i + 1) % (#HOLD_STEPS + 1)
		state.needleHold = i ~= 0 and i or nil
		local hold = HOLD_STEPS[i]
		if not hold then
			Data.toast(player, "Price hold off: SELL NEEDLES sells at today's price.")
			return
		end
		local mine = {}
		for _, n in Needle.inBox(inside, insideSize) do
			if n:GetAttribute("OwnerId") == player.UserId then
				local id = n:GetAttribute("NeedleId") or Needle.default.id
				mine[id] = (mine[id] or 0) + Needle.count(n)
			end
		end
		local example = heldText(mine, hold)
		Data.toast(player, ("Your bins hold needles until they pay %d%% of list%s. They sell by themselves when it gets there."):format(
			math.round(hold * 100), example and (": " .. example) or ""))
	end)

	-- Drops one existing needle (a visible one a sorter caught) into the bin as it is.
	function bin.put(ownerId, needleId, mult, polished, grade)
		local at = cornerFor(needleId or Needle.default.id) or Vector3.zero
		local spread = cornerFor(needleId or Needle.default.id) and 0.7 or 2
		local n = Needle.setGrade(Needle.make(floor * CFrame.new(at + Vector3.new(rng:NextNumber(-spread, spread), 0.8, rng:NextNumber(-spread, spread))), ownerId, needleId, mult, polished), grade)
		n.Anchored = false
		refresh()
	end

	-- Needles in the bin, as { [key] = count } with Needle.keyOf keys ("steel", or "steel*12" when mutated); a bundle
	-- counts as its 10 needles. Everyone's, or only ownerId's.
	function bin.contents(ownerId)
		local byKey = {}
		local seen = {}
		local function add(n)
			seen[n] = true
			if ownerId == nil or n:GetAttribute("OwnerId") == ownerId then
				local key = Needle.keyOfPart(n)
				byKey[key] = (byKey[key] or 0) + Needle.count(n)
			end
		end
		for _, n in Needle.inBox(inside, insideSize) do
			add(n)
		end
		for token in flying do
			if token.part then
				if token.part.Parent and not seen[token.part] then
					add(token.part)
				end
			elseif ownerId == nil or token.ownerId == ownerId then
				local key = Needle.keyOf(token.id, 1, false, token.grade)
				byKey[key] = (byKey[key] or 0) + 1 -- not thrown yet, so not rolled: saved plain
			end
		end
		return byKey
	end

	-- Puts saved needles ({ [key] = count }, as contents returns) straight back in the bin, plain ones tied in bundles,
	-- laid in rows on the floor (anchored, so a big pile can't spill).
	-- Lays count saved needles of one key at spot() as Needle.bundleIn would leave them: a crate once there are
	-- LineMath.CRATE_AT bundles' worth (or mutated needles), bundles of 10, and loose singles, all anchored.
	local function placeStack(spot, ownerId, id, mult, polished, grade, count)
		local stack = mult == 1 and (count // Needle.BUNDLE) * Needle.BUNDLE or count
		if (mult == 1 and stack >= LineMath.CRATE_AT * Needle.BUNDLE) or (mult > 1 and count >= LineMath.CRATE_AT) then
			Needle.setGrade(Needle.bundle(spot(), ownerId, id, polished, stack, mult), grade).Anchored = true
			count -= stack
		end
		if mult == 1 then
			while count >= Needle.BUNDLE do
				Needle.setGrade(Needle.bundle(spot(), ownerId, id, polished), grade).Anchored = true
				count -= Needle.BUNDLE
			end
		end
		for _ = 1, count do
			Needle.setGrade(Needle.make(spot(), ownerId, id, mult, polished), grade).Anchored = true
		end
	end

	function bin.fill(ownerId, byKey)
		local perRow, rows = 4, 24
		local placed = 0
		local function nextSpot()
			local col = placed % perRow
			local row = math.floor(placed / perRow) % rows
			local layer = math.floor(placed / (perRow * rows))
			placed += 1
			return floor * CFrame.new(-1.95 + col * 1.3, 0.3 + layer * 0.6, -2.3 + row * 0.2)
		end
		for key, count in byKey do
			local id, mult, polished, grade = Needle.parseKey(key)
			if typeof(count) ~= "number" then
				continue
			end
			local at = cornerFor(id)
			if at then
				-- A split bin keeps each type in its corner: stack them there.
				-- 3 x 3 spots, five layers high, so the pile stays inside the bin; past that, the shared rows.
				local stacked = 0
				local function cornerSpot()
					if stacked >= 45 then
						return nextSpot()
					end
					local col, row, layer = stacked % 3, (stacked // 3) % 3, stacked // 9
					stacked += 1
					return floor * CFrame.new(at + Vector3.new((col - 1) * 0.7, 0.3 + layer * 0.6, (row - 1) * 0.7))
				end
				placeStack(cornerSpot, ownerId, id, mult, polished, grade, count)
				continue
			end
			placeStack(nextSpot, ownerId, id, mult, polished, grade, count)
		end
		refresh()
	end

	-- Removes every needle in the bin (the plot was given up).
	function bin.clear()
		generation += 1
		for token in flying do
			if token.part then
				token.part:Destroy()
			end
		end
		table.clear(flying)
		for _, n in Needle.inBox(inside, insideSize) do
			n:Destroy()
		end
		refresh()
	end

	bin.model = model
	local _, padSign = Machines.stepPad(model, (frame * CFrame.new(0, 0, T)).Position, C.pad, "SELL NEEDLES\nbin and pocket", bin.sell)
	padLabel = padSign
	refresh()
	return bin
end

-- Seconds a sorter spends on one bale's worth of hay, from its tier's hay per minute.
function Machines.sortSeconds(tierId, hay)
	local tier = tiers[tierId]
	return LineMath.sortSeconds(tier and tier.hayPerMin or math.huge, hay) -- no upper clamp, so every tier's speed is felt
end

-- Needle sorter over two belt cells: the cell at frame and the next one downstream. Bales wait at its rubber flap,
-- go in one at a time, the needles it finds fly to `bin` (a Machines.needleBin), and a clean bale comes out the far end.
-- payTo (optional) maps the owner of incoming hay to who gets paid and owns the needles (a plot's crew pays the owner).
local RATE_WINDOW = 120 -- seconds of work a sorter's sign averages over

-- How each sorter tier reads from across a plot (CEO #27), part-built until every tier has its Blender mesh: a painted
-- band along both sides, stars on the sign, and a silhouette of its own on the roof. The tier parts sit in the sorter
-- model, so an imported mesh replaces them like the rest of the fallback.
local TIER_LOOKS = {
	hand_sieve = { stars = 1, band = Color3.fromRGB(160, 132, 96) }, -- bare wood
	shaker_table = { stars = 2, band = Color3.fromRGB(122, 138, 104) }, -- sage paint
	conveyor_sorter = { stars = 3, band = Color3.fromRGB(104, 124, 140) }, -- slate blue paint
	magnet_drum = { stars = 4, band = Color3.fromRGB(150, 72, 58) }, -- barn red paint
	optical_sorter = { stars = 5, band = Color3.fromRGB(196, 160, 84) }, -- brass
	alien_collector = { stars = 6, band = Color3.fromRGB(96, 196, 180) },
}
Machines.TierLooks = TIER_LOOKS

local function moving(p, kind)
	p:SetAttribute("Motion", kind)
	CollectionService:AddTag(p, "PropMotion") -- turns or rattles only while the sorter is Running (Conveyors.client)
	return p
end

-- Adds tier's band and roof silhouette to a sorter model (center: middle of its two cells, height: its side walls).
local function dressTier(model, center, tier, height)
	local look = TIER_LOOKS[tier.id] or TIER_LOOKS.conveyor_sorter
	local paint = look.band
	for _, sx in { -1, 1 } do
		part(model, "TierBand", Vector3.new(0.7, 0.9, T * 2 + 0.1), center * CFrame.new(sx * (T / 2 - 0.3), TOP + height - 1, 0), paint, Enum.Material.Wood)
	end
	-- The hopper takes the upstream half of the roof, so each silhouette sits on the downstream half.
	local top = center * CFrame.new(0, TOP + height + 1, -T / 2 - 0.2)
	if tier.id == "hand_sieve" then
		-- A round riddle sieve resting on the roof: a wooden hoop with mesh in it.
		local rim = part(model, "SieveRim", Vector3.new(0.6, 4.6, 4.6), top * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), paint, Enum.Material.Wood)
		rim.Shape = Enum.PartType.Cylinder
		local screen = part(model, "SieveScreen", Vector3.new(0.62, 4, 4), rim.CFrame, C.darkMetal, Enum.Material.DiamondPlate)
		screen.Shape = Enum.PartType.Cylinder
		moving(screen, "Shake")
	elseif tier.id == "shaker_table" then
		-- A slatted deck tipped toward the chute, standing on four coil springs.
		for _, x in { -1.8, 1.8 } do
			for _, z in { -1.8, 1.8 } do
				local spring = part(model, "Spring", Vector3.new(0.9, 0.7, 0.7), top * CFrame.new(x, 0.45, z) * CFrame.Angles(0, 0, math.pi / 2), C.metal, Enum.Material.Metal)
				spring.Shape = Enum.PartType.Cylinder
			end
		end
		local deck = part(model, "ShakerDeck", Vector3.new(5, 0.3, 5.2), top * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(-8)), paint, Enum.Material.WoodPlanks)
		moving(deck, "Shake")
	elseif tier.id == "conveyor_sorter" then
		-- A covered belt climbing over the roof, driven by a motor on its high end.
		part(model, "BeltHood", Vector3.new(3.6, 1.4, 5.4), top * CFrame.new(0, 1, 0) * CFrame.Angles(math.rad(12), 0, 0), paint, Enum.Material.Metal)
		local motor = part(model, "Motor", Vector3.new(1.6, 1.4, 1.4), top * CFrame.new(2.2, 0.8, -2.2), C.darkMetal, Enum.Material.Metal)
		motor.Shape = Enum.PartType.Cylinder
		moving(motor, "Spin")
	elseif tier.id == "magnet_drum" then
		-- A big painted drum across the roof between two bearing blocks.
		for _, sx in { -1, 1 } do
			part(model, "Bearing", Vector3.new(0.8, 2.4, 1.4), top * CFrame.new(sx * (T / 2 - 0.6), 1.2, 0), C.darkMetal, Enum.Material.Metal)
		end
		local drum = part(model, "MagnetDrum", Vector3.new(T - 2, 4, 4), top * CFrame.new(0, 2.4, 0), paint, Enum.Material.Metal)
		drum.Shape = Enum.PartType.Cylinder
		moving(drum, "Spin")
	elseif tier.id == "optical_sorter" then
		-- A tall brass-trimmed cabinet with a camera hood whose lamp glows while it works.
		part(model, "Cabinet", Vector3.new(4.4, 4.5, 4.4), top * CFrame.new(0, 2.25, 0), C.darkMetal, Enum.Material.Metal)
		part(model, "CabinetTrim", Vector3.new(4.6, 0.4, 4.6), top * CFrame.new(0, 4.5, 0), paint, Enum.Material.Metal)
		local hood = part(model, "CameraHood", Vector3.new(2, 1.6, 1.4), top * CFrame.new(0, 5.5, -1.2), paint, Enum.Material.Metal)
		local lens = part(model, "Lens", Vector3.new(1.2, 0.8, 0.2), hood.CFrame * CFrame.new(0, 0, -0.75), Color3.fromRGB(255, 226, 160), Enum.Material.Glass)
		lens.Transparency = 0.2
		local light = Instance.new("PointLight")
		light.Color = lens.Color
		light.Range = 8
		light.Brightness = 0
		light.Parent = lens
		model:GetAttributeChangedSignal("Running"):Connect(function()
			light.Brightness = model:GetAttribute("Running") and 2 or 0
		end)
	elseif tier.id == "alien_collector" then
		local dome = part(model, "Dome", Vector3.new(4.8, 4.8, 4.8), top * CFrame.new(0, 1, 0), Color3.fromRGB(170, 230, 220), Enum.Material.Glass)
		dome.Shape = Enum.PartType.Ball
		dome.Transparency = 0.4
		local ring = part(model, "DomeRing", Vector3.new(0.4, 5.4, 5.4), top * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), paint, Enum.Material.Neon)
		ring.Shape = Enum.PartType.Cylinder
		moving(ring, "Spin")
	end
	return look
end

function Machines.sorter(parent, frame, tierId, bin, payTo)
	local tier = tiers[tierId] or tiers.conveyor_sorter
	local center = frame * CFrame.new(0, 0, -T / 2) -- middle of the two cells
	local model = Instance.new("Model")
	model.Name = "NeedleSorter"
	model:SetAttribute("Tier", tier.id)
	model:SetAttribute("Running", false) -- the machine mesh's moving pieces turn only while this is true
	model.Parent = parent

	local height = 7
	for _, sx in { -1, 1 } do
		part(model, "Side", Vector3.new(0.6, height, T * 2), center * CFrame.new(sx * (T / 2 - 0.3), TOP + height / 2, 0), C.planks, Enum.Material.WoodPlanks)
	end
	local roof = part(model, "Roof", Vector3.new(T + 0.4, 1, T * 2 + 0.4), center * CFrame.new(0, TOP + height + 0.5, 0), C.darkMetal, Enum.Material.Metal)
	local hopper = part(model, "Hopper", Vector3.new(T - 1.4, 1.4, 3), center * CFrame.new(0, TOP + height + 1.7, 1), C.metal, Enum.Material.Metal)
	-- The flap blocks the way in. Bales wait against it until the sorter takes them.
	local flap = part(model, "Flap", Vector3.new(T - 1.2, height - 0.6, 0.4), center * CFrame.new(0, TOP + (height - 0.6) / 2 + 0.3, T - 0.2), C.rubber)
	flap.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
	-- A chute on the left side points at the bin.
	local chuteFrom = (center * CFrame.new(-T / 2 - 0.2, TOP + 3, 0)).Position
	part(model, "Chute", Vector3.new(3, 0.3, 2), center * CFrame.new(-T / 2 - 1.4, TOP + 2.5, 0) * CFrame.Angles(0, 0, math.rad(-20)), C.metal, Enum.Material.Metal)
	local isAlienTier = tier.hayPerMin == math.huge -- no rate on its sign: it sorts only while its beam is up
	local look = dressTier(model, center, tier, height)
	local title = tier.name:upper() .. " " .. string.rep("★", look.stars)
	local label = sign(roof, title, Vector3.new(0, 9, 0)) -- above the tallest roof silhouette, five lines tall

	-- The oil can on the right side: click it to buy a can of oil, and the sorter works faster for a while.
	local canModel = Instance.new("Model")
	canModel.Name = "OilCan"
	canModel.Parent = model
	local canBase = center * CFrame.new(T / 2 + 0.6, TOP - 0.6, 1)
	part(canModel, "Shelf", Vector3.new(1.4, 0.2, 1.6), canBase * CFrame.new(0, -0.1, 0), C.wood, Enum.Material.WoodPlanks)
	local can = part(canModel, "Can", Vector3.new(1.3, 0.9, 0.9), canBase * CFrame.new(0, 0.65, 0) * CFrame.Angles(0, 0, math.pi / 2), C.darkMetal, Enum.Material.Metal)
	can.Shape = Enum.PartType.Cylinder
	part(canModel, "Spout", Vector3.new(0.15, 0.15, 0.9), canBase * CFrame.new(0, 1.4, -0.35) * CFrame.Angles(math.rad(-35), 0, 0), C.metal, Enum.Material.Metal)
	local oilClick = Instance.new("ClickDetector")
	oilClick.MaxActivationDistance = 14
	oilClick.Parent = can
	Skins.dress("sorter_boost_oil", can, canModel, canBase)
	local oiled = 0 -- bales left that sort faster
	-- The tier's Blender machine, when it was imported. Its Roller*, Drum and Crank parts spin and its Shaker rattles
	-- while the model's Running attribute is true (Skins, Conveyors.client).
	Skins.dress(tier.id, roof, model, center)

	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.6, 1.2)
	dust.Speed = NumberRange.new(3, 7)
	dust.SpreadAngle = Vector2.new(60, 60)
	dust.Color = ColorSequence.new(C.cleanHay)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	dust.Parent = hopper

	local zone = center * CFrame.new(0, TOP + 3.5, T + 1.6) -- just upstream of the flap
	local zoneSize = Vector3.new(T - 0.8, 7, 3.2)
	local out = center * CFrame.new(0, TOP + 1.45, -T + 2) * CFrame.Angles(0, math.pi / 2, 0)
	local sorted = 0
	local recent = {} -- { { t, bales, needles, dollars } } over the last RATE_WINDOW seconds, for the sign (CEO #28)
	local lastHay = "meadow"
	-- Bottleneck lamp state (CEO #29, rules in LineMath.lamp).
	local sortingNow, lastSortEnd = false, os.clock()
	local lastRefused, refusedNeed = nil, nil
	local lampWhy = nil

	-- The sign: tier, bales sorted, what the line did lately next to what this sorter makes kept full (the same
	-- formula as tools/line_sim.py, at today's market price for the hay it last sorted).
	local function refreshLabel()
		local rateText = ""
		if not isAlienTier then
			local bpm, npm, perHour = LineRate.measured(recent, os.clock(), RATE_WINDOW)
			local needleId = Needle.forHay(lastHay)
			local full = LineRate.line(lastHay, tier.id, nil, oiled > 0, true, Market.multiplier(needleId))
			rateText = ("\n%s bales/min, %s needles/min, $%s/hr\nkept full: $%s/hr"):format(
				LineRate.short(bpm),
				LineRate.short(npm),
				LineRate.short(perHour),
				LineRate.short(full.perHour)
			)
		end
		label.Text = ("%s\n%d bales sorted, finds %d%%%s%s%s"):format(
			title,
			sorted,
			math.round(tier.recovery * 100),
			rateText,
			oiled > 0 and ("\nOILED: %d bales"):format(oiled) or "",
			lampWhy and ("\n" .. lampWhy:upper()) or ""
		)
		can.Color = oiled > 0 and C.go or C.darkMetal
	end
	if not isAlienTier then -- the collector's sign counts down its beam instead
		task.spawn(function()
			while model.Parent do
				task.wait(5)
				refreshLabel()
			end
		end)
	end

	oilClick.MouseClick:Connect(function(player)
		local more = LineMath.oilAdd(oiled, Oil.bales, Oil.maxBales)
		if not more then
			Data.toast(player, ("This sorter is already well oiled (%d bales)."):format(oiled))
			return
		end
		local ok, why = Bank.charge(player, Oil.price, "Sorter oil")
		if not ok then
			Data.toast(player, ("Sorter oil costs $%d. %s"):format(Oil.price, why or ""))
			return
		end
		oiled = more
		refreshLabel()
		Feedback.play("Scoop", can)
		Data.toast(player, ("Oiled the %s: %d%% faster for the next %d bales."):format(tier.name:lower(), math.round(Oil.speedup * 100), Oil.bales))
	end)

	-- needleBoost: times the hidden needles (rich field, chute, region event, golden field: the bale's NeedleBoost,
	-- as breaking it by hand gives). mutationBoost: times each found needle's mutation chance (Hay Market bales).
	local function sort(hay, ownerId, hayType, recoveryMult, needleBoost, mutationBoost)
		sortingNow = true
		model:SetAttribute("Running", true)
		dust.Rate = 30
		local rest = roof.CFrame
		local started = os.clock()
		local seconds
		seconds, oiled = LineMath.oiledSeconds(Machines.sortSeconds(tier.id, hay), oiled, Oil.speedup)
		while os.clock() - started < seconds do
			roof.CFrame = rest * CFrame.new(rng:NextNumber(-0.08, 0.08), rng:NextNumber(-0.05, 0.05), 0)
			task.wait(0.05)
		end
		roof.CFrame = rest
		dust.Rate = 0
		model:SetAttribute("Running", false)
		sortingNow, lastSortEnd = false, os.clock()

		-- Each hidden needle is found with the tier's recovery chance. The rest stay lost in the hay.
		local hidden = Economy.rollNeedles(rng, hay, math.min(needleChance(hayType) * (needleBoost or 1), 1))
		local found = LineMath.found(rng, hidden, tier.recovery, recoveryMult)
		if bin then
			local dry = bin.add(chuteFrom, ownerId, found, Needle.forHay(hayType), Needle.gradeFor(tier.id), ownerId and (dryRun[ownerId] or 0), mutationBoost)
			if ownerId then
				dryRun[ownerId] = dry
			end
		end
		spawnSortedBale(out, ownerId, hay, hayType)
		local bales = hay / (Config.PiecesPerBale * Config.HayPerPiece)
		LineStats.record(ownerId, "bales", bales)
		LineStats.record(ownerId, "needles", found)
		lastHay = hayType or "meadow"
		local needlePrice = Needle.priceOf(Needle.forHay(lastHay), 1, false, Needle.gradeFor(tier.id))
		table.insert(recent, { os.clock(), bales, found, hay * Economy.HAY_PRICE + found * needlePrice })
		sorted += 1
		model:SetAttribute("Sorted", sorted)
		refreshLabel()
	end

	-- Region hay (Factory.Treatments) that still needs its region machine, and a reminder to its owner now and then.
	local function untreated(body)
		local t = Factory.Treatments[hayTypeOf(body)]
		if t and not body:GetAttribute(t.mark) then
			return t
		end
		return nil
	end
	local toldAt = {}
	local function refuse(ownerId, need)
		lastRefused, refusedNeed = os.clock(), string.gsub(need.machine, "_", " ")
		local owner = ownerId and Players:GetPlayerByUserId(ownerId)
		if owner and os.clock() - (toldAt[ownerId] or -math.huge) > 15 then
			toldAt[ownerId] = os.clock()
			Data.toast(owner, need.refuse)
		end
	end

	-- Hay that was sorted upstream goes straight out the far end.
	local function passThrough(p)
		p.CFrame = out * CFrame.new(0, 0, rng:NextNumber(-1, 1))
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
	end

	-- The Alien collector (quest only) sorts everything instantly at 100%, but only while its beam is up: a player
	-- steps on BEAM UP once a day (UTC) to open a window of Factory.AlienWindowSeconds. Bales wait at the flap otherwise.
	local isAlien = tier.hayPerMin == math.huge
	local beamUntil = 0
	if isAlien then
		local beam = part(model, "Beam", Vector3.new(T - 1.6, 60, T - 1.6), center * CFrame.new(0, TOP + height + 31, 0), C.go, Enum.Material.Neon)
		beam.Shape = Enum.PartType.Cylinder
		beam.CFrame = center * CFrame.new(0, TOP + height + 31, 0) * CFrame.Angles(0, 0, math.pi / 2)
		beam.Size = Vector3.new(60, T - 1.6, T - 1.6)
		beam.CanCollide = false
		beam.CanQuery = false
		beam.Transparency = 1
		local padAt = (center * CFrame.new(T / 2 + 2.5, 0, -T / 2 - 1)).Position
		Machines.stepPad(model, padAt, C.go, "BEAM UP\nonce a day", function(player)
			if os.clock() < beamUntil then
				return
			end
			local today = math.floor(os.time() / 86400)
			if alienUsedDay[player.UserId] == today then
				local left = (today + 1) * 86400 - os.time()
				Data.toast(player, ("The collector is recharging. Next beam in %dh %dm."):format(left // 3600, (left % 3600) // 60))
				return
			end
			alienUsedDay[player.UserId] = today
			beamUntil = os.clock() + Factory.AlienWindowSeconds
			beam.Transparency = 0.6
			Data.toast(player, ("The beam is up for %d seconds. Feed it everything you have."):format(Factory.AlienWindowSeconds))
			task.spawn(function()
				while os.clock() < beamUntil and model.Parent do
					label.Text = ("ALIEN COLLECTOR\nBEAM UP: %ds"):format(math.ceil(beamUntil - os.clock()))
					task.wait(0.5)
				end
				beam.Transparency = 1
				refreshLabel()
			end)
		end)
	end

	-- The bottleneck lamp on the upstream corner: green sorting, amber starved, red backed up, jammed or refusing.
	local LAMP = { green = C.go, amber = Color3.fromRGB(230, 170, 60), red = Color3.fromRGB(200, 70, 55) }
	local lampAt = center * CFrame.new(-T / 2 + 0.4, TOP + height + 1, T - 0.4)
	part(model, "LampPost", Vector3.new(0.3, 1.2, 0.3), lampAt * CFrame.new(0, 0.6, 0), C.darkMetal, Enum.Material.Metal)
	local lamp = part(model, "BottleneckLamp", Vector3.new(0.9, 0.9, 0.9), lampAt * CFrame.new(0, 1.5, 0), LAMP.amber, Enum.Material.Neon)
	lamp.Shape = Enum.PartType.Ball
	lamp.CanCollide = false
	local lampLight = Instance.new("PointLight")
	lampLight.Range = 6
	lampLight.Brightness = 1
	lampLight.Color = LAMP.amber
	lampLight.Parent = lamp
	-- Two cells upstream of the flap: where a queue of bales stands when this sorter can't keep up.
	local queueBox = center * CFrame.new(0, TOP + 2, T * 2)
	local queueSize = Vector3.new(T - 0.4, 4, T * 2)
	task.spawn(function()
		local queueSince = nil
		while model.Parent do
			task.wait(0.5)
			local queued, jam = 0, false
			for _, p in Workspace:GetPartBoundsInBox(queueBox, queueSize) do
				local b = Bales.fromPart(p)
				if b and p == b.body and not b.gone and not b.sorted then
					queued += 1
					jam = jam or Jams.isJammed(p)
				end
			end
			local now = os.clock()
			if queued >= 2 then
				queueSince = queueSince or now
			else
				queueSince = nil
			end
			local color, why = LineMath.lamp({
				sorting = sortingNow,
				idleSeconds = now - lastSortEnd,
				queued = queued,
				queuedSeconds = queueSince and now - queueSince or 0,
				jammed = jam,
				refusedSeconds = lastRefused and now - lastRefused,
				need = refusedNeed,
				beamDown = isAlien and now >= beamUntil,
			})
			lamp.Color, lampLight.Color = LAMP[color], LAMP[color]
			model:SetAttribute("Lamp", color)
			if why ~= lampWhy then
				lampWhy = why
				if not (isAlien and now < beamUntil) then
					refreshLabel()
				end
			end
		end
	end)

	task.spawn(function()
		while model.Parent do
			task.wait(isAlien and 0.05 or 0.2)
			if isAlien and os.clock() >= beamUntil then
				continue
			end
			local bale, loose = nil, {}
			for _, p in Workspace:GetPartBoundsInBox(zone, zoneSize) do
				local b = Bales.fromPart(p)
				if b and not b.gone and not b.carriedBy and not b.breaking then
					local need = not b.sorted and not isAlien and p == b.body and untreated(p)
					if need and need.required then
						passThrough(p) -- region hay that skipped its machine rides on, unsorted
						refuse(b.ownerId, need)
					elseif not b.sorted then
						bale = bale or b
					elseif p == b.body then
						passThrough(p) -- already sorted upstream: never sorted twice, and never left jamming the flap
					end
				elseif Hay.isPiece(p) then
					if Needle.isNeedle(p) then
						-- A visible needle that spilled from a bale: it goes to the bin as it is, not counted as a strand.
						if bin and p.Parent then
							local owner = p:GetAttribute("OwnerId")
							bin.put(payTo and payTo(owner) or owner, p:GetAttribute("NeedleId"), p:GetAttribute("Mutation"), p:GetAttribute("Polished"), p:GetAttribute("Grade"))
							Hay.remove(p)
						else
							passThrough(p)
						end
					elseif p:GetAttribute("Sorted") then
						passThrough(p)
					else
						table.insert(loose, p)
					end
				end
			end
			if bale then
				local ownerId, hayType = bale.ownerId, hayTypeOf(bale.body)
				if payTo then
					ownerId = payTo(ownerId)
				end
				local need = not isAlien and untreated(bale.body)
				if need then
					refuse(bale.ownerId, need) -- not required, so it sorts, at need.penalty of the recovery
				end
				local needleBoost, mutationBoost = baleBoosts(bale.body)
				Bales.consume(bale)
				sort(Config.PiecesPerBale * Config.HayPerPiece, ownerId, hayType, need and need.penalty or 1, needleBoost, mutationBoost)
			elseif #loose > 0 then
				-- One owner and one hay type per batch; anything else in the hopper goes next tick.
				local firstOwner, hayType = loose[1]:GetAttribute("OwnerId"), hayTypeOf(loose[1])
				local ownerId = firstOwner
				if payTo then
					ownerId = payTo(ownerId)
				end
				local taken, boosted = 0, 0
				for _, p in loose do
					if p:GetAttribute("OwnerId") == firstOwner and hayTypeOf(p) == hayType then
						local strands = Hay.strandsIn(p) -- a raked pile counts every strand in it
						taken += strands
						boosted += strands * boostOf(p, "NeedleBoost") -- strands from a rich bale keep its boost
						Hay.remove(p)
					end
				end
				sort(taken * Config.HayPerPiece, ownerId, hayType, 1, taken > 0 and boosted / taken or 1)
			end
		end
	end)
	return model
end

-- Hay buyer: an open hopper at the end of a belt (the belt comes in from local +Z). Pays whoever owns what drops in:
-- sorted bales at the hay price, and unsorted hay at the hay price plus only $1 per hidden needle. payTo (optional)
-- maps that owner to who gets paid, as for Machines.sorter.
function Machines.hayBuyer(parent, frame, title, payTo)
	local model = Instance.new("Model")
	model.Name = "HayBuyer"
	model.Parent = parent
	local floorY = TOP - 2
	part(model, "Base", Vector3.new(T, floorY, T), frame * CFrame.new(0, floorY / 2, 0), C.wood, Enum.Material.WoodPlanks)
	part(model, "Back", Vector3.new(T, 5, 0.4), frame * CFrame.new(0, floorY + 2.5, -T / 2 + 0.2), C.planks, Enum.Material.WoodPlanks)
	for _, sx in { -1, 1 } do
		part(model, "Side", Vector3.new(0.4, 5, T), frame * CFrame.new(sx * (T / 2 - 0.2), floorY + 2.5, 0), C.planks, Enum.Material.WoodPlanks)
	end
	sign(model.Back, title, Vector3.new(0, 5, 0))

	local zone = frame * CFrame.new(0, floorY + 3, 0)
	local unsorted = {} -- ownerId -> { hay, needles } waiting to be paid in one message
	task.spawn(function()
		while model.Parent do
			task.wait(0.25)
			for _, p in Workspace:GetPartBoundsInBox(zone, Vector3.new(T - 0.8, 6, T - 0.8)) do
				local sortedBale = Bales.fromPart(p)
				if sortedBale and sortedBale.sorted and p == sortedBale.body and not sortedBale.gone and not sortedBale.carriedBy and not sortedBale.breaking then
					local hay = sortedBale.sortedHay or 0
					local value = math.floor(hay * Economy.HAY_PRICE)
					local ownerId = sortedBale.ownerId
					if payTo then
						ownerId = payTo(ownerId)
					end
					-- Hay nobody has handled has no one to pay, so it stays in the hopper until someone picks it up.
					if ownerId and Players:GetPlayerByUserId(ownerId) then
						Bales.consume(sortedBale)
						Machines.pay(ownerId, value, ("Paid $%d for %d sorted hay."):format(value, hay), "Hay buyer")
					end
				else
					local b = Bales.fromPart(p)
					local hay, ownerId, hayType = 0, nil, "meadow"
					local take = nil
					local clean = false
					-- A bale being broken open spills its strands here next: pay for those, not the bale too.
					if b and p == b.body and not b.gone and not b.carriedBy and not b.breaking then
						hay, ownerId, hayType = Config.PiecesPerBale * Config.HayPerPiece, b.ownerId, hayTypeOf(p)
						local seller = ownerId -- who handled the bale, before payTo sends the cash to the plot owner
						take = function()
							Bales.consume(b)
							if seller then
								Events.fire(seller, "bale_sold", 1, { hayType = hayType })
							end
						end
					elseif Hay.isPiece(p) and not Needle.isNeedle(p) then -- a visible needle stays for its finder to pick up
						hay, ownerId, hayType = Config.HayPerPiece * Hay.strandsIn(p), p:GetAttribute("OwnerId"), hayTypeOf(p)
						clean = p:GetAttribute("Sorted") == true -- from a sorted bale that broke: its needles are gone
						take = function()
							Hay.remove(p)
						end
					end
					if hay > 0 and ownerId and payTo then
						ownerId = payTo(ownerId)
					end
					-- Hay nobody has handled has no one to pay, so it stays in the hopper until someone picks it up.
					if hay > 0 and ownerId and Players:GetPlayerByUserId(ownerId) then
						take()
						local t = unsorted[ownerId] or { hay = 0, needles = 0 }
						t.hay += hay
						if not clean then
							t.needles += Economy.rollNeedles(rng, hay, needleChance(hayType))
						end
						unsorted[ownerId] = t
					end
				end
			end
			for ownerId, t in unsorted do
				local value = Economy.rawLoadValue(t.hay, t.needles)
				Machines.pay(
					ownerId,
					value,
					("Paid $%d for %d hay. It had %d needles in it, paid at only $%d each. Sort them yourself for full price."):format(
						value,
						t.hay,
						t.needles,
						Economy.RAW_NEEDLE_PRICE
					)
				)
			end
			table.clear(unsorted)
		end
	end)
	return model
end

-- A splitter tile: loads come in from behind and leave through its left or right side onto the tiles there.
-- rule "alternate" sends them left, right, left...; rule "sorted" sends sorted bales left and everything else
-- (unsorted bales, loose hay, needles) right, so unsorted hay can loop back to a sorter. A side with no tile is skipped.
-- Lay it before Conveyors.finish(grid), like any tile. Returns the tile's model.
function Machines.splitter(grid, gx, gz, dir, rule)
	local belt = Conveyors.place(grid, gx, gz, dir)
	local tile = Conveyors.makeSplitter(grid, gx, gz)
	belt.AssemblyLinearVelocity = Vector3.zero -- the splitter pushes each load itself
	belt:SetAttribute("Speed", 0)
	local left, right = Conveyors.sides(tile.d)
	local center = Conveyors.cellCenter(grid, gx, gz)
	local zone = CFrame.new(center + Vector3.new(0, TOP + 2.5, 0))
	local zoneSize = Vector3.new(T - 0.4, 5, T - 0.4)
	local label = sign(belt, rule == "sorted" and "SPLITTER\nsorted left" or "SPLITTER", Vector3.new(0, 4, 0))
	label.Parent.MaxDistance = 40

	-- A side is a way out when a tile there takes loads from this side: any flat belt not running straight back at us,
	-- or a ramp whose foot is that cell and climbs away from us (its sides are rails).
	local function open(side)
		local nx, nz = gx + math.round(side.X), gz + math.round(side.Z)
		local n = Conveyors.tileAt(grid, nx, nz)
		if not n then
			return false
		end
		if n.kind == "ramp" then
			local i = n.inAt
			return i ~= nil and i.level == 0 and i.gx == nx and i.gz == nz and (n.d - side).Magnitude < 0.01
		end
		return (n.d + side).Magnitude > 0.01
	end

	local going = {} -- part -> side it is being pushed out of
	local nextLeft = true
	local function pick(p)
		local want
		if rule == "sorted" then
			local b = Bales.fromPart(p)
			want = (b and b.sorted) and left or right
		else
			want = nextLeft and left or right
			nextLeft = not nextLeft
		end
		local other = want == left and right or left
		if not open(want) and open(other) then
			return other
		end
		return want
	end

	task.spawn(function()
		local nextScan = 0
		while tile.model.Parent do
			if os.clock() >= nextScan then
				nextScan = os.clock() + 0.15
				local seen = {}
				for _, p in Workspace:GetPartBoundsInBox(zone, zoneSize) do
					local b = Bales.fromPart(p)
					local load = (b and p == b.body and not b.gone and not b.carriedBy) or Hay.isPiece(p) or Needle.isNeedle(p)
					if load and not p.Anchored then
						seen[p] = true
						if not going[p] then
							going[p] = pick(p)
							pcall(function()
								p:SetNetworkOwner(nil)
							end)
						end
					end
				end
				for p in going do
					if not seen[p] then
						going[p] = nil
					end
				end
			end
			for p, side in going do
				if p.Parent then
					local v = p.AssemblyLinearVelocity
					p.AssemblyLinearVelocity = side * Factory.BeltSpeed + Vector3.new(0, math.min(v.Y, 0), 0)
				end
			end
			RunService.Heartbeat:Wait()
		end
	end)
	return tile.model
end

return Machines
