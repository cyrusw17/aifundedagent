--!nonstrict
-- Loose hay pieces. A broken barrel leaves a pile of them. The shovel scoops pieces up, the rake drags them across
-- the ground, and pieces left on the sell pad sell. Every piece is a small real part.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Groups = require(script.Parent.Groups)

local Hay = {}

local rng = Random.new()
local pieces = {} -- piece part -> time it last moved or was made
local count = 0
local overlap = OverlapParams.new()

local COLORS = {
	Color3.fromRGB(232, 201, 90),
	Color3.fromRGB(220, 184, 70),
	Color3.fromRGB(244, 218, 120),
	Color3.fromRGB(205, 170, 60),
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
				if now - born > Config.LooseHayLifetime then
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
			if born < oldestTime then
				oldest, oldestTime = piece, born
			end
		end
		if not oldest then
			return
		end
		Hay.remove(oldest)
	end
end

function Hay.spawnPiece(position, velocity, ownerId)
	local piece = Instance.new("Part")
	piece.Name = "HayPiece"
	piece.Size = Vector3.new(rng:NextNumber(0.9, 1.5), 0.3, 0.3)
	piece.CFrame = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.3, 0.3))
	piece.Color = COLORS[rng:NextInteger(1, #COLORS)]
	piece.Material = Enum.Material.Fabric
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.CollisionGroup = Groups.Loose
	piece.CustomPhysicalProperties = PhysicalProperties.new(0.4, 1, 0, 1, 1)
	piece.AssemblyLinearVelocity = velocity
	piece.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
	piece:SetAttribute("OwnerId", ownerId)
	pieces[piece] = os.clock()
	count += 1
	piece.Parent = Hay.folder
	trim()
	return piece
end

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

-- The rake drags pieces toward the player and spreads them sideways, so a pile smears across the ground.
function Hay.rake(center, fromPosition, radius, ownerId)
	local moved = 0
	for _, piece in Hay.near(center, radius, nil) do
		local toward = Vector3.new(fromPosition.X - piece.Position.X, 0, fromPosition.Z - piece.Position.Z)
		local distance = toward.Magnitude
		if distance > 3 then
			local dir = toward.Unit
			local side = Vector3.new(-dir.Z, 0, dir.X) * rng:NextNumber(-7, 7)
			local speed = math.clamp(distance * 1.5, 8, 22)
			piece.AssemblyLinearVelocity = dir * speed + side + Vector3.new(0, rng:NextNumber(4, 8), 0)
			piece.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
		end
		piece:SetAttribute("OwnerId", ownerId)
		pieces[piece] = os.clock()
		moved += 1
	end
	return moved
end

return Hay
