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
local count = 0 -- loose straw strands (needles are counted apart, so they never crowd out new hay)
local needleCount = 0
local needleSet = {} -- piece -> true for the visible needles among the pieces

-- Forgets a piece however it leaves the world. Returns true if it was still known.
local function forget(piece)
	if not pieces[piece] then
		return false
	end
	pieces[piece] = nil
	if needleSet[piece] then
		needleSet[piece] = nil
		needleCount -= 1
	else
		count -= 1
	end
	return true
end
local overlap = OverlapParams.new()

local HayLooks = require(ReplicatedStorage.Shared.Config.HayLooks)

-- The look for a hay type (Config/HayLooks), meadow when unknown.
function Hay.look(hayType)
	return HayLooks[hayType or "meadow"] or HayLooks.meadow
end

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
				-- Needles stay much longer than straw, so there is time to find them, but not forever.
				local life = if needleSet[piece] or piece:GetAttribute("Strands")
					then Config.LooseNeedleLifetime
					else Config.LooseHayLifetime
				if now - born > life then
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
	forget(piece)
	piece:Destroy()
end

function Hay.fadeOut(piece)
	if not forget(piece) then
		return
	end
	piece.CanCollide = false
	local tween = TweenService:Create(piece, TweenInfo.new(0.6), { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		piece:Destroy()
	end)
end

-- Past the caps the oldest strand (or, for needles, the oldest needle) goes, so the server never fills up.
local function trimKind(isNeedle, over)
	while over() do
		local oldest, oldestTime = nil, math.huge
		for piece, born in pieces do
			-- Piles are a player's raked work, so the cap never takes them.
			local kindMatches = (needleSet[piece] == true) == isNeedle and not piece:GetAttribute("Strands")
			if born < oldestTime and kindMatches then
				oldest, oldestTime = piece, born
			end
		end
		if not oldest then
			return
		end
		Hay.remove(oldest)
	end
end

local function trim()
	trimKind(false, function()
		return count > Config.MaxLoosePieces
	end)
	trimKind(true, function()
		return needleCount > Config.MaxLooseNeedles
	end)
end

-- A loose strand of straw: thin, a little bent, in a spread of weathered hay colors.
-- A strand in its region's colors and shape.
local function makeStraw(hayType)
	local look = Hay.look(hayType)
	local c = look.colors[rng:NextInteger(1, #look.colors)]
	local thick = rng:NextNumber(look.thick[1], look.thick[2])
	local piece = Instance.new("Part")
	piece.Name = "Straw"
	piece.Size = Vector3.new(rng:NextNumber(look.length[1], look.length[2]), thick, thick * rng:NextNumber(0.85, 1.15))
	piece.Color = Color3.fromRGB(c[1], c[2], c[3])
	piece.Material = look.material and Enum.Material[look.material] or Enum.Material.Fabric
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
-- hayType picks the needle kind (a Pine bale spills Pine needles) when the shared needle knows how.
local function makeNeedle(cframe, ownerId, hayType)
	if Needle then
		local needleId = hayType and Needle.forHay and Needle.forHay(hayType) or nil
		local piece = Needle.make(cframe, ownerId, needleId)
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

-- kind is "Needle" for a visible needle (of the kind found in hayType), otherwise a strand of hayType's straw.
function Hay.spawnPiece(position, velocity, ownerId, kind, hayType)
	local cframe = CFrame.new(position)
		* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.4, 0.4))
	local piece = kind == "Needle" and makeNeedle(cframe, ownerId, hayType) or makeStraw(hayType)
	piece.CFrame = cframe
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.CollisionGroup = Groups.Loose
	piece.AssemblyLinearVelocity = velocity
	piece.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
	piece:SetAttribute("OwnerId", ownerId)
	pieces[piece] = os.clock()
	if kind == "Needle" then
		needleSet[piece] = true
		needleCount += 1
	else
		count += 1
	end
	-- A needle can be clicked up and destroyed elsewhere, so forget a piece however it leaves.
	piece.Destroying:Connect(function()
		forget(piece)
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
		forget(piece)
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
-- How many strands a loose piece stands for: 1, or a whole pile's worth.
function Hay.strandsIn(piece)
	return piece:GetAttribute("Strands") or 1
end

function Hay.isPile(piece)
	return piece:GetAttribute("Strands") ~= nil
end

-- Sizes a pile's mound to how much hay is in it.
local function shapePile(pile, n)
	local width = math.min(1.6 + n * 0.035, 6)
	local height = math.min(0.5 + n * 0.012, 2.2)
	pile.Size = Vector3.new(width, height, width * 0.85)
	pile:SetAttribute("Strands", n)
end

-- Takes n strands off a pile (for a scoop that has less room than the pile). The rest stays.
function Hay.takeFromPile(pile, n)
	local left = Hay.strandsIn(pile) - n
	if left <= 0 then
		Hay.remove(pile)
	else
		shapePile(pile, left)
	end
end

-- Packs the loose strands raked around a spot into one pile, once there are PileMin of them (an existing pile there
-- grows instead). Sorted hay only piles with sorted hay, so a pile is sorted or not as a whole.
local function packPile(at, ownerId)
	local groups = {}
	for _, piece in Hay.near(at, Config.PileRadius, nil) do
		if not needleSet[piece] then
			local key = piece:GetAttribute("Sorted") and "sorted" or "raw"
			groups[key] = groups[key] or { strands = 0, parts = {}, pile = nil }
			local g = groups[key]
			if Hay.isPile(piece) and not g.pile then
				g.pile = piece
			else
				table.insert(g.parts, piece)
			end
			g.strands += Hay.strandsIn(piece)
		end
	end
	for key, g in groups do
		if g.strands >= Config.PileMin and (#g.parts > 0) then
			local pile = g.pile
			if not pile then
				local first = g.parts[1]
				local hayType = first:GetAttribute("HayType") or "meadow"
				local look = Hay.look(hayType)
				local c = look.colors[1]
				pile = Instance.new("Part")
				pile.Name = "HayPile"
				pile.Color = Color3.fromRGB(c[1], c[2], c[3])
				pile.Material = Enum.Material.Fabric
				pile.CollisionGroup = Groups.Loose
				pile.CustomPhysicalProperties = PhysicalProperties.new(0.6, 1.5, 0, 1, 1)
				-- A rounded mound: a sphere mesh stretched to the part (a Ball part would have to stay round).
				local mound = Instance.new("SpecialMesh")
				mound.MeshType = Enum.MeshType.Sphere
				mound.Parent = pile
				pile:SetAttribute("HayType", hayType)
				if key == "sorted" then
					pile:SetAttribute("Sorted", true)
				end
				pile:SetAttribute("OwnerId", ownerId)
				shapePile(pile, g.strands)
				pile.CFrame = CFrame.new(at.X, at.Y + pile.Size.Y / 2, at.Z)
				pieces[pile] = os.clock()
				count += 1
				pile.Destroying:Connect(function()
					forget(pile)
				end)
				pile.Parent = Hay.folder
				pcall(function()
					pile:SetNetworkOwner(nil)
				end)
			end
			for _, piece in g.parts do
				Hay.remove(piece)
			end
			-- Grow it upward, so the bigger mound does not sink into the ground and pop out.
			local oldHeight = pile.Size.Y
			shapePile(pile, g.strands)
			pile.CFrame += Vector3.new(0, (pile.Size.Y - oldHeight) / 2, 0)
			pieces[pile] = os.clock()
		end
	end
end

function Hay.rake(center, gatherAt, radius, ownerId)
	local list = Hay.near(center, radius, nil)
	for _, piece in list do
		-- Raked straw is paid to the raker; a visible needle stays with whoever's bale it came from.
		if not needleSet[piece] then
			piece:SetAttribute("OwnerId", ownerId)
		end
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
		-- Raking a big enough heap together packs it into one pile the shovel can take at once.
		task.wait(0.25)
		packPile(gatherAt - Vector3.new(0, 2.5, 0), ownerId)
	end)
	return #list
end

return Hay
