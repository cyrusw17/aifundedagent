--!nonstrict
-- The hay press: a line machine that squeezes sorted hay into thatch blocks, the building material for blueprints
-- (Blocks.luau "thatch"). It sits over two belt cells like a sorter: sorted bales (and loose sorted hay) go in at the
-- upstream end, and every press drops one thatch block onto the pallet on its right side. Unsorted hay rides on
-- through untouched (its needles would end up in the walls), so the line should run through a sorter first.
--
-- Thatch blocks are physical parts (tag "ThatchBlock", attributes OwnerId and Units). Clicking one adds its units to
-- the player's thatch (the "Thatch" player attribute), which blueprint building spends.
--
--   Press.build(parent, frame)        -- frame: Conveyors.frame of the upstream cell, facing the flow
--   Press.thatch(player)              -- how much thatch the player carries
--   Press.spend(player, units)        -- true and takes it, or false when they have too little
--   Press.give(player, units)         -- for loading saves
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factory = require(Shared.Config.Factory)
local Config = require(Shared.Config.Game)
local Blocks = require(Shared.Config.Blocks)
local Data = require(script.Parent.Data)
local Bales = require(script.Parent.Bales)
local Hay = require(script.Parent.Hay)
local Groups = require(script.Parent.Groups)
local Feedback = require(script.Parent.Feedback)
local Machines = require(script.Parent.Machines)
local Skins = require(script.Parent.Skins)

local Press = {}

local T = Factory.TileSize
local TOP = Factory.BeltTop
local C = Machines.Colors
local part = Machines.part
local THATCH = Color3.fromRGB(196, 170, 110)
local BLOCK = Vector3.new(2, 2, 2)
local PRESS_SECONDS = 2.5
local PICKUP_REACH = 12

-- Thatch carried lives in the save slot (Data state.thatch), so it saves and loads with the slot.
local function publish(player)
	player:SetAttribute("Thatch", Press.thatch(player))
end

function Press.thatch(player)
	local state = Data.get(player)
	return state and state.thatch or 0
end

function Press.give(player, units)
	local state = Data.get(player)
	if not state then
		return
	end
	state.thatch = (state.thatch or 0) + units
	publish(player)
end

function Press.spend(player, units)
	local state = Data.get(player)
	if not state or (state.thatch or 0) < units then
		return false
	end
	state.thatch -= units
	publish(player)
	return true
end

local function spawnBlock(cframe, ownerId, units)
	local block = part(Workspace, "ThatchBlock", BLOCK, cframe, THATCH, Enum.Material.Fabric)
	block.Anchored = false
	block.CollisionGroup = Groups.Loose
	block:SetAttribute("OwnerId", ownerId)
	block:SetAttribute("Units", units)
	CollectionService:AddTag(block, "ThatchBlock")
	for _, y in { -0.5, 0.5 } do
		local band = part(block, "Twine", Vector3.new(BLOCK.X + 0.06, 0.15, BLOCK.Z + 0.06), cframe * CFrame.new(0, y, 0), C.twine, Enum.Material.Fabric)
		band.Anchored = false
		band.CanCollide = false
		band.CanQuery = false
		band.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = block
		weld.Part1 = band
		weld.Parent = band
	end
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = PICKUP_REACH
	click.MouseClick:Connect(function(player)
		if not block.Parent then
			return
		end
		if not Data.get(player) then
			return
		end
		if ownerId and player.UserId ~= ownerId then
			Data.toast(player, "That thatch belongs to whoever's hay it was pressed from.")
			return
		end
		Press.give(player, units)
		block:Destroy()
		Data.toast(player, ("Picked up %d thatch. You carry %d for building."):format(units, Press.thatch(player)))
	end)
	click.Parent = block
	pcall(function()
		block:SetNetworkOwner(nil)
	end)
	return block
end

function Press.build(parent, frame)
	local center = frame * CFrame.new(0, 0, -T / 2) -- middle of the two cells
	local model = Instance.new("Model")
	model.Name = "HayPress"
	model:SetAttribute("Running", false)
	model.Parent = parent

	local height = 7
	for _, sx in { -1, 1 } do
		part(model, "Post", Vector3.new(0.8, height + 1, 0.8), center * CFrame.new(sx * (T / 2 - 0.4), TOP + (height + 1) / 2, 0), C.wood, Enum.Material.WoodPlanks)
	end
	local beam = part(model, "Beam", Vector3.new(T, 1, 1.4), center * CFrame.new(0, TOP + height + 1, 0), C.darkMetal, Enum.Material.Metal)
	local plate = part(model, "Plate", Vector3.new(T - 1.8, 0.5, 4), center * CFrame.new(0, TOP + height - 0.5, 0), C.metal, Enum.Material.Metal)
	plate.CanCollide = false
	local screw = part(model, "Screw", Vector3.new(0.5, height - 1, 0.5), center * CFrame.new(0, TOP + height / 2 + 0.5, 0), C.metal, Enum.Material.Metal)
	screw.CanCollide = false
	-- The pallet on the right side where blocks land.
	local pallet = center * CFrame.new(T / 2 + 2, 0, 0)
	part(model, "Pallet", Vector3.new(3.2, 0.5, 5), pallet * CFrame.new(0, 0.25, 0), C.planks, Enum.Material.WoodPlanks)
	local label = Machines.sign(beam, "HAY PRESS\nsorted hay to thatch", Vector3.new(0, 3, 0))
	Skins.dress("hay_press", beam, model, center)

	local zone = center * CFrame.new(0, TOP + 2.5, 0)
	local zoneSize = Vector3.new(T - 0.8, 5, T * 2 - 1)
	local pressed, refusedAt = 0, 0

	local function press(hay, ownerId)
		model:SetAttribute("Running", true)
		local top, down = plate.CFrame, plate.CFrame * CFrame.new(0, -(height - 3.6), 0)
		local started = os.clock()
		while os.clock() - started < PRESS_SECONDS do
			local t = (os.clock() - started) / PRESS_SECONDS
			plate.CFrame = top:Lerp(down, math.sin(t * math.pi))
			task.wait(0.03)
		end
		plate.CFrame = top
		model:SetAttribute("Running", false)

		local units = math.floor(hay / Blocks.Materials.thatch.per)
		if units < 1 then
			return
		end
		-- Four spots on the pallet, stacked three high, so a new block never lands inside one nobody picked up.
		local stack, layer = pressed % 4, (pressed // 4) % 3
		local at = pallet * CFrame.new((stack % 2 - 0.5) * 1.1, 0.5 + BLOCK.Y / 2 + 0.2 + layer * (BLOCK.Y + 0.1), (math.floor(stack / 2) - 0.5) * 2.2)
		spawnBlock(at, ownerId, units)
		Feedback.play("BaleSetDown", beam)
		pressed += 1
		label.Text = ("HAY PRESS\n%d blocks pressed"):format(pressed)
	end

	-- Everything sorted that reaches the press comes off the belt at once and waits its turn here, so nothing rides
	-- through while the plate is down.
	local queue = {}
	-- Loose sorted strands wait here per owner and are pressed in whole thatch units, once a bale's worth is in or
	-- nothing more has come for a moment, so strands trickling in press to the same thatch as a bale (they used to
	-- round up to a block each).
	local pending = {} -- ownerId (0 = nobody) -> hay
	local lastIn = {} -- ownerId -> os.clock() of the last strand in
	task.spawn(function()
		while model.Parent do
			local job = table.remove(queue, 1)
			if job then
				press(job.hay, job.ownerId)
			else
				task.wait(0.25)
			end
		end
	end)

	task.spawn(function()
		while model.Parent do
			task.wait(0.25)
			local refused = nil
			local loose = {} -- ownerId -> strands
			for _, p in Workspace:GetPartBoundsInBox(zone, zoneSize) do
				local b = Bales.fromPart(p)
				if b and p == b.body and not b.gone and not b.carriedBy and not b.breaking then
					if b.sorted then
						local hay = b.sortedHay or Config.PiecesPerBale * Config.HayPerPiece
						table.insert(queue, { hay = hay, ownerId = b.ownerId })
						Bales.consume(b)
					else
						refused = b.ownerId
					end
				elseif Hay.isPiece(p) and p:GetAttribute("Sorted") and p.Parent then
					local ownerId = p:GetAttribute("OwnerId") or 0
					loose[ownerId] = (loose[ownerId] or 0) + Hay.strandsIn(p)
					Hay.remove(p)
				end
			end
			for ownerId, strands in loose do
				pending[ownerId] = (pending[ownerId] or 0) + strands * Config.HayPerPiece
				lastIn[ownerId] = os.clock()
			end
			local per = Blocks.Materials.thatch.per
			local baleHay = Config.PiecesPerBale * Config.HayPerPiece
			for ownerId, hay in pending do
				if hay >= baleHay or os.clock() - (lastIn[ownerId] or 0) > 2 then
					local whole = math.floor(math.min(hay, baleHay) / per) * per
					if whole > 0 then
						pending[ownerId] = hay - whole
						table.insert(queue, { hay = whole, ownerId = ownerId ~= 0 and ownerId or nil })
					end
				end
			end
			if refused and os.clock() - refusedAt > 8 then
				refusedAt = os.clock()
				local owner = Players:GetPlayerByUserId(refused or 0)
				if owner then
					Data.toast(owner, "The hay press only presses sorted hay; this bale rides on. Run hay through a needle sorter first.")
				end
			end
		end
	end)
	return model
end

-- Blocks nobody can pick up any more go when their owner leaves.
Players.PlayerRemoving:Connect(function(player)
	for _, block in CollectionService:GetTagged("ThatchBlock") do
		if block:GetAttribute("OwnerId") == player.UserId then
			block:Destroy()
		end
	end
end)

return Press
