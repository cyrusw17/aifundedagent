--!nonstrict
-- What each tool does when you click with it. The click itself comes from the tool's server-side Activated
-- signal. The client also reports where the click pointed (ToolAim), so a tool works on the exact hay piece or
-- bale you clicked. If no aim arrives, the tool works on what is in front of you.
--   shovel: smash the clicked bale, or scoop the clicked hay piece and the pieces next to it
--   shovel with hay in your arms: click a truck bed, a hopper, a belt or the sell pad to pour it there
--   rake:   drag the loose pieces around the click back toward you, spreading them across the ground
-- Bare hands lift a whole bale with its Pick up button (see Bales.luau).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Economy = require(ReplicatedStorage.Shared.Economy)
local HayMath = require(ReplicatedStorage.Shared.HayMath)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)
local Bales = require(script.Parent.Bales)
local Hay = require(script.Parent.Hay)
local Gloves = require(script.Parent.Gloves)
local Events = require(script.Parent.Events)
local Feedback = require(script.Parent.Feedback)
local Finds = require(script.Parent.Finds)
local Wheelbarrow = require(script.Parent.Wheelbarrow)
local Vehicles = require(script.Parent.Vehicles)
local ToolSkins = require(script.Parent.ToolSkins)

local Tools = {}

local rng = Random.new()
local aims = {} -- player -> { position, part, time } from the latest click
local combos = {} -- player -> { count, last } for the scoop combo

local AIM_FRESH = 0.4 -- seconds an aim counts as belonging to the current click
local AIM_WAIT = 0.15 -- how long a click waits for its aim to arrive

-- The spot on the ground a little in front of the player.
local function spotInFront(root, distance)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	return root.Position + flat.Unit * distance - Vector3.new(0, 2, 0)
end

-- The aim for this click if the client sent one in reach, waiting briefly since it may land just after the click.
local function currentAim(player, root)
	local started = os.clock()
	while true do
		local aim = aims[player]
		if aim and os.clock() - aim.time < AIM_FRESH then
			aims[player] = nil
			if (aim.position - root.Position).Magnitude <= Config.ToolReach then
				return aim
			end
			return nil
		end
		if os.clock() - started > AIM_WAIT then
			return nil
		end
		task.wait()
	end
end

-- A little "+3 combo" that floats up over the player and fades.
local function comboPop(root, count)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(140, 40)
	gui.StudsOffset = Vector3.new(0, 3.5, 0)
	gui.MaxDistance = 60
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = ("+%d combo"):format(count)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(240, 214, 140)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = root
	TweenService:Create(gui, TweenInfo.new(0.8), { StudsOffset = Vector3.new(0, 5.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(gui, 0.9)
end

-- Counts this scoop into the player's combo and returns the extra strands it earns.
local function comboBonus(player, root)
	local now = os.clock()
	local combo = combos[player]
	if combo and now - combo.last <= Config.ComboWindowSeconds then
		combo.count += 1
	else
		combo = { count = 1 }
		combos[player] = combo
	end
	combo.last = now
	if combo.count < Config.ComboStart then
		return 0
	end
	comboPop(root, combo.count)
	Feedback.juice(player, "combo", combo.count - Config.ComboStart + 1)
	return HayMath.comboExtra(combo.count, Config)
end

-- Machines that take loose hay in (the sorter's hopper, the hay buyer, the baler, the docks' funnels).
local POUR_INTO = { NeedleSorter = true, HayBuyer = true, HayBaler = true, DockFunnel = true, PlotDock = true }

-- How far point is from the nearest point of a box (CFrame at its middle, and its size); 0 inside it.
local function distanceToBox(point, box, size)
	local p = box:PointToObjectSpace(point)
	local half = size / 2
	local outside = Vector3.new(
		math.max(math.abs(p.X) - half.X, 0),
		math.max(math.abs(p.Y) - half.Y, 0),
		math.max(math.abs(p.Z) - half.Z, 0)
	)
	return outside.Magnitude
end

-- Where a pour can go: the cargo box of the truck or trailer clicked (returns its box CFrame and size), or the clicked
-- spot on a conveyor belt, a machine's hopper, the dock or the sell pad. Anything else (the ground, a wall) is not a
-- pour target, so a stray click never dumps your hay. Everything is checked on the server against where the player
-- stands: the click names a part, and the client could name any part on the map, so the bed (or the belt or hopper
-- under the click) must be within Config.ToolReach of the player.
function Tools.pourTarget(aim, root)
	if not aim or not aim.part or not root then
		return nil
	end
	local part = aim.part
	local box, size = Wheelbarrow.cargoOf(part)
	if box then
		if distanceToBox(root.Position, box, size) > Config.ToolReach then
			return nil
		end
		return { box = box, size = size }
	end
	-- The clicked spot must really be on the clicked part, and in reach.
	if (aim.position - root.Position).Magnitude > Config.ToolReach or distanceToBox(aim.position, part.CFrame, part.Size) > 1.5 then
		return nil
	end
	if CollectionService:HasTag(part, "ConveyorBelt") or part.Name == "Hopper" or part.Name == "SellPad" then
		return { at = aim.position }
	end
	local node = part.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and (POUR_INTO[node.Name] or node:GetAttribute("Machine")) then
			return { at = aim.position }
		end
		node = node.Parent
	end
	return nil
end

-- Pours up to Config.PourStrands of the hay in your arms onto target, in an arc: real loose strands that land where
-- they land, so the hay becomes truck cargo or line feed. Hay scooped from sorted bales stays sorted. The hidden
-- needles rolled when the hay was scooped go back with it in proportion (the strands roll their own again wherever
-- they end up), so pouring out and scooping up again never makes needles.
function Tools.pour(player, root, target)
	local state = Data.get(player)
	if not state or state.loadHay < Config.HayPerPiece then
		return 0
	end
	local held = math.floor(state.loadHay / Config.HayPerPiece)
	local split = HayMath.pourSplit({
		hay = state.loadHay,
		sorted = state.loadSortedHay,
		needles = state.loadNeedles,
		wet = state.loadWetHay,
	}, Config.PourStrands, Config.HayPerPiece)
	local n, sortedOut, needlesOut, wetOut = split.n, split.sortedOut, split.needlesOut, split.wetOut
	local fraction = n / held

	state.loadHay -= n * Config.HayPerPiece
	state.loadSortedHay = math.max(0, (state.loadSortedHay or 0) - sortedOut * Config.HayPerPiece)
	state.loadWetHay = math.max(0, (state.loadWetHay or 0) - wetOut * Config.HayPerPiece)
	state.loadNeedles = math.max(0, (state.loadNeedles or 0) - needlesOut)
	state.loadWeight = (state.loadWeight or 0) * (1 - fraction)
	local hayType = state.loadType or "meadow"
	if state.loadHay <= 0 then
		state.loadHay, state.loadSortedHay, state.loadNeedles, state.loadWeight, state.loadTier = 0, 0, 0, 0, 0
		state.loadWetHay = 0
		state.loadType = nil
	end
	Data.sync(player)
	Avatar.refreshSpeed(player)

	local from = root.Position + Vector3.new(0, 1.5, 0) + root.CFrame.LookVector * 1.2
	local flight = Config.PourFlightSeconds
	local gravity = Vector3.new(0, -workspace.Gravity, 0)
	for i = 1, n do
		local landAt
		if target.box then
			-- Anywhere across the bed, a little above its floor, keeping off the walls.
			local size = target.size
			landAt = (
				target.box
				* CFrame.new(
					rng:NextNumber(-size.X / 2 + 0.6, size.X / 2 - 0.6),
					-size.Y / 2 + 0.6,
					rng:NextNumber(-size.Z / 2 + 0.6, size.Z / 2 - 0.6)
				)
			).Position
		else
			local spread = Config.PourSpread
			landAt = target.at + Vector3.new(rng:NextNumber(-spread, spread), 0.5, rng:NextNumber(-spread, spread))
		end
		-- The launch speed that lands it there after `flight` seconds under gravity.
		local velocity = (landAt - from - 0.5 * gravity * flight * flight) / flight
		task.delay((i - 1) * Config.PourStagger, function()
			local piece = Hay.spawnPiece(from, velocity, player.UserId, nil, hayType)
			if i <= sortedOut then
				piece:SetAttribute("Sorted", true)
			end
			if i > n - wetOut then
				Bales.wetPiece(piece)
			end
		end)
	end
	Feedback.play("Scoop", root, 0.8)
	Events.fire(player, "hay_poured", n, { position = target.at or target.box.Position })
	return n
end

local function useShovel(player, root, aim)
	local bale
	if aim then
		bale = aim.part and Bales.fromPart(aim.part)
	else
		bale = Bales.inFront(root, Config.ShovelReach)
	end
	-- The aim's position is range-checked, but the part it names could be any bale in the world.
	if bale and (bale.body.Position - root.Position).Magnitude > Config.ToolReach then
		bale = nil
	end
	if bale and not bale.carriedBy then
		Avatar.swing(player, "Shovel", function()
			Bales.breakOpen(player, bale)
		end)
		return
	end

	local state = Data.get(player)
	if not state then
		return
	end
	-- Hay in your arms and a truck bed, hopper, belt or sell pad clicked: pour it there.
	local target = state.loadHay >= Config.HayPerPiece and Tools.pourTarget(aim, root)
	if target then
		Avatar.swing(player, "Shovel", function()
			Tools.pour(player, root, target)
		end)
		return
	end
	-- The clicked spot, or else the ground in front of you. Pieces right at your feet count too.
	local function targetPieces(max)
		local center = aim and aim.position or spotInFront(root, Config.ShovelReach / 2)
		local list = Hay.near(center, Config.ShovelRadius, max)
		if #list == 0 and not aim then
			list = Hay.near(root.Position - Vector3.new(0, 2.5, 0), Config.ShovelRadius, max)
		end
		return list
	end

	if #targetPieces(1) == 0 then
		Data.toast(player, "No hay there. Click a bale or a hay piece.")
		return
	end
	local capacity = Gloves.carryCapacity(player)
	if state.loadHay + Config.HayPerPiece > capacity then
		Data.toast(player, "You are carrying all the hay you can. Sell it at the pad by the shop.")
		return
	end

	Avatar.swing(player, "Shovel", function()
		-- The swing takes a moment, so look again when the shovel lands and respect the carry limit.
		-- Better gloves scoop more; hay rarer than your gloves are rated for scoops less.
		local room = math.floor((capacity - state.loadHay) / Config.HayPerPiece)
		-- The hay's tier comes from the first strand in reach, not a needle (needles carry no hay type).
		local first
		for _, piece in targetPieces(8) do
			if not Hay.isNeedle(piece) then
				first = piece
				break
			end
		end
		if not first then
			return
		end
		local hayTier = select(2, Gloves.pieceWeight(first))
		local bonus = comboBonus(player, root)
		local list = targetPieces(math.min(Gloves.scoopSize(player, hayTier) + bonus, room))
		if #list == 0 then
			return
		end
		local strands, found, unsorted, wet = 0, 0, 0, 0
		local roomLeft = room
		for i = #list, 1, -1 do
			local piece = list[i]
			if Hay.isPile(piece) then
				-- A raked pile goes in one scoop, as much of it as you have room for.
				local take = math.min(Hay.strandsIn(piece), math.max(roomLeft, 0))
				if take <= 0 then
					table.remove(list, i)
					continue
				end
				roomLeft -= take
				strands += take
				if not piece:GetAttribute("Sorted") then
					unsorted += take
				end
				if piece:GetAttribute("Wet") then
					wet += take
				end
				local weight, tier = Gloves.pieceWeight(piece)
				state.loadWeight = (state.loadWeight or 0) + weight * take
				state.loadTier = math.max(state.loadTier or 0, tier)
				if take < Hay.strandsIn(piece) then
					Hay.takeFromPile(piece, take)
					table.remove(list, i) -- the rest of the pile stays on the ground
				end
			elseif Hay.isNeedle(piece) then
				if Hay.sharedNeedles then
					table.remove(list, i) -- a shared needle is picked up by clicking it, so the shovel leaves it
				else
					found += 1
				end
			else
				strands += 1
				roomLeft -= 1
				if not piece:GetAttribute("Sorted") then
					unsorted += 1 -- hay from a sorted bale has had its needles taken out already
				end
				if piece:GetAttribute("Wet") then
					wet += 1
				end
				local weight, tier = Gloves.pieceWeight(piece)
				state.loadWeight = (state.loadWeight or 0) + weight
				state.loadTier = math.max(state.loadTier or 0, tier)
			end
		end
		local hay = strands * Config.HayPerPiece
		state.loadHay += hay
		-- What kind of hay is in your arms, so it pours back out as the same (Tools.pour).
		state.loadSortedHay = (state.loadSortedHay or 0) + (strands - unsorted) * Config.HayPerPiece
		state.loadWetHay = (state.loadWetHay or 0) + wet * Config.HayPerPiece
		state.loadType = state.loadType or first:GetAttribute("HayType") or "meadow"
		state.loadNeedles += found
			+ Economy.rollNeedles(rng, unsorted * Config.HayPerPiece, Config.NeedleChancePerHay)
		Data.sync(player)
		Hay.flyToPlayer(root, list)
		Feedback.play("Scoop", root)
		if found > 0 then
			Feedback.needle(root)
			Data.toast(player, found == 1 and "You found a needle in the hay!" or ("You found %d needles!"):format(found))
		end
	end)
end

local function useRake(player, root, aim)
	local center = aim and aim.position or spotInFront(root, Config.RakeRadius)
	Avatar.swing(player, "Rake", function()
		-- Gather toward the ground a couple of studs in front of the player, on the side the hay is on.
		local flat = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z)
		local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local gatherAt = root.Position + dir * Config.RakeGatherDistance
		-- A stroke that ends at a conveyor belt (or a click on the belt itself) flicks the hay up onto it, so raking
		-- feeds the line. Otherwise the hay is pulled into a row in front of you.
		local belt, landAt
		if aim and aim.part and CollectionService:HasTag(aim.part, "ConveyorBelt") then
			belt, landAt = Hay.beltNear(aim.position, 1)
		end
		if not belt then
			belt, landAt = Hay.beltNear(gatherAt - Vector3.new(0, 1, 0), Config.RakeBeltReach)
		end
		-- Dust kicks up where the tines drag, and along the way back toward you.
		Feedback.dust(center, nil, 8)
		Feedback.dust(center:Lerp(gatherAt, 0.5) - Vector3.new(0, 1.5, 0), nil, 5)
		if belt then
			Hay.rakeOntoBelt(center, belt, landAt, Config.RakeRadius, player.UserId)
			Events.fire(player, "raked_onto_belt", 1, { center = center })
		else
			Hay.rake(center, gatherAt, Config.RakeRadius, player.UserId)
		end
		Events.fire(player, "raked", 1, { center = center })
		Feedback.play("Rake", center)
	end)
end

function Tools.init()
	Feedback.init()
	Gloves.init()
	Finds.init()
	Wheelbarrow.init(currentAim)
	ToolSkins.init()
	-- Crew hand-offs (Bales): until Land says exactly who shares a farm, a teammate is anyone allowed to drive the
	-- other's truck, either way round (a farm's owner and its crew).
	if not Bales.isTeammate then
		Bales.isTeammate = function(a, b)
			local canDrive = Vehicles.canDrive
			return canDrive ~= nil and (canDrive(a, b) == true or canDrive(b, a) == true)
		end
	end
	-- The glove and wheelbarrow stands go beside the sell pad once the world has built it.
	task.defer(function()
		local world = workspace:FindFirstChild("Needlewood")
		local pad = world and world:WaitForChild("SellPad", 10)
		if pad then
			Gloves.buildStand(world, CFrame.new(pad.Position.X - pad.Size.X / 2 - 3.5, 0, pad.Position.Z))
			Wheelbarrow.buildStand(world, CFrame.new(pad.Position.X - pad.Size.X / 2 - 3.5, 0, pad.Position.Z + 9))
		end
	end)

	local aimRemote = Instance.new("RemoteEvent")
	aimRemote.Name = "ToolAim"
	aimRemote.Parent = ReplicatedStorage
	aimRemote.OnServerEvent:Connect(function(player, position, part)
		if typeof(position) ~= "Vector3" or (part ~= nil and typeof(part) ~= "Instance") then
			return
		end
		aims[player] = { position = position, part = part, time = os.clock() }
	end)
	Players.PlayerRemoving:Connect(function(player)
		aims[player] = nil
		combos[player] = nil
	end)

	Avatar.onToolActivated = function(player, kind)
		local root = Avatar.getRoot(player)
		local state = Data.get(player)
		if not root or not state or state.carryBale then
			return
		end
		local aim = currentAim(player, root)
		if kind == "Shovel" then
			useShovel(player, root, aim)
		elseif kind == "Rake" then
			useRake(player, root, aim)
		end
	end

	-- Putting a carried bale down from the keyboard (G) or a click. The bale's own button does the same.
	local dropRemote = Instance.new("RemoteEvent")
	dropRemote.Name = "DropBale"
	dropRemote.Parent = ReplicatedStorage
	-- With a charge (0..1, from holding the click) it throws the bale instead.
	dropRemote.OnServerEvent:Connect(function(player, power)
		if typeof(power) == "number" then
			Bales.toss(player, power)
		else
			Bales.drop(player)
		end
	end)
end

return Tools
