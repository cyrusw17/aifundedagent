--!nonstrict
-- Needle display walls: a plot piece where an owner puts their rarest needles on show for visitors.
-- A wall takes one grid cell. It stands along the back edge of the cell (the side the frame faces) with its face to
-- the front, and has SLOTS pegs in two rows. The owner clicks an empty peg to hang the most valuable needle from their
-- pocket there, and clicks a full peg to take that needle back. Anyone can read the plaque under each needle. Needles
-- on show are plain decorations, not "Needle" parts, so visitors cannot pick them up.
--
--   local wall = Display.wall(parent, frame, getOwnerId, saved)  -- getOwnerId() returns the plot owner's UserId or nil
--   wall.contents()  -> { { slot = 1, id = "ice", mult = 1 }, ... } for the save
--   wall.clear()     -> empties the pegs without giving needles back (call it after saving, before freeing a plot)
-- Destroying the wall model otherwise hands its needles back to the owner's pocket (selling the piece).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Factory = require(ReplicatedStorage.Shared.Config.Factory)
local WorldLabel = require(ReplicatedStorage.Shared.WorldLabel)
local Data = require(script.Parent.Data)
local Machines = require(script.Parent.Machines)
local Needle = require(script.Parent.Needle)

local Display = {}

local T = Factory.TileSize
local SLOTS = 6
local HEIGHT = 7
local C = Machines.Colors
local part = Machines.part

local function plaque(parent, text)
	return WorldLabel.billboard(parent, text, { offset = Vector3.new(0, -0.9, 0), kind = "tag", distance = 30 })
end

local function describe(n)
	local grade = (n.grade and n.grade ~= "B") and (n.grade .. " grade ") or ""
	local name = grade .. (n.polished and "Polished " or "") .. Needle.info(n.id).name
	if (n.mult or 1) > 1 then
		return ("x%d MUTATED %s\n$%d"):format(n.mult, name:upper(), Needle.priceOf(n.id, n.mult, n.polished, n.grade))
	end
	return ("%s needle\n$%d"):format(name, Needle.priceOf(n.id, n.mult, n.polished, n.grade))
end

function Display.wall(parent, frame, getOwnerId, saved)
	local model = Instance.new("Model")
	model.Name = "NeedleDisplay"
	model.Parent = parent

	-- The board stands at the back of the cell; its face looks toward the front (-LookVector).
	local back = frame * CFrame.new(0, 0, -T / 2 + 0.6) * CFrame.Angles(0, math.pi, 0)
	part(model, "Board", Vector3.new(T - 0.4, HEIGHT, 0.4), back * CFrame.new(0, HEIGHT / 2, 0.2), C.planks, Enum.Material.WoodPlanks)
	for _, x in { -1, 1 } do
		part(model, "Post", Vector3.new(0.5, HEIGHT + 0.6, 0.6), back * CFrame.new(x * (T / 2 - 0.25), (HEIGHT + 0.6) / 2, 0.3), C.wood, Enum.Material.WoodPlanks)
	end
	part(model, "Cap", Vector3.new(T + 0.2, 0.4, 1), back * CFrame.new(0, HEIGHT + 0.6, 0.3), C.darkMetal, Enum.Material.Metal)
	Machines.sign(model.Cap, "NEEDLE DISPLAY", Vector3.new(0, 1.6, 0))

	local slots = {}
	for i = 1, SLOTS do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local at = back * CFrame.new((col - 1) * 1.8, HEIGHT - 2 - row * 3, -0.15)
		local peg = part(model, "Peg", Vector3.new(0.9, 0.3, 0.3), at, C.metal, Enum.Material.Metal)
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 14
		click.Parent = peg
		slots[i] = { peg = peg, at = at * CFrame.new(0, 0.5, -0.2), needle = nil, shown = nil }
	end

	local function show(slot, n)
		if slot.shown then
			slot.shown:Destroy()
			slot.shown = nil
		end
		slot.needle = n
		if not n then
			return
		end
		local mutated = (n.mult or 1) > 1
		local p = part(model, "OnShow", mutated and Vector3.new(1.9, 0.24, 0.24) or Vector3.new(1.2, 0.15, 0.15), slot.at, C.metal)
		p.Shape = Enum.PartType.Cylinder
		p.CanCollide = false
		p.Color, p.Material = Needle.look(n.id, n.mult)
		if n.polished then
			p.Reflectance = 0.45
		end
		if p.Material == Enum.Material.Neon then
			local light = Instance.new("PointLight")
			light.Color = p.Color
			light.Range = mutated and 8 or 4
			light.Brightness = mutated and 2 or 1
			light.Parent = p
		end
		if mutated then
			local sparkle = Instance.new("Sparkles")
			sparkle.SparkleColor = p.Color
			sparkle.Parent = p
		end
		plaque(p, describe(n))
		slot.shown = p
	end

	for _, s in saved or {} do
		local slot = typeof(s) == "table" and slots[s.slot]
		if slot and typeof(s.id) == "string" then
			show(slot, { id = s.id, mult = typeof(s.mult) == "number" and math.clamp(math.floor(s.mult), 1, 25) or 1, polished = s.polished == true, grade = (s.grade == "A" or s.grade == "S") and s.grade or nil })
		end
	end

	for _, slot in slots do
		slot.peg.ClickDetector.MouseClick:Connect(function(player: Player)
			if getOwnerId() ~= player.UserId then
				Data.toast(player, "Only this farm's owner can change its display.")
				return
			end
			if slot.needle then
				Needle.give(player, slot.needle)
				Data.toast(player, "Took the needle back into your pocket.")
				show(slot, nil)
				return
			end
			local n = Needle.takeBest(player)
			if not n then
				Data.toast(player, "Pick up a needle first. Your most valuable one goes on show.")
				return
			end
			show(slot, n)
			Data.toast(player, ("Put your %s on show."):format((describe(n):gsub("\n.*", ""))))
		end)
	end

	local wall = { model = model }

	function wall.contents()
		local list = {}
		for i, slot in slots do
			if slot.needle then
				table.insert(list, { slot = i, id = slot.needle.id, mult = slot.needle.mult, polished = slot.needle.polished, grade = slot.needle.grade })
			end
		end
		return list
	end

	function wall.clear()
		for _, slot in slots do
			show(slot, nil)
		end
	end

	-- If the model is removed (the piece is sold), the owner gets their needles back in their pocket.
	model.Destroying:Connect(function()
		local owner = Players:GetPlayerByUserId(getOwnerId() or 0)
		for _, slot in slots do
			if slot.needle and owner then
				Needle.give(owner, slot.needle)
			end
		end
	end)

	return wall
end

return Display
