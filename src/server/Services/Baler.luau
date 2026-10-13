--!nonstrict
-- The hay baler: a line machine that packs loose strands back into a standard bale, so raking and scooping can feed
-- a line. It sits over two belt cells like the press: strands that ride in at the upstream end are pulled into its
-- chamber, and every Config.PiecesPerBale strands of one owner and one hay type come out the far end as one bale.
-- Sorted strands make a sorted bale (worth sorted price, and no sorter takes it again); unsorted ones a plain bale.
-- Whole bales ride straight through. Strands still in the chamber when it is removed are lost, like a real hopper.
--
--   Baler.build(parent, frame)   -- frame: Conveyors.frame of the upstream cell, facing the flow
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factory = require(Shared.Config.Factory)
local Config = require(Shared.Config.Game)
local Bales = require(script.Parent.Bales)
local Hay = require(script.Parent.Hay)
local Feedback = require(script.Parent.Feedback)
local Machines = require(script.Parent.Machines)
local Needle = require(script.Parent.Needle)
local Skins = require(script.Parent.Skins)

local Baler = {}

local T = Factory.TileSize
local TOP = Factory.BeltTop
local C = Machines.Colors
local part = Machines.part
local BALE_SECONDS = 1.5

function Baler.build(parent, frame)
	local center = frame * CFrame.new(0, 0, -T / 2) -- middle of the two cells
	local model = Instance.new("Model")
	model.Name = "HayBaler"
	model:SetAttribute("Running", false)
	model.Parent = parent

	local height = 6
	for _, sx in { -1, 1 } do
		part(model, "Side", Vector3.new(0.6, height, T * 2), center * CFrame.new(sx * (T / 2 - 0.3), TOP + height / 2, 0), C.darkMetal, Enum.Material.Metal)
	end
	local roof = part(model, "Roof", Vector3.new(T + 0.4, 0.8, T * 2 + 0.4), center * CFrame.new(0, TOP + height + 0.4, 0), C.metal, Enum.Material.Metal)
	local ram = part(model, "Ram", Vector3.new(T - 1.4, 3, 0.6), center * CFrame.new(0, TOP + 1.6, T - 0.8), C.metal, Enum.Material.Metal)
	ram.CanCollide = false
	local flywheel = part(model, "Flywheel", Vector3.new(0.5, 3, 3), center * CFrame.new(T / 2 + 0.4, TOP + 2.5, 0), C.darkMetal, Enum.Material.Metal)
	flywheel.Shape = Enum.PartType.Cylinder
	flywheel:SetAttribute("Motion", "Spin")
	game:GetService("CollectionService"):AddTag(flywheel, "PropMotion")
	local label = Machines.sign(roof, "HAY BALER", Vector3.new(0, 3, 0))
	Skins.dress("hay_baler", roof, model, center)

	-- Strands are taken from the upstream cell; whole bales are left to ride through.
	local zone = center * CFrame.new(0, TOP + 2, T / 2)
	local zoneSize = Vector3.new(T - 0.8, 4, T - 0.6)
	local out = center * CFrame.new(0, TOP + 1.45, -T + 2) * CFrame.Angles(0, math.pi / 2, 0)
	local chamber = {} -- "ownerId|hayType|sorted" -> strands waiting
	local baled = 0

	local function refresh()
		local most = 0
		for _, n in chamber do
			most = math.max(most, n)
		end
		model:SetAttribute("Baled", baled)
		label.Text = ("HAY BALER\n%d / %d strands, %d bales made"):format(most, Config.PiecesPerBale, baled)
	end
	refresh()

	local function makeBale(ownerId, hayType, sorted)
		model:SetAttribute("Running", true)
		local rest = ram.CFrame
		local started = os.clock()
		while os.clock() - started < BALE_SECONDS do
			local t = (os.clock() - started) / BALE_SECONDS
			ram.CFrame = rest * CFrame.new(0, 0, -math.sin(t * math.pi) * (T - 1))
			task.wait(0.03)
		end
		ram.CFrame = rest
		model:SetAttribute("Running", false)
		local hay = Config.PiecesPerBale * Config.HayPerPiece
		if sorted then
			Machines.spawnSortedBale(out, ownerId, hay, hayType)
		else
			local b = Bales.spawn(out.Position, false, false, hayType)
			b.ownerId = ownerId
			b.body.CFrame = out
			b.body.Anchored = false
			pcall(function()
				b.body:SetNetworkOwner(nil)
			end)
		end
		Feedback.play("BaleSetDown", roof)
		baled += 1
		refresh()
	end

	local queue = {}
	task.spawn(function()
		while model.Parent do
			local job = table.remove(queue, 1)
			if job then
				makeBale(job.ownerId, job.hayType, job.sorted)
			else
				task.wait(0.25)
			end
		end
	end)

	task.spawn(function()
		while model.Parent do
			task.wait(0.25)
			local took = false
			for _, p in Workspace:GetPartBoundsInBox(zone, zoneSize) do
				if Hay.isPiece(p) and p.Parent and not Needle.isNeedle(p) then -- visible needles ride on
					local ownerId = p:GetAttribute("OwnerId") or 0
					local hayType = p:GetAttribute("HayType") or "meadow"
					local sorted = p:GetAttribute("Sorted") == true
					local key = ("%s|%s|%s"):format(tostring(ownerId), hayType, sorted and "1" or "0")
					local strands = Hay.strandsIn(p) -- a raked pile counts every strand in it
					Hay.remove(p)
					took = true
					chamber[key] = (chamber[key] or 0) + strands
					while chamber[key] >= Config.PiecesPerBale do
						chamber[key] -= Config.PiecesPerBale
						table.insert(queue, { ownerId = ownerId ~= 0 and ownerId or nil, hayType = hayType, sorted = sorted })
					end
				end
			end
			if took then
				refresh()
			end
		end
	end)
	return model
end

return Baler
