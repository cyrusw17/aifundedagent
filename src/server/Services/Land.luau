--!nonstrict
-- Land you can buy and build on. The land office south of the main road sells plots of different sizes; each plot is
-- a grid of conveyor tiles where its owner places belts, needle sorters (one per tier in Sorters.luau), hay buyers, a
-- hay silo and a parking pad. Belts, sorters and buyers are the same pieces as the public sell shop (Conveyors.luau,
-- Machines.luau). Every plot has a needle bin with a SELL NEEDLES pad on its north strip, and every sorter on the plot
-- throws its needles there.
--
-- One plot per save. The save remembers which plot and what was built (Data `land`). When a save is loaded the farm
-- is rebuilt on that plot, or on the next free one big enough, and the save's truck and trailer park on its parking
-- pad. The server checks every purchase and placement.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factory = require(Shared.Config.Factory)
local LandConfig = require(Shared.Config.Land)
local Meadow = require(Shared.Config.Meadow)
local Rustic = require(Shared.Config.Rustic)
local Props = require(script.Parent.Props)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Bales = require(script.Parent.Bales)
local Conveyors = require(script.Parent.Conveyors)
local Machines = require(script.Parent.Machines)
local Vehicles = require(script.Parent.Vehicles)

local Land = {}

local T = Factory.TileSize
local TOP = Factory.BeltTop
local STRIP = LandConfig.StripDepth
local FENCE_HEIGHT = 3

local pieces = {}
for _, def in LandConfig.Pieces do
	pieces[def.id] = def
end

local plots = {} -- index -> plot record
local plotOf = {} -- player -> plot record
local lastAction = {} -- player -> os.clock() of their last place or remove
local state = nil -- ReplicatedStorage.Land: remotes and what the client needs to know about every plot
local vehiclesFolder = nil

local part = Machines.part
local sign = Machines.sign

local function key(gx, gz)
	return gx .. "," .. gz
end

local function step(dir)
	local d = Conveyors.Dirs[dir]
	return math.round(d.X), math.round(d.Z)
end

-- The cells a piece covers. The anchor is its back-left cell; it runs size[2] cells forward in the direction it
-- faces and size[1] cells to the right.
local function cellsFor(def, gx, gz, dir)
	local fx, fz = step(dir)
	local rx, rz = -fz, fx
	local cells = {}
	for across = 0, def.size[1] - 1 do
		for along = 0, def.size[2] - 1 do
			table.insert(cells, { gx + fx * along + rx * across, gz + fz * along + rz * across })
		end
	end
	return cells
end

local function isCell(n)
	return typeof(n) == "number" and n == n and math.floor(n) == n
end

-- Ground CFrame at the middle of a piece's footprint, facing its direction.
local function footprintFrame(plot, def, gx, gz, dir)
	local fx, fz = step(dir)
	local rx, rz = -fz, fx
	local a = Conveyors.cellCenter(plot.grid, gx, gz)
	local mid = a + Vector3.new(fx, 0, fz) * (def.size[2] - 1) * T / 2 + Vector3.new(rx, 0, rz) * (def.size[1] - 1) * T / 2
	return CFrame.lookAt(mid, mid + Vector3.new(fx, 0, fz))
end

-- Client-facing copy of a plot's state, so the panel and the build ghost work without asking the server.
local function publish(plot)
	local info = plot.info
	info:SetAttribute("OwnerId", plot.ownerId or 0)
	info:SetAttribute("OwnerName", plot.ownerName or "")
	local taken = {}
	for k in plot.taken do
		table.insert(taken, k)
	end
	info:SetAttribute("Taken", table.concat(taken, ";"))
	if plot.ownerId then
		plot.label.Text = ("%s\n%s's farm"):format(plot.def.name:upper(), plot.ownerName)
	else
		plot.label.Text = ("%s FOR SALE\n$%d at the Land Office"):format(plot.def.name:upper(), plot.def.price)
	end
end

-- Rails depend on which belts feed into which, so they are redone whenever a piece is added or removed.
local function refreshRails(plot)
	for _, tile in plot.grid.tiles do
		for _, child in tile.model:GetChildren() do
			if child.Name == "Rail" then
				child:Destroy()
			end
		end
	end
	Conveyors.finish(plot.grid)
end

-- Silo --------------------------------------------------------------------------------------------------------------

-- A tall round silo over its footprint. Bales set down against its back or sides go in; one at a time they come out
-- of the chute at the front onto the belt there (in the lane of the silo's anchor cell).
local function buildSilo(plot, item, def)
	local frame = footprintFrame(plot, def, item.gx, item.gz, item.dir)
	local w, l = def.size[1] * T, def.size[2] * T
	local model = Instance.new("Model")
	model.Name = "HaySilo"
	model.Parent = plot.items

	local height = 20
	local body = part(model, "Body", Vector3.new(height, w - 1, w - 1), frame * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Rustic.PaintCream, Enum.Material.Metal)
	body.Shape = Enum.PartType.Cylinder
	local cap = part(model, "Cap", Vector3.new(w - 1.6, 2.4, w - 1.6), frame * CFrame.new(0, height + 1.2, 0), Rustic.Metal, Enum.Material.Metal)
	cap.Shape = Enum.PartType.Ball
	part(model, "Band", Vector3.new(0.4, w - 0.6, w - 0.6), frame * CFrame.new(0, 6, 0) * CFrame.Angles(0, 0, math.pi / 2), Rustic.WoodDark, Enum.Material.Wood).Shape = Enum.PartType.Cylinder
	-- The chute comes out over the anchor lane at belt height.
	local laneX = -(def.size[1] - 1) * T / 2
	part(model, "Chute", Vector3.new(4, 3.2, 3), frame * CFrame.new(laneX, TOP + 1.6, -l / 2 + 1), Rustic.Metal, Enum.Material.Metal)
	local label = sign(cap, "", Vector3.new(0, 4, 0))

	local mesh = Props.make("silo_small", frame * CFrame.new(0, height / 2, 0), Vector3.new(w - 0.5, height + 2, w - 0.5))
	if mesh then
		Props.restOn(mesh, 0)
		for _, p in mesh:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanCollide = false
			end
		end
		mesh.Parent = model
		body.Transparency = 1
		cap.Transparency = 1
	end

	item.stored = math.clamp(item.stored or 0, 0, LandConfig.SiloCapacity)
	local function refresh()
		label.Text = ("HAY SILO\n%d / %d bales"):format(item.stored, LandConfig.SiloCapacity)
	end
	refresh()

	-- Intake: the footprint grown 2.5 studs to the back and sides (not the front, where bales come out). Sorted bales
	-- are left alone, or a silo could hand them back to a sorter to find their needles twice.
	local intake = frame * CFrame.new(0, 4, 1.25)
	local intakeSize = Vector3.new(w + 5, 8, l + 2.5)
	local outSpot = frame * CFrame.new(laneX, 0, -l / 2 - T / 2 - 1)
	local lastOut = 0
	task.spawn(function()
		while model.Parent do
			task.wait(0.25)
			local changed = false
			for _, p in Workspace:GetPartBoundsInBox(intake, intakeSize) do
				local b = Bales.fromPart(p)
				if b and p == b.body and not b.gone and not b.carriedBy and not b.breaking and not b.sorted and item.stored < LandConfig.SiloCapacity then
					Bales.consume(b)
					item.stored += 1
					changed = true
				end
			end
			if item.stored > 0 and os.clock() - lastOut >= LandConfig.SiloFeedSeconds then
				-- Only feed when the spot in front is clear, so bales don't pile up on the belt.
				local clear = true
				for _, p in Workspace:GetPartBoundsInBox(outSpot * CFrame.new(0, TOP + 1.5, 0), Vector3.new(4, 2.6, 4)) do
					if Bales.fromPart(p) or p.Name == "CleanBale" then
						clear = false
						break
					end
				end
				if clear then
					lastOut = os.clock()
					item.stored -= 1
					changed = true
					local b = Bales.spawn(outSpot.Position + Vector3.new(0, TOP + 0.1, 0), false)
					if b then
						b.ownerId = plot.ownerId
						b.body.CFrame = CFrame.lookAt(b.body.Position, b.body.Position + outSpot.RightVector)
						b.body.Anchored = false
						pcall(function()
							b.body:SetNetworkOwner(nil)
						end)
					end
				end
			end
			if changed then
				refresh()
				plot.dirty = true
			end
		end
	end)
	return model
end

-- Parking pad -------------------------------------------------------------------------------------------------------

local function buildParking(plot, item, def)
	local frame = footprintFrame(plot, def, item.gx, item.gz, item.dir)
	local model = Instance.new("Model")
	model.Name = "ParkingPad"
	model.Parent = plot.items
	local w, l = def.size[1] * T, def.size[2] * T
	part(model, "Pad", Vector3.new(w - 0.4, 0.3, l - 0.4), frame * CFrame.new(0, 0.15, 0), Rustic.Stone, Enum.Material.Concrete)
	for _, x in { -w / 2 + 0.6, w / 2 - 0.6 } do
		part(model, "Line", Vector3.new(0.3, 0.05, l - 1.2), frame * CFrame.new(x, 0.32, 0), Rustic.PaintCream)
	end
	local arrow = part(model, "Arrow", Vector3.new(1.4, 0.05, 3), frame * CFrame.new(0, 0.32, -l / 2 + 3), Rustic.PaintYellow)
	sign(arrow, "PARKING", Vector3.new(0, 3, 0))
	item.parkAt = frame * CFrame.new(0, 0, -l / 2 + 1)
	return model
end

-- Pieces ------------------------------------------------------------------------------------------------------------

-- Builds one piece on a plot. No checks and no charge: callers do that.
local function spawnItem(plot, def, gx, gz, dir, stored)
	local item = { id = def.id, gx = gx, gz = gz, dir = dir, cells = cellsFor(def, gx, gz, dir), instances = {}, stored = stored }
	local frame = Conveyors.frame(plot.grid, gx, gz, dir)
	if def.kind == "belt" or def.kind == "separator" then
		-- A sorter sits over belt tiles of its own, so a line runs straight through it.
		for _, cell in item.cells do
			local belt = Conveyors.place(plot.grid, cell[1], cell[2], dir)
			table.insert(item.instances, belt.Parent)
		end
	end
	if def.kind == "separator" then
		table.insert(item.instances, Machines.sorter(plot.items, frame, def.id, plot.bin))
	elseif def.kind == "buyer" then
		table.insert(item.instances, Machines.hayBuyer(plot.items, frame, "HAY BUYER"))
	elseif def.kind == "silo" then
		table.insert(item.instances, buildSilo(plot, item, def))
	elseif def.kind == "parking" then
		table.insert(item.instances, buildParking(plot, item, def))
	end
	for _, cell in item.cells do
		plot.taken[key(cell[1], cell[2])] = item
	end
	table.insert(plot.list, item)
	return item
end

local function destroyItem(plot, item)
	for _, instance in item.instances do
		instance:Destroy()
	end
	for _, cell in item.cells do
		local k = key(cell[1], cell[2])
		plot.taken[k] = nil
		plot.grid.tiles[k] = nil
	end
	local i = table.find(plot.list, item)
	if i then
		table.remove(plot.list, i)
	end
end

-- Whether a piece fits: every cell on the plot and free.
local function fits(plot, def, gx, gz, dir)
	for _, cell in cellsFor(def, gx, gz, dir) do
		local x, z = cell[1], cell[2]
		if x < 0 or z < 0 or x >= plot.tiles.X or z >= plot.tiles.Z or plot.taken[key(x, z)] then
			return false
		end
	end
	return true
end

-- What gets saved: the plot and the pieces by id, anchor cell and direction (and a silo's bales).
local function saveItems(player, plot)
	local s = Data.get(player)
	if not s or not s.land then
		return
	end
	local items = {}
	for _, item in plot.list do
		table.insert(items, { id = item.id, gx = item.gx, gz = item.gz, dir = item.dir, stored = item.stored })
	end
	s.land.items = items
	s.land.plot = plot.index
	plot.dirty = false
end

-- Vehicles ----------------------------------------------------------------------------------------------------------

-- Parks the save's truck (and its trailer, hitched) on the plot's parking pad, or at the plot's road gate.
local function parkVehicles(player, plot)
	local s = Data.get(player)
	local truckId = s and s.trucks and s.trucks[1]
	local def = truckId and Vehicles.get(truckId)
	if not def then
		return
	end
	local at = nil
	for _, item in plot.list do
		if item.parkAt then
			at = item.parkAt
			break
		end
	end
	if not at then
		-- No parking pad: on the lane in front of the plot, facing east.
		local gate = Vector3.new(plot.corner.X + plot.size.X / 2, 0, plot.laneZ)
		at = CFrame.lookAt(gate, gate + Vector3.xAxis) * CFrame.new(0, 0, -10)
	end
	-- The truck's middle sits half its length back from the front of the pad.
	local truckCF = at * CFrame.new(0, 0.3, def.length / 2) -- on top of the pad
	local trailerId = s.trailers and s.trailers[1]
	local ok, err = pcall(Vehicles.spawnOwned, player, truckId, truckCF, { trailer = trailerId, parent = vehiclesFolder })
	if not ok then
		warn("[Needlewood] couldn't park the truck on the plot: " .. tostring(err))
	end
end

-- Claiming and releasing --------------------------------------------------------------------------------------------

local function clearPlot(plot)
	for i = #plot.list, 1, -1 do
		destroyItem(plot, plot.list[i])
	end
	plot.grid.tiles = {}
	plot.taken = {}
end

local function release(plot)
	if plot.owner then
		plotOf[plot.owner] = nil
		plot.owner:SetAttribute("LandPlot", 0)
	end
	clearPlot(plot)
	plot.owner, plot.ownerId, plot.ownerName = nil, nil, nil
	publish(plot)
end

-- Gives a plot to a player and rebuilds what they saved on it. Pieces that don't fit (a smaller plot) are skipped.
local function claim(plot, player, saved)
	plot.owner, plot.ownerId, plot.ownerName = player, player.UserId, player.DisplayName
	plotOf[player] = plot
	player:SetAttribute("LandPlot", plot.index)
	for _, s in saved.items or {} do
		local def = typeof(s) == "table" and pieces[s.id]
		if def and isCell(s.gx) and isCell(s.gz) and typeof(s.dir) == "string" and Conveyors.Dirs[s.dir] and fits(plot, def, s.gx, s.gz, s.dir) then
			spawnItem(plot, def, s.gx, s.gz, s.dir, typeof(s.stored) == "number" and s.stored or nil)
		end
	end
	refreshRails(plot)
	publish(plot)
	saveItems(player, plot)
end

-- The saved plot if it is free, otherwise the smallest free plot at least as big, otherwise any free plot.
local function pickPlot(wanted)
	local saved = plots[wanted]
	if saved and not saved.ownerId then
		return saved
	end
	local need = saved and saved.tiles.X * saved.tiles.Z or 0
	local best, fallback = nil, nil
	for _, plot in plots do
		if not plot.ownerId then
			local area = plot.tiles.X * plot.tiles.Z
			fallback = fallback or plot
			if area >= need and (not best or area < best.tiles.X * best.tiles.Z) then
				best = plot
			end
		end
	end
	return best or fallback
end

-- Buying ------------------------------------------------------------------------------------------------------------

local function onBuy(player, index)
	local s = Data.get(player)
	if not s then
		return false, "Pick a save first."
	end
	if s.land and s.land.owned then
		local mine = plotOf[player]
		return false, mine and ("You already own %s."):format(mine.def.name) or "This save already owns land."
	end
	local plot = typeof(index) == "number" and plots[index]
	if not plot then
		return false, "That plot doesn't exist."
	end
	if plot.ownerId then
		return false, ("%s already belongs to %s."):format(plot.def.name, plot.ownerName)
	end
	local paid, why = Bank.charge(player, plot.def.price, "Land: " .. plot.def.name)
	if not paid then
		return false, why
	end
	s.land = { owned = true, plot = index, items = {} }
	claim(plot, player, s.land)
	Data.sync(player)
	task.spawn(Data.save, player)
	Data.toast(player, ("%s is yours! Walk down the plot road and press BUILD."):format(plot.def.name))
	return true, ("%s is yours. Follow the plot road south and press BUILD."):format(plot.def.name)
end

-- Building ----------------------------------------------------------------------------------------------------------

local function ownPlot(player)
	local plot = plotOf[player]
	if not plot or plot.ownerId ~= player.UserId then
		return nil, "You need to own land to build. Buy a plot at the Land Office."
	end
	if os.clock() - (lastAction[player] or 0) < 0.12 then
		return nil, nil
	end
	lastAction[player] = os.clock()
	return plot
end

local function onPlace(player, id, gx, gz, dir)
	local plot, why = ownPlot(player)
	if not plot then
		return false, why
	end
	local def = typeof(id) == "string" and pieces[id]
	if not def or not isCell(gx) or not isCell(gz) or typeof(dir) ~= "string" or not Conveyors.Dirs[dir] then
		return false, "Can't build that there."
	end
	if not fits(plot, def, gx, gz, dir) then
		return false, "That spot is taken or off your land."
	end
	local paid, short = Bank.charge(player, def.price, "Built a " .. def.name:lower())
	if not paid then
		return false, short
	end
	spawnItem(plot, def, gx, gz, dir)
	refreshRails(plot)
	publish(plot)
	saveItems(player, plot)
	Data.sync(player)
	return true, ("Built a %s for $%d."):format(def.name:lower(), def.price)
end

local function onRemove(player, gx, gz)
	local plot, why = ownPlot(player)
	if not plot then
		return false, why
	end
	if not isCell(gx) or not isCell(gz) then
		return false, nil
	end
	local item = plot.taken[key(gx, gz)]
	if not item then
		return false, "Nothing built there."
	end
	local def = pieces[item.id]
	destroyItem(plot, item)
	refreshRails(plot)
	publish(plot)
	saveItems(player, plot)
	local refund = math.floor(def.price * LandConfig.RefundShare)
	Bank.give(player, refund, "Removed a " .. def.name:lower())
	return true, ("Removed the %s. Got $%d back."):format(def.name:lower(), refund)
end

-- World -------------------------------------------------------------------------------------------------------------

-- A low wooden fence along one edge, from a to b on the ground.
local function fence(parent, a, b)
	local length = (b - a).Magnitude
	local along = CFrame.lookAt((a + b) / 2, b)
	for i = 0, math.ceil(length / 6) do
		local p = a + (b - a).Unit * math.min(i * 6, length)
		part(parent, "Post", Vector3.new(0.6, FENCE_HEIGHT, 0.6), CFrame.new(p + Vector3.new(0, FENCE_HEIGHT / 2, 0)), Rustic.WoodDark, Enum.Material.Wood)
	end
	for _, y in { 1.1, 2.4 } do
		part(parent, "Rail", Vector3.new(0.25, 0.4, length), along + Vector3.new(0, y, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	end
end

local function zoneOf(def)
	for _, zone in Meadow.Plots do
		if zone.id == def.zone then
			return zone
		end
	end
	error("no Meadow plot zone " .. tostring(def.zone))
end

local function buildPlot(parent, index, def)
	-- The grid is centered east-west in its Meadow zone, with the strip on the lane side (open) and the grid behind it.
	local zone = zoneOf(def)
	local size = Vector3.new(def.tiles.X * T, 0, def.tiles.Y * T)
	local x0 = math.floor((zone.min.X + zone.max.X - size.X) / 2)
	local x1 = x0 + size.X
	local stripZ, z0, z1
	if def.open == "S" then
		stripZ = zone.max.Y - STRIP / 2
		z1 = zone.max.Y
		z0 = zone.max.Y - STRIP - size.Z
	else
		stripZ = zone.min.Y + STRIP / 2
		z0 = zone.min.Y
		z1 = zone.min.Y + STRIP + size.Z
	end
	local corner = Vector3.new(x0, 0, def.open == "S" and z0 or z0 + STRIP)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model.Parent = parent

	-- Packed dirt over the build grid, and the strip for the sign and the needle bin.
	part(model, "Ground", Vector3.new(size.X, 0.2, size.Z), CFrame.new(corner + Vector3.new(size.X / 2, 0.1, size.Z / 2)), Rustic.Dirt, Enum.Material.Ground)
	part(model, "Strip", Vector3.new(size.X, 0.2, STRIP), CFrame.new((x0 + x1) / 2, 0.1, stripZ), Rustic.Mud, Enum.Material.Ground)

	-- Fence on three sides. The lane side stays open.
	local fences = Instance.new("Model")
	fences.Name = "Fence"
	fences.Parent = model
	fence(fences, Vector3.new(x0, 0, z0), Vector3.new(x0, 0, z1))
	fence(fences, Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1))
	local farZ = def.open == "S" and z0 or z1
	fence(fences, Vector3.new(x0, 0, farZ), Vector3.new(x1, 0, farZ))

	-- The needle bin sits at the west end of the strip, with its SELL NEEDLES pad toward the middle.
	local binX = x0 + T * 0.5 + 0.5
	local binFrame = CFrame.lookAt(Vector3.new(binX, 0, stripZ), Vector3.new(binX - 1, 0, stripZ))

	-- Sign post in the middle of the strip.
	local post = part(model, "SignPost", Vector3.new(0.8, 6, 0.8), CFrame.new((x0 + x1) / 2, 3, stripZ), Rustic.WoodDark, Enum.Material.Wood)
	local board = part(model, "SignBoard", Vector3.new(8, 2.4, 0.4), CFrame.new((x0 + x1) / 2, 5.4, stripZ), Rustic.Wood, Enum.Material.WoodPlanks)
	board.CanCollide = false
	local label = sign(post, "", Vector3.new(0, 6, 0))

	local items = Instance.new("Folder")
	items.Name = "Built"
	items.Parent = model

	local info = Instance.new("Configuration")
	info.Name = "Plot" .. index
	info:SetAttribute("Index", index)
	info:SetAttribute("Name", def.name)
	info:SetAttribute("Price", def.price)
	info:SetAttribute("Corner", corner)
	info:SetAttribute("TilesX", def.tiles.X)
	info:SetAttribute("TilesZ", def.tiles.Y)
	info:SetAttribute("Open", def.open)
	info.Parent = state

	local plot = {
		index = index,
		def = def,
		corner = corner,
		size = size,
		laneZ = def.open == "S" and z1 + 8 or z0 - 8,
		tiles = { X = def.tiles.X, Z = def.tiles.Y },
		model = model,
		items = items,
		info = info,
		label = label,
		grid = Conveyors.newGrid(model, corner),
		bin = Machines.needleBin(model, binFrame),
		list = {},
		taken = {},
	}
	plots[index] = plot
	publish(plot)
	return plot
end

local function buildOffice(parent)
	local center = LandConfig.OfficeCenter
	local model = Instance.new("Model")
	model.Name = "LandOffice"
	model.Parent = parent
	local function at(x, y, z)
		return CFrame.new(center + Vector3.new(x, y, z))
	end
	-- 18 wide, 10 deep, open to the north (the main road side).
	part(model, "Floor", Vector3.new(18, 0.6, 10), at(0, 0.3, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	part(model, "BackWall", Vector3.new(18, 9, 0.8), at(0, 4.5, 4.6), Rustic.PaintCream, Enum.Material.WoodPlanks)
	part(model, "LeftWall", Vector3.new(0.8, 9, 10), at(-8.6, 4.5, 0), Rustic.PaintCream, Enum.Material.WoodPlanks)
	part(model, "RightWall", Vector3.new(0.8, 9, 10), at(8.6, 4.5, 0), Rustic.PaintCream, Enum.Material.WoodPlanks)
	local roof = part(model, "Roof", Vector3.new(20, 0.8, 12), at(0, 9.4, 0) * CFrame.Angles(math.rad(-8), 0, 0), Rustic.PaintGreen, Enum.Material.Metal)
	part(model, "Trim", Vector3.new(20, 0.5, 0.5), at(0, 8.8, -5.6), Rustic.Wood, Enum.Material.Wood)
	part(model, "Counter", Vector3.new(12, 3.6, 1.6), at(0, 2.1, 1.8), Rustic.Wood, Enum.Material.WoodPlanks)
	part(model, "CounterTop", Vector3.new(12.4, 0.3, 2), at(0, 4.05, 1.8), Rustic.WoodDark, Enum.Material.Wood)
	-- A map of the plots on the back wall, drawn to scale.
	local map = part(model, "PlotMap", Vector3.new(9, 5, 0.2), at(0, 6, 4.1), Rustic.Cloth, Enum.Material.Fabric)
	-- Seen from the counter you face south, so south is up and west is on your right.
	local scale = 1 / 32
	for _, def in LandConfig.Plots do
		local zone = zoneOf(def)
		local mid = (zone.min + zone.max) / 2
		local w, d = def.tiles.X * T * scale, (def.tiles.Y * T + STRIP) * scale
		part(model, "MapPlot", Vector3.new(w, d, 0.1), map.CFrame * CFrame.new((mid.X + 26) * scale, (mid.Y - 156) * scale, -0.12), Rustic.PaintGreen)
	end
	-- Stand on the rug in front of the counter to open the land panel.
	local rug = part(model, "Rug", Vector3.new(10, 0.1, 4), at(0, 0.65, -1.6), Rustic.PaintRed, Enum.Material.Fabric)
	rug.CanCollide = false
	CollectionService:AddTag(rug, "LandCounter")
	sign(roof, "MEADOW LAND OFFICE\nBuy a plot, build a farm", Vector3.new(0, 4, 0))
end

-- A save was picked: give back its farm, if it owns land.
local function onLoaded(player)
	local s = Data.get(player)
	if not s or not (s.land and s.land.owned) then
		return
	end
	local plot = pickPlot(s.land.plot)
	if not plot then
		Data.toast(player, "Every plot on this server is taken, so your farm can't be set up here. It is still saved.")
		return
	end
	claim(plot, player, s.land)
	parkVehicles(player, plot)
	Data.toast(player, ("Your farm is on %s, down the plot road south of the main road."):format(plot.def.name))
end

function Land.build(worldFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Land"
	folder.Parent = worldFolder
	vehiclesFolder = Instance.new("Folder")
	vehiclesFolder.Name = "ParkedTrucks"
	vehiclesFolder.Parent = worldFolder

	state = Instance.new("Folder")
	state.Name = "Land"
	local remotes = {}
	for _, name in { "Buy", "Place", "Remove" } do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = state
		remotes[name] = remote
	end

	buildOffice(folder)
	for i, def in LandConfig.Plots do
		buildPlot(folder, i, def)
	end
	state.Parent = ReplicatedStorage

	local function guard(fn)
		return function(player, ...)
			local ok, result, message = pcall(fn, player, ...)
			if not ok then
				warn("[Needlewood] land error: " .. tostring(result))
				return false, "Something went wrong."
			end
			return result, message
		end
	end
	remotes.Buy.OnServerInvoke = guard(onBuy)
	remotes.Place.OnServerInvoke = guard(onPlace)
	remotes.Remove.OnServerInvoke = guard(onRemove)

	Data.loaded.Event:Connect(onLoaded)
	for _, player in Players:GetPlayers() do
		if Data.get(player) then
			task.spawn(onLoaded, player)
		end
	end
	-- Silo counts change on their own; keep the save's copy current.
	task.spawn(function()
		while true do
			task.wait(5)
			for player, plot in plotOf do
				if plot.dirty then
					saveItems(player, plot)
				end
			end
		end
	end)
	-- Save the plot before Data saves the player on leaving, then free it.
	Data.beforeSave = function(player)
		local plot = plotOf[player]
		if plot then
			saveItems(player, plot)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		local plot = plotOf[player]
		if plot then
			saveItems(player, plot)
			release(plot)
		end
	end)
end

return Land
