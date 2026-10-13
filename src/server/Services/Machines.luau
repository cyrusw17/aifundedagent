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
require(script.Parent.Jams) -- watches belts for stuck bales (Jams.luau)
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
	local function refresh()
		Needle.bundleIn(inside, insideSize)
		local count = 0
		for _, n in Needle.inBox(inside, insideSize) do
			count += Needle.count(n)
		end
		label.Text = ("NEEDLE BIN\n%d needles%s"):format(count, corners and ", by type" or "")
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

	-- Throws count needles from `from` into the bin, owned by ownerId.
	function bin.add(from, ownerId, count, needleId)
		local gen = generation
		for i = 1, count do
			local token = { ownerId = ownerId, id = needleId or Needle.default.id }
			flying[token] = true
			task.delay(i * 0.08, function()
				if gen ~= generation or not model.Parent then
					flying[token] = nil
					return
				end
				local at = cornerFor(needleId or Needle.default.id)
				local spread = at and 0.7 or 2
				local to = (floor * CFrame.new((at or Vector3.zero) + Vector3.new(rng:NextNumber(-spread, spread), 0.3, rng:NextNumber(-spread, spread)))).Position
				token.part = Needle.throw(from, to, ownerId, needleId)
				task.delay(2.5, function()
					flying[token] = nil -- landed (the longest hover plus flight is 2.1 seconds)
				end)
			end)
		end
	end

	function bin.sell(player)
		if not Data.get(player) then
			return -- save still loading: selling now would take needles it can't pay for
		end
		local count, value = Needle.sellHeld(player)
		for _, n in Needle.inBox(inside, insideSize) do
			if n:GetAttribute("OwnerId") == player.UserId then
				count += Needle.count(n)
				value += Needle.value(n)
				Market.sold(n:GetAttribute("NeedleId"), Needle.count(n))
				n:Destroy()
			end
		end
		refresh()
		if count == 0 then
			Data.toast(player, "You have no needles in this bin or your pocket. Run some hay through a sorter.")
			return
		end
		Machines.pay(player.UserId, value, ("Sold %d sorted needles for $%d."):format(count, value), "Sorted needles")
		Events.fire(player, "needles_sold", count)
	end

	-- Needles in the bin, as { [key] = count } with Needle.keyOf keys ("steel", or "steel*12" when mutated); a bundle
	-- counts as its 10 needles. Everyone's, or only ownerId's.
	function bin.contents(ownerId)
		local byKey = {}
		local seen = {}
		local function add(n)
			seen[n] = true
			if ownerId == nil or n:GetAttribute("OwnerId") == ownerId then
				local key = Needle.keyOf(n:GetAttribute("NeedleId") or Needle.default.id, n:GetAttribute("Mutation"), n:GetAttribute("Polished"))
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
				byKey[token.id] = (byKey[token.id] or 0) + 1 -- not thrown yet, so not rolled: saved plain
			end
		end
		return byKey
	end

	-- Puts saved needles ({ [key] = count }, as contents returns) straight back in the bin, plain ones tied in bundles,
	-- laid in rows on the floor (anchored, so a big pile can't spill).
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
			local id, mult, polished = Needle.parseKey(key)
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
				if mult == 1 then
					while count >= Needle.BUNDLE do
						Needle.bundle(cornerSpot(), ownerId, id, polished).Anchored = true
						count -= Needle.BUNDLE
					end
				end
				for _ = 1, count do
					Needle.make(cornerSpot(), ownerId, id, mult, polished).Anchored = true
				end
				continue
			end
			if mult == 1 then
				while count >= Needle.BUNDLE do
					Needle.bundle(nextSpot(), ownerId, id, polished).Anchored = true
					count -= Needle.BUNDLE
				end
			end
			for _ = 1, count do
				local n = Needle.make(nextSpot(), ownerId, id, mult, polished)
				n.Anchored = true
			end
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
	Machines.stepPad(model, (frame * CFrame.new(0, 0, T)).Position, C.pad, "SELL NEEDLES\nbin and pocket", bin.sell)
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
	local label = sign(roof, tier.name:upper(), Vector3.new(0, 4, 0))

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
	-- The tier's Blender machine, when it was imported (the hand sieve is a hand tool, not a machine).
	if tier.id ~= "hand_sieve" then
		Skins.dress(tier.id, roof, model, center)
	end

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

	local function refreshLabel()
		label.Text = ("%s\n%d bales sorted, finds %d%%%s"):format(
			tier.name:upper(),
			sorted,
			math.round(tier.recovery * 100),
			oiled > 0 and ("\nOILED: %d bales"):format(oiled) or ""
		)
		can.Color = oiled > 0 and C.go or C.darkMetal
	end

	oilClick.MouseClick:Connect(function(player)
		if oiled + Oil.bales > Oil.maxBales then
			Data.toast(player, ("This sorter is already well oiled (%d bales)."):format(oiled))
			return
		end
		local ok, why = Bank.charge(player, Oil.price, "Sorter oil")
		if not ok then
			Data.toast(player, ("Sorter oil costs $%d. %s"):format(Oil.price, why or ""))
			return
		end
		oiled += Oil.bales
		refreshLabel()
		Feedback.play("Scoop", can)
		Data.toast(player, ("Oiled the %s: %d%% faster for the next %d bales."):format(tier.name:lower(), math.round(Oil.speedup * 100), Oil.bales))
	end)

	local function sort(hay, ownerId, hayType)
		model:SetAttribute("Running", true)
		dust.Rate = 30
		local rest = roof.CFrame
		local started = os.clock()
		local seconds = Machines.sortSeconds(tier.id, hay)
		if oiled > 0 then
			seconds /= 1 + Oil.speedup
			oiled -= 1
		end
		while os.clock() - started < seconds do
			roof.CFrame = rest * CFrame.new(rng:NextNumber(-0.08, 0.08), rng:NextNumber(-0.05, 0.05), 0)
			task.wait(0.05)
		end
		roof.CFrame = rest
		dust.Rate = 0
		model:SetAttribute("Running", false)

		-- Each hidden needle is found with the tier's recovery chance. The rest stay lost in the hay.
		local hidden = Economy.rollNeedles(rng, hay, needleChance(hayType))
		local found = 0
		for _ = 1, hidden do
			if rng:NextNumber() < tier.recovery then
				found += 1
			end
		end
		if bin then
			bin.add(chuteFrom, ownerId, found, Needle.forHay(hayType))
		end
		spawnSortedBale(out, ownerId, hay, hayType)
		LineStats.record(ownerId, "bales", hay / (Config.PiecesPerBale * Config.HayPerPiece))
		LineStats.record(ownerId, "needles", found)
		sorted += 1
		model:SetAttribute("Sorted", sorted)
		refreshLabel()
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
					if not b.sorted then
						bale = bale or b
					elseif p == b.body then
						passThrough(p) -- already sorted upstream: never sorted twice, and never left jamming the flap
					end
				elseif Hay.isPiece(p) then
					if p:GetAttribute("Sorted") then
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
				Bales.consume(bale)
				sort(Config.PiecesPerBale * Config.HayPerPiece, ownerId, hayType)
			elseif #loose > 0 then
				-- One owner and one hay type per batch; anything else in the hopper goes next tick.
				local firstOwner, hayType = loose[1]:GetAttribute("OwnerId"), hayTypeOf(loose[1])
				local ownerId = firstOwner
				if payTo then
					ownerId = payTo(ownerId)
				end
				local taken = 0
				for _, p in loose do
					if p:GetAttribute("OwnerId") == firstOwner and hayTypeOf(p) == hayType then
						Hay.remove(p)
						taken += 1
					end
				end
				sort(taken * Config.HayPerPiece, ownerId, hayType)
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
				if sortedBale and sortedBale.sorted and p == sortedBale.body and not sortedBale.gone and not sortedBale.carriedBy then
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
					if b and p == b.body and not b.gone and not b.carriedBy then
						hay, ownerId, hayType = Config.PiecesPerBale * Config.HayPerPiece, b.ownerId, hayTypeOf(p)
						take = function()
							Events.fire(ownerId, "bale_sold", 1, { hayType = hayType })
							Bales.consume(b)
						end
					elseif Hay.isPiece(p) then
						hay, ownerId, hayType = Config.HayPerPiece, p:GetAttribute("OwnerId"), hayTypeOf(p)
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
