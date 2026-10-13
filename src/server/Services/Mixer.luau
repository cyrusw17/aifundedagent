--!nonstrict
-- The alloy mixer: two needle types in, a block of alloy building material out (recipes in Config/Alloys.luau).
-- It stands on one plot cell. Pull the lever to pick a recipe, then click the hopper: it takes the recipe's needles
-- from your pocket, churns for a few seconds and drops an alloy block on its tray. Click the block to carry its
-- material, which blueprint building spends (Data state.materials, saved with the slot).
--
--   Mixer.build(parent, frame)              -- frame: Conveyors.frame of its cell, facing the front
--   Mixer.material(player, id)              -- units of a material the player carries
--   Mixer.spend(player, id, units)          -- true and takes it, or false when they have too little
--   Mixer.give(player, id, units)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factory = require(Shared.Config.Factory)
local Alloys = require(Shared.Config.Alloys)
local LineMath = require(Shared.LineMath)
local Data = require(script.Parent.Data)
local Groups = require(script.Parent.Groups)
local Feedback = require(script.Parent.Feedback)
local Machines = require(script.Parent.Machines)
local Needle = require(script.Parent.Needle)
local Skins = require(script.Parent.Skins)

local Mixer = {}

-- Unexpired trade locks on the plain keys of a needle type (state.tradeLocks, kept by Trade.luau).
local function lockedPlain(player, id)
	local state = Data.get(player)
	local locks = state and state.tradeLocks
	if typeof(locks) ~= "table" then
		return 0
	end
	local now, total = os.time(), 0
	for _, key in LineMath.plainKeys(id) do
		for _, lock in locks[key] or {} do
			if lock.untilTime > now then
				total += lock.count
			end
		end
	end
	return total
end

local T = Factory.TileSize
local C = Machines.Colors
local part = Machines.part
local MIX_SECONDS = 3
local BLOCK = Vector3.new(2, 1.2, 1.2)

local byId = {}
for _, r in Alloys do
	byId[r.id] = r
end

local function materials(player)
	local state = Data.get(player)
	if not state then
		return nil
	end
	state.materials = state.materials or {}
	return state.materials
end

function Mixer.material(player, id)
	local m = materials(player)
	return m and m[id] or 0
end

function Mixer.give(player, id, units)
	local m = materials(player)
	if m then
		m[id] = (m[id] or 0) + units
		player:SetAttribute("Material_" .. id, m[id])
	end
end

function Mixer.spend(player, id, units)
	local m = materials(player)
	if not m or (m[id] or 0) < units then
		return false
	end
	m[id] -= units
	player:SetAttribute("Material_" .. id, m[id])
	return true
end

local function spawnBlock(cframe, recipe, ownerId)
	local block = part(Workspace, "AlloyBlock", BLOCK, cframe, Color3.fromRGB(table.unpack(recipe.color)), Enum.Material.Metal)
	block.Anchored = false
	block.Reflectance = 0.2
	block.CollisionGroup = Groups.Loose
	block:SetAttribute("Material", recipe.id)
	block:SetAttribute("Units", recipe.units)
	block:SetAttribute("OwnerId", ownerId)
	CollectionService:AddTag(block, "AlloyBlock")
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 12
	click.MouseClick:Connect(function(player)
		if not block.Parent or not Data.get(player) then
			return -- no save loaded yet: leave the block, or the alloy would be lost
		end
		if player.UserId ~= ownerId then
			Data.toast(player, "That alloy belongs to whoever mixed it.")
			return
		end
		Mixer.give(player, recipe.id, recipe.units)
		block:Destroy()
		Data.toast(player, ("Picked up %d %s. You carry %d for building."):format(recipe.units, recipe.name:lower(), Mixer.material(player, recipe.id)))
	end)
	click.Parent = block
	pcall(function()
		block:SetNetworkOwner(nil)
	end)
	return block
end

function Mixer.build(parent, frame)
	local model = Instance.new("Model")
	model.Name = "AlloyMixer"
	model:SetAttribute("Running", false)
	model.Parent = parent

	local base = part(model, "Base", Vector3.new(T - 1, 2, T - 1), frame * CFrame.new(0, 1, 0), C.wood, Enum.Material.WoodPlanks)
	local drum = part(model, "Drum", Vector3.new(T - 2, 3.4, 3.4), frame * CFrame.new(0, 3.9, 0), C.darkMetal, Enum.Material.Metal)
	drum.Shape = Enum.PartType.Cylinder
	drum:SetAttribute("Motion", "Spin")
	CollectionService:AddTag(drum, "PropMotion")
	local hopper = part(model, "Hopper", Vector3.new(2.4, 1.6, 2.4), frame * CFrame.new(0, 6.4, 0), C.metal, Enum.Material.Metal)
	local lever = part(model, "Lever", Vector3.new(0.3, 2.4, 0.3), frame * CFrame.new(T / 2 - 0.6, 3.2, -T / 2 + 0.8) * CFrame.Angles(0, 0, math.rad(20)), C.wood, Enum.Material.WoodPlanks)
	part(model, "Tray", Vector3.new(3, 0.3, 2), frame * CFrame.new(0, 2.15, -T / 2 - 0.4), C.planks, Enum.Material.WoodPlanks)
	local label = Machines.sign(hopper, "ALLOY MIXER", Vector3.new(0, 3, 0))
	Skins.dress("alloy_mixer", base, model, frame)

	local pick = 1
	local busy = false
	local function show()
		local r = Alloys[pick]
		label.Text = ("ALLOY MIXER: %s\n%d %s + %d %s needles\npull lever to change, click hopper to mix"):format(
			r.name:upper(),
			r.each,
			Needle.info(r.a).name:lower(),
			r.each,
			Needle.info(r.b).name:lower()
		)
	end
	show()

	local leverClick = Instance.new("ClickDetector")
	leverClick.MaxActivationDistance = 12
	leverClick.MouseClick:Connect(function()
		if busy then
			return
		end
		pick = pick % #Alloys + 1
		show()
	end)
	leverClick.Parent = lever

	local hopperClick = Instance.new("ClickDetector")
	hopperClick.MaxActivationDistance = 14
	hopperClick.MouseClick:Connect(function(player)
		if busy then
			return
		end
		local r = Alloys[pick]
		if Needle.plainCount(player, r.a) < r.each or Needle.plainCount(player, r.b) < r.each then
			Data.toast(player, ("%s needs %d plain %s and %d plain %s needles in your pocket."):format(
				r.name,
				r.each,
				Needle.info(r.a).name:lower(),
				r.each,
				Needle.info(r.b).name:lower()
			))
			return
		end
		-- Needles received in a trade stay locked for a day (Trade.luau), and an alloy trades freely, so mix only free ones.
		if Needle.plainCount(player, r.a) - lockedPlain(player, r.a) < r.each or Needle.plainCount(player, r.b) - lockedPlain(player, r.b) < r.each then
			Data.toast(player, "Needles you got in a trade can't go in the mixer until their trade lock runs out.")
			return
		end
		if not (Needle.takeFromPocket(player, r.a, r.each) and Needle.takeFromPocket(player, r.b, r.each)) then
			return
		end
		busy = true
		model:SetAttribute("Running", true)
		Feedback.play("Scoop", hopper)
		task.delay(MIX_SECONDS, function()
			model:SetAttribute("Running", false)
			busy = false
			if model.Parent then
				spawnBlock(frame * CFrame.new(0, 2.9, -T / 2 - 0.4), r, player.UserId)
				Feedback.play("BaleSetDown", base)
			elseif player.Parent and Data.get(player) then
				-- The mixer was taken away mid-mix: the needles go back in the pocket.
				Needle.giveKey(player, r.a, r.each)
				Needle.giveKey(player, r.b, r.each)
			end
		end)
	end)
	hopperClick.Parent = hopper
	return model
end

-- Blocks nobody can pick up any more go when their owner leaves.
Players.PlayerRemoving:Connect(function(player)
	for _, block in CollectionService:GetTagged("AlloyBlock") do
		if block:GetAttribute("OwnerId") == player.UserId then
			block:Destroy()
		end
	end
end)

return Mixer
