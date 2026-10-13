--!nonstrict
-- Region machines: the thawing shed (Frozen hay), the drying rack (Bog reed) and the ash sifter (Ashen hay). Each sits
-- over two belt cells like the press. A bale of its hay type that rides through gets the machine's mark attribute
-- (Config/Factory Treatments), and sorters check that mark: Frozen hay and Bog reed are refused untreated, Ashen hay
-- sorts at half recovery. The drying rack also dries any rain-wet bale. Every other bale rides through untouched, so a line can keep one in place for any hay.
--
--   Treat.build(parent, frame, machineId)   -- frame: Conveyors.frame of the upstream cell, facing the flow
--   Treat.needs(body)                       -- the Treatments entry a bale body still needs, or nil
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factory = require(Shared.Config.Factory)
local HayTypes = require(Shared.Config.Gloves).HayTypes
local Bales = require(script.Parent.Bales)
local Machines = require(script.Parent.Machines)
local Feedback = require(script.Parent.Feedback)
local Skins = require(script.Parent.Skins)

local Treat = {}

local T = Factory.TileSize
local TOP = Factory.BeltTop
local C = Machines.Colors
local part = Machines.part

-- How each machine looks (the part build, under the Blender mesh once it is imported) and what it does to the bale.
local LOOKS = {
	thawing_shed = {
		title = "THAWING SHED",
		walls = Color3.fromRGB(120, 92, 70),
		glow = Color3.fromRGB(255, 150, 70),
		tint = Color3.fromRGB(212, 190, 140), -- a thawed bale loses its frost
		particle = Color3.fromRGB(230, 230, 235), -- steam
	},
	drying_rack = {
		title = "DRYING RACK",
		walls = Color3.fromRGB(104, 84, 60),
		glow = Color3.fromRGB(255, 214, 140),
		tint = Color3.fromRGB(150, 140, 96),
		particle = Color3.fromRGB(210, 220, 200),
	},
	ash_sifter = {
		title = "ASH SIFTER",
		walls = Color3.fromRGB(88, 88, 92),
		glow = Color3.fromRGB(255, 120, 60),
		tint = nil,
		particle = Color3.fromRGB(70, 66, 64), -- ash
	},
}

local byMachine = {} -- machineId -> { hayType, treatment }
for hayType, t in Factory.Treatments do
	byMachine[t.machine] = { hayType = hayType, treatment = t }
end

function Treat.needs(body)
	local t = Factory.Treatments[body:GetAttribute("HayType") or "meadow"]
	if t and not body:GetAttribute(t.mark) then
		return t
	end
	return nil
end

function Treat.build(parent, frame, machineId)
	local spec = byMachine[machineId]
	local look = LOOKS[machineId]
	assert(spec and look, "Treat.build: unknown machine " .. tostring(machineId))
	local center = frame * CFrame.new(0, 0, -T / 2) -- middle of the two cells
	local model = Instance.new("Model")
	model.Name = "RegionMachine"
	model:SetAttribute("Machine", machineId)
	model:SetAttribute("Running", false)
	model.Parent = parent

	local height = 6.5
	for _, sx in { -1, 1 } do
		part(model, "Wall", Vector3.new(0.5, height, T * 2), center * CFrame.new(sx * (T / 2 - 0.25), TOP + height / 2, 0), look.walls, Enum.Material.WoodPlanks)
	end
	local roof = part(model, "Roof", Vector3.new(T + 0.6, 0.6, T * 2 + 0.6), center * CFrame.new(0, TOP + height + 0.3, 0), C.darkMetal, Enum.Material.Metal)
	local lamp = part(model, "Lamp", Vector3.new(T - 1.6, 0.3, T * 2 - 1), center * CFrame.new(0, TOP + height - 0.2, 0), look.glow, Enum.Material.Neon)
	lamp.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = look.glow
	light.Range = 10
	light.Brightness = 0
	light.Parent = lamp
	local puff = Instance.new("ParticleEmitter")
	puff.Rate = 0
	puff.Lifetime = NumberRange.new(0.8, 1.6)
	puff.Speed = NumberRange.new(2, 4)
	puff.SpreadAngle = Vector2.new(40, 40)
	puff.Color = ColorSequence.new(look.particle)
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2) })
	puff.Transparency = NumberSequence.new(0.3, 1)
	puff.Parent = roof
	local label = Machines.sign(roof, look.title, Vector3.new(0, 3, 0))
	-- The Blender machine (belt along the flow, belt top at 3.5) takes over the look once imported; its Roller, Vent,
	-- Fan, Drum and Shaker pieces move while the machine is Running (Skins.luau, Conveyors.client.luau).
	Skins.dress(machineId, roof, model, center)

	local zone = center * CFrame.new(0, TOP + 2, 0)
	local zoneSize = Vector3.new(T - 0.8, 4, T * 2 - 0.5)
	local treated = 0
	local lastWork = 0
	local hayName = HayTypes[spec.hayType] and HayTypes[spec.hayType].name or spec.hayType

	local function refresh()
		label.Text = ("%s\nfor %s, %d bales done"):format(look.title, hayName, treated)
	end
	refresh()

	task.spawn(function()
		while model.Parent do
			task.wait(0.2)
			for _, p in Workspace:GetPartBoundsInBox(zone, zoneSize) do
				local b = Bales.fromPart(p)
				-- A drying rack also dries rain-wet bales of any hay type (Bales.dry, from the hay thread).
				if machineId == "drying_rack" and b and p == b.body and not b.gone and not b.carriedBy and p:GetAttribute("Wet") and Bales.dry and Bales.dry(b) then
					treated += 1
					lastWork = os.clock()
					refresh()
				end
				if b and p == b.body and not b.gone and not b.carriedBy and (p:GetAttribute("HayType") or "meadow") == spec.hayType and not p:GetAttribute(spec.treatment.mark) then
					p:SetAttribute(spec.treatment.mark, true)
					if look.tint then
						p.Color = look.tint
					end
					treated += 1
					lastWork = os.clock()
					Feedback.play("Scoop", roof)
					refresh()
				end
			end
			local busy = os.clock() - lastWork < Factory.TreatSeconds
			model:SetAttribute("Running", busy)
			puff.Rate = busy and 25 or 0
			light.Brightness = busy and 2 or 0
		end
	end)
	return model
end

return Treat
