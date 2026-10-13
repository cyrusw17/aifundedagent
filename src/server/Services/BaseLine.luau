--!nonstrict
-- The starter base, tycoon style. A conveyor line is already built:
--   trailer dock -> belt -> needle sorter -> belt -> hay buyer
-- Step on ORDER HAY TRAILER and a truck backs a trailer of bales up to the dock. Step on UNLOAD TRAILER and the
-- trailer floor pushes the bales onto the belt. The sorter opens each bale, throws the needles it finds into the
-- needle bin, and sends the clean hay on to the buyer, who pays for it. Step on SELL NEEDLES to sell your needles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factory = require(Shared.Config.Factory)
local Config = require(Shared.Config.Game)
local Needles = require(Shared.Config.Needles)
local Sorters = require(Shared.Config.Sorters)
local Economy = require(Shared.Economy)
local Data = require(script.Parent.Data)
local Bales = require(script.Parent.Bales)
local Hay = require(script.Parent.Hay)
local Groups = require(script.Parent.Groups)
local Conveyors = require(script.Parent.Conveyors)
local Trailer = require(script.Parent.Trailer)

local BaseLine = {}

local T = Factory.TileSize
local TOP = Factory.BeltTop
local ORIGIN = Vector3.new(48, 0, -40) -- ground corner of grid cell 0,0

-- Rustic palette (blender/lib/style.py): weathered wood, rusty metal, muted straw.
-- Pads keep a soft glow so they still read as buttons.
local BODY = Color3.fromRGB(179, 153, 115) -- machine body: weathered planks
local RUST = Color3.fromRGB(102, 66, 42) -- roofs and trim: rust
local WOOD = Color3.fromRGB(133, 110, 82)
local PLANKS = Color3.fromRGB(179, 153, 115)
local IRON = Color3.fromRGB(41, 33, 26)
local STEEL = Color3.fromRGB(128, 117, 105)
local TWINE = Color3.fromRGB(97, 84, 69) -- twine
local CLEAN_HAY = Color3.fromRGB(219, 204, 153)
local GREEN = Color3.fromRGB(150, 170, 100)
local PAD = Color3.fromRGB(205, 150, 80)

local rng = Random.new()
local folder = nil
local grid = nil

local recovery = 0.5
for _, tier in Sorters do
	if tier.id == Factory.SorterTier then
		recovery = tier.recovery
	end
end
local needle = Needles[1]
for _, n in Needles do
	if n.id == Factory.NeedleId then
		needle = n
	end
end

local function part(parent, name, size, cframe, color, material)
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

local function sign(parent, text, offset)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 60)
	gui.StudsOffset = offset
	gui.MaxDistance = 120
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	return label
end

local function cell(gx, gz)
	return Conveyors.cellCenter(grid, gx, gz)
end

local function pay(ownerId, amount, text)
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	local state = owner and Data.get(owner)
	if not state then
		return
	end
	state.cash += amount
	Data.sync(owner)
	Data.toast(owner, text)
end

local function toast(player, text)
	Data.toast(player, text)
end

-- A tycoon button: a round pad on the ground that fires once each time a player steps onto it.
local function stepPad(name, position, color, text, onStep)
	local pad = part(folder, name, Vector3.new(0.4, 5, 5), CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Neon)
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

-- Clean bales come out of the sorter. They ride the belt to the buyer. Nobody needs to carry them.
local cleanBales = {}

local function spawnCleanBale(position, ownerId, hay)
	local body = part(folder, "CleanBale", Vector3.new(4.6, 2.6, 3.2), CFrame.new(position), CLEAN_HAY, Enum.Material.Fabric)
	body.Anchored = false
	body.CustomPhysicalProperties = PhysicalProperties.new(1.2, 1.2, 0, 1, 1)
	for _, x in { -1.2, 1.2 } do
		local band = part(body, "Twine", Vector3.new(0.2, 2.7, 3.3), body.CFrame * CFrame.new(x, 0, 0), TWINE, Enum.Material.Fabric)
		band.Anchored = false
		band.CanCollide = false
		band.CanQuery = false
		band.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = band
		weld.Parent = band
	end
	body:SetAttribute("OwnerId", ownerId)
	body:SetAttribute("Hay", hay)
	cleanBales[body] = true
	pcall(function()
		body:SetNetworkOwner(nil)
	end)
	task.delay(Factory.LooseBaleSeconds, function()
		if cleanBales[body] then
			cleanBales[body] = nil
			body:Destroy()
		end
	end)
end

-- Needle bin. Each player's needles are counted separately, and drawn as a pile.
local binCounts = {} -- userId -> needles waiting to be sold
local binNeedles = {} -- visible needle parts, oldest first
local binInside = nil -- CFrame of the bin floor center
local binLabel = nil

local function refreshBin()
	local total = 0
	for _, n in binCounts do
		total += n
	end
	binLabel.Text = ("NEEDLE BIN\n%d %s needles"):format(total, needle.name:lower())
end

local function addNeedle(from, ownerId)
	local target = binInside * CFrame.new(rng:NextNumber(-2, 2), 0.6, rng:NextNumber(-4.5, 4.5))
	local n = part(folder, "Needle", Vector3.new(1.2, 0.15, 0.15), CFrame.new(from), STEEL, Enum.Material.Metal)
	n.Shape = Enum.PartType.Cylinder
	n.CanCollide = false
	n.CollisionGroup = Groups.Loose
	n:SetAttribute("OwnerId", ownerId)
	table.insert(binNeedles, n)
	while #binNeedles > Factory.MaxVisibleNeedles do
		table.remove(binNeedles, 1):Destroy()
	end

	-- Arc out of the sorter's side chute and drop into the bin, then settle into the pile.
	task.spawn(function()
		local started = os.clock()
		local control = (from + target.Position) / 2 + Vector3.new(0, 4, 0)
		while n.Parent do
			local alpha = math.min((os.clock() - started) / 0.6, 1)
			local inv = 1 - alpha
			local pos = inv * inv * from + 2 * inv * alpha * control + alpha * alpha * target.Position
			n.CFrame = CFrame.new(pos) * CFrame.Angles(alpha * 9, alpha * 5, 0)
			if alpha >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		if n.Parent then
			n.CanCollide = true
			n.Anchored = false
			pcall(function()
				n:SetNetworkOwner(nil)
			end)
		end
	end)
end

local function sellNeedles(player)
	local count = binCounts[player.UserId] or 0
	if count <= 0 then
		toast(player, "You have no needles in the bin yet. Run some hay through the sorter.")
		return
	end
	local value = count * needle.sortedValue
	binCounts[player.UserId] = nil
	for i = #binNeedles, 1, -1 do
		if binNeedles[i]:GetAttribute("OwnerId") == player.UserId then
			table.remove(binNeedles, i):Destroy()
		end
	end
	refreshBin()
	pay(player.UserId, value, ("Sold %d sorted %s needles for $%d."):format(count, needle.name:lower(), value))
end

local function buildBin(gx, gz)
	-- Two cells long, open on top, wooden walls.
	local center = (cell(gx, gz) + cell(gx, gz + 1)) / 2
	local model = Instance.new("Model")
	model.Name = "NeedleBin"
	model.Parent = folder
	local length = T * 2
	part(model, "Floor", Vector3.new(T, 0.4, length), CFrame.new(center + Vector3.new(0, 0.2, 0)), PLANKS, Enum.Material.WoodPlanks)
	for _, sx in { -1, 1 } do
		part(model, "Wall", Vector3.new(0.4, 3, length), CFrame.new(center + Vector3.new(sx * (T / 2 - 0.2), 1.5, 0)), WOOD, Enum.Material.WoodPlanks)
	end
	for _, sz in { -1, 1 } do
		part(model, "Wall", Vector3.new(T, 3, 0.4), CFrame.new(center + Vector3.new(0, 1.5, sz * (length / 2 - 0.2))), WOOD, Enum.Material.WoodPlanks)
	end
	binInside = CFrame.new(center + Vector3.new(0, 0.4, 0))
	local post = part(model, "SignPost", Vector3.new(0.4, 0.4, 0.4), CFrame.new(center + Vector3.new(0, 3, 0)), WOOD)
	post.Transparency = 1
	post.CanCollide = false
	binLabel = sign(post, "", Vector3.new(0, 4, 0))
	refreshBin()
end

-- The needle sorter sits over the belt. Bales stop at its rubber flap; it takes them in one at a time.
local function buildSorter(gx, gz)
	local first, last = cell(gx, gz), cell(gx, gz + 1)
	local center = (first + last) / 2
	local entryZ = first.Z - T / 2
	local exitZ = last.Z + T / 2
	local model = Instance.new("Model")
	model.Name = "NeedleSorter"
	model.Parent = folder

	local height = 7
	for _, sx in { -1, 1 } do
		part(model, "Side", Vector3.new(0.6, height, T * 2), CFrame.new(center + Vector3.new(sx * (T / 2 - 0.3), TOP + height / 2, 0)), BODY, Enum.Material.WoodPlanks)
	end
	part(model, "Roof", Vector3.new(T + 0.4, 1, T * 2 + 0.4), CFrame.new(center + Vector3.new(0, TOP + height + 0.5, 0)), RUST, Enum.Material.CorrodedMetal)
	part(model, "Hopper", Vector3.new(T - 1.4, 1.4, 3), CFrame.new(center + Vector3.new(0, TOP + height + 1.7, -1)), STEEL, Enum.Material.Metal)
	-- The flap blocks the way in. Bales wait against it until the sorter takes them.
	local flap = part(model, "Flap", Vector3.new(T - 1.2, height - 0.6, 0.4), CFrame.new(Vector3.new(center.X, TOP + (height - 0.6) / 2 + 0.3, entryZ + 0.2)), IRON)
	flap.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
	-- Side chute toward the needle bin.
	local chuteFrom = Vector3.new(center.X - T / 2 - 0.2, TOP + 3, center.Z)
	part(model, "Chute", Vector3.new(3, 0.3, 2), CFrame.new(chuteFrom + Vector3.new(-1.2, -0.5, 0)) * CFrame.Angles(0, 0, math.rad(-20)), STEEL, Enum.Material.Metal)
	local signLabel = sign(model.Roof, "NEEDLE SORTER", Vector3.new(0, 4, 0))

	-- Dust and straw while it works.
	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.6, 1.2)
	dust.Speed = NumberRange.new(3, 7)
	dust.SpreadAngle = Vector2.new(60, 60)
	dust.Color = ColorSequence.new(CLEAN_HAY)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	dust.Parent = model.Hopper

	local overlap = OverlapParams.new()
	local zoneCFrame = CFrame.new(Vector3.new(center.X, TOP + 3.5, entryZ - 1.6))
	local zoneSize = Vector3.new(T - 0.8, 7, 3.2)
	local outSpot = Vector3.new(center.X, TOP + 1.45, exitZ - 2)
	local sorted = 0

	local function sort(hay, ownerId)
		dust.Rate = 30
		local rest = model.Roof.CFrame
		local started = os.clock()
		while os.clock() - started < Factory.SortSecondsPerBale do
			model.Roof.CFrame = rest * CFrame.new(rng:NextNumber(-0.08, 0.08), rng:NextNumber(-0.05, 0.05), 0)
			task.wait(0.05)
		end
		model.Roof.CFrame = rest
		dust.Rate = 0

		-- Each hidden needle is found with the sorter's recovery chance. The rest stay lost in the hay.
		local hidden = Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay)
		local found = 0
		for _ = 1, hidden do
			if rng:NextNumber() < recovery then
				found += 1
			end
		end
		if ownerId then
			binCounts[ownerId] = (binCounts[ownerId] or 0) + found
		end
		for i = 1, found do
			task.delay(i * 0.08, addNeedle, chuteFrom, ownerId)
		end
		task.delay(found * 0.08 + 0.7, refreshBin)
		spawnCleanBale(outSpot, ownerId, hay)
		sorted += 1
		signLabel.Text = ("NEEDLE SORTER\n%d bales sorted"):format(sorted)
	end

	task.spawn(function()
		while model.Parent do
			task.wait(0.2)
			local bale, loose = nil, {}
			for _, p in Workspace:GetPartBoundsInBox(zoneCFrame, zoneSize, overlap) do
				local b = Bales.fromPart(p)
				if b and not b.gone and not b.carriedBy and not b.breaking then
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
end

-- The hay buyer: an open hopper at the end of the line that pays for clean hay dropped into it.
local function buildBuyer(gx, gz)
	local center = cell(gx, gz)
	local model = Instance.new("Model")
	model.Name = "HayBuyer"
	model.Parent = folder
	local floorY = TOP - 2
	part(model, "Floor", Vector3.new(T, 0.4, T), CFrame.new(center + Vector3.new(0, floorY, 0)), WOOD, Enum.Material.WoodPlanks)
	part(model, "Base", Vector3.new(T, floorY, T), CFrame.new(center + Vector3.new(0, floorY / 2, 0)), WOOD, Enum.Material.WoodPlanks)
	part(model, "Back", Vector3.new(0.4, 5, T), CFrame.new(center + Vector3.new(T / 2 - 0.2, floorY + 2.5, 0)), PLANKS, Enum.Material.WoodPlanks)
	for _, sz in { -1, 1 } do
		part(model, "Side", Vector3.new(T, 5, 0.4), CFrame.new(center + Vector3.new(0, floorY + 2.5, sz * (T / 2 - 0.2))), PLANKS, Enum.Material.WoodPlanks)
	end
	sign(model.Back, "HAY BUYER", Vector3.new(0, 5, 0))

	local zone = CFrame.new(center + Vector3.new(0, floorY + 3, 0))
	task.spawn(function()
		while model.Parent do
			task.wait(0.25)
			for _, p in Workspace:GetPartBoundsInBox(zone, Vector3.new(T - 0.8, 6, T - 0.8)) do
				if cleanBales[p] then
					cleanBales[p] = nil
					local hay = p:GetAttribute("Hay") or 0
					local value = math.floor(hay * Economy.HAY_PRICE)
					pay(p:GetAttribute("OwnerId"), value, ("Hay buyer paid $%d for %d clean hay."):format(value, hay))
					p:Destroy()
				else
					local b = Bales.fromPart(p)
					if b and not b.gone and not b.carriedBy then
						-- A bale that skipped the sorter sells raw, needles and all.
						local hay = Config.PiecesPerBale * Config.HayPerPiece
						local value = Economy.rawLoadValue(hay, Economy.rollNeedles(rng, hay, Config.NeedleChancePerHay))
						local ownerId = b.ownerId
						Bales.consume(b)
						pay(ownerId, value, ("Hay buyer paid $%d for an unsorted bale."):format(value))
					end
				end
			end
		end
	end)
end

function BaseLine.build(worldFolder)
	folder = Instance.new("Folder")
	folder.Name = "StarterBase"
	folder.Parent = worldFolder

	-- Concrete slab under the whole base.
	part(folder, "Slab", Vector3.new(T * 8, 0.2, T * 8), CFrame.new(ORIGIN + Vector3.new(T * 3.5, 0.1, T * 2.5)), Color3.fromRGB(150, 140, 125), Enum.Material.Concrete)

	-- The line, on the grid. Dock at the east end, then west, south through the sorter, east to the buyer.
	grid = Conveyors.newGrid(folder, ORIGIN)
	Conveyors.place(grid, 6, 0, "W", true) -- dock tile, open at the back for the trailer
	Conveyors.run(grid, 5, 0, "W", 3)
	Conveyors.place(grid, 2, 0, "S")
	Conveyors.run(grid, 2, 1, "S", 4) -- the sorter sits over cells 2,2 and 2,3
	Conveyors.place(grid, 2, 5, "E")
	Conveyors.run(grid, 3, 5, "E", 2)
	Conveyors.finish(grid)

	buildSorter(2, 2)
	buildBin(0, 2)
	buildBuyer(5, 5)

	local dock = cell(6, 0) + Vector3.new(T / 2, 0, 0)
	Trailer.init(folder, dock, Vector3.new(1, 0, 0), Vector3.new(0, 0, -1))

	local _, orderLabel = stepPad("OrderPad", cell(5, -1), GREEN, "ORDER HAY TRAILER", function(player)
		local ok, why = Trailer.order(player)
		if ok then
			toast(player, "A trailer of hay is on its way. Wait for it to back up to the dock.")
		else
			toast(player, why)
		end
	end)
	local _, unloadLabel = stepPad("UnloadPad", cell(4, -1), PAD, "UNLOAD TRAILER", function(player)
		if Trailer.state == "parked" then
			Trailer.unload()
			toast(player, "Unloading onto the belt.")
		elseif Trailer.state == "none" then
			toast(player, "No trailer here. Step on ORDER HAY TRAILER first.")
		else
			toast(player, "Wait until the trailer has backed up to the dock.")
		end
	end)
	stepPad("SellNeedlesPad", cell(0, 4), PAD, ("SELL NEEDLES\n$%d each"):format(needle.sortedValue), sellNeedles)

	local words = {
		none = { "ORDER HAY TRAILER", "UNLOAD TRAILER" },
		arriving = { "TRAILER ON ITS WAY", "WAIT FOR TRAILER" },
		parked = { "TRAILER AT DOCK", "UNLOAD TRAILER" },
		unloading = { "UNLOADING", "UNLOADING" },
		leaving = { "TRUCK LEAVING", "TRUCK LEAVING" },
	}
	Trailer.changed.Event:Connect(function(state)
		orderLabel.Text, unloadLabel.Text = unpack(words[state])
	end)
end

return BaseLine
