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

		local units = math.max(1, math.floor(hay / Blocks.Materials.thatch.per))
		local stack = pressed % 4
		local at = pallet * CFrame.new((stack % 2 - 0.5) * 1.1, 0.5 + BLOCK.Y / 2 + 0.2, (math.floor(stack / 2) - 0.5) * 2.2)
		spawnBlock(at, ownerId, units)
		Feedback.play("BaleSetDown", beam)
		pressed += 1
		label.Text = ("HAY PRESS\n%d blocks pressed"):format(pressed)
	end

	task.spawn(function()
		while model.Parent do
			task.wait(0.25)
			local bale, loose, refused = nil, {}, nil
			for _, p in Workspace:GetPartBoundsInBox(zone, zoneSize) do
				local b = Bales.fromPart(p)
				if b and p == b.body and not b.gone and not b.carriedBy and not b.breaking then
					if b.sorted then
						bale = bale or b
					else
						refused = b.ownerId
					end
				elseif Hay.isPiece(p) and p:GetAttribute("Sorted") then
					table.insert(loose, p)
				end
			end
			if bale then
				local ownerId = bale.ownerId
				local hay = bale.sortedHay or Config.PiecesPerBale * Config.HayPerPiece
				Bales.consume(bale)
				press(hay, ownerId)
			elseif #loose > 0 then
				local ownerId = loose[1]:GetAttribute("OwnerId")
				for _, p in loose do
					Hay.remove(p)
				end
				press(#loose * Config.HayPerPiece, ownerId)
			elseif refused and os.clock() - refusedAt > 8 then
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

return Press
