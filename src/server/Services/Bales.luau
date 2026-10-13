--!nonstrict
-- Wrapped hay bales. Bare hands lift a whole bale and carry it. Set one down and it lands on whatever is in front
-- of you, so bales stack into piles. The shovel cuts a bale open: the twine snaps and the hay spills into a pile of
-- loose pieces (see Hay.luau). Bales are real physical blocks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local GloveConfig = require(ReplicatedStorage.Shared.Config.Gloves)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)
local Hay = require(script.Parent.Hay)
local Groups = require(script.Parent.Groups)
local Tutorial = require(script.Parent.Tutorial)
local Props = require(script.Parent.Props)
local PropsConfig = require(ReplicatedStorage.Shared.Config.Props)
local Gloves = require(script.Parent.Gloves)
local Feedback = require(script.Parent.Feedback)
local Events = require(script.Parent.Events)
local Finds = require(script.Parent.Finds)
local Announce = require(script.Parent.Announce)
local Weather = require(script.Parent.Weather)
local HayMath = require(ReplicatedStorage.Shared.HayMath)
local Boosts = require(ReplicatedStorage.Shared.Boosts)
local BOOST_TERMS = Boosts.terms(require(ReplicatedStorage.Shared.Config.Prices))
local LandConfig = require(ReplicatedStorage.Shared.Config.Land)
local WorldRegions = require(ReplicatedStorage.Shared.WorldRegions)

local Bales = {}

local rng = Random.new()
local folder = nil
local dropOff = nil -- the pad where set-down bales are kept for later
local byBody = {} -- bale body part -> bale record

local SIZE = Vector3.new(4.6, 2.6, 3.2) -- length, height, depth of one bale
local CARRY_OFFSET = CFrame.new(0, 0.4, -2.8)
local TWINE = Color3.fromRGB(97, 84, 66)
local TWINE_X = { -1.2, 1.2 } -- two bands of twine around the bale

-- Turns a bale's Pick up button on or off for everyone. The Usable attribute tells each client too, since clients
-- also hide the buttons locally while a tool is out (Main.client.luau).
local function setUsable(b, on)
	b.prompt:SetAttribute("Usable", on)
	b.prompt.Enabled = on
end

-- The bale's own color: the first of its hay's colors (Config/HayLooks).
local function hayColor(hayType)
	local c = Hay.look(hayType).colors[1]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function buildBale(position, hayType)
	hayType = hayType or "meadow"
	local body = Instance.new("Part")
	body.Name = "HayBale"
	body:SetAttribute("HayType", hayType) -- Config/Gloves hay type; set another for rarer bales
	body.Size = SIZE
	body.CFrame = CFrame.new(position + Vector3.new(0, SIZE.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0)
	body.Color = hayColor(hayType)
	body.Material = Enum.Material.Fabric
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Anchored = true
	-- Heavy and grippy with no bounce, so a stack settles instead of sliding apart. The heavy friction and elasticity
	-- weights make the bale's own grip and zero bounce win against whatever it rests on (a slick metal truck bed, a
	-- springy floor), so two bales stacked in a moving pickup ride it out instead of skating or popping apart.
	body.CustomPhysicalProperties = PhysicalProperties.new(1.2, 1.4, 0, 50, 100)

	-- The Rustic bale mesh, stretched over the hitbox so stacking and carrying work exactly as before. The body
	-- stays the real physics block and click target. Each client hides the part look once the mesh has loaded.
	-- Each region's hay has its own bale mesh (bale_pine, bale_star, ...); the meadow bale is hay_bale.
	local regionalName = PropsConfig.BaleForHay[hayType] or ("bale_%s"):format(hayType)
	local regional = hayType ~= "meadow" and Props.has(regionalName)
	local mesh = Props.make(regional and regionalName or "hay_bale", body.CFrame, SIZE)
	if mesh then
		-- Tint the meadow mesh for rarer hay that has no mesh of its own (an untextured mesh takes the color; a
		-- textured one keeps its own).
		if hayType ~= "meadow" and not regional then
			for _, d in mesh:GetDescendants() do
				if d:IsA("MeshPart") then
					d.Color = body.Color
				end
			end
		end
		Props.weldTo(mesh, body, body)
	end

	-- The twine bands wrap the part bale. They are visual only and ride along with it.
	for _, x in TWINE_X do
		local band = Instance.new("Part")
		band.Name = "Twine"
		band.Size = Vector3.new(0.12, SIZE.Y + 0.06, SIZE.Z + 0.06)
		band.CFrame = body.CFrame * CFrame.new(x, 0, 0)
		band.Color = TWINE
		band.Material = Enum.Material.Fabric
		band.CanCollide = false
		band.CanQuery = false
		band.Massless = true
		band.Parent = body
		local weld = Instance.new("Weld")
		weld.Part0 = body
		weld.Part1 = band
		weld.C0 = CFrame.new(x, 0, 0)
		weld.Parent = band
	end

	-- The small Pick up / Put down button. Click or tap it (or press its key). It lives on the bale, so
	-- while you carry it the button travels with you and puts it down.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = (GloveConfig.HayTypes[hayType] or GloveConfig.HayTypes.meadow).name .. " bale"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.PickupReach
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.UIOffset = Vector2.new(0, 24)
	prompt.Parent = body

	CollectionService:AddTag(body, "HayBale")
	return body, prompt
end

-- Removes a bale from the world for good (sold, smashed, or timed out).
function Bales.consume(b)
	if b.gone then
		return
	end
	b.gone = true
	byBody[b.body] = nil
	b.body:Destroy()
end

-- The nearest bale standing within reach and roughly in front of the player, or nil.
function Bales.inFront(root, reach)
	local look = root.CFrame.LookVector
	local best, bestDistance = nil, reach
	for body, b in byBody do
		if not b.gone and not b.carriedBy and not b.breaking then
			local offset = body.Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local distance = flat.Magnitude
			local facing = distance < 0.01 or flat.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) > 0.3
			if distance < bestDistance and facing then
				best, bestDistance = b, distance
			end
		end
	end
	return best
end

function Bales.fromPart(part)
	return byBody[part] or (part.Parent and byBody[part.Parent]) or nil
end

-- True when the bale rests on the drop-off pad (checked in the pad's own flat space, ignoring height).
function Bales.isAtDropOff(b)
	if not dropOff or b.gone then
		return false
	end
	local spot = dropOff.CFrame:PointToObjectSpace(b.body.Position)
	return math.abs(spot.X) <= dropOff.Size.X / 2 and math.abs(spot.Z) <= dropOff.Size.Z / 2 and spot.Y < 8
end

-- Bales left out in the world disappear after a while. Bales on the drop-off pad, in a truck, or in a neat stack of
-- Config.StackMin or more are kept.
local function startDespawnTimer(b)
	b.dropToken += 1
	local token = b.dropToken
	local function check()
		if b.gone or b.carriedBy or b.home or b.dropToken ~= token then
			return
		end
		if Bales.isAtDropOff(b) or b.body:GetAttribute("InTruck") or b.inStack then
			task.delay(Config.DroppedBaleSeconds, check) -- still stored or riding in a truck, look again later
			return
		end
		Bales.consume(b)
	end
	task.delay(Config.DroppedBaleSeconds, check)
end

function Bales.setDropOff(part)
	dropOff = part
end

-- A home bale is gone from its spot (smashed or lifted), so a fresh one grows back there.
local function scheduleRegrow(b)
	if not b.home then
		return
	end
	b.home = false
	local function regrow()
		-- Wait while anything (a bale put back on its spot, say) is in the way, so a new bale never spawns inside it.
		local center = b.spawnPosition + Vector3.new(0, SIZE.Y / 2, 0)
		for _, part in workspace:GetPartBoundsInBox(CFrame.new(center), SIZE * 0.9) do
			if Bales.fromPart(part) then
				task.delay(5, regrow)
				return
			end
		end
		local fresh = Bales.spawn(b.spawnPosition, true, true, b.hayType)
		if b.onRegrow then
			b.onRegrow(fresh)
		end
	end
	task.delay(Config.BaleRefillSeconds, regrow)
end

local function debrisPart(shape, size, cframe, color, material, velocity)
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.CollisionGroup = Groups.Loose
	part.AssemblyLinearVelocity = velocity
	part.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
	part.Parent = Hay.folder
	task.delay(7, function()
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(1), { Transparency = 1 }):Play()
			Debris:AddItem(part, 1.1)
		end
	end)
	return part
end

-- Straw and dust thrown up when the bale bursts.
local function burstEffects(position, hayType)
	local look = Hay.look(hayType)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position
	anchor.Parent = Hay.folder

	local straw = Instance.new("ParticleEmitter")
	straw.Rate = 0
	straw.Lifetime = NumberRange.new(0.6, 1.1)
	straw.Speed = NumberRange.new(10, 22)
	straw.SpreadAngle = Vector2.new(180, 180)
	straw.Acceleration = Vector3.new(0, -25, 0)
	straw.Color = ColorSequence.new(hayColor(hayType))
	straw.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	straw.Parent = anchor

	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.8, 1.4)
	dust.Speed = NumberRange.new(3, 8)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Color = ColorSequence.new(Color3.fromRGB(look.dust[1], look.dust[2], look.dust[3]))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust.Parent = anchor

	straw:Emit(40)
	dust:Emit(18)
	-- The stranger hays throw up a few drifting specks: ash embers, frost, crystal glints, star dust.
	if look.motes then
		local motes = Instance.new("ParticleEmitter")
		motes.Rate = 0
		motes.Lifetime = NumberRange.new(1.2, 2.2)
		motes.Speed = NumberRange.new(1, 4)
		motes.SpreadAngle = Vector2.new(180, 180)
		motes.Acceleration = Vector3.new(0, 1.5, 0)
		motes.LightEmission = 0.6
		motes.Color = ColorSequence.new(Color3.fromRGB(look.motes[1], look.motes[2], look.motes[3]))
		motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		motes.Parent = anchor
		motes:Emit(24)
	end
	Debris:AddItem(anchor, 2.5)
end

-- The shovel cuts a bale open: it shudders, the twine snaps, the bale bursts into flakes, and the hay
-- pours out in three waves into a pile.
function Bales.breakOpen(player, b)
	if b.gone or b.carriedBy or b.breaking then
		return
	end
	b.breaking = true
	setUsable(b, false)
	Tutorial.mark(player, "broke")
	scheduleRegrow(b)

	task.spawn(function()
		local body = b.body
		body.Anchored = true
		body.AssemblyLinearVelocity = Vector3.zero
		local rest = body.CFrame
		for _ = 1, 6 do
			body.CFrame = rest * CFrame.new(rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.1, 0.1), rng:NextNumber(-0.2, 0.2))
			task.wait(0.04)
		end

		local center = rest.Position
		-- Which hay this bale holds (set by whoever placed it; meadow by default). Its strands carry it on.
		local hayType = b.body:GetAttribute("HayType") or "meadow"
		-- A rich field (WorldMap.luau) marks its bales with NeedleBoost: that many times the needles.
		local boost = b.body:GetAttribute("NeedleBoost") or 1
		local mutation = b.body:GetAttribute("MutationBoost") -- a Hay Market bale's mutation odds ride on its strands
		local wet = b.body:GetAttribute("Wet") == true -- a soaked bale spills soaked hay
		-- A golden field bale (1 in GoldenBaleOneIn) holds GoldenBaleNeedles times the needles on top of that.
		local golden = b.body:GetAttribute("GoldenField") == true
		if golden then
			boost *= Config.GoldenBaleNeedles
			Announce.say(("%s broke open a golden bale!"):format(player.DisplayName), "gold")
		end
		-- The play-together bonus only stacks up to Prices.Boosts.Cap (Boosts.fit, CEO H13); its strands keep the result.
		if b.body:GetAttribute("TogetherBoost") == true then
			local together = LandConfig.TogetherBonus or 1
			boost = Boosts.fit(BOOST_TERMS, boost / together, 1, together, 1)
		end
		Bales.consume(b)
		burstEffects(center + Vector3.new(0, 1.5, 0), hayType)
		Feedback.play("BaleBurst", center)
		Feedback.juice(player, "burst")
		Events.fire(player, "bale_broken", 1, { position = center, hayType = hayType })
		-- The first bale a player ever breaks always shows them a glinting needle: that is the hook.
		-- A sorted bale has had its needles taken out, so it spills none.
		local sorted = b.sorted == true
		local promiseNeedle = not sorted and Gloves.firstBaleBreak(player)

		local baleOwner = player.UserId
		-- The twine snaps and flies off, and the bale's packed hay bursts into flakes.
		for _, x in TWINE_X do
			debrisPart(
				Enum.PartType.Block,
				Vector3.new(0.12, 0.12, SIZE.Z + 0.5),
				rest * CFrame.new(x, SIZE.Y / 2, 0),
				TWINE,
				Enum.Material.Fabric,
				Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(10, 14), rng:NextNumber(-6, 6))
			)
		end
		for i = 1, 6 do
			local x = -SIZE.X / 2 + (i - 0.5) * SIZE.X / 6
			local flake = rest * CFrame.new(x, 0, 0)
			local out = (flake.Position - center).Unit
			debrisPart(
				Enum.PartType.Block,
				Vector3.new(SIZE.X / 6, SIZE.Y * 0.8, SIZE.Z * 0.8),
				flake,
				hayColor(hayType),
				Enum.Material.Fabric,
				out * rng:NextNumber(6, 10) + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(5, 9), rng:NextNumber(-2, 2))
			)
		end

		-- The hay pours out in waves so it looks like it spills, not like it teleports. It comes out in clumps of a few
		-- strands (Config.StrandsPerClump), every strand of the bale accounted for.
		local waves = 3
		local clumps = HayMath.clumps(Config.PiecesPerBale, Config.StrandsPerClump or 1)
		local perWave = math.ceil(#clumps / waves)
		for wave = 1, waves do
			for k = (wave - 1) * perWave + 1, math.min(wave * perWave, #clumps) do
				local offset = Vector3.new(rng:NextNumber(-1.2, 1.2), 2 + wave * 0.5, rng:NextNumber(-1.2, 1.2))
				local velocity = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(3, 8), rng:NextNumber(-4, 4))
				local piece = Hay.spawnPiece(center + offset, velocity, baleOwner, nil, hayType, clumps[k])
				piece:SetAttribute("HayType", hayType)
				if boost ~= 1 then
					piece:SetAttribute("NeedleBoost", boost)
				end
				if mutation then
					piece:SetAttribute("MutationBoost", mutation)
				end
				if sorted then
					piece:SetAttribute("Sorted", true)
				end
				if wet then
					Bales.wetPiece(piece)
				end
			end
			-- Now and then a needle tumbles out with the hay.
			if not sorted and (rng:NextNumber() < Config.VisibleNeedleChance * boost or (promiseNeedle and wave == waves)) then
				promiseNeedle = false
				local offset = Vector3.new(rng:NextNumber(-1, 1), 2 + wave * 0.5, rng:NextNumber(-1, 1))
				local needle = Hay.spawnPiece(
					center + offset,
					Vector3.new(rng:NextNumber(-3, 3), 5, rng:NextNumber(-3, 3)),
					baleOwner,
					"Needle",
					hayType
				)
				Feedback.needle(needle, Hay.needleValue(needle))
			end
			task.wait(0.22)
		end
		-- Once in a while something odd was baled up with the hay (Config/Finds).
		if not sorted then
			Finds.roll(center + Vector3.new(0, 2, 0), baleOwner)
		end
	end)
end

function Bales.pickup(player, b)
	local state = Data.get(player)
	local root = Avatar.getRoot(player)
	if not state or not root or b.gone or b.carriedBy or b.breaking then
		return
	end
	-- One bale in your arms, or two (one on top of the other) with Reinforced gloves or better.
	local second = state.carryBale ~= nil
	if second and (state.carryExtra or not Bales.canDoubleCarry(player)) then
		return
	end
	if Avatar.equippedKind(player) ~= nil then
		return -- only bare hands lift a whole bale; with a tool out, a click belongs to the tool
	end
	if (b.body.Position - root.Position).Magnitude > Config.PickupReach + 4 then
		return
	end

	b.carriedBy = player
	b.ownerId = b.ownerId or player.UserId -- the first to haul it keeps it, so nobody can lift another's bale to sell
	b.dropToken += 1
	if second then
		state.carryExtra = b
	else
		state.carryBale = b
	end

	-- The bale itself is welded in front of the player, so what you carry is the real bale. A second rides on top.
	local offset = second and CARRY_OFFSET * CFrame.new(0, SIZE.Y + 0.05, 0) or CARRY_OFFSET
	b.body.Anchored = false
	b.body.CanCollide = false
	b.body.Massless = true
	b.body.CFrame = root.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = b.body
	weld.C0 = offset
	weld.Parent = b.body
	b.carryWeld = weld
	b.prompt.ActionText = "Put down"

	scheduleRegrow(b)
	Feedback.play("BaleLift", b.body)
	Avatar.setCarry(player)
	Avatar.refreshSpeed(player) -- setCarry skips this when already carrying, and the second bale weighs too
	Data.sync(player)
end

-- True when this player's gloves are good enough to carry two bales at once (Config.DoubleCarryTier).
function Bales.canDoubleCarry(player)
	local glove = Gloves.get(player)
	return glove ~= nil and (glove.tier or 0) >= Config.DoubleCarryTier
end

-- Sets a bale down square to the player on top of whatever is in front: the ground, or another bale, so bales stack.
local function setDown(b, root)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local spot = root.Position + flat * (SIZE.Z / 2 + 2.2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { b.body, root.Parent, Hay.folder }
	local down = workspace:Raycast(spot + Vector3.new(0, Config.StackReach, 0), Vector3.new(0, -Config.StackReach - 20, 0), params)
	local floorY = down and down.Position.Y or (root.Position.Y - 3)
	local center = Vector3.new(spot.X, floorY + SIZE.Y / 2 + 0.05, spot.Z)
	b.body.CFrame = CFrame.lookAt(center, center + flat)
	b.body.Massless = false
	b.body.CanCollide = true
	b.body.Anchored = false
	b.body.AssemblyLinearVelocity = Vector3.zero
	b.body.AssemblyAngularVelocity = Vector3.zero
	b.prompt.ActionText = "Pick up"
	-- A set-down bale is a loose physical block: never welded or anchored, so it can ride in a truck bed and slide
	-- or tip like real cargo. Roblox picks its network owner automatically, so a bale in a moving truck follows the
	-- driver's physics instead of lagging behind.
	pcall(function()
		b.body:SetNetworkOwnershipAuto()
	end)
end

-- Lobs a bale forward from where it is held. power 0..1 sets the range, from a short toss to Config.TossRange studs
-- on flat ground. The bale flies loose with real physics and lands however it lands.
local function toss(b, root, power, lift)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	-- A 45 degree lob: speed for the range under this place's gravity, the same up and forward.
	local speed = HayMath.tossSpeed(power, Config, workspace.Gravity)
	b.body.Massless = false
	b.body.CanCollide = true
	b.body.Anchored = false
	b.body.CFrame = b.body.CFrame + Vector3.new(0, lift, 0)
	b.prompt.ActionText = "Pick up"
	-- The server flies it, so the throw is the same for everyone, then hands it back to Roblox once it has landed.
	pcall(function()
		b.body:SetNetworkOwner(nil)
	end)
	b.body.AssemblyLinearVelocity = flat * speed + Vector3.new(0, speed, 0) + root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	b.body.AssemblyAngularVelocity = root.CFrame.RightVector * -rng:NextNumber(1, 3)
	local token = b.dropToken
	task.delay(Config.TossFlightSeconds, function()
		if not b.gone and not b.carriedBy and b.dropToken == token and not b.body:GetAttribute("InTruck") then
			pcall(function()
				b.body:SetNetworkOwnershipAuto()
			end)
		end
	end)
end

-- Lets go of everything the player holds (the carried bale and a second on top). Returns the bales, bottom first,
-- or nil if a carried bale has gone away (then the player's hands are simply freed).
local function letGo(player, state)
	local held = {}
	for _, b in { state.carryBale, state.carryExtra } do
		if b and not b.gone then
			if b.carryWeld then
				b.carryWeld:Destroy()
				b.carryWeld = nil
			end
			b.carriedBy = nil
			table.insert(held, b)
		end
	end
	state.carryBale = nil
	state.carryExtra = nil
	Data.sync(player)
	Avatar.clearCarry(player)
	return held
end

-- Put the carried bale down in front of you. It lands square on the ground or on top of the bale there. A second
-- carried bale goes down on top of the first.
function Bales.drop(player)
	local state = Data.get(player)
	if not state or not state.carryBale then
		return
	end
	local root = Avatar.getRoot(player)
	for _, b in letGo(player, state) do
		if not root or not root.Parent then
			Bales.consume(b)
		else
			setDown(b, root)
			Feedback.play("BaleSetDown", b.body)
			startDespawnTimer(b)
		end
	end
end

-- Crew hand-offs. Set by whoever knows the farm crews (Land.luau, or Tools.luau's fallback):
-- function(thrower, catcher) -> true when catcher may catch thrower's bales.
Bales.isTeammate = nil

-- While a thrown bale is in the air, a bare-handed teammate it flies close to catches it (Config.CatchRadius), so a
-- crew can pass bales down a line into a truck bed.
function Bales.watchForCatch(b, thrower)
	if not Bales.isTeammate then
		return
	end
	local token = b.dropToken
	local started = os.clock()
	task.spawn(function()
		while os.clock() - started < Config.CatchWindowSeconds do
			task.wait()
			if b.gone or b.carriedBy or b.dropToken ~= token then
				return
			end
			-- Not in the thrower's own crew's hands at the very start: someone standing beside the thrower lets it fly.
			if os.clock() - started < 0.2 then
				continue
			end
			-- Landed and settled: too late to catch.
			if os.clock() - started > 0.3 and b.body.AssemblyLinearVelocity.Magnitude < 2 then
				return
			end
			for _, player in Players:GetPlayers() do
				if player ~= thrower then
					local root = Avatar.getRoot(player)
					if
						root
						and (root.Position - b.body.Position).Magnitude <= Config.CatchRadius
						and Bales.isTeammate(thrower, player)
					then
						local state = Data.get(player)
						local free = state and (not state.carryBale or (not state.carryExtra and Bales.canDoubleCarry(player)))
						if free and Avatar.equippedKind(player) == nil then
							Bales.pickup(player, b)
							if b.carriedBy == player then
								Feedback.play("BaleLift", b.body, 1.2)
								Events.fire(player, "bale_caught", 1, { from = thrower.UserId })
								return
							end
						end
					end
				end
			end
		end
	end)
end

-- Throw the carried bale(s) forward. power is 0..1 from how long the throw was charged. A tiny power (a plain click)
-- just sets the bale down instead.
function Bales.toss(player, power)
	local state = Data.get(player)
	if not state or not state.carryBale then
		return
	end
	power = typeof(power) == "number" and power == power and math.clamp(power, 0, 1) or 0
	local root = Avatar.getRoot(player)
	if not root or power < Config.TossMinPower then
		Bales.drop(player)
		return
	end
	for i, b in letGo(player, state) do
		toss(b, root, power, (i - 1) * 0.2)
		Feedback.play("BaleLift", b.body, 0.8)
		startDespawnTimer(b)
		Bales.watchForCatch(b, player)
	end
end

-- Loads a bale into something the player moves (a wheelbarrow): welded to anchor at offset, out of play until
-- released. Returns true if it was loaded.
function Bales.stow(player, b, anchor, offset)
	if b.gone or b.carriedBy or b.breaking then
		return false
	end
	b.carriedBy = player
	b.ownerId = b.ownerId or player.UserId -- the first to haul it keeps it, so nobody can lift another's bale to sell
	b.dropToken += 1
	setUsable(b, false)
	b.body.Anchored = false
	b.body.CanCollide = false
	b.body.CanQuery = false -- so bales set down from the same barrow stack on the ground, not on this one
	b.body.Massless = true
	b.body.CFrame = anchor.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = anchor
	weld.Part1 = b.body
	weld.C0 = offset
	weld.Parent = b.body
	b.carryWeld = weld
	scheduleRegrow(b)
	Feedback.play("BaleLift", b.body)
	return true
end

-- Takes a stowed bale out and drops it loose at cframe (into a truck bed, say), with real physics from there.
function Bales.releaseAt(b, cframe)
	if b.gone then
		return
	end
	if b.carryWeld then
		b.carryWeld:Destroy()
		b.carryWeld = nil
	end
	b.carriedBy = nil
	setUsable(b, true)
	b.body.CFrame = cframe
	b.body.Massless = false
	b.body.CanCollide = true
	b.body.CanQuery = true
	b.body.Anchored = false
	b.body.AssemblyLinearVelocity = Vector3.zero
	b.body.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		b.body:SetNetworkOwnershipAuto()
	end)
	Feedback.play("BaleSetDown", b.body)
	startDespawnTimer(b)
end

-- Takes a stowed bale out and sets it down in front of the player (or gets rid of it if the player is gone).
function Bales.release(b, root)
	if b.gone then
		return
	end
	if b.carryWeld then
		b.carryWeld:Destroy()
		b.carryWeld = nil
	end
	b.carriedBy = nil
	setUsable(b, true)
	if not root or not root.Parent then
		Bales.consume(b)
		return
	end
	setDown(b, root)
	b.body.CanQuery = true
	Feedback.play("BaleSetDown", b.body)
	startDespawnTimer(b)
end

-- position is the ground point under the bale. home bales regrow after being smashed or lifted, as the same hay.
-- hayType is a Config/Gloves hay (meadow when nil). Set b.onRegrow(newBale) to hear about the bale that grows back.
function Bales.spawn(position, home, fadeIn, hayType)
	local body, prompt = buildBale(position, hayType)
	local b = {
		hayType = hayType,
		body = body,
		prompt = prompt,
		home = home,
		spawnPosition = position,
		carriedBy = nil,
		ownerId = nil,
		carryWeld = nil,
		dropToken = 0,
		breaking = false,
		gone = false,
	}
	byBody[body] = b
	-- Now and then a field bale grows golden: it glints, and holds Config.GoldenBaleNeedles times the needles.
	if home and rng:NextInteger(1, Config.GoldenBaleOneIn) == 1 then
		Bales.makeGolden(b, fadeIn)
	end
	body.Parent = folder

	if fadeIn then
		local info = TweenInfo.new(0.7)
		for _, part in { body, unpack(body:GetDescendants()) } do
			if part:IsA("BasePart") and part.Transparency < 1 then
				local shown = part.Transparency
				part.Transparency = 1
				TweenService:Create(part, info, { Transparency = shown }):Play()
			end
		end
	end

	prompt.Triggered:Connect(function(player)
		if b.carriedBy == player then
			Bales.drop(player)
		elseif not b.carriedBy then
			Bales.pickup(player, b)
		end
	end)
	return b
end

-- Turns a bale golden: gold twine-wrapped hay with a glint and a soft glow, named in its button. announce tells the
-- server one has grown (left off for the bales placed when the world is built, so the start isn't a flood).
function Bales.makeGolden(b, announce)
	local body = b.body
	body:SetAttribute("GoldenField", true)
	body.Color = Color3.fromRGB(222, 182, 72)
	body.Material = Enum.Material.Fabric
	for _, d in body:GetDescendants() do
		if d:IsA("MeshPart") or (d:IsA("BasePart") and d.Name ~= "Twine") then
			pcall(function()
				d.Color = Color3.fromRGB(222, 182, 72)
			end)
		elseif d:IsA("SpecialMesh") then
			d.VertexColor = Vector3.new(1.25, 1.05, 0.45)
		end
	end
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(255, 226, 130)
	sparkles.Parent = body
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 214, 120)
	light.Brightness = 1.2
	light.Range = 10
	light.Parent = body
	b.prompt.ObjectText = "Golden " .. (b.prompt.ObjectText ~= "" and b.prompt.ObjectText or "bale")
	if announce then
		local hay = GloveConfig.HayTypes[b.hayType or "meadow"]
		Announce.say(("A golden bale has grown in the %s fields!"):format(hay and hay.map or "Meadow"), "gold")
	end
end

-- Wet hay (Config.WetWeather). A wet bale is darker and drips; its weight (Gloves) and price (Gameplay) follow the
-- Wet attribute.
local WET_DARKEN = 0.62

local function tintAll(body, factor)
	for _, d in { body, unpack(body:GetDescendants()) } do
		if d:IsA("BasePart") and d.Name ~= "Twine" then
			local base = d:GetAttribute("DryColor")
			if factor < 1 then
				if not base then
					d:SetAttribute("DryColor", d.Color)
					base = d.Color
				end
				d.Color = Color3.new(base.R * factor, base.G * factor, base.B * factor)
			elseif base then
				d.Color = base
				d:SetAttribute("DryColor", nil)
			end
		end
	end
end

-- Soaks a bale: heavier, worth less, darker, and dripping until it dries.
function Bales.wet(b)
	if b.gone or b.body:GetAttribute("Wet") then
		return false
	end
	b.body:SetAttribute("Wet", true)
	b.dryFor = 0
	tintAll(b.body, WET_DARKEN)
	local drips = Instance.new("ParticleEmitter")
	drips.Name = "WetDrips"
	drips.Rate = 6
	drips.Lifetime = NumberRange.new(0.4, 0.7)
	drips.Speed = NumberRange.new(0, 0.5)
	drips.Acceleration = Vector3.new(0, -30, 0)
	drips.EmissionDirection = Enum.NormalId.Bottom
	drips.Size = NumberSequence.new(0.08)
	drips.Color = ColorSequence.new(Color3.fromRGB(170, 190, 210))
	drips.Transparency = NumberSequence.new(0.3, 1)
	drips.Parent = b.body
	return true
end

-- Dries a wet bale (the sun, or Conveyor's drying rack). Returns true if it was wet.
function Bales.dry(b)
	if b.gone or not b.body:GetAttribute("Wet") then
		return false
	end
	b.body:SetAttribute("Wet", nil)
	b.rainFor, b.dryFor = 0, 0
	tintAll(b.body, 1)
	local drips = b.body:FindFirstChild("WetDrips")
	if drips then
		drips:Destroy()
	end
	return true
end

-- Marks a loose strand as wet (spilled from a wet bale, or poured from a wet load).
function Bales.wetPiece(piece)
	piece:SetAttribute("Wet", true)
	local c = piece.Color
	piece.Color = Color3.new(c.R * WET_DARKEN, c.G * WET_DARKEN, c.B * WET_DARKEN)
end

-- Whether rain falls on this spot: its region is in wet weather and nothing overhead shelters it.
local skyParams = RaycastParams.new()
skyParams.FilterType = Enum.RaycastFilterType.Exclude
function Bales.rainingOn(position, ignore)
	local region = WorldRegions.at(position)
	if not region or not Config.WetWeather[Weather.get(region.id)] then
		return false
	end
	skyParams.FilterDescendantsInstances = ignore
	return workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, 120, 0), skyParams) == nil
end

-- Every few seconds: bales out in the rain soak, wet bales out of it dry.
local WEATHER_TICK = 5
local function weatherTick()
	local ignore = { folder, Hay.folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, b in byBody do
		if not b.gone and not b.carriedBy and not b.breaking and b.body.Parent then
			if Bales.rainingOn(b.body.Position, ignore) then
				b.dryFor = 0
				b.rainFor = (b.rainFor or 0) + WEATHER_TICK
				if b.rainFor >= Config.WetSoakSeconds then
					Bales.wet(b)
				end
			else
				b.rainFor = 0
				if b.body:GetAttribute("Wet") then
					b.dryFor = (b.dryFor or 0) + WEATHER_TICK
					if b.dryFor >= Config.WetDrySeconds then
						Bales.dry(b)
					end
				end
			end
		end
	end
end

-- The "Stack N" label over the top of a neat stack.
local function stackLabel(top, n)
	local gui = top.body:FindFirstChild("StackLabel")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "StackLabel"
		gui.Size = UDim2.fromOffset(90, 28)
		gui.StudsOffset = Vector3.new(0, SIZE.Y / 2 + 1.2, 0)
		gui.MaxDistance = 50
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.TextColor3 = Color3.fromRGB(240, 214, 140)
		text.TextStrokeTransparency = 0.4
		text.Parent = gui
		gui.Parent = top.body
	end
	gui.Text.Text = ("Stack %d"):format(n)
end

-- Finds neat stacks: bales resting one on another, square on top within a stud or so. Every bale in a stack of
-- Config.StackMin or more is marked inStack (kept, see startDespawnTimer) and the top one shows the count.
local function scanStacks()
	local list = {}
	for _, b in byBody do
		if not b.gone and not b.carriedBy and not b.breaking and b.body.Parent then
			b.wasInStack, b.inStack = b.inStack, false
			table.insert(list, b)
		end
	end
	table.sort(list, function(a, c)
		return a.body.Position.Y < c.body.Position.Y
	end)
	local columns = {}
	for _, b in list do
		local p = b.body.Position
		local placed = false
		for _, column in columns do
			local top = column[#column].body.Position
			local flat = Vector3.new(p.X - top.X, 0, p.Z - top.Z).Magnitude
			if flat < 1.4 and math.abs(p.Y - top.Y - SIZE.Y) < 0.6 then
				table.insert(column, b)
				placed = true
				break
			end
		end
		if not placed then
			table.insert(columns, { b })
		end
	end
	for _, column in columns do
		local neat = #column >= Config.StackMin
		for _, b in column do
			b.inStack = neat
		end
		if neat then
			stackLabel(column[#column], #column)
		end
	end
	for _, b in list do
		local label = b.body:FindFirstChild("StackLabel")
		local isTop = false
		if b.inStack then
			for _, column in columns do
				if column[#column] == b then
					isTop = true
				end
			end
		end
		if label and not isTop then
			label:Destroy()
		end
		-- A bale that just left a stack starts its normal countdown again.
		if b.wasInStack and not b.inStack and not b.home then
			startDespawnTimer(b)
		end
		b.wasInStack = nil
	end
end

-- A bale does not stay stuck to a player who left the game: whatever they held goes, and their hands are free.
function Bales.playerLeft(player)
	for _, b in byBody do
		if b.carriedBy == player and not b.gone then
			Bales.consume(b)
		end
	end
	local state = Data.get(player)
	if state then
		state.carryBale = nil
		state.carryExtra = nil
	end
end

function Bales.init(worldFolder)
	folder = worldFolder

	task.spawn(function()
		while true do
			task.wait(WEATHER_TICK)
			local ok, err = pcall(weatherTick)
			if not ok then
				warn("[Needlewood] wet bales: " .. tostring(err))
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(scanStacks)
			if not ok then
				warn("[Needlewood] bale stacks: " .. tostring(err))
			end
		end
	end)

	local function watch(player)
		local function onCharacter(character)
			local humanoid = character:WaitForChild("Humanoid")
			humanoid.Died:Connect(function()
				Bales.drop(player)
			end)
		end
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			task.spawn(onCharacter, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	Players.PlayerRemoving:Connect(Bales.playerLeft)
end

return Bales
