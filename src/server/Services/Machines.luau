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
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factory = require(Shared.Config.Factory)
local Config = require(Shared.Config.Game)
local Needles = require(Shared.Config.Needles)
local Sorters = require(Shared.Config.Sorters)
local Economy = require(Shared.Economy)
local WorldLabel = require(Shared.WorldLabel)
local Data = require(script.Parent.Data)
local Tutorial = require(script.Parent.Tutorial)
local Bank = require(script.Parent.Bank)
local Bales = require(script.Parent.Bales)
local Hay = require(script.Parent.Hay)
local Needle = require(script.Parent.Needle)

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
	Tutorial.mark(owner, "sold")
	Tutorial.earned(owner, amount)
	Data.toast(owner, text)
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
local function spawnSortedBale(cframe, ownerId, hay)
	local b = Bales.spawn(Vector3.zero, false, false)
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

	local function refresh()
		label.Text = ("NEEDLE BIN\n%d needles"):format(#Needle.inBox(inside, insideSize))
	end
	refresh()
	task.spawn(function()
		while model.Parent do
			task.wait(1)
			refresh()
		end
	end)

	-- Throws count needles from `from` into the bin, owned by ownerId.
	function bin.add(from, ownerId, count, needleId)
		for i = 1, count do
			task.delay(i * 0.08, function()
				local to = (floor * CFrame.new(rng:NextNumber(-2, 2), 0.3, rng:NextNumber(-2, 2))).Position
				Needle.throw(from, to, ownerId, needleId)
			end)
		end
	end

	function bin.sell(player)
		local byType = Needle.takeHeld(player)
		for _, n in Needle.inBox(inside, insideSize) do
			if n:GetAttribute("OwnerId") == player.UserId then
				local id = n:GetAttribute("NeedleId") or Needle.default.id
				byType[id] = (byType[id] or 0) + 1
				n:Destroy()
			end
		end
		local count, value = 0, 0
		for id, k in byType do
			count += k
			value += k * Needle.info(id).sortedValue
		end
		refresh()
		if count == 0 then
			Data.toast(player, "You have no needles in this bin or your pocket. Run some hay through a sorter.")
			return
		end
		Machines.pay(player.UserId, value, ("Sold %d sorted needles for $%d."):format(count, value), "Sorted needles")
	end

	-- Needles in the bin, as { [needleId] = count }: everyone's, or only ownerId's.
	function bin.contents(ownerId)
		local byType = {}
		for _, n in Needle.inBox(inside, insideSize) do
			if ownerId == nil or n:GetAttribute("OwnerId") == ownerId then
				local id = n:GetAttribute("NeedleId") or Needle.default.id
				byType[id] = (byType[id] or 0) + 1
			end
		end
		return byType
	end

	-- Puts saved needles straight back in the bin, laid in rows on the floor (anchored, so a big pile can't spill).
	function bin.fill(ownerId, byType)
		local perRow, rows = 4, 24
		local placed = 0
		for id, count in byType do
			for _ = 1, count do
				local col = placed % perRow
				local row = math.floor(placed / perRow) % rows
				local layer = math.floor(placed / (perRow * rows))
				local at = floor * CFrame.new(-1.95 + col * 1.3, 0.1 + layer * 0.16, -2.3 + row * 0.2)
				local n = Needle.spawn(at.Position, ownerId, id)
				n.CFrame = at
				n.Anchored = true
				placed += 1
			end
		end
		refresh()
	end

	-- Removes every needle in the bin (the plot was given up).
	function bin.clear()
		for _, n in Needle.inBox(inside, insideSize) do
			n:Destroy()
		end
		refresh()
	end

	bin.model = model
	Machines.stepPad(model, (frame * CFrame.new(0, 0, T)).Position, C.pad, ("SELL NEEDLES\n$%d each"):format(needle.sortedValue), bin.sell)
	return bin
end

-- Seconds a sorter spends on one bale's worth of hay, from its tier's hay per minute.
function Machines.sortSeconds(tierId, hay)
	local tier = tiers[tierId]
	if not tier or tier.hayPerMin == math.huge then
		return 0.4
	end
	return math.max(hay / tier.hayPerMin * 60, 0.5) -- no upper clamp, so every tier's speed is felt
end

-- Needle sorter over two belt cells: the cell at frame and the next one downstream. Bales wait at its rubber flap,
-- go in one at a time, the needles it finds fly to `bin` (a Machines.needleBin), and a clean bale comes out the far end.
function Machines.sorter(parent, frame, tierId, bin)
	local tier = tiers[tierId] or tiers.conveyor_sorter
	local center = frame * CFrame.new(0, 0, -T / 2) -- middle of the two cells
	local model = Instance.new("Model")
	model.Name = "NeedleSorter"
	model:SetAttribute("Tier", tier.id)
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

	local function sort(hay, ownerId)
		dust.Rate = 30
		local rest = roof.CFrame
		local started = os.clock()
		while os.clock() - started < Machines.sortSeconds(tier.id, hay) do
			roof.CFrame = rest * CFrame.new(rng:NextNumber(-0.08, 0.08), rng:NextNumber(-0.05, 0.05), 0)
			task.wait(0.05)
		end
		roof.CFrame = rest
		dust.Rate = 0

		-- Each hidden needle is found with the tier's recovery chance. The rest stay lost in the hay.
		local hidden = Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay)
		local found = 0
		for _ = 1, hidden do
			if rng:NextNumber() < tier.recovery then
				found += 1
			end
		end
		if bin then
			bin.add(chuteFrom, ownerId, found)
		end
		spawnSortedBale(out, ownerId, hay)
		sorted += 1
		label.Text = ("%s\n%d bales sorted, finds %d%%"):format(tier.name:upper(), sorted, math.round(tier.recovery * 100))
	end

	task.spawn(function()
		while model.Parent do
			task.wait(0.2)
			local bale, loose = nil, {}
			for _, p in Workspace:GetPartBoundsInBox(zone, zoneSize) do
				local b = Bales.fromPart(p)
				if b and not b.gone and not b.carriedBy and not b.breaking and not b.sorted then
					bale = bale or b
				elseif Hay.isPiece(p) then
					table.insert(loose, p)
				end
			end
			if bale then
				local ownerId = bale.ownerId
				Bales.consume(bale)
				sort(Config.PiecesPerBale * Config.HayPerPiece, ownerId)
			elseif #loose > 0 then
				local ownerId = loose[1]:GetAttribute("OwnerId")
				for _, p in loose do
					Hay.remove(p)
				end
				sort(#loose * Config.HayPerPiece, ownerId)
			end
		end
	end)
	return model
end

-- Hay buyer: an open hopper at the end of a belt (the belt comes in from local +Z). Pays whoever owns what drops in:
-- sorted bales at the hay price, and unsorted hay at the hay price plus only $1 per hidden needle.
function Machines.hayBuyer(parent, frame, title)
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
					Bales.consume(sortedBale)
					Machines.pay(ownerId, value, ("Paid $%d for %d sorted hay."):format(value, hay), "Hay buyer")
				else
					local b = Bales.fromPart(p)
					local hay, ownerId = 0, nil
					if b and p == b.body and not b.gone and not b.carriedBy then
						hay, ownerId = Config.PiecesPerBale * Config.HayPerPiece, b.ownerId
						Bales.consume(b)
					elseif Hay.isPiece(p) then
						hay, ownerId = Config.HayPerPiece, p:GetAttribute("OwnerId")
						Hay.remove(p)
					end
					if hay > 0 and ownerId then
						local t = unsorted[ownerId] or { hay = 0, needles = 0 }
						t.hay += hay
						t.needles += Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay)
						unsorted[ownerId] = t
					end
				end
			end
			for ownerId, t in unsorted do
				local value = Economy.rawLoadValue(t.hay, t.needles)
				Machines.pay(
					ownerId,
					value,
					("Paid $%d for %d hay. It had %d needles in it, paid at only $%d each. Sort them yourself for $%d each."):format(
						value,
						t.hay,
						t.needles,
						Economy.RAW_NEEDLE_PRICE,
						needle.sortedValue
					)
				)
			end
			table.clear(unsorted)
		end
	end)
	return model
end

return Machines
