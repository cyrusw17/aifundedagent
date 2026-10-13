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
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factory = require(Shared.Config.Factory)
local LandConfig = require(Shared.Config.Land)
local Meadow = require(Shared.Config.Meadow)
local Rustic = require(Shared.Config.Rustic)
local GameConfig = require(Shared.Config.Game)
local Sorters = require(Shared.Config.Sorters)
local Economy = require(Shared.Economy)
local Props = require(script.Parent.Props)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Bales = require(script.Parent.Bales)
local Conveyors = require(script.Parent.Conveyors)
local Machines = require(script.Parent.Machines)
local Tutorial = require(script.Parent.Tutorial)
local Vehicles = require(script.Parent.Vehicles)
local Likes = require(script.Parent.Likes)
local Needle = require(script.Parent.Needle)
local Starbeam = require(script.Parent.Starbeam)
local Press = require(script.Parent.Press)
local Baler = require(script.Parent.Baler)
local Vault = require(script.Parent.Vault)
local Blueprints = require(script.Parent.Blueprints)
local Display = require(script.Parent.Display)
local Skins = require(script.Parent.Skins)
local Mixer = require(script.Parent.Mixer)
local LineStats = require(script.Parent.LineStats)
local Quests = require(script.Parent.Quests)

local Land = {}

local T = Factory.TileSize
local TOP = Factory.BeltTop
local STRIP = LandConfig.StripDepth
local FENCE_HEIGHT = 3

local pieces = {}
for _, def in LandConfig.Pieces do
	pieces[def.id] = def
end

local themes = {}
for _, theme in LandConfig.Themes do
	themes[theme.id] = theme
end
local DEFAULT_THEME = LandConfig.Themes[1]

local plots = {} -- index -> plot record
local farmNames = {} -- userId -> the name on their first farm, for the likes board while they are on this server
local plotOf = {} -- player -> the plot record they build on (their active farm)
local farms = {} -- player -> { land = plot, land2 = plot }: every plot they own, by save key
local lastAction = {} -- player -> os.clock() of their last place or remove
local state = nil -- ReplicatedStorage.Land: remotes and what the client needs to know about every plot
local vehiclesFolder = nil

local part = Machines.part
local sign = Machines.sign

-- A tile's key, as Conveyors.luau keys its grid: "gx,gz" on the ground, "gx,gz,1" on the raised belt level.
local addBinPrompt -- defined with the plot setup below
local dress -- plot themes, defined with the plot setup below

local function key(gx, gz, level)
	if level and level > 0 then
		return ("%d,%d,%d"):format(gx, gz, level)
	end
	return gx .. "," .. gz
end

-- The belt levels a piece takes: a ramp both, a raised belt level 1, everything else the ground.
local function levelsOf(def)
	if def.kind == "ramp" then
		return { 0, 1 }
	end
	return { def.level or 0 }
end

-- The piece at a tile, the raised one first (it is the one on top).
local function itemAt(plot, gx, gz)
	return plot.taken[key(gx, gz, 1)] or plot.taken[key(gx, gz)]
end

-- The piece with this id anchored at (gx, gz), on either level.
local function anchoredAt(plot, id, gx, gz)
	for _, level in { 1, 0 } do
		local item = plot.taken[key(gx, gz, level)]
		if item and item.id == id and item.gx == gx and item.gz == gz then
			return item
		end
	end
	return nil
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

-- Saves keep pieces in plot tiles as seen with the lane to the south, so a farm rebuilds the same on any plot. Plots
-- that open to the north are that same plot turned half a turn; this maps a piece between the two (both ways). The
-- back-left anchor turns with the piece, so it lands on the turned piece's back-left cell.
local OPPOSITE = { N = "S", S = "N", E = "W", W = "E" }
local function turnFor(plot, gx, gz, dir)
	if plot.def.open == "S" then
		return gx, gz, dir
	end
	return plot.tiles.X - 1 - gx, plot.tiles.Z - 1 - gz, OPPOSITE[dir] or dir
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
-- Farm crew: players the owner lets drive their truck and work their line. Hay a crew member runs through the plot's
-- sorters and buyers pays the owner, and the needles it finds go in the owner's bin.
local CREW_MAX = 6
local function payeeFor(plot)
	return function(ownerId)
		if ownerId and plot.ownerId and (ownerId == plot.ownerId or (plot.crew and plot.crew[ownerId])) then
			return plot.ownerId
		end
		return ownerId
	end
end

local function publish(plot)
	local info = plot.info
	info:SetAttribute("OwnerId", plot.ownerId or 0)
	info:SetAttribute("OwnerName", plot.ownerName or "")
	local taken = {}
	for k in plot.taken do
		table.insert(taken, k)
	end
	info:SetAttribute("Taken", table.concat(taken, ";"))
	local crew = {}
	for userId in plot.crew or {} do
		table.insert(crew, tostring(userId))
	end
	info:SetAttribute("Crew", table.concat(crew, ","))
	info:SetAttribute("Likes", plot.likes or 0)
	info:SetAttribute("LockedRows", plot.locked or 0)
	info:SetAttribute("Theme", plot.theme or "")
	info:SetAttribute("FarmName", plot.farmName or "")
	plot.likePrompt.Enabled = plot.ownerId ~= nil
	plot.likePrompt.ObjectText = plot.ownerName and (plot.ownerName .. "'s farm") or ""
	if plot.ownerId then
		local title = plot.farmName and ("%s\n%s's farm"):format(plot.farmName:upper(), plot.ownerName) or ("%s's farm"):format(plot.ownerName)
		plot.label.Text = ("%s\n%s\n♥ %d this week"):format(plot.def.name:upper(), title, plot.likes or 0)
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

	local capacity = def.capacity or LandConfig.SiloCapacity
	local laneX = -(def.size[1] - 1) * T / 2
	local label
	if def.look == "barn" then
		-- A red barn: plank walls, a pitched roof, white trim, and big doors at the front over the chute.
		model.Name = "HayBarn"
		local wallH = 10
		local body = part(model, "Body", Vector3.new(w - 1, wallH, l - 1), frame * CFrame.new(0, wallH / 2, 0), Rustic.PaintRed, Enum.Material.WoodPlanks)
		local pitch = math.rad(35)
		local roofW = (w - 1) / 2 / math.cos(pitch) + 0.6
		for _, side in { -1, 1 } do
			part(model, "Roof", Vector3.new(roofW, 0.6, l), frame * CFrame.new(side * (w - 1) / 4, wallH + (w - 1) / 4 * math.tan(pitch), 0) * CFrame.Angles(0, 0, -side * pitch), Rustic.Metal, Enum.Material.Metal)
		end
		for _, x in { -(w - 1) / 2, (w - 1) / 2 } do
			part(model, "Trim", Vector3.new(0.3, wallH, 0.3), frame * CFrame.new(x, wallH / 2, -(l - 1) / 2 - 0.1), Rustic.PaintCream, Enum.Material.WoodPlanks)
		end
		part(model, "Doors", Vector3.new(w * 0.5, wallH * 0.7, 0.3), frame * CFrame.new(0, wallH * 0.35, -(l - 1) / 2 - 0.15), Rustic.PaintRedDark, Enum.Material.WoodPlanks)
		part(model, "Chute", Vector3.new(4, 3.2, 3), frame * CFrame.new(laneX, TOP + 1.6, -l / 2 + 1), Rustic.Metal, Enum.Material.Metal)
		label = sign(body, "", Vector3.new(0, wallH / 2 + (w - 1) / 4 + 3, 0))
		local mesh = Props.make("barn", frame * CFrame.new(0, wallH / 2, 0), Vector3.new(w - 0.5, wallH + (w - 1) / 2, l - 0.5))
		if mesh then
			Props.restOn(mesh, frame.Position.Y)
			for _, p in mesh:GetDescendants() do
				if p:IsA("BasePart") then
					p.CanCollide = false
				end
			end
			Props.weldTo(mesh, body, { body })
		end
	else
		local height = 20
		local body = part(model, "Body", Vector3.new(height, w - 1, w - 1), frame * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Rustic.PaintCream, Enum.Material.Metal)
		body.Shape = Enum.PartType.Cylinder
		local cap = part(model, "Cap", Vector3.new(w - 1.6, 2.4, w - 1.6), frame * CFrame.new(0, height + 1.2, 0), Rustic.Metal, Enum.Material.Metal)
		cap.Shape = Enum.PartType.Ball
		part(model, "Band", Vector3.new(0.4, w - 0.6, w - 0.6), frame * CFrame.new(0, 6, 0) * CFrame.Angles(0, 0, math.pi / 2), Rustic.WoodDark, Enum.Material.Wood).Shape = Enum.PartType.Cylinder
		-- The chute comes out over the anchor lane at belt height.
		part(model, "Chute", Vector3.new(4, 3.2, 3), frame * CFrame.new(laneX, TOP + 1.6, -l / 2 + 1), Rustic.Metal, Enum.Material.Metal)
		label = sign(cap, "", Vector3.new(0, 4, 0))

		local mesh = Props.make("silo_small", frame * CFrame.new(0, height / 2, 0), Vector3.new(w - 0.5, height + 2, w - 0.5))
		if mesh then
			Props.restOn(mesh, frame.Position.Y) -- on the plot's ground, wherever the plot sits
			for _, p in mesh:GetDescendants() do
				if p:IsA("BasePart") then
					p.CanCollide = false
				end
			end
			-- The part silo stays until this client has loaded the mesh (PropMeshes.client.luau), so it is never invisible.
			Props.weldTo(mesh, body, { body, cap })
		end
	end

	item.stored = math.clamp(item.stored or 0, 0, capacity)
	local function refresh()
		label.Text = ("%s\n%d / %d bales"):format(def.name:upper(), item.stored, capacity)
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
				if b and p == b.body and not b.gone and not b.carriedBy and not b.breaking and not b.sorted and item.stored < capacity then
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

-- Blueprints: a see-through template that turns solid once it is filled. Bales dropped into it make thatch; needles
-- used from your pocket at it make iron. item.stored counts what is in so far and item.fill is the material.
local BLUEPRINT_GHOST = Color3.fromRGB(150, 185, 215)
local FILLS = {
	hay = { color = Color3.fromRGB(205, 182, 120), material = Enum.Material.Fabric, label = "thatch" },
	needle = { color = Color3.fromRGB(128, 117, 105), material = Enum.Material.DiamondPlate, label = "iron" },
}

local function blueprintShape(frame, shape)
	if shape == "post" then
		return Vector3.new(1.2, 5, 1.2), frame * CFrame.new(0, 2.5, 0)
	elseif shape == "wall" then
		return Vector3.new(T, 6, 0.6), frame * CFrame.new(0, 3, T / 2 - 0.3)
	end
	return Vector3.new(T, 0.6, T), frame * CFrame.new(0, 0.3, 0)
end

-- Takes up to n needles from a player's pocket. Returns how many it took.
local function takeNeedles(player, n)
	local pocket = Needle.held(player)
	local took = 0
	-- Plain needles first, so a mutated or polished one isn't spent as one unit of iron.
	local keys = {}
	for key in pocket do
		table.insert(keys, key)
	end
	local function worth(key)
		local _, mult, polished = Needle.parseKey(key)
		return mult + (polished and 0.5 or 0)
	end
	table.sort(keys, function(a, b)
		return worth(a) < worth(b)
	end)
	for _, key in keys do
		local count = pocket[key]
		local use = math.min(count, n - took)
		pocket[key] = count - use > 0 and count - use or nil
		took += use
		if took >= n then
			break
		end
	end
	Data.sync(player)
	return took
end

local function buildBlueprint(plot, item, def)
	local frame = footprintFrame(plot, def, item.gx, item.gz, item.dir)
	local model = Instance.new("Model")
	model.Name = "Blueprint"
	model.Parent = plot.items
	local size, cframe = blueprintShape(frame, def.shape)
	local body = part(model, "Body", size, cframe, BLUEPRINT_GHOST, Enum.Material.ForceField)
	body.CanCollide = false
	local label = sign(body, "", Vector3.new(0, 3, 0))
	if not FILLS[item.fill] then
		item.fill = nil
	end

	local function needed()
		return item.fill == "needle" and def.needles or def.bales
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FillPrompt"
	prompt.ActionText = "Fill with needles"
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	local thatchPrompt = prompt:Clone()
	thatchPrompt.Name = "ThatchPrompt"
	thatchPrompt.ActionText = "Fill with thatch"
	thatchPrompt.KeyboardKeyCode = Enum.KeyCode.F
	thatchPrompt.UIOffset = Vector2.new(0, 60)
	thatchPrompt.Parent = body

	local function refresh()
		item.stored = math.clamp(item.stored or 0, 0, needed())
		local done = item.stored >= needed()
		if done then
			local look = FILLS[item.fill]
			body.Color = look.color
			body.Material = look.material
			body.Transparency = 0
			body.CanCollide = true
			label.Text = ""
			prompt.Enabled = false
			thatchPrompt.Enabled = false
		elseif item.fill then
			body.Transparency = 0.45 - 0.3 * item.stored / needed()
			label.Text = item.fill == "hay" and ("%d / %d bales"):format(item.stored, def.bales)
				or ("%d / %d needles"):format(item.stored, def.needles)
			prompt.Enabled = item.fill == "needle"
			thatchPrompt.Enabled = item.fill == "hay"
		else
			body.Transparency = 0.5
			label.Text = ("BLUEPRINT\n%d bales, %d thatch or %d needles"):format(def.bales, def.thatch, def.needles)
			prompt.Enabled = true
			thatchPrompt.Enabled = true
		end
		return done
	end
	refresh()

	prompt.Triggered:Connect(function(player)
		if plot.owner ~= player and not plot.crew[player.UserId] then
			Data.toast(player, "Only the farm's owner and crew can fill its blueprints.")
			return
		end
		if item.fill == "hay" then
			Data.toast(player, "This one is being filled with bales. Drop bales into it.")
			return
		end
		local took = takeNeedles(player, def.needles - (item.stored or 0))
		if took == 0 then
			Data.toast(player, "You have no needles in your pocket. Pick some up from a bin.")
			return
		end
		item.fill = "needle"
		item.stored = (item.stored or 0) + took
		plot.dirty = true
		if refresh() then
			Data.toast(player, ("Built an iron %s."):format(def.shape))
		end
	end)

	-- Thatch from a hay press finishes the hay fill: the share of the bales still missing, in thatch.
	thatchPrompt.Triggered:Connect(function(player)
		if plot.owner ~= player and not plot.crew[player.UserId] then
			Data.toast(player, "Only the farm's owner and crew can fill its blueprints.")
			return
		end
		if item.fill == "needle" then
			Data.toast(player, "This one is being filled with needles.")
			return
		end
		local missing = def.bales - (item.stored or 0)
		local cost = math.max(1, math.ceil(def.thatch * missing / def.bales))
		if not Press.spend(player, cost) then
			Data.toast(player, ("This needs %d thatch. You carry %d. Press sorted bales at a hay press."):format(cost, Press.thatch(player)))
			return
		end
		item.fill = "hay"
		item.stored = def.bales
		plot.dirty = true
		if refresh() then
			Data.toast(player, ("Built a thatch %s."):format(def.shape))
		end
	end)

	-- Bales dropped into the template fill it with thatch.
	local intakeSize = size + Vector3.new(3, 4, 3)
	task.spawn(function()
		while model.Parent and (item.stored or 0) < needed() do
			task.wait(0.3)
			if item.fill ~= "needle" then
				for _, p in Workspace:GetPartBoundsInBox(cframe, intakeSize) do
					local b = Bales.fromPart(p)
					if b and p == b.body and not b.gone and not b.carriedBy and not b.breaking and (item.stored or 0) < def.bales then
						Bales.consume(b)
						item.fill = "hay"
						item.stored = (item.stored or 0) + 1
						plot.dirty = true
						if refresh() and plot.owner then
							Data.toast(plot.owner, ("Built a thatch %s."):format(def.shape))
						end
					end
				end
			end
		end
	end)
	return model
end

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

-- Decor: looks only, built from parts in the Rustic palette (the scarecrow wears its Blender mesh when imported).
local function buildDecor(plot, item, def)
	local frame = footprintFrame(plot, def, item.gx, item.gz, item.dir)
	local model = Instance.new("Model")
	model.Name = "Decor_" .. def.look
	model.Parent = plot.items
	if def.look == "flowers" then
		part(model, "Box", Vector3.new(4, 1.4, 1.6), frame * CFrame.new(0, 0.7, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
		part(model, "Soil", Vector3.new(3.6, 0.2, 1.2), frame * CFrame.new(0, 1.45, 0), Rustic.Mud, Enum.Material.Ground)
		local colors = { Rustic.PaintRed, Rustic.PaintYellow, Rustic.PaintCream, Rustic.PaintBlue }
		for i = 0, 5 do
			local x = -1.5 + i * 0.6
			part(model, "Stem", Vector3.new(0.12, 0.8, 0.12), frame * CFrame.new(x, 1.9, (i % 2 - 0.5) * 0.4), Rustic.PaintGreen)
			local bloom = part(model, "Bloom", Vector3.new(0.45, 0.45, 0.45), frame * CFrame.new(x, 2.35, (i % 2 - 0.5) * 0.4), colors[i % #colors + 1], Enum.Material.Fabric)
			bloom.Shape = Enum.PartType.Ball
			bloom.CanCollide = false
		end
	elseif def.look == "bench" then
		for _, x in { -1.6, 1.6 } do
			part(model, "Bale", Vector3.new(1.6, 1.6, 2.4), frame * CFrame.new(x, 0.8, 0), Rustic.Hay, Enum.Material.Fabric)
			part(model, "Twine", Vector3.new(1.66, 1.66, 0.15), frame * CFrame.new(x, 0.8, 0.5), Rustic.Twine, Enum.Material.Fabric).CanCollide = false
		end
		local seat = part(model, "Seat", Vector3.new(4.8, 0.3, 1.8), frame * CFrame.new(0, 1.75, 0), Rustic.Wood, Enum.Material.WoodPlanks)
		local sit = Instance.new("Seat")
		sit.Name = "Sit"
		sit.Size = Vector3.new(1.6, 0.2, 1.4)
		sit.CFrame = seat.CFrame * CFrame.new(0, 0.25, 0)
		sit.Transparency = 1
		sit.Anchored = true
		sit.Parent = model
	elseif def.look == "lantern" then
		part(model, "Post", Vector3.new(0.5, 7, 0.5), frame * CFrame.new(0, 3.5, 0), Rustic.WoodDark, Enum.Material.Wood)
		part(model, "Arm", Vector3.new(0.3, 0.3, 1.6), frame * CFrame.new(0, 6.8, -0.8), Rustic.WoodDark, Enum.Material.Wood)
		part(model, "Cap", Vector3.new(0.9, 0.3, 0.9), frame * CFrame.new(0, 6.5, -1.5), Rustic.Metal, Enum.Material.Metal)
		local glass = part(model, "Lamp", Vector3.new(0.7, 0.9, 0.7), frame * CFrame.new(0, 5.9, -1.5), Rustic.PaintYellow, Enum.Material.Neon)
		glass.CanCollide = false
		glass.Transparency = 0.2
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 200, 130)
		light.Range = 16
		light.Brightness = 1.2
		light.Parent = glass
		CollectionService:AddTag(glass, "NightLamp")
	elseif def.look == "scarecrow" then
		local post = part(model, "Post", Vector3.new(0.4, 6.5, 0.4), frame * CFrame.new(0, 3.25, 0), Rustic.WoodDark, Enum.Material.Wood)
		local body = Instance.new("Model")
		body.Name = "Body"
		body.Parent = model
		part(body, "Arms", Vector3.new(4.2, 0.35, 0.35), frame * CFrame.new(0, 4.8, 0), Rustic.WoodDark, Enum.Material.Wood)
		part(body, "Shirt", Vector3.new(1.8, 2, 0.9), frame * CFrame.new(0, 4.3, 0), Rustic.PaintRed, Enum.Material.Fabric)
		part(body, "Sleeves", Vector3.new(3.6, 0.6, 0.6), frame * CFrame.new(0, 4.8, 0), Rustic.PaintRedDark, Enum.Material.Fabric)
		local head = part(body, "Head", Vector3.new(1.2, 1.2, 1.2), frame * CFrame.new(0, 5.95, 0), Rustic.Cloth, Enum.Material.Fabric)
		head.Shape = Enum.PartType.Ball
		part(body, "Hat", Vector3.new(1.8, 0.15, 1.8), frame * CFrame.new(0, 6.6, 0), Rustic.Hay, Enum.Material.Fabric)
		part(body, "Crown", Vector3.new(1, 0.6, 1), frame * CFrame.new(0, 6.95, 0), Rustic.Hay, Enum.Material.Fabric)
		Skins.dress("scarecrow", post, body, frame, CFrame.Angles(0, 0, 0))
	end
	return model
end

-- Pieces ------------------------------------------------------------------------------------------------------------

-- Builds one piece on a plot. No checks and no charge: callers do that.
-- stored, fill and display come back from a save: a silo's bales, a blueprint's fill, a display's needles.
local function spawnItem(plot, def, gx, gz, dir, stored, fill, display)
	local item = { id = def.id, gx = gx, gz = gz, dir = dir, cells = cellsFor(def, gx, gz, dir), instances = {}, stored = stored, fill = fill }
	local frame = Conveyors.frame(plot.grid, gx, gz, dir)
	if def.kind == "ramp" then
		table.insert(item.instances, Conveyors.ramp(plot.grid, gx, gz, dir, def.up).Parent)
	elseif def.kind == "belt" or def.kind == "separator" or def.kind == "press" or def.kind == "baler" or def.kind == "starbeam" then
		-- A sorter sits over belt tiles of its own, so a line runs straight through it.
		for _, cell in item.cells do
			local belt = Conveyors.place(plot.grid, cell[1], cell[2], dir, nil, def.level)
			table.insert(item.instances, belt.Parent)
		end
	end
	if def.kind == "separator" then
		table.insert(item.instances, Machines.sorter(plot.items, frame, def.id, plot.bin, payeeFor(plot)))
	elseif def.kind == "press" then
		table.insert(item.instances, Press.build(plot.items, frame))
	elseif def.kind == "baler" then
		table.insert(item.instances, Baler.build(plot.items, frame))
	elseif def.kind == "starbeam" then
		table.insert(item.instances, Starbeam.build(plot.items, frame, function()
			return plot.ownerId
		end))
	elseif def.kind == "mixer" then
		table.insert(item.instances, Mixer.build(plot.items, frame))
	elseif def.kind == "splitter" then
		table.insert(item.instances, Machines.splitter(plot.grid, gx, gz, dir, def.rule))
	elseif def.kind == "display" then
		item.wall = Display.wall(plot.items, frame, function()
			return plot.ownerId
		end, typeof(display) == "table" and display or nil)
		table.insert(item.instances, item.wall.model)
	elseif def.kind == "vault" then
		-- Saved and cleared like the display (item.wall): contents() goes in the save, clear() before freeing a plot.
		item.wall = Vault.build(plot.items, frame, function()
			return plot.ownerId
		end, typeof(display) == "table" and display or nil)
		table.insert(item.instances, item.wall.model)
	elseif def.kind == "buyer" then
		table.insert(item.instances, Machines.hayBuyer(plot.items, frame, "HAY BUYER", payeeFor(plot)))
	elseif def.kind == "silo" then
		table.insert(item.instances, buildSilo(plot, item, def))
	elseif def.kind == "parking" then
		table.insert(item.instances, buildParking(plot, item, def))
	elseif def.kind == "blueprint" then
		table.insert(item.instances, buildBlueprint(plot, item, def))
	elseif def.kind == "decor" then
		table.insert(item.instances, buildDecor(plot, item, def))
	end
	for _, cell in item.cells do
		for _, level in levelsOf(def) do
			plot.taken[key(cell[1], cell[2], level)] = item
		end
	end
	table.insert(plot.list, item)
	return item
end

local function destroyItem(plot, item)
	local models = {}
	for _, instance in item.instances do
		models[instance] = true
		instance:Destroy()
	end
	for k, it in plot.taken do
		if it == item then
			plot.taken[k] = nil
		end
	end
	for k, tile in plot.grid.tiles do
		if models[tile.model] then
			plot.grid.tiles[k] = nil
		end
	end
	local i = table.find(plot.list, item)
	if i then
		table.remove(plot.list, i)
	end
end

-- Whether a piece fits: every cell on the plot and free.
-- A tile row counted from the back fence (0) toward the lane, the same on both sides of the lane.
local function rowFromBack(plot, z)
	return if plot.def.open == "S" then z else plot.tiles.Z - 1 - z
end

-- ignore (optional) is an item whose own cells count as free, for moving it.
local function fits(plot, def, gx, gz, dir, ignore)
	for _, cell in cellsFor(def, gx, gz, dir) do
		local x, z = cell[1], cell[2]
		if x < 0 or z < 0 or x >= plot.tiles.X or z >= plot.tiles.Z then
			return false
		end
		for _, level in levelsOf(def) do
			local taken = plot.taken[key(x, z, level)]
			if taken and taken ~= ignore then
				return false
			end
		end
		-- Only a plain belt runs under a raised belt; machines are too tall.
		local below, above = plot.taken[key(x, z)], plot.taken[key(x, z, 1)]
		if def.level == 1 and below and below ~= ignore and pieces[below.id].kind ~= "belt" then
			return false
		end
		if def.kind ~= "ramp" and (def.level or 0) == 0 and def.kind ~= "belt" and above and above ~= ignore then
			return false
		end
		if rowFromBack(plot, z) < (plot.locked or 0) then
			return false
		end
	end
	return true
end

-- What gets saved: the plot and the pieces by id, anchor cell and direction (and a silo's bales).
-- Writes a plot into its save table (plot-local, so it loads onto any free plot). ownerId picks whose bin needles go in.
local function writeLand(land, plot, ownerId)
	local items = {}
	for _, item in plot.list do
		local gx, gz, dir = turnFor(plot, item.gx, item.gz, item.dir)
		table.insert(items, { id = item.id, gx = gx, gz = gz, dir = dir, stored = item.stored, fill = item.fill, display = item.wall and item.wall.contents() or nil })
	end
	-- Pieces that didn't fit this plot stay in the save, so moving back to a bigger plot brings them back.
	for _, saved in plot.leftOut or {} do
		table.insert(items, saved)
	end
	land.items = items
	land.plot = plot.index
	land.expansions = LandConfig.ExpansionRows - (plot.locked or 0)
	land.binSorted = plot.binSorted or nil
	land.binPolisher = plot.binPolisher or nil
	land.theme = plot.theme
	land.name = plot.farmName or plot.pendingName -- a saved name still being re-filtered stays saved
	land.savedAt = os.time() -- for the mailbox: how long the farm sat while its owner was away
	land.needles = plot.bin.contents(ownerId)
	local crew = {}
	for userId in plot.crew do
		table.insert(crew, userId)
	end
	land.crew = crew
end

local function saveItems(player, plot)
	local s = Data.get(player)
	local land = s and s[plot.landKey or "land"]
	if not land then
		return
	end
	writeLand(land, plot, player.UserId)
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
		-- No parking pad: on the lane in front of the plot. Plots across the lane from each other share a middle, so
		-- the south row parks west of it facing east and the north row east of it facing west: nose to nose, 6 apart,
		-- each on its own side of the lane.
		local away = if plot.def.open == "S" then -1 else 1
		local nose = Vector3.new(plot.corner.X + plot.size.X / 2 + away * 3, 0, plot.laneZ + away * 3)
		at = CFrame.lookAt(nose, nose - Vector3.xAxis * away)
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

-- Locked rows at the back of the plot: rough ground with a sign until the owner buys them.
local function drawLocks(plot)
	for _, p in plot.lockParts or {} do
		p:Destroy()
	end
	plot.lockParts = {}
	for r = 0, (plot.locked or 0) - 1 do
		local z = if plot.def.open == "S" then r else plot.tiles.Z - 1 - r
		local at = plot.corner + Vector3.new(plot.size.X / 2, 0.25, z * T + T / 2)
		local p = part(plot.model, "LockedRow", Vector3.new(plot.size.X, 0.3, T), CFrame.new(at), Rustic.Mud, Enum.Material.Grass)
		p.CanCollide = false
		table.insert(plot.lockParts, p)
		if r == 0 then
			sign(p, ("LOCKED ROWS\nBUILD > EXPAND, $%d a row"):format(LandConfig.ExpansionPrice), Vector3.new(0, 4, 0))
		end
	end
end

-- The owner can buy dividers that sort the plot's needle bin by type.
addBinPrompt = function(plot)
	local floor = plot.bin.model:FindFirstChild("Floor")
	if not floor then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DividerPrompt"
	prompt.ActionText = ("Add type dividers $%d"):format(LandConfig.BinDividersPrice)
	prompt.ObjectText = "Needle bin"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = floor
	prompt.Triggered:Connect(function(player)
		if plot.owner ~= player then
			Data.toast(player, "Only the farm's owner can add dividers to its bin.")
			return
		end
		if plot.binSorted then
			return
		end
		local paid, why = Bank.charge(player, LandConfig.BinDividersPrice, "Land: bin dividers")
		if not paid then
			Data.toast(player, why or "Not enough money.")
			return
		end
		plot.binSorted = true
		plot.bin.splitByType()
		prompt.Enabled = false
		saveItems(player, plot)
		Data.toast(player, "Your needle bin now sorts needles into a corner per type.")
	end)
	plot.binPrompt = prompt

	-- And a polishing wheel on its side: polished needles sell for more.
	local polish = Instance.new("ProximityPrompt")
	polish.Name = "PolisherPrompt"
	polish.ActionText = ("Fit a needle polisher $%d"):format(LandConfig.PolisherPrice)
	polish.ObjectText = "Needle bin"
	polish.HoldDuration = 0.5
	polish.MaxActivationDistance = 10
	polish.RequiresLineOfSight = false
	polish.UIOffset = Vector2.new(0, 80) -- below the dividers prompt
	polish.Parent = floor
	polish.Triggered:Connect(function(player)
		if plot.owner ~= player then
			Data.toast(player, "Only the farm's owner can fit a polisher to its bin.")
			return
		end
		if plot.binPolisher then
			return
		end
		local paid, why = Bank.charge(player, LandConfig.PolisherPrice, "Land: needle polisher")
		if not paid then
			Data.toast(player, why or "Not enough money.")
			return
		end
		plot.binPolisher = true
		plot.bin.fitPolisher()
		polish.Enabled = false
		saveItems(player, plot)
		Data.toast(player, "Needles resting in your bin now get polished, and polished needles sell for more.")
	end)
	plot.polishPrompt = polish
end

-- Farm names. Anything another player will read goes through Roblox's text filter first, as the owner's own words.
local NAME_MAX = 24
local function filterName(raw, userId)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(raw, userId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()
	end)
	return ok and result or nil
end

local function setFarmName(plot, name)
	plot.farmName = name
	plot.pendingName = nil
	if plot.ownerId and plot.landKey == "land" then
		farmNames[plot.ownerId] = name
	end
end

local function release(plot)
	local owner = plot.owner
	if owner then
		local mine = farms[owner]
		if mine then
			mine[plot.landKey or "land"] = nil
		end
		if plotOf[owner] == plot then
			plotOf[owner] = mine and (mine.land or mine.land2) or nil
		end
		owner:SetAttribute("LandPlot", plotOf[owner] and plotOf[owner].index or 0)
		owner:SetAttribute("FarmCount", mine and ((mine.land and 1 or 0) + (mine.land2 and 1 or 0)) or 0)
	end
	plot.landKey = nil
	-- The owner's displayed needles are in their save; emptying the pegs first keeps them from going back to the pocket
	-- as well.
	for _, item in plot.list do
		if item.wall then
			item.wall.clear()
		end
	end
	clearPlot(plot)
	-- Visitors who sorted here keep what their hay gave up: it goes to their pockets before the bin empties.
	for _, other in Players:GetPlayers() do
		local s = other ~= owner and Data.get(other)
		if s then
			local theirs = plot.bin.contents(other.UserId)
			if next(theirs) then
				for k, count in theirs do
					s.pocket[k] = (s.pocket[k] or 0) + count
				end
				Data.sync(other)
			end
		end
	end
	plot.bin.clear() -- the owner's needles are in their save; nobody else's should sit on a free plot
	if plot.binSorted or plot.binPolisher then
		-- Dividers and the polisher belong to the owner's save; the next owner gets a plain bin.
		plot.bin.model:Destroy()
		plot.bin = Machines.needleBin(plot.model, plot.binFrame)
		plot.binSorted = nil
		plot.binPolisher = nil
		addBinPrompt(plot)
	end
	plot.leftOut = nil
	if plot.ownerId and farmNames[plot.ownerId] == plot.farmName then
		farmNames[plot.ownerId] = nil
	end
	plot.farmName, plot.pendingName = nil, nil
	plot.crew = {}
	plot.locked = 0
	dress(plot, nil)
	drawLocks(plot)
	plot.mailLabel.Text = "MAILBOX\nNo mail."
	plot.owner, plot.ownerId, plot.ownerName = nil, nil, nil
	publish(plot)
end

-- Gives a plot to a player and rebuilds what they saved on it. Pieces that don't fit (an older save) are skipped but kept.
-- landKey is the save's key for this farm: "land" (the first) or "land2" (a second plot).
local function claim(plot, player, saved, landKey)
	landKey = landKey or "land"
	plot.owner, plot.ownerId, plot.ownerName = player, player.UserId, player.DisplayName
	plot.landKey = landKey
	farms[player] = farms[player] or {}
	farms[player][landKey] = plot
	if not plotOf[player] or landKey == "land" then
		plotOf[player] = plot
	end
	player:SetAttribute("FarmCount", (farms[player].land and 1 or 0) + (farms[player].land2 and 1 or 0))
	plot.likes = 0
	task.spawn(function()
		local count = Likes.count(player.UserId)
		if plot.ownerId == player.UserId then
			plot.likes = count
			publish(plot)
		end
	end)
	player:SetAttribute("LandPlot", plotOf[player].index)
	plot.leftOut = {}
	plot.crew = {}
	-- Saves from before expansions existed get the whole plot.
	local bought = typeof(saved.expansions) == "number" and saved.expansions or LandConfig.ExpansionRows
	plot.locked = LandConfig.ExpansionRows - math.clamp(math.floor(bought), 0, LandConfig.ExpansionRows)
	drawLocks(plot)
	dress(plot, saved.theme)
	plot.farmName, plot.pendingName = nil, nil
	if typeof(saved.name) == "string" and saved.name ~= "" then
		-- Saved names were filtered when they were set; filter again before showing it, in case the filter changed.
		local raw = saved.name
		plot.pendingName = raw
		task.spawn(function()
			local clean = filterName(raw, player.UserId)
			if clean and clean ~= "" and plot.owner == player and plot.landKey == landKey and plot.pendingName == raw then
				setFarmName(plot, clean)
				publish(plot)
			end
		end)
	end
	if saved.binSorted then
		plot.binSorted = true
		plot.bin.splitByType()
		if plot.binPrompt then
			plot.binPrompt.Enabled = false
		end
	end
	if saved.binPolisher then
		plot.binPolisher = true
		plot.bin.fitPolisher()
		if plot.polishPrompt then
			plot.polishPrompt.Enabled = false
		end
	end
	for _, userId in (typeof(saved.crew) == "table" and saved.crew or {}) do
		if typeof(userId) == "number" and userId ~= player.UserId then
			plot.crew[userId] = true
		end
	end
	for _, s in saved.items or {} do
		local def = typeof(s) == "table" and pieces[s.id]
		if def and isCell(s.gx) and isCell(s.gz) and typeof(s.dir) == "string" and Conveyors.Dirs[s.dir] then
			local gx, gz, dir = turnFor(plot, s.gx, s.gz, s.dir)
			if fits(plot, def, gx, gz, dir) then
				spawnItem(plot, def, gx, gz, dir, typeof(s.stored) == "number" and s.stored or nil, typeof(s.fill) == "string" and s.fill or nil, s.display)
			else
				table.insert(plot.leftOut, s)
			end
		end
	end
	refreshRails(plot)
	publish(plot)
	-- saveItems copies the bin into the save, and the bin is still empty here: keep the saved needles for
	-- restoreNeedles, which runs right after this.
	local keepNeedles = saved.needles
	saveItems(player, plot)
	saved.needles = keepNeedles
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
	-- A save with a farm can buy one more plot, at the second-plot price.
	local landKey = "land"
	local price = nil
	if s.land and s.land.owned then
		if (s.land2 and s.land2.owned) or not plotOf[player] then
			return false, "This save already owns all the land it can."
		end
		landKey = "land2"
		price = LandConfig.SecondPlotPrice
	end
	local plot = typeof(index) == "number" and plots[index]
	if not plot then
		return false, "That plot doesn't exist."
	end
	if plot.ownerId then
		return false, ("%s already belongs to %s."):format(plot.def.name, plot.ownerName)
	end
	local paid, why = Bank.charge(player, price or plot.def.price, "Land: " .. plot.def.name)
	if not paid then
		return false, why
	end
	s[landKey] = { owned = true, plot = index, items = {}, expansions = 0 }
	claim(plot, player, s[landKey], landKey)
	if landKey == "land2" then
		Data.sync(player)
		task.spawn(Data.save, player)
		return true, ("%s is your second farm. Press SWITCH FARM in build mode to build there."):format(plot.def.name)
	end
	Data.sync(player)
	task.spawn(Data.save, player)
	Data.toast(player, ("%s is yours! Walk down the plot road and press BUILD."):format(plot.def.name))
	return true, ("%s is yours. Follow the plot road south and press BUILD."):format(plot.def.name)
end

-- Building ----------------------------------------------------------------------------------------------------------

local remember -- defined below with the undo history

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

-- Undo history: the last few build actions per player, newest last.
local HISTORY = 30
local history = {} -- player -> { entry, ... }
remember = function(player, entry)
	local list = history[player] or {}
	table.insert(list, entry)
	if #list > HISTORY then
		table.remove(list, 1)
	end
	history[player] = list
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
	if def.quest and not Quests.has(player, def.quest) then
		return false, ("The %s is a quest reward. See the quest log (Q)."):format(def.name)
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
	Tutorial.placed(player, def.id)
	remember(player, { kind = "place", anchors = { { id = def.id, gx = gx, gz = gz, price = def.price } } })
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
	local item = itemAt(plot, gx, gz)
	if not item then
		return false, "Nothing built there."
	end
	local def = pieces[item.id]
	local was = { id = item.id, gx = item.gx, gz = item.gz, dir = item.dir, stored = item.stored, fill = item.fill }
	destroyItem(plot, item)
	refreshRails(plot)
	publish(plot)
	saveItems(player, plot)
	local refund = math.floor(def.price * LandConfig.RefundShare)
	Bank.give(player, refund, "Removed a " .. def.name:lower())
	remember(player, { kind = "remove", was = was, refund = refund })
	return true, ("Removed the %s. Got $%d back."):format(def.name:lower(), refund)
end

local function afterEdit(player, plot)
	refreshRails(plot)
	publish(plot)
	saveItems(player, plot)
	Data.sync(player)
end

-- The piece covering a tile: { id, gx, gz, dir } of its anchor, so the client can pick it up to move it.
local function onPick(player, gx, gz)
	local plot = plotOf[player]
	local item = plot and isCell(gx) and isCell(gz) and itemAt(plot, gx, gz)
	if not item then
		return false, "Nothing built there."
	end
	return true, { id = item.id, gx = item.gx, gz = item.gz, dir = item.dir }
end

-- Moves the piece anchored at (fromX, fromZ) to (gx, gz) facing dir, for free. A silo keeps its bales and a blueprint
-- what is in it.
local function onMove(player, fromX, fromZ, gx, gz, dir)
	local plot, why = ownPlot(player)
	if not plot then
		return false, why
	end
	if not isCell(fromX) or not isCell(fromZ) or not isCell(gx) or not isCell(gz) or typeof(dir) ~= "string" or not Conveyors.Dirs[dir] then
		return false, nil
	end
	local item = itemAt(plot, fromX, fromZ)
	if item and (item.gx ~= fromX or item.gz ~= fromZ) then
		item = plot.taken[key(fromX, fromZ)]
	end
	if not item or item.gx ~= fromX or item.gz ~= fromZ then
		return false, "That piece isn't there any more."
	end
	local def = pieces[item.id]
	if not fits(plot, def, gx, gz, dir, item) then
		return false, "That spot is taken or off your land."
	end
	local stored, fill, oldDir = item.stored, item.fill, item.dir
	local display = item.wall and item.wall.contents() or nil
	if item.wall then
		item.wall.clear() -- the needles move with it instead of going back to the pocket
	end
	destroyItem(plot, item)
	spawnItem(plot, def, gx, gz, dir, stored, fill, display)
	afterEdit(player, plot)
	remember(player, { kind = "move", id = def.id, from = { gx = fromX, gz = fromZ, dir = oldDir }, to = { gx = gx, gz = gz, dir = dir } })
	return true, ("Moved the %s."):format(def.name:lower())
end

-- Copies the pieces anchored inside a rectangle of tiles, as offsets from its north-west corner.
local function onCopy(player, x1, z1, x2, z2)
	local plot = plotOf[player]
	if not plot or not (isCell(x1) and isCell(z1) and isCell(x2) and isCell(z2)) then
		return false, nil
	end
	local minX, maxX, minZ, maxZ = math.min(x1, x2), math.max(x1, x2), math.min(z1, z2), math.max(z1, z2)
	local list, total = {}, 0
	for _, item in plot.list do
		if item.gx >= minX and item.gx <= maxX and item.gz >= minZ and item.gz <= maxZ then
			table.insert(list, { id = item.id, dx = item.gx - minX, dz = item.gz - minZ, dir = item.dir })
			total += pieces[item.id].price
		end
	end
	if #list == 0 then
		return false, "Nothing built in that area."
	end
	return true, list, total
end

-- Builds a copied set of pieces with its north-west corner at (gx, gz), paying for all of them at once.
local MAX_PASTE = 60
local function onPaste(player, list, gx, gz)
	local plot, why = ownPlot(player)
	if not plot then
		return false, why
	end
	if typeof(list) ~= "table" or #list == 0 or #list > MAX_PASTE or not isCell(gx) or not isCell(gz) then
		return false, "Nothing to paste."
	end
	local claimed, total, todo = {}, 0, {}
	for _, entry in list do
		local def = typeof(entry) == "table" and typeof(entry.id) == "string" and pieces[entry.id]
		if not def or not isCell(entry.dx) or not isCell(entry.dz) or typeof(entry.dir) ~= "string" or not Conveyors.Dirs[entry.dir] then
			return false, "Nothing to paste."
		end
		if def.quest and not Quests.has(player, def.quest) then
			return false, ("The %s is a quest reward. See the quest log (Q)."):format(def.name)
		end
		local ax, az = gx + entry.dx, gz + entry.dz
		if not fits(plot, def, ax, az, entry.dir) then
			return false, "Part of that doesn't fit there."
		end
		for _, cell in cellsFor(def, ax, az, entry.dir) do
			for _, level in levelsOf(def) do
				local k = key(cell[1], cell[2], level)
				if claimed[k] then
					return false, "Part of that doesn't fit there."
				end
				claimed[k] = true
			end
		end
		total += def.price
		table.insert(todo, { def = def, gx = ax, gz = az, dir = entry.dir })
	end
	local paid, short = Bank.charge(player, total, ("Built %d pieces"):format(#todo))
	if not paid then
		return false, short
	end
	local anchors = {}
	for _, t in todo do
		spawnItem(plot, t.def, t.gx, t.gz, t.dir)
		table.insert(anchors, { id = t.def.id, gx = t.gx, gz = t.gz, price = t.def.price })
	end
	afterEdit(player, plot)
	remember(player, { kind = "place", anchors = anchors })
	return true, ("Built %d pieces for $%d."):format(#todo, total)
end

-- Takes back the player's last build action: a placement is removed with its full price back, a removal is rebuilt
-- for the refund it gave, and a move goes back.
local function onUndo(player)
	local plot, why = ownPlot(player)
	if not plot then
		return false, why
	end
	local list = history[player]
	local entry = list and table.remove(list)
	if not entry then
		return false, "Nothing to undo."
	end
	if entry.kind == "place" then
		local gone, back = 0, 0
		for _, a in entry.anchors do
			local item = anchoredAt(plot, a.id, a.gx, a.gz)
			if item then
				destroyItem(plot, item)
				gone += 1
				back += a.price -- pieces removed since were already refunded, so only those still standing count
			end
		end
		if gone == 0 then
			return false, "Those pieces are already gone."
		end
		Bank.give(player, back, "Undo")
		afterEdit(player, plot)
		return true, ("Undid that. Got $%d back."):format(back)
	elseif entry.kind == "remove" then
		local was = entry.was
		local def = pieces[was.id]
		if not fits(plot, def, was.gx, was.gz, was.dir) then
			return false, "Something else is built there now."
		end
		local paid, short = Bank.charge(player, entry.refund, "Undo")
		if not paid then
			table.insert(list, entry)
			return false, short
		end
		spawnItem(plot, def, was.gx, was.gz, was.dir, was.stored, was.fill)
		afterEdit(player, plot)
		return true, ("Put the %s back."):format(def.name:lower())
	elseif entry.kind == "move" then
		local item = anchoredAt(plot, entry.id, entry.to.gx, entry.to.gz)
		local def = pieces[entry.id]
		if not item
			or not fits(plot, def, entry.from.gx, entry.from.gz, entry.from.dir, item) then
			return false, "Can't move it back now."
		end
		local stored, fill = item.stored, item.fill
		local display = item.wall and item.wall.contents() or nil
		if item.wall then
			item.wall.clear()
		end
		destroyItem(plot, item)
		spawnItem(plot, def, entry.from.gx, entry.from.gz, entry.from.dir, stored, fill, display)
		afterEdit(player, plot)
		return true, ("Moved the %s back."):format(def.name:lower())
	end
	return false, "Nothing to undo."
end

-- World -------------------------------------------------------------------------------------------------------------

-- A low wooden fence along one edge, from a to b on the ground.
-- Buys the next locked row at the back of the owner's plot.
local function onExpand(player)
	local plot = plotOf[player]
	local s = Data.get(player)
	if not plot or not s or not s.land then
		return false, "Buy a plot first."
	end
	if (plot.locked or 0) <= 0 then
		return false, "Your plot is already full size."
	end
	local paid, why = Bank.charge(player, LandConfig.ExpansionPrice, "Land: expansion")
	if not paid then
		return false, why
	end
	plot.locked -= 1
	drawLocks(plot)
	saveItems(player, plot)
	publish(plot)
	Data.sync(player)
	return true, ("Your plot grew by a row of %d tiles."):format(plot.tiles.X)
end

-- Switches which of the player's two farms build mode works on.
local function onSwitch(player)
	local mine = farms[player]
	if not mine or not (mine.land and mine.land2) then
		return false, "You have one farm."
	end
	plotOf[player] = plotOf[player] == mine.land and mine.land2 or mine.land
	history[player] = nil -- undo steps belong to the other farm
	player:SetAttribute("LandPlot", plotOf[player].index)
	return true, ("Now building on %s."):format(plotOf[player].def.name)
end

-- Puts the owner's plot in another theme (free).
local function onTheme(player, id)
	local plot = plotOf[player]
	if not plot then
		return false, "Buy a plot first."
	end
	if typeof(id) ~= "string" or not themes[id] then
		return false, nil
	end
	if os.clock() - (lastAction[player] or 0) < 0.5 then
		return false, nil
	end
	lastAction[player] = os.clock()
	dress(plot, id)
	saveItems(player, plot)
	publish(plot)
	return true, ("Your farm is now %s."):format(themes[id].name:lower())
end

-- Names the owner's active farm. An empty name clears it.
local function onName(player, raw)
	local plot = plotOf[player]
	if not plot then
		return false, "Buy a plot first."
	end
	if typeof(raw) ~= "string" then
		return false, nil
	end
	if os.clock() - (lastAction[player] or 0) < 3 then
		return false, "Wait a moment before renaming again."
	end
	lastAction[player] = os.clock()
	raw = raw:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if raw == "" then
		setFarmName(plot, nil)
		saveItems(player, plot)
		publish(plot)
		return true, "Your farm's name is cleared."
	end
	if utf8.len(raw) == nil or utf8.len(raw) > NAME_MAX then
		return false, ("Farm names are up to %d letters."):format(NAME_MAX)
	end
	local clean = filterName(raw, player.UserId)
	if not clean then
		return false, "Couldn't check that name right now. Try again."
	end
	if plot.owner ~= player then
		return false, nil
	end
	setFarmName(plot, clean)
	saveItems(player, plot)
	publish(plot)
	if clean ~= raw then
		return true, ("Some of that name was filtered. Your farm is %s."):format(clean)
	end
	return true, ("Your farm is now called %s."):format(clean)
end

-- Adds (on = true) or removes a player from the owner's farm crew.
local function onCrew(player, userId, on)
	local plot = plotOf[player]
	if not plot then
		return false, "Buy a plot first."
	end
	if typeof(userId) ~= "number" or userId == player.UserId then
		return false, "Pick another player."
	end
	if on then
		local mate = Players:GetPlayerByUserId(userId)
		if not mate then
			return false, "That player isn't on this server."
		end
		local count = 0
		for _ in plot.crew do
			count += 1
		end
		if not plot.crew[userId] and count >= CREW_MAX then
			return false, ("A crew holds %d players."):format(CREW_MAX)
		end
		plot.crew[userId] = true
		Data.toast(mate, ("%s added you to their farm crew. You can drive their truck, and hay you run through their line pays them."):format(player.DisplayName))
	else
		plot.crew[userId] = nil
	end
	plot.dirty = true
	publish(plot)
	return true, on and "Added to your crew." or "Removed from your crew."
end

local function fence(parent, a, b, theme)
	theme = theme or DEFAULT_THEME
	local length = (b - a).Magnitude
	local along = CFrame.lookAt((a + b) / 2, b)
	if theme.style == "wall" then
		part(parent, "Wall", Vector3.new(1.2, 2.2, length + 1.2), along + Vector3.new(0, 1.1, 0), theme.rail.color, theme.rail.material)
		part(parent, "Cap", Vector3.new(1.5, 0.35, length + 1.4), along + Vector3.new(0, 2.35, 0), theme.post.color, theme.post.material)
		return
	end
	for i = 0, math.ceil(length / 6) do
		local p = a + (b - a).Unit * math.min(i * 6, length)
		part(parent, "Post", Vector3.new(0.6, FENCE_HEIGHT, 0.6), CFrame.new(p + Vector3.new(0, FENCE_HEIGHT / 2, 0)), theme.post.color, theme.post.material)
	end
	for _, y in { 1.1, 2.4 } do
		part(parent, "Rail", Vector3.new(0.25, 0.4, length), along + Vector3.new(0, y, 0), theme.rail.color, theme.rail.material)
	end
end

-- A lamp post with a warm lantern, for the lane corners of a plot.
local function lamp(parent, at, theme)
	part(parent, "LampPost", Vector3.new(0.5, 7, 0.5), CFrame.new(at + Vector3.new(0, 3.5, 0)), theme.lamp.color, theme.lamp.material)
	local lantern = part(parent, "Lantern", Vector3.new(0.9, 1.1, 0.9), CFrame.new(at + Vector3.new(0, 7.4, 0)), Color3.fromRGB(235, 200, 140), Enum.Material.Neon)
	lantern.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 205, 150)
	light.Range = 18
	light.Brightness = 1.2
	light.Parent = lantern
	CollectionService:AddTag(lantern, "NightLamp") -- lit from dusk to dawn (WorldClock)
end

-- Builds the plot's fence, sign and lamps in a theme (an id from LandConfig.Themes; unknown ids get the default).
dress = function(plot, themeId)
	local theme = themes[themeId] or DEFAULT_THEME
	plot.theme = theme.id
	plot.fences:ClearAllChildren()
	for _, line in plot.fenceLines do
		fence(plot.fences, line[1], line[2], theme)
	end
	for _, corner in plot.lampAt do
		lamp(plot.fences, corner, theme)
	end
	plot.signPost.Color, plot.signPost.Material = theme.post.color, theme.post.material
	plot.signBoard.Color, plot.signBoard.Material = theme.board.color, theme.board.material
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
	local farZ = def.open == "S" and z0 or z1
	local laneEdge = def.open == "S" and z1 or z0
	local fenceLines = {
		{ Vector3.new(x0, 0, z0), Vector3.new(x0, 0, z1) },
		{ Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1) },
		{ Vector3.new(x0, 0, farZ), Vector3.new(x1, 0, farZ) },
	}
	local lampAt = { Vector3.new(x0, 0, laneEdge), Vector3.new(x1, 0, laneEdge) }

	-- The needle bin sits at the left end of the strip (seen from the lane), with its SELL NEEDLES pad toward the middle:
	-- the west end on plots south of the lane, the east end on the turned-around plots north of it.
	local binX = if def.open == "S" then x0 + T * 0.5 + 0.5 else x1 - T * 0.5 - 0.5
	local away = if def.open == "S" then -1 else 1
	local binFrame = CFrame.lookAt(Vector3.new(binX, 0, stripZ), Vector3.new(binX + away, 0, stripZ))

	-- Sign post in the middle of the strip.
	local post = part(model, "SignPost", Vector3.new(0.8, 6, 0.8), CFrame.new((x0 + x1) / 2, 3, stripZ), Rustic.WoodDark, Enum.Material.Wood)
	local board = part(model, "SignBoard", Vector3.new(8, 2.4, 0.4), CFrame.new((x0 + x1) / 2, 5.4, stripZ), Rustic.Wood, Enum.Material.WoodPlanks)
	board.CanCollide = false
	local label = sign(post, "", Vector3.new(0, 6, 0))
	-- The mailbox beside the sign: what the farm earned while its owner was away.
	local mailAt = Vector3.new((x0 + x1) / 2 + 6, 0, stripZ)
	local mailPost = part(model, "MailPost", Vector3.new(0.4, 3.6, 0.4), CFrame.new(mailAt + Vector3.new(0, 1.8, 0)), Rustic.WoodDark, Enum.Material.Wood)
	local mailBox = part(model, "Mailbox", Vector3.new(1.4, 1.2, 2.2), CFrame.new(mailAt + Vector3.new(0, 4.1, 0)), Rustic.Metal, Enum.Material.Metal)
	part(model, "MailFlag", Vector3.new(0.1, 0.8, 0.4), CFrame.new(mailAt + Vector3.new(0.75, 4.5, 0.5)), Rustic.PaintRed, Enum.Material.SmoothPlastic)
	mailPost.CanCollide = false
	local mailLabel = sign(mailBox, "MAILBOX\nNo mail.", Vector3.new(0, 2.6, 0))
	mailLabel.Parent.MaxDistance = 30
	-- Visitors like the farm here, once a week.
	local likePrompt = Instance.new("ProximityPrompt")
	likePrompt.Name = "LikePrompt"
	likePrompt.ActionText = "Like this farm"
	likePrompt.HoldDuration = 0.3
	likePrompt.MaxActivationDistance = 10
	likePrompt.RequiresLineOfSight = false
	likePrompt.Enabled = false
	likePrompt.Parent = post

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
		stripZ = stripZ,
		tiles = { X = def.tiles.X, Z = def.tiles.Y },
		model = model,
		items = items,
		info = info,
		label = label,
		likePrompt = likePrompt,
		likes = 0,
		owner = nil,
		locked = 0,
		lockParts = {},
		ownerId = nil,
		ownerName = nil,
		grid = Conveyors.newGrid(model, corner),
		bin = Machines.needleBin(model, binFrame),
		binFrame = binFrame,
		fences = fences,
		fenceLines = fenceLines,
		lampAt = lampAt,
		signPost = post,
		mailLabel = mailLabel,
		signBoard = board,
		theme = DEFAULT_THEME.id,
		list = {},
		taken = {},
		crew = {},
	}
	plots[index] = plot
	addBinPrompt(plot)
	-- The line stats board at the other end of the strip from the bin, facing the lane: the owner's bales, needles and
	-- dollars a minute.
	local statsX = if def.open == "S" then x1 - T * 0.5 - 0.5 else x0 + T * 0.5 + 0.5
	local statsAt = Vector3.new(statsX, 0, stripZ)
	LineStats.board(model, CFrame.lookAt(statsAt, Vector3.new(statsX, 0, plot.laneZ)), function()
		return plot.ownerId
	end)
	dress(plot, DEFAULT_THEME.id)
	likePrompt.Triggered:Connect(function(player)
		local ownerId = plot.ownerId
		if not ownerId then
			return
		end
		if os.clock() - (lastAction[player] or 0) < 1 then
			return
		end
		lastAction[player] = os.clock()
		local ok, message, count = Likes.like(player, ownerId)
		Data.toast(player, message)
		if plot.ownerId == ownerId then
			plot.likes = count
			publish(plot)
			if ok and plot.owner then
				Data.toast(plot.owner, ("%s liked your farm! ♥ %d this week."):format(player.DisplayName, count))
			end
		end
	end)
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

	-- The weekly board on the inside of the west wall: the most liked farms.
	local wall = model:FindFirstChild("LeftWall")
	local board = Instance.new("SurfaceGui")
	board.Name = "BestFarms"
	board.Face = Enum.NormalId.Right
	board.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	board.PixelsPerStud = 40
	board.Parent = wall
	local boardText = Instance.new("TextLabel")
	boardText.Size = UDim2.fromScale(0.86, 0.8)
	boardText.Position = UDim2.fromScale(0.07, 0.1)
	boardText.BackgroundColor3 = Rustic.Cloth
	boardText.TextColor3 = Color3.fromRGB(40, 34, 28)
	boardText.Font = Enum.Font.GothamBold
	boardText.TextScaled = true
	boardText.TextYAlignment = Enum.TextYAlignment.Top
	boardText.Text = "BEST FARMS THIS WEEK"
	boardText.Parent = board
	task.spawn(function()
		while model.Parent do
			local ok, top = pcall(Likes.top, 10)
			local lines = { "BEST FARMS THIS WEEK" }
			if ok and #top > 0 then
				for i, entry in top do
					local farm = farmNames[entry.userId]
					local who = farm and ("%s (%s)"):format(farm, entry.name) or entry.name
					table.insert(lines, ("%d. %s  ♥ %d"):format(i, who, entry.likes))
				end
			else
				table.insert(lines, "No likes yet. Visit a farm and like it at its sign.")
			end
			boardText.Text = table.concat(lines, "\n")
			task.wait(30)
		end
	end)
	sign(roof, "MEADOW LAND OFFICE\nBuy a plot, build a farm", Vector3.new(0, 4, 0), "sign")
end

-- A save was picked: give back its farm, if it owns land.
-- Puts the player at the front of their plot, on the strip, facing into the farm.
local function sendHome(player, plot)
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character and character:WaitForChild("HumanoidRootPart", 10)
	if not root or not player.Parent then
		return
	end
	local inward = plot.def.open == "S" and -1 or 1
	local at = Vector3.new(plot.corner.X + plot.size.X / 2 + 8, 4, plot.stripZ)
	character:PivotTo(CFrame.lookAt(at, at + Vector3.new(0, 0, inward)))
end

-- Takes a visitor to the front of someone else's farm.
local function onVisit(player, index)
	local plot = typeof(index) == "number" and plots[index]
	if not plot or not plot.ownerId then
		return false, "Nobody farms there yet."
	end
	if os.clock() - (lastAction[player] or 0) < 1 then
		return false, "One moment."
	end
	lastAction[player] = os.clock()
	task.spawn(sendHome, player, plot)
	return true, ("Visiting %s's farm. Like it at the sign by the lane."):format(plot.ownerName)
end

-- A save was picked (with the plot the player chose in the picker, if any): set up its farm, or buy the chosen plot
-- for a save with no land yet.
-- Puts the needles saved in the bin back in this plot's bin. Past BinRestoreCap physical needles the rest go in the
-- pocket, so a big hoard doesn't bury the bin.
local BinRestoreCap = 300
local function restoreNeedles(player, plot, land)
	local saved = Data.countMap(land.needles)
	local inBin, toPocket, room = {}, {}, BinRestoreCap
	for id, count in saved do
		local here = math.min(count, room)
		room -= here
		if here > 0 then
			inBin[id] = here
		end
		if count > here then
			toPocket[id] = count - here
		end
	end
	plot.bin.fill(player.UserId, inBin)
	local s = Data.get(player)
	if s and next(toPocket) then
		for id, count in toPocket do
			s.pocket[id] = (s.pocket[id] or 0) + count
		end
		Data.sync(player)
	end
	land.needles = inBin
end

-- The mailbox: while the owner was away, the silo kept feeding the line, but only from bales already in it (no
-- income out of nothing). Works on the save before the plot is built, so the silos come back emptier and the found
-- needles land in the bin. Needs a hay buyer on the plot; the best sorter there sets speed and needles found.
local MAIL_MAX_AWAY = 8 * 3600
local function mailbox(player, land)
	local away = math.min(os.time() - (land.savedAt or os.time()), MAIL_MAX_AWAY)
	if away < 60 or typeof(land.items) ~= "table" then
		return nil
	end
	local silos, stored, hasBuyer, best = {}, 0, false, nil
	for _, s in land.items do
		local def = typeof(s) == "table" and pieces[s.id]
		if def and def.kind == "silo" and typeof(s.stored) == "number" and s.stored > 0 then
			table.insert(silos, s)
			stored += s.stored
		elseif def and def.kind == "buyer" then
			hasBuyer = true
		elseif def and def.kind == "separator" then
			for _, tier in Sorters do
				if tier.id == def.id and (not best or tier.recovery > best.recovery) then
					best = tier
				end
			end
		end
	end
	if stored == 0 then
		return nil
	end
	if not hasBuyer then
		return ("Your silo holds %d bales, but there is no hay buyer on your line, so nothing sold while you were away."):format(stored)
	end
	local hayPerBale = GameConfig.PiecesPerBale * GameConfig.HayPerPiece
	local perBale = LandConfig.SiloFeedSeconds
	if best then
		perBale = math.max(perBale, Machines.sortSeconds(best.id, hayPerBale))
	end
	local bales = math.min(stored, math.floor(away / perBale))
	if bales <= 0 then
		return nil
	end
	-- Take the bales out of the silos, first silo first.
	local left = bales
	for _, s in silos do
		local take = math.min(s.stored, left)
		s.stored -= take
		left -= take
	end
	local hay = bales * hayPerBale
	local hidden = math.floor(hay * GameConfig.NeedleChancePerHay + 0.5)
	local cash, found = 0, 0
	if best then
		found = math.floor(hidden * best.recovery + 0.5)
		cash = math.floor(hay * Economy.HAY_PRICE)
		local needles = land.needles or {}
		local id = Needle.default.id
		needles[id] = (needles[id] or 0) + found
		land.needles = needles
	else
		cash = Economy.rawLoadValue(hay, hidden)
	end
	Bank.earn(player, cash, "While you were away")
	local hours = away / 3600
	local when = hours >= 1 and ("%.1f hours"):format(hours) or ("%d minutes"):format(math.floor(away / 60))
	local letter = ("While you were away (%s) your silo fed %d bales: +$%d"):format(when, bales, cash)
	if found > 0 then
		letter ..= (", and %d needles are waiting in your bin"):format(found)
	end
	return letter .. "."
end

local function onLoaded(player)
	local s = Data.get(player)
	if not s then
		return
	end
	local picked = s.pickedPlot and plots[s.pickedPlot]
	s.pickedPlot = nil
	if not (s.land and s.land.owned) then
		if picked then
			local ok, message = onBuy(player, picked.index)
			if ok then
				task.spawn(sendHome, player, picked)
			else
				Data.toast(player, message)
			end
		end
		return
	end
	local plot = (picked and not picked.ownerId) and picked or pickPlot(s.land.plot)
	if not plot then
		Data.toast(player, "Every plot on this server is taken, so your farm can't be set up here. It is still saved.")
		return
	end
	local letter = mailbox(player, s.land)
	claim(plot, player, s.land)
	restoreNeedles(player, plot, s.land)
	plot.mailLabel.Text = letter and ("MAILBOX\n" .. letter) or "MAILBOX\nNo mail."
	-- A second farm goes on another free plot, if one is left.
	if s.land2 and s.land2.owned then
		local second = pickPlot(s.land2.plot)
		if second then
			local letter2 = mailbox(player, s.land2)
			claim(second, player, s.land2, "land2")
			restoreNeedles(player, second, s.land2)
			second.mailLabel.Text = letter2 and ("MAILBOX\n" .. letter2) or "MAILBOX\nNo mail."
			if letter2 then
				letter = letter and (letter .. " " .. letter2) or letter2
			end
		else
			task.delay(6, function()
				if player.Parent then
					Data.toast(player, "No second plot is free on this server, so your second farm waits in your save.")
				end
			end)
		end
	end
	parkVehicles(player, plot)
	task.spawn(sendHome, player, plot)
	local message = ("Your farm is on %s."):format(plot.def.name)
	if #plot.leftOut > 0 then
		message ..= (" %d saved pieces don't fit here; they're still kept in your save."):format(#plot.leftOut)
	end
	Data.toast(player, message)
	if letter then
		task.delay(4, function()
			if player.Parent then
				Data.toast(player, letter)
			end
		end)
	end
end

-- For SelfTests/Land.luau only: the internals its checks drive. Nothing in the game reads this.
Land.test = {
	plots = plots,
	pieces = pieces,
	farms = farms,
	plotOf = plotOf,
	key = key,
	levelsOf = levelsOf,
	turnFor = turnFor,
	fits = fits,
	spawnItem = spawnItem,
	destroyItem = destroyItem,
	writeLand = writeLand,
	claim = claim,
	release = release,
	pickPlot = pickPlot,
	restoreNeedles = restoreNeedles,
	mailbox = mailbox,
	onPlace = onPlace,
	onUndo = onUndo,
}

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
	for _, name in { "Buy", "Place", "Remove", "Crew", "Visit", "Expand", "Pick", "Move", "Copy", "Paste", "Undo", "Theme", "Switch", "FarmName" } do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = state
		remotes[name] = remote
	end

	buildOffice(folder)
	Blueprints.init() -- named presets for the COPY / PASTE tools
	for i, def in LandConfig.Plots do
		buildPlot(folder, i, def)
	end
	state.Parent = ReplicatedStorage

	local function guard(fn)
		return function(player, ...)
			local out = table.pack(pcall(fn, player, ...))
			if not out[1] then
				warn("[Needlewood] land error: " .. tostring(out[2]))
				return false, "Something went wrong."
			end
			return table.unpack(out, 2, out.n)
		end
	end
	remotes.Buy.OnServerInvoke = guard(onBuy)
	remotes.Place.OnServerInvoke = guard(onPlace)
	remotes.Remove.OnServerInvoke = guard(onRemove)
	remotes.Crew.OnServerInvoke = guard(onCrew)
	remotes.Visit.OnServerInvoke = guard(onVisit)
	remotes.Expand.OnServerInvoke = guard(onExpand)
	remotes.Pick.OnServerInvoke = guard(onPick)
	remotes.Move.OnServerInvoke = guard(onMove)
	remotes.Copy.OnServerInvoke = guard(onCopy)
	remotes.Paste.OnServerInvoke = guard(onPaste)
	remotes.Undo.OnServerInvoke = guard(onUndo)
	remotes.Theme.OnServerInvoke = guard(onTheme)
	remotes.FarmName.OnServerInvoke = guard(onName)
	remotes.Switch.OnServerInvoke = guard(onSwitch)
	-- Crew members may drive the owner's truck.
	Vehicles.canDrive = function(driver, owner)
		for _, plot in farms[owner] or {} do
			if plot.crew[driver.UserId] then
				return true
			end
		end
		return false
	end

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
			for player, mine in farms do
				for _, plot in mine do
					if plot.dirty then
						saveItems(player, plot)
					end
				end
			end
		end
	end)
	-- Save the plot before Data saves the player on leaving, then free it.
	Data.beforeSave = function(player)
		for _, plot in farms[player] or {} do
			saveItems(player, plot)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		history[player] = nil
		local mine = {}
		for _, plot in farms[player] or {} do
			table.insert(mine, plot)
		end
		for _, plot in mine do
			saveItems(player, plot)
			release(plot)
		end
		farms[player] = nil
		plotOf[player] = nil
	end)
end

return Land
