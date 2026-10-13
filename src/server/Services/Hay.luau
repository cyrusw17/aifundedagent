--!nonstrict
-- Loose hay. A broken bale spills into a pile of small straw strands with the odd needle hidden among them. The
-- shovel scoops pieces up, the rake drags them across the ground, and pieces left on the sell pad sell. Every
-- strand is a small real part, capped at MaxLoosePieces so the server stays light.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Groups = require(script.Parent.Groups)
-- The game's one shared needle (Needle.luau, from the conveyor work) when it is present, so a needle spilled from
-- a bale looks, picks up and sells the same as one anywhere else. Without it, a local stand-in is used.
local NeedleModule = script.Parent:FindFirstChild("Needle")
local Needle = NeedleModule and require(NeedleModule)

local Hay = {}

local rng = Random.new()
local pieces = {} -- piece part -> time it last moved or was made
local count = 0
local overlap = OverlapParams.new()

local COLORS = {
	Color3.fromRGB(219, 204, 153),
	Color3.fromRGB(205, 189, 136),
	Color3.fromRGB(189, 168, 112),
	Color3.fromRGB(168, 149, 95),
	Color3.fromRGB(133, 115, 71),
	Color3.fromRGB(150, 148, 96), -- the odd greener stalk
}

Hay.folder = nil

function Hay.init(parent)
	local folder = Instance.new("Folder")
	folder.Name = "LooseHay"
	folder.Parent = parent
	Hay.folder = folder
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { folder }

	-- Hay nobody touches for a while shrinks away so the world never clogs up.
	task.spawn(function()
		while true do
			task.wait(3)
			local now = os.clock()
			for piece, born in pieces do
				-- Needles never fade: they stay physical until someone picks them up.
				if now - born > Config.LooseHayLifetime and not Hay.isNeedle(piece) then
					Hay.fadeOut(piece)
				end
			end
		end
	end)
end

function Hay.isPiece(part)
	return pieces[part] ~= nil
end

function Hay.remove(piece)
	if pieces[piece] then
		pieces[piece] = nil
		count -= 1
	end
	piece:Destroy()
end

function Hay.fadeOut(piece)
	if not pieces[piece] then
		return
	end
	pieces[piece] = nil
	count -= 1
	piece.CanCollide = false
	local tween = TweenService:Create(piece, TweenInfo.new(0.6), { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		piece:Destroy()
	end)
end

local function trim()
	while count > Config.MaxLoosePieces do
		local oldest, oldestTime = nil, math.huge
		for piece, born in pieces do
			if born < oldestTime and not Hay.isNeedle(piece) then
				oldest, oldestTime = piece, born
			end
		end
		if not oldest then
			return
		end
		Hay.remove(oldest)
	end
end

-- A loose strand of straw: thin, a little bent, in a spread of weathered hay colors.
local function makeStraw()
	local piece = Instance.new("Part")
	piece.Name = "Straw"
	piece.Size = Vector3.new(rng:NextNumber(0.5, 1.1), rng:NextNumber(0.1, 0.14), rng:NextNumber(0.1, 0.14))
	piece.Color = COLORS[rng:NextInteger(1, #COLORS)]
	piece.Material = Enum.Material.Fabric
	piece.CustomPhysicalProperties = PhysicalProperties.new(0.3, 1.2, 0, 1, 1)
	return piece
end

local function addGlint(piece)
	local glint = Instance.new("ParticleEmitter")
	glint.Name = "Glint"
	glint.Rate = 1.2
	glint.Lifetime = NumberRange.new(0.25, 0.4)
	glint.Speed = NumberRange.new(0)
	glint.LightEmission = 1
	glint.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	glint.Color = ColorSequence.new(Color3.new(1, 1, 1))
	glint.Parent = piece
end

-- A needle hiding in the hay: a thin steel sliver that catches the light now and then, so a sharp eye can spot it.
local function makeNeedle(cframe, ownerId)
	if Needle then
		local piece = Needle.make(cframe, ownerId)
		addGlint(piece)
		return piece
	end
	local piece = Instance.new("Part")
	piece.Name = "Needle"
	piece.Shape = Enum.PartType.Cylinder
	piece.Size = Vector3.new(0.75, 0.09, 0.09)
	piece.Color = Color3.fromRGB(196, 198, 202)
	piece.Material = Enum.Material.Metal
	piece.Reflectance = 0.35
	piece.CustomPhysicalProperties = PhysicalProperties.new(2, 0.8, 0, 1, 1)
	piece:SetAttribute("Needle", true)
	addGlint(piece)
	return piece
end

-- kind is "Needle" for a visible needle, otherwise a strand of straw.
function Hay.spawnPiece(position, velocity, ownerId, kind)
	local cframe = CFrame.new(position)
		* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.4, 0.4))
	local piece = kind == "Needle" and makeNeedle(cframe, ownerId) or makeStraw()
	piece.CFrame = cframe
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.CollisionGroup = Groups.Loose
	piece.AssemblyLinearVelocity = velocity
	piece.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
	piece:SetAttribute("OwnerId", ownerId)
	pieces[piece] = os.clock()
	count += 1
	-- A needle can be clicked up and destroyed elsewhere, so forget a piece however it leaves.
	piece.Destroying:Connect(function()
		if pieces[piece] then
			pieces[piece] = nil
			count -= 1
		end
	end)
	piece.Parent = Hay.folder
	-- The server simulates loose hay. Otherwise a nearby player's client owns each strand's physics and quietly
	-- overrides the rake's pull, which is why raking used to feel weak.
	pcall(function()
		piece:SetNetworkOwner(nil)
	end)
	trim()
	return piece
end

function Hay.isNeedle(part)
	if Needle and Needle.isNeedle(part) then
		return true
	end
	return part:GetAttribute("Needle") == true
end

-- What a found needle is worth: the shared needle's full value, or the raw $1 without it.
function Hay.needleValue(part)
	return Needle and Needle.value(part) or 1
end

-- True when needles are the shared kind, which players pick up by clicking rather than with the shovel.
Hay.sharedNeedles = Needle ~= nil

-- Pieces within radius of position, nearest first, at most max of them.
function Hay.near(position, radius, max)
	local found = {}
	for _, part in workspace:GetPartBoundsInRadius(position, radius, overlap) do
		if pieces[part] then
			table.insert(found, part)
		end
	end
	table.sort(found, function(a, b)
		return (a.Position - position).Magnitude < (b.Position - position).Magnitude
	end)
	while max and #found > max do
		table.remove(found)
	end
	return found
end

-- The scooped pieces leave the world at once and arc into the player's chest.
function Hay.flyToPlayer(root, list)
	for i, piece in list do
		if pieces[piece] then
			pieces[piece] = nil
			count -= 1
		end
		piece.Anchored = true
		piece.CanCollide = false
		local from = piece.Position
		task.delay((i - 1) * 0.04, function()
			local started = os.clock()
			local duration = Config.HayFlightSeconds
			while piece.Parent do
				local alpha = (os.clock() - started) / duration
				if alpha >= 1 or not root.Parent then
					break
				end
				local target = root.Position + Vector3.new(0, 1, 0)
				local control = (from + target) / 2 + Vector3.new(0, 4, 0)
				local inv = 1 - alpha
				local pos = inv * inv * from + 2 * inv * alpha * control + alpha * alpha * target
				piece.CFrame = CFrame.new(pos) * (piece.CFrame - piece.CFrame.Position) * CFrame.Angles(0.2, 0.3, 0)
				RunService.Heartbeat:Wait()
			end
			piece:Destroy()
		end)
	end
end

-- The rake gathers. For a short stroke every strand around the click slides along the ground toward a spot just in
-- front of the player, so a scattered spill gets pulled into a neat row. Strands keep their own fall and tumble a
-- little, but they are steered rather than flung, which suits small light straw.
function Hay.rake(center, gatherAt, radius, ownerId)
	local list = Hay.near(center, radius, nil)
	for _, piece in list do
		piece:SetAttribute("OwnerId", ownerId)
		pieces[piece] = os.clock()
		-- Each strand stops a slightly different distance short of the gather spot, so they pile in a row, not a point.
		piece:SetAttribute("RakeStop", rng:NextNumber(0.6, 2.2))
	end
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < Config.RakeStrokeSeconds do
			for _, piece in list do
				if piece.Parent and pieces[piece] then
					local toward = Vector3.new(gatherAt.X - piece.Position.X, 0, gatherAt.Z - piece.Position.Z)
					local distance = toward.Magnitude
					local fall = math.min(piece.AssemblyLinearVelocity.Y, 2)
					if distance > (piece:GetAttribute("RakeStop") or 1) then
						local speed = math.clamp(distance * 2.2, 3, Config.RakeMaxSpeed)
						piece.AssemblyLinearVelocity = toward.Unit * speed + Vector3.new(0, fall, 0)
					else
						piece.AssemblyLinearVelocity = Vector3.new(0, fall, 0)
					end
				end
			end
			RunService.Heartbeat:Wait()
		end
	end)
	return #list
end

return Hay
