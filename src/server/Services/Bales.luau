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
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)
local Hay = require(script.Parent.Hay)
local Groups = require(script.Parent.Groups)
local Tutorial = require(script.Parent.Tutorial)
local Props = require(script.Parent.Props)
local Gloves = require(script.Parent.Gloves)
local Feedback = require(script.Parent.Feedback)
local Events = require(script.Parent.Events)

local Bales = {}

local rng = Random.new()
local folder = nil
local dropOff = nil -- the pad where set-down bales are kept for later
local byBody = {} -- bale body part -> bale record

local SIZE = Vector3.new(4.6, 2.6, 3.2) -- length, height, depth of one bale
local CARRY_OFFSET = CFrame.new(0, 0.4, -2.8)
local HAY = Color3.fromRGB(189, 168, 112) -- rustic palette: muted, weathered
local TWINE = Color3.fromRGB(97, 84, 66)
local TWINE_X = { -1.2, 1.2 } -- two bands of twine around the bale

local function buildBale(position)
	local body = Instance.new("Part")
	body.Name = "HayBale"
	body:SetAttribute("HayType", "meadow") -- Config/Gloves hay type; set another for rarer bales
	body.Size = SIZE
	body.CFrame = CFrame.new(position + Vector3.new(0, SIZE.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0)
	body.Color = HAY
	body.Material = Enum.Material.Fabric
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Anchored = true
	-- Heavy and grippy with no bounce, so a stack settles instead of sliding apart.
	body.CustomPhysicalProperties = PhysicalProperties.new(1.2, 1.2, 0, 1, 1)

	-- The Rustic bale mesh, stretched over the hitbox so stacking and carrying work exactly as before. The body
	-- stays the real physics block and click target. Each client hides the part look once the mesh has loaded.
	local mesh = Props.make("hay_bale", body.CFrame, SIZE)
	if mesh then
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
	prompt.ObjectText = "Hay bale"
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

-- Bales left out in the world disappear after a while. Bales on the drop-off pad are kept.
local function startDespawnTimer(b)
	b.dropToken += 1
	local token = b.dropToken
	local function check()
		if b.gone or b.carriedBy or b.home or b.dropToken ~= token then
			return
		end
		if Bales.isAtDropOff(b) or b.body:GetAttribute("InTruck") then
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
local function burstEffects(position)
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
	straw.Color = ColorSequence.new(HAY)
	straw.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	straw.Parent = anchor

	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.8, 1.4)
	dust.Speed = NumberRange.new(3, 8)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Color = ColorSequence.new(Color3.fromRGB(175, 160, 125))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust.Parent = anchor

	straw:Emit(40)
	dust:Emit(18)
	Debris:AddItem(anchor, 2.5)
end

-- The shovel cuts a bale open: it shudders, the twine snaps, the bale bursts into flakes, and the hay
-- pours out in three waves into a pile.
function Bales.breakOpen(player, b)
	if b.gone or b.carriedBy or b.breaking then
		return
	end
	b.breaking = true
	b.prompt.Enabled = false
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
		Bales.consume(b)
		burstEffects(center + Vector3.new(0, 1.5, 0))
		Feedback.play("BaleBurst", center)
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
				HAY,
				Enum.Material.Fabric,
				out * rng:NextNumber(6, 10) + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(5, 9), rng:NextNumber(-2, 2))
			)
		end

		-- The hay pours out in waves so it looks like it spills, not like it teleports.
		local waves = 3
		local perWave = math.ceil(Config.PiecesPerBale / waves)
		for wave = 1, waves do
			for _ = 1, perWave do
				local offset = Vector3.new(rng:NextNumber(-1.2, 1.2), 2 + wave * 0.5, rng:NextNumber(-1.2, 1.2))
				local velocity = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(3, 8), rng:NextNumber(-4, 4))
				local piece = Hay.spawnPiece(center + offset, velocity, baleOwner)
				piece:SetAttribute("HayType", hayType)
				if boost ~= 1 then
					piece:SetAttribute("NeedleBoost", boost)
				end
				if sorted then
					piece:SetAttribute("Sorted", true)
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
	end)
end

function Bales.pickup(player, b)
	local state = Data.get(player)
	local root = Avatar.getRoot(player)
	if not state or not root or state.carryBale or b.gone or b.carriedBy or b.breaking then
		return
	end
	if Avatar.equippedKind(player) ~= nil then
		return -- only bare hands lift a whole bale; with a tool out, a click belongs to the tool
	end
	if (b.body.Position - root.Position).Magnitude > Config.PickupReach + 4 then
		return
	end

	b.carriedBy = player
	b.ownerId = player.UserId
	b.dropToken += 1
	state.carryBale = b

	-- The bale itself is welded in front of the player, so what you carry is the real bale.
	b.body.Anchored = false
	b.body.CanCollide = false
	b.body.Massless = true
	b.body.CFrame = root.CFrame * CARRY_OFFSET
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = b.body
	weld.C0 = CARRY_OFFSET
	weld.Parent = b.body
	b.carryWeld = weld
	b.prompt.ActionText = "Put down"

	scheduleRegrow(b)
	Feedback.play("BaleLift", b.body)
	Avatar.setCarry(player)
	Data.sync(player)
end

-- Put the carried bale down in front of you. It lands square on the ground or on top of the bale there.
function Bales.drop(player)
	local state = Data.get(player)
	local b = state and state.carryBale
	if not b or b.gone then
		return
	end
	local root = Avatar.getRoot(player)
	state.carryBale = nil
	Data.sync(player)

	if b.carryWeld then
		b.carryWeld:Destroy()
		b.carryWeld = nil
	end
	b.carriedBy = nil

	if not root or not root.Parent then
		Bales.consume(b)
		return
	end

	-- Set it down square to the player on top of whatever is in front: the ground, or another bale, so bales stack.
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

	Feedback.play("BaleSetDown", b.body)
	Avatar.clearCarry(player)
	startDespawnTimer(b)
end

-- position is the ground point under the bale. home bales regrow after being smashed or lifted, as the same hay.
-- hayType is a Config/Gloves hay (meadow when nil). Set b.onRegrow(newBale) to hear about the bale that grows back.
function Bales.spawn(position, home, fadeIn, hayType)
	local body, prompt = buildBale(position)
	if hayType then
		body:SetAttribute("HayType", hayType)
	end
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

function Bales.init(worldFolder)
	folder = worldFolder

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

	-- A bale does not stay stuck to a player who left the game.
	Players.PlayerRemoving:Connect(function(player)
		for _, b in byBody do
			if b.carriedBy == player then
				Bales.consume(b)
			end
		end
	end)
end

return Bales
