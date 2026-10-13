--!nonstrict
-- Ferries and the zeppelin: big roll-on, roll-off decks that carry trucks with their trailers hitched.
--
-- A ferry runs between two piers on a timetable: it boards at one pier (gates open, a ramp plate bridges the gap),
-- sounds a warning, then lashes every truck and trailer on its deck down for the crossing and sails to the other
-- pier, where it lets them go. Drive on at one end, drive off the far end, no reversing. The deck is a physics body
-- held on its course by rigid align constraints and owned by the server, so people walking on it ride along.
-- Bales stay loose in the beds; the lashed truck is part of the ferry's body while it sails (Vehicles.luau gives
-- their physics to the server while a vehicle has the OnFerry attribute).
--
-- The zeppelin to Sky Island is the same machine with a gondola for a deck.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local Prices = require(Shared.Config.Prices)
local Vehicles = require(script.Parent.Vehicles)
local Bank = require(script.Parent.Bank)
local Data = require(script.Parent.Data)
local Props = require(script.Parent.Props)
local WorldShape = require(script.Parent.WorldShape)

local Ferry = {}

local IRON = Color3.new(0.48, 0.48, 0.47)
local IRON_DARK = Color3.new(0.40, 0.38, 0.35)
local SEA = Map.SeaLevel
local GATE_H = 3.2
local LASH_HEIGHT = 16 -- how far above the deck a vehicle can be and still get lashed

local shuttles = {}

local function part(parent, name, size, cframe, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if collide == false then
		p.CanCollide = false
	end
	p.Parent = parent
	return p
end

-- Floating text goes through the shared WorldLabel helper.
local function boardLabel(parent, offset, distance)
	return WorldLabel.billboard(parent, "", { offset = offset, kind = "sign", distance = distance or 220, color = Color3.fromRGB(240, 232, 210) })
end

local function yawOf(cframe)
	local look = cframe.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- Piers --------------------------------------------------------------------------------------------------------

-- A plank pier on posts from the shore out to where the ferry docks, its deck level with the ferry's.
local function buildPier(parent, shore, pierEnd, deckTop, width, name)
	local model = Instance.new("Model")
	model.Name = name .. " Pier"
	local a = Vector3.new(shore.X, deckTop, shore.Y)
	local b = Vector3.new(pierEnd.X, deckTop, pierEnd.Y)
	local dir = (b - a).Unit
	-- Start a little inland so the pier meets the quay with no step.
	a -= dir * 20
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	local deck = part(model, "PierDeck", Vector3.new(width, 1.2, length), cf * CFrame.new(0, -0.6, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	deck.CustomPhysicalProperties = PhysicalProperties.new(1, 0.8, 0, 1, 1)
	for _, side in { -1, 1 } do
		part(model, "PierRail", Vector3.new(0.6, 1.6, length), cf * CFrame.new(side * (width / 2 - 0.3), 0.8, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	for d = 0, length, 16 do
		for _, side in { -1, 1 } do
			local p = cf * CFrame.new(side * (width / 2 - 1.5), 0, -length / 2 + d)
			local bottom = math.min(WorldShape.heightAt(p.X, p.Z), SEA) - 4
			local height = deckTop - 1.2 - bottom
			if height > 1 then
				part(model, "PierPost", Vector3.new(1.6, height, 1.6), CFrame.new(p.X, bottom + height / 2, p.Z), Rustic.WoodDark, Enum.Material.Wood)
			end
		end
	end
	-- A lamp post and the departures board at the end.
	local endCF = CFrame.lookAt(b, b + dir) * CFrame.new(width / 2 - 2, 0, 6)
	part(model, "LampPost", Vector3.new(0.6, 12, 0.6), endCF * CFrame.new(0, 6, 0), IRON, Enum.Material.Metal)
	local lamp = part(model, "Lamp", Vector3.new(1.2, 1.2, 1.2), endCF * CFrame.new(0, 12.4, 0), Color3.fromRGB(255, 220, 160), Enum.Material.Neon, false)
	local l = Instance.new("PointLight")
	l.Range = 40
	l.Color = Color3.fromRGB(255, 220, 160)
	l.Parent = lamp
	local board = part(model, "Departures", Vector3.new(10, 5, 0.5), CFrame.lookAt(a + dir * 24, a) * CFrame.new(-(width / 2 + 3), 6, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	part(model, "BoardPost", Vector3.new(0.6, 6, 0.6), board.CFrame * CFrame.new(0, -5.5, 0), Rustic.WoodDark, Enum.Material.Wood)
	model.PrimaryPart = deck
	model.Parent = parent
	return model, board
end

-- The deck -----------------------------------------------------------------------------------------------------

-- Deck life (cosmetic, nothing here touches hay or needles) ----------------------------------------------------------

local SNACKS = { "a hay-dusted pretzel", "a cup of chowder", "a toffee apple", "a mug of cocoa", "a fish sandwich" }
local CATCHES = {
	{ "an old boot", 30 },
	{ "a herring", 25 },
	{ "a mackerel", 20 },
	{ "a tangle of twine", 15 },
	{ "a crab, who lets go and leaves", 8 },
	{ "a message in a bottle (it just says HELLO)", 2 },
}
local fishing = {} -- player -> true while a line is out

local function prompt(parent, action, object, hold)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = 8
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local function catch()
	local total = 0
	for _, c in CATCHES do
		total += c[2]
	end
	local pick = math.random() * total
	for _, c in CATCHES do
		pick -= c[2]
		if pick <= 0 then
			return c[1]
		end
	end
	return CATCHES[1][1]
end

local function deckLife(spots)
	if spots.counter then
		prompt(spots.counter, ("Buy a snack ($%d)"):format(Prices.Travel.snack or 15), "Galley").Triggered:Connect(function(player)
			local ok, why = Bank.charge(player, Prices.Travel.snack or 15, "Ferry snack")
			Data.toast(player, ok and ("You enjoy %s and watch the sea."):format(SNACKS[math.random(#SNACKS)]) or (why or "Not enough cash for a snack."))
		end)
	end
	if spots.board then
		CollectionService:AddTag(spots.board, "BountyBoard")
		prompt(spots.board, "Read", "Bounty board").Triggered:Connect(function(player)
			Data.toast(player, "Today's bounties are pinned here. Open your quest log, Bounties tab, to track them.")
		end)
	end
	if spots.fishing then
		prompt(spots.fishing, "Cast a line", "Fishing spot", 2).Triggered:Connect(function(player)
			if fishing[player] then
				return
			end
			fishing[player] = true
			task.delay(math.random(3, 7), function()
				fishing[player] = nil
				if player.Parent then
					player:SetAttribute("FishCaught", (player:GetAttribute("FishCaught") or 0) + 1)
					Data.toast(player, ("You reel in %s!"):format(catch()))
				end
			end)
		end)
	end
end

-- Builds a shuttle's deck (ferry hull or zeppelin gondola) centered on cframe, deck top at cframe's height.
-- Returns the model, its root deck part and the gate parts at each end.
local function buildDeck(def, cframe, parent)
	local model = Instance.new("Model")
	model.Name = def.name
	local L, W = def.length, def.width
	local root = part(model, "Deck", Vector3.new(W, 1.2, L), cframe * CFrame.new(0, -0.6, 0), def.zeppelin and Rustic.Wood or IRON, def.zeppelin and Enum.Material.WoodPlanks or Enum.Material.DiamondPlate)
	root.CustomPhysicalProperties = PhysicalProperties.new(3, 0.9, 0, 1, 1)
	model.PrimaryPart = root

	local visuals = {}
	local snacks = {}
	local function look(name, size, offset, color, material, collide, shape)
		local p = part(model, name, size, cframe * offset, color, material, collide)
		if shape then
			p.Shape = shape
		end
		table.insert(visuals, p)
		return p
	end

	-- Side rails, and lane stripes for three lanes of trucks.
	for _, side in { -1, 1 } do
		look("Bulwark", Vector3.new(1, GATE_H, L), CFrame.new(side * (W / 2 - 0.5), GATE_H / 2, 0), def.zeppelin and Rustic.WoodDark or IRON_DARK, Enum.Material.Metal)
	end
	for _, x in { -W / 6, W / 6 } do
		look("LaneStripe", Vector3.new(0.5, 0.05, L - 8), CFrame.new(x, 0.03, 0), Rustic.PaintYellow, Enum.Material.SmoothPlastic, false)
	end

	-- Gates across both ends: shut while moving, open (and out of the way) while boarding.
	local gates = {}
	for _, z in { -L / 2 + 0.4, L / 2 - 0.4 } do
		local gate = look("Gate", Vector3.new(W - 2, GATE_H, 0.6), CFrame.new(0, GATE_H / 2, z), Rustic.PaintYellow, Enum.Material.Metal)
		table.insert(gates, gate)
	end

	if def.zeppelin then
		-- The gondola hangs under a long canvas envelope on struts high enough for a truck to pass under.
		local high = 26
		look("Envelope", Vector3.new(L * 0.95, 26, 26), CFrame.new(0, high + 14, 0) * CFrame.Angles(0, math.pi / 2, 0), Rustic.Cloth, Enum.Material.Fabric, true, Enum.PartType.Cylinder)
		for _, z in { -L * 0.47, L * 0.47 } do
			look("EnvelopeEnd", Vector3.new(26, 26, 26), CFrame.new(0, high + 14, z), Rustic.Cloth, Enum.Material.Fabric, true, Enum.PartType.Ball)
		end
		for _, x in { -W / 2 + 0.6, W / 2 - 0.6 } do
			for _, z in { -L * 0.35, 0, L * 0.35 } do
				look("Strut", Vector3.new(0.6, high, 0.6), CFrame.new(x, high / 2, z), Rustic.WoodDark, Enum.Material.Wood)
			end
		end
		for _, side in { -1, 1 } do
			look("Propeller", Vector3.new(0.4, 10, 1.2), CFrame.new(side * 15, high + 6, L * 0.48), Rustic.WoodDark, Enum.Material.Wood)
		end
		look("Fin", Vector3.new(0.6, 14, 12), CFrame.new(0, high + 28, L * 0.45), Rustic.PaintRed, Enum.Material.Fabric)
	else
		-- A ferry hull under the deck (it never collides, so the sea floor can't snag it), a wheelhouse on the
		-- south rail clear of the lanes, and a funnel.
		look("Hull", Vector3.new(W + 2, 7, L), CFrame.new(0, -4.7, 0), IRON_DARK, Enum.Material.Metal, false)
		look("Waterline", Vector3.new(W + 2.2, 1, L + 0.2), CFrame.new(0, -3.2, 0), Rustic.PaintRedDark, Enum.Material.Metal, false)
		local house = CFrame.new(W / 2 + 4, 0, 0)
		look("WheelhouseBase", Vector3.new(7, 4, 36), house * CFrame.new(0, -2, 0), IRON_DARK, Enum.Material.Metal)
		look("Wheelhouse", Vector3.new(7, 10, 26), house * CFrame.new(0, 5, 0), Rustic.PaintCream, Enum.Material.Metal)
		look("WheelhouseRoof", Vector3.new(8, 0.6, 28), house * CFrame.new(0, 10.3, 0), Rustic.PaintRedDark, Enum.Material.Metal)
		look("Windows", Vector3.new(7.1, 2.2, 22), house * CFrame.new(0, 7, 0), Rustic.Glass, Enum.Material.Glass, false)
		look("Funnel", Vector3.new(4, 9, 4), house * CFrame.new(0, 15, 6), IRON_DARK, Enum.Material.Metal)
		look("FunnelBand", Vector3.new(4.2, 1.4, 4.2), house * CFrame.new(0, 18, 6), Rustic.PaintRed, Enum.Material.Metal, false)

		-- The promenade along the north rail, for drivers stretching their legs on the crossing: a snack stand, a
		-- bounty board and a fishing spot at the stern. Up a step and outside the bulwark, so it never takes a lane.
		local walk = CFrame.new(-(W / 2 + 4), 0, 0)
		look("PromenadeBase", Vector3.new(7, 4, 70), walk * CFrame.new(0, -2, 0), IRON_DARK, Enum.Material.Metal)
		look("Promenade", Vector3.new(7, 0.4, 70), walk * CFrame.new(0, 0.2, 0), Rustic.Wood, Enum.Material.WoodPlanks)
		look("PromenadeRail", Vector3.new(0.4, 3, 70), walk * CFrame.new(-3.3, 1.9, 0), Rustic.WoodDark, Enum.Material.Wood)
		-- Snack stand.
		local stand = walk * CFrame.new(0.5, 0, -22)
		local counter = look("SnackCounter", Vector3.new(3, 3.2, 8), stand * CFrame.new(-1.5, 2, 0), Rustic.PaintCream, Enum.Material.WoodPlanks)
		local standLook = { counter }
		standLook[2] = look("SnackAwning", Vector3.new(5, 0.3, 9), stand * CFrame.new(-1, 6.2, 0) * CFrame.Angles(0, 0, math.rad(-12)), Rustic.PaintRed, Enum.Material.Fabric, false)
		for _, z in { -4, 4 } do
			standLook[#standLook + 1] = look("SnackPole", Vector3.new(0.3, 4.4, 0.3), stand * CFrame.new(1.2, 4, z), Rustic.WoodDark, Enum.Material.Wood, false)
		end
		snacks.counter = look("SnackSign", Vector3.new(0.2, 1.2, 5), stand * CFrame.new(0, 3.9, 0), Rustic.PaintYellow, Enum.Material.WoodPlanks, false)
		-- Bounty board.
		local board = look("FerryBountyBoard", Vector3.new(0.4, 4, 6), walk * CFrame.new(-2.8, 3.6, 4), Rustic.Wood, Enum.Material.WoodPlanks)
		snacks.board = board
		-- Fishing spot at the stern rail.
		snacks.fishing = look("FishingSpot", Vector3.new(2, 0.3, 2), walk * CFrame.new(-1.5, 0.45, 30), Rustic.WoodDark, Enum.Material.Wood, false)
		-- The Blender snack stand (service side +X, toward the lanes, like this one) and fishing spot when imported.
		-- Each is only a look, welded to its part, which keeps the prompt and stays the look until the mesh loads.
		table.insert(standLook, snacks.counter)
		local deckTop = (cframe * walk).Y + 0.4
		local standMesh = Props.make("ferry_snack_stand", cframe * stand * CFrame.new(-0.9, 3.3, 0))
		if standMesh then
			Props.restOn(standMesh, deckTop)
			Props.weldTo(standMesh, counter, standLook)
		end
		local spotMesh = Props.make("fishing_spot", cframe * walk * CFrame.new(-1.5, 2, 30))
		if spotMesh then
			Props.restOn(spotMesh, deckTop)
			Props.weldTo(spotMesh, snacks.fishing, snacks.fishing)
		end
	end

	-- Everything rides on the deck.
	for _, p in visuals do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Anchored = false
		p.Massless = true
	end
	model.Parent = parent
	deckLife(snacks)
	return model, root, gates
end

-- Lashing ------------------------------------------------------------------------------------------------------

local function setDrive(model, enabled)
	local chassis = model.PrimaryPart
	if not chassis then
		return
	end
	for _, name in { "Drive", "Steer" } do
		local c = chassis:FindFirstChild(name)
		if c then
			if name == "Steer" and enabled then
				c.CFrame = CFrame.Angles(0, yawOf(chassis.CFrame), 0)
			end
			c.Enabled = enabled
		end
	end
end

local function giveBack(model)
	local owner = Players:GetPlayerByUserId(model:GetAttribute("OwnerId") or 0)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and not p.Anchored then
			pcall(function()
				p:SetNetworkOwner(owner)
			end)
		end
	end
end

-- Is a vehicle standing on this deck?
local function onDeck(shuttle, model)
	local chassis = model.PrimaryPart
	if not chassis or chassis.Anchored then
		return false
	end
	local spot = shuttle.root.CFrame:PointToObjectSpace(chassis.Position)
	return math.abs(spot.X) < shuttle.def.width / 2 and math.abs(spot.Z) < shuttle.def.length / 2 and spot.Y > -2 and spot.Y < LASH_HEIGHT
end

-- Fares -------------------------------------------------------------------------------------------------------

local function tell(player, text)
	if player and Data.get(player) then
		Data.toast(player, text)
	end
end

-- The trailer hitched to a truck, if its owner has one on.
local function trailerOf(truck)
	local id = truck:GetAttribute("TruckId")
	for model in Vehicles.all() do
		if model ~= truck and model:GetAttribute("HitchedTo") == id and model:GetAttribute("OwnerId") == truck:GetAttribute("OwnerId") then
			return model
		end
	end
	return nil
end

-- Rolls an unpaid truck (and its trailer) back onto the pier at this stop, off the deck, keeping its heading.
local function sendBack(model, stop)
	local chassis = model.PrimaryPart
	if not chassis then
		return
	end
	local from = chassis.Position
	local to = stop.edge + stop.inland * 20
	local move = CFrame.new(Vector3.new(to.X - from.X, 0.5, to.Z - from.Z))
	local trailer = trailerOf(model)
	model:PivotTo(move * model:GetPivot())
	if trailer then
		trailer:PivotTo(move * trailer:GetPivot())
	end
end

-- Every truck on the deck pays its fare once per crossing (trailers ride free with their truck). A truck whose
-- owner can't pay is rolled back onto the pier with the reason.
-- The Captain's Barge (the Captain's Log quest reward) is a lifetime pass: its holder's trucks sail free.
local Quests = nil
local function sailsFree(owner)
	if Quests == nil then
		local ok, module = pcall(require, script.Parent.Quests)
		Quests = ok and module or false
	end
	return Quests and Quests.has and Quests.has(owner, "captains_barge") == true
end

local function collectFares(shuttle, stop)
	for model, owner in Vehicles.all() do
		if shuttle.paid[model] or not model:GetAttribute("TruckId") or model:GetAttribute("OnFerry") or not onDeck(shuttle, model) then
			continue
		end
		local fare = sailsFree(owner) and 0 or (shuttle.def.fare or 0)
		local ok, message = Bank.charge(owner, fare, shuttle.def.name .. " fare")
		if ok then
			shuttle.paid[model] = true
			if fare > 0 then
				tell(owner, ("%s: fare $%d paid. Stay on board, the gates close at departure."):format(shuttle.def.name, fare))
			elseif (shuttle.def.fare or 0) > 0 then
				tell(owner, ("%s: the Captain's Barge pass, you sail free. Stay on board."):format(shuttle.def.name))
			end
		else
			tell(owner, ("The %s fare is $%d. %s"):format(shuttle.def.name, fare, message or ""))
			sendBack(model, stop)
		end
	end
end

local function lash(shuttle)
	for model in Vehicles.all() do
		-- Only paid trucks sail (collectFares rolled the others back); trailers ride with them.
		if model:GetAttribute("TruckId") and not shuttle.paid[model] then
			continue
		end
		if not model:GetAttribute("OnFerry") and onDeck(shuttle, model) then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "FerryLash"
			weld.Part0 = shuttle.root
			weld.Part1 = model.PrimaryPart
			weld.Parent = model.PrimaryPart
			model:SetAttribute("OnFerry", shuttle.def.name)
			setDrive(model, false)
			shuttle.lashed[model] = weld
		end
	end
	pcall(function()
		shuttle.root:SetNetworkOwner(nil)
	end)
end

local function unlash(shuttle)
	for model, weld in shuttle.lashed do
		weld:Destroy()
		if model.Parent then
			model:SetAttribute("OnFerry", nil)
			setDrive(model, true)
			giveBack(model)
		end
	end
	shuttle.lashed = {}
	shuttle.paid = {}
	pcall(function()
		shuttle.root:SetNetworkOwner(nil)
	end)
end

-- Timetable ----------------------------------------------------------------------------------------------------

local function setGates(shuttle, closed)
	for _, gate in shuttle.gates do
		gate.CanCollide = closed
		gate.Transparency = closed and 0 or 0.85
	end
	for _, apron in shuttle.aprons do
		apron.CanCollide = not closed
		apron.Transparency = closed and 1 or 0
	end
end

local function setBoards(shuttle, text)
	for _, label in shuttle.labels do
		label.Text = text
	end
end

-- Moves the deck from one stop to the other along the route's path (the two stops, or round its via points):
-- speeds up, cruises, slows down, and turns to face along each leg of the way.
local function travel(shuttle, from, to)
	local points = { from.Position }
	local via = shuttle.via
	if via then
		local forward = from == shuttle.stops[1].cframe
		for i = forward and 1 or #via, forward and #via or 1, forward and 1 or -1 do
			table.insert(points, via[i])
		end
	end
	table.insert(points, to.Position)
	local legs, distance = {}, 0
	for i = 1, #points - 1 do
		local length = (points[i + 1] - points[i]).Magnitude
		table.insert(legs, { a = points[i], b = points[i + 1], start = distance, length = length })
		distance += length
	end
	-- The deck always faces from stop A to stop B along a leg, so it backs along the way home.
	local function facing(leg)
		local dir = leg.b - leg.a
		if to ~= shuttle.stops[2].cframe then
			dir = -dir
		end
		return CFrame.lookAt(Vector3.zero, Vector3.new(dir.X, 0, dir.Z))
	end
	local speed = shuttle.def.speed
	local ramp = math.min(distance / 2, speed * 3)
	local elapsed = 0
	local covered = 0
	local v = 0
	local leg = 1
	while covered < distance do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		local left = distance - covered
		local target = left < ramp and math.max(2, speed * left / ramp) or speed
		v = math.min(target, v + speed / 3 * dt)
		covered = math.min(distance, covered + v * dt)
		while leg < #legs and covered > legs[leg].start + legs[leg].length do
			leg += 1
		end
		local l = legs[leg]
		shuttle.align.Position = l.a:Lerp(l.b, math.clamp((covered - l.start) / math.max(l.length, 0.01), 0, 1))
		if #legs > 1 then
			-- Swing round onto the new heading over the first 60 studs of each leg.
			local turn = leg > 1 and math.clamp((covered - l.start) / 60, 0, 1) or 1
			local rotation = leg > 1 and facing(legs[leg - 1]):Lerp(facing(l), turn) or facing(l)
			shuttle.orient.CFrame = rotation
		end
		local remaining = math.ceil((distance - covered) / math.max(v, 1))
		if math.floor(elapsed) ~= math.floor(elapsed - dt) then
			setBoards(shuttle, ("%s\nUnderway, arriving in about %ds"):format(shuttle.def.name:upper(), remaining))
		end
	end
	shuttle.align.Position = to.Position
	shuttle.orient.CFrame = to.Rotation
end

local function run(shuttle)
	local stops = shuttle.stops
	local at = 1
	while shuttle.root.Parent do
		local here, there = stops[at], stops[3 - at]
		-- Boarding.
		setGates(shuttle, false)
		for t = shuttle.def.dock, 1, -1 do
			local text = ("%s\nBoarding at %s for %s\nFare $%d a truck, trailer free\nLeaves in %ds"):format(shuttle.def.name:upper(), here.name, there.name, shuttle.def.fare or 0, t)
			if t <= shuttle.def.warn then
				text ..= "\nAll aboard!"
			end
			setBoards(shuttle, text)
			collectFares(shuttle, here)
			task.wait(1)
		end
		-- Last fares, then lash everything down, close the gates, go.
		collectFares(shuttle, here)
		setGates(shuttle, true)
		lash(shuttle)
		travel(shuttle, here.cframe, there.cframe)
		task.wait(0.5)
		unlash(shuttle)
		at = 3 - at
	end
end

-- Builds one shuttle between two stops. Each stop is { name, cframe (deck top center at the stop, facing the way
-- to the other stop) }. aprons are plates at the piers that bridge the gap while docked.
local function startShuttle(def, stops, parent, labels, aprons, via)
	local model, root, gates = buildDeck(def, stops[1].cframe, parent)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Course"
	attachment.Position = Vector3.new(0, 0.6, 0) -- the deck top's center
	attachment.Parent = root
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.Position = stops[1].cframe.Position
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = attachment
	orient.RigidityEnabled = true
	orient.CFrame = stops[1].cframe.Rotation
	orient.Parent = root
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local shuttle = {
		def = def,
		model = model,
		root = root,
		gates = gates,
		align = align,
		orient = orient,
		via = via,
		stops = stops,
		labels = labels,
		aprons = aprons,
		lashed = {},
		paid = {},
	}
	table.insert(labels, boardLabel(root, Vector3.new(0, def.zeppelin and 50 or 16, 0), 320))
	table.insert(shuttles, shuttle)
	task.spawn(run, shuttle)
	return shuttle
end

-- A ramp plate at the end of a pier that bridges onto the docked deck.
local function apron(parent, pierEnd, dir, deckTop, width)
	local p = part(parent, "Apron", Vector3.new(width - 4, 0.4, 5), CFrame.lookAt(pierEnd, pierEnd + dir) * CFrame.new(0, deckTop - pierEnd.Y - 0.15, -1.6), IRON, Enum.Material.DiamondPlate)
	return p
end

function Ferry.build(worldFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Ferries"
	folder.Parent = worldFolder
	local F = Map.Ferry
	local deckTop = F.DeckTop

	for _, route in F.Routes do
		local a2, b2 = route.a.pierEnd, route.b.pierEnd
		-- Each pier points out along the first (or last) leg; without via that is straight at the other pier.
		local via = route.via
		local outA2 = ((via and via[1] or b2) - a2).Unit
		local outB2 = (b2 - (via and via[#via] or a2)).Unit
		local dirA = Vector3.new(outA2.X, 0, outA2.Y)
		local dirB = Vector3.new(outB2.X, 0, outB2.Y)
		local _, boardA = buildPier(folder, route.a.shore, a2, deckTop, 30, route.a.name)
		local _, boardB = buildPier(folder, route.b.shore, b2, deckTop, 30, route.b.name)
		local labels = { boardLabel(boardA, Vector3.new(0, 3, 0)), boardLabel(boardB, Vector3.new(0, 3, 0)) }
		local aprons = {
			apron(folder, Vector3.new(a2.X, deckTop, a2.Y), dirA, deckTop, 30),
			apron(folder, Vector3.new(b2.X, deckTop, b2.Y), -dirB, deckTop, 30),
		}
		-- The deck docks with its end against the pier end; it faces from A to B.
		local half = F.Length / 2 + 0.6
		local stopA = CFrame.new(Vector3.new(a2.X, deckTop, a2.Y) + dirA * half) * CFrame.lookAt(Vector3.zero, dirA)
		local stopB = CFrame.new(Vector3.new(b2.X, deckTop, b2.Y) - dirB * half) * CFrame.lookAt(Vector3.zero, dirB)
		local path = nil
		if via then
			path = {}
			for _, p in via do
				table.insert(path, Vector3.new(p.X, deckTop, p.Y))
			end
		end
		startShuttle({
			name = route.name,
			length = F.Length,
			width = F.Width,
			speed = F.Speed,
			dock = F.Dock,
			warn = F.Warn,
			fare = Prices.Travel.ferry,
		}, {
			{ name = route.a.name, cframe = stopA, edge = Vector3.new(a2.X, deckTop, a2.Y), inland = -dirA },
			{ name = route.b.name, cframe = stopB, edge = Vector3.new(b2.X, deckTop, b2.Y), inland = dirB },
		}, folder, labels, aprons, path)
	end

	-- The zeppelin: it lands on the Homestead field, and docks beside a platform at the edge of Sky Island.
	-- Sky Island is out for now (Config WorldMap.Zeppelin is nil).
	local Z = Map.Zeppelin
	if not Z then
		return folder
	end
	local a, b = Z.a.pos, Z.b.pos
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
	local facing = CFrame.lookAt(Vector3.zero, flat)
	local stopA = CFrame.new(a) * facing
	local stopB = CFrame.new(b) * facing
	-- The sky platform runs from the zeppelin's front end onto the island.
	local platformStart = b + flat * (Z.Length / 2 + 0.6)
	local platformLength = 70
	local platformCF = CFrame.lookAt(platformStart + flat * platformLength / 2, platformStart + flat * platformLength)
	local sky = Instance.new("Model")
	sky.Name = "Sky Dock"
	part(sky, "SkyDock", Vector3.new(Z.Width, 1.2, platformLength), platformCF * CFrame.new(0, -0.6, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		part(sky, "SkyRail", Vector3.new(0.6, 1.6, platformLength), platformCF * CFrame.new(side * (Z.Width / 2 - 0.3), 0.8, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	local skyBoard = part(sky, "Departures", Vector3.new(10, 5, 0.5), platformCF * CFrame.new(Z.Width / 2 + 3, 6, 10) * CFrame.Angles(0, math.pi / 2, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	sky.Parent = folder
	-- The mooring mast on the field.
	local mast = Instance.new("Model")
	mast.Name = "Mooring Mast"
	local mastBase = stopA * CFrame.new(Z.Width / 2 + 8, 0, 0)
	part(mast, "Mast", Vector3.new(2, 46, 2), mastBase * CFrame.new(0, 23, 0), IRON, Enum.Material.Metal)
	part(mast, "MastTop", Vector3.new(4, 1, 4), mastBase * CFrame.new(0, 46.5, 0), Rustic.PaintRed, Enum.Material.Metal)
	local fieldBoard = part(mast, "Departures", Vector3.new(10, 5, 0.5), mastBase * CFrame.new(0, 6, 3) * CFrame.Angles(0, math.pi / 2, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	mast.Parent = folder
	local labels = { boardLabel(fieldBoard, Vector3.new(0, 3, 0)), boardLabel(skyBoard, Vector3.new(0, 3, 0)) }
	startShuttle({
		name = Z.name,
		zeppelin = true,
		length = Z.Length,
		width = Z.Width,
		speed = Z.Speed,
		dock = Z.Dock,
		warn = 6,
		fare = Prices.Travel.zeppelin,
	}, {
		{ name = Z.a.name, cframe = stopA, edge = a - flat * (Z.Length / 2 + 4), inland = -flat },
		{ name = Z.b.name, cframe = stopB, edge = platformStart, inland = flat },
	}, folder, labels, {})
	-- Small ramps at the field, since the gondola's deck sits a step above the grass.
	for _, side in { -1, 1 } do
		local edge = stopA * CFrame.new(0, 0, side * (Z.Length / 2 + 2.5))
		local ramp = Instance.new("WedgePart")
		ramp.Name = "FieldRamp"
		ramp.Size = Vector3.new(Z.Width - 4, 1.2, 4)
		-- A wedge is tallest at its back (+Z); that side meets the gondola.
		ramp.CFrame = edge * CFrame.new(0, -0.6, 0) * CFrame.Angles(0, side > 0 and math.pi or 0, 0)
		ramp.Color = Rustic.Wood
		ramp.Material = Enum.Material.WoodPlanks
		ramp.Anchored = true
		ramp.Parent = folder
	end
	return folder
end

-- The ferries and the zeppelin, for the map: { name, model }.
function Ferry.all()
	return shuttles
end

-- For the self-tests (SelfTests/Map.luau): is a vehicle on this shuttle's deck, and roll one back to a stop's pier.
Ferry.onDeck = onDeck
Ferry.sendBack = sendBack

return Ferry
