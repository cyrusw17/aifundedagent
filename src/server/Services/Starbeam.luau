--!nonstrict
-- The Starbeam Collector, the reward for the alien collector gauntlet (Quests). A beacon tower that stands over one
-- belt tile on a plot and, every Prices.Starbeam.minutes, pulls a bale of Star hay down out of the sky onto that belt.
-- Star hay hides Cosmic needles (Needle.forHay), so it feeds the richest line in the game. The bale belongs to the
-- plot owner, rides the belt like any other and is sorted by whatever sorter is downstream.
--
--   Starbeam.build(parent, frame, getOwnerId)   -- frame: Conveyors.frame of its belt cell; lay the belt tile first
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factory = require(Shared.Config.Factory)
local Prices = require(Shared.Config.Prices)
local Bales = require(script.Parent.Bales)
local Machines = require(script.Parent.Machines)
local Skins = require(script.Parent.Skins)

local Starbeam = {}

local T = Factory.TileSize
local TOP = Factory.BeltTop
local C = Machines.Colors
local part = Machines.part
local STAR = Color3.fromRGB(150, 140, 255)
local HEIGHT = 22

function Starbeam.build(parent, frame, getOwnerId)
	local model = Instance.new("Model")
	model.Name = "StarbeamCollector"
	model:SetAttribute("Running", false)
	model.Parent = parent

	-- Four iron legs over the belt, a dish on top pointing at the sky, and a crystal under the dish.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "Leg", Vector3.new(0.6, HEIGHT, 0.6), frame * CFrame.new(sx * (T / 2 + 0.2), HEIGHT / 2, sz * (T / 2 + 0.2)), C.darkMetal, Enum.Material.Metal)
		end
	end
	local deck = part(model, "Deck", Vector3.new(T + 1.4, 0.6, T + 1.4), frame * CFrame.new(0, HEIGHT, 0), C.metal, Enum.Material.Metal)
	local dish = part(model, "Dish", Vector3.new(1.2, T + 2, T + 2), frame * CFrame.new(0, HEIGHT + 1.2, 0) * CFrame.Angles(0, 0, math.pi / 2), C.metal, Enum.Material.Metal)
	dish.Shape = Enum.PartType.Cylinder
	local crystal = part(model, "Crystal", Vector3.new(1.4, 2.4, 1.4), frame * CFrame.new(0, HEIGHT - 1.6, 0) * CFrame.Angles(0, math.pi / 4, 0), STAR, Enum.Material.Neon)
	crystal.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = STAR
	light.Range = 14
	light.Brightness = 1
	light.Parent = crystal
	local beam = part(model, "Beam", Vector3.new(HEIGHT - TOP - 2, T - 1.6, T - 1.6), frame * CFrame.new(0, (HEIGHT + TOP) / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), STAR, Enum.Material.Neon)
	beam.Shape = Enum.PartType.Cylinder
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Transparency = 1
	local label = Machines.sign(deck, "STARBEAM COLLECTOR", Vector3.new(0, 5, 0))
	Skins.dress("starbeam_collector", deck, model, frame)

	local period = Prices.Starbeam.minutes * 60
	local dropAt = frame * CFrame.new(0, TOP + 6, 0)
	local clearZone = frame * CFrame.new(0, TOP + 2, 0)

	local function beamDown()
		local ownerId = getOwnerId()
		if not ownerId then
			return false, "waiting for its owner"
		end
		-- Wait for the belt under the tower to be clear, so bales don't stack up on a jammed line.
		for _, p in Workspace:GetPartBoundsInBox(clearZone, Vector3.new(T - 1, 3, T - 1)) do
			local b = Bales.fromPart(p)
			if b and not b.gone then
				return false, "waiting for a clear belt"
			end
		end
		model:SetAttribute("Running", true)
		beam.Transparency = 0.4
		TweenService:Create(beam, TweenInfo.new(1.6), { Transparency = 1 }):Play()
		local b = Bales.spawn(dropAt.Position, false, false, "star")
		b.ownerId = ownerId
		b.body.CFrame = dropAt
		b.body.Anchored = false
		pcall(function()
			b.body:SetNetworkOwner(nil)
		end)
		task.delay(1.6, function()
			model:SetAttribute("Running", false)
		end)
		return true
	end

	task.spawn(function()
		local nextAt = os.clock() + period
		while model.Parent do
			local left = nextAt - os.clock()
			if left <= 0 then
				local ok, why = beamDown()
				if ok then
					nextAt = os.clock() + period
				else
					label.Text = "STARBEAM COLLECTOR\n" .. why
					task.wait(2)
					continue
				end
			else
				label.Text = ("STARBEAM COLLECTOR\nnext star bale in %d:%02d"):format(left // 60, math.floor(left % 60))
			end
			crystal.Transparency = 0.2 + 0.3 * (1 + math.sin(os.clock() * 2)) / 2
			task.wait(1)
		end
	end)
	return model
end

return Starbeam
