--!nonstrict
-- Dresses conveyor tiles and line machines in their Rustic Blender meshes (Props.luau), when they were imported.
-- The part-built pieces keep doing all the work (collisions, belts, intake zones); the mesh only rides on top, and
-- each client swaps it in once it has loaded. Without Props or an import, nothing changes.
--
-- Rigged meshes carry moving pieces (Roller, Drum, Reel, Flywheel, Crank, Shaker). Those stay anchored where they were
-- placed and are tagged "PropMotion", and Conveyors.client.luau spins or shakes them. A piece inside a model with a
-- "Running" attribute only moves while that is true (a sorter while it sorts); other pieces always move.
local CollectionService = game:GetService("CollectionService")

local Props = script.Parent:FindFirstChild("Props") and require(script.Parent.Props)

local Skins = {}

local SPIN = { "Roller", "Drum", "Reel", "Flywheel", "Crank" }
local SHAKE = { "Shaker" }

-- Half the size of a part as seen along axis (world space).
local function reach(part, axis)
	local cf, s = part.CFrame, part.Size / 2
	return math.abs(cf.RightVector:Dot(axis)) * s.X + math.abs(cf.UpVector:Dot(axis)) * s.Y + math.abs(cf.LookVector:Dot(axis)) * s.Z
end

-- How far the model reaches along axis, end to end.
local function length(model, axis)
	local lo, hi = math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local at = d.Position:Dot(axis)
			local r = reach(d, axis)
			lo = math.min(lo, at - r)
			hi = math.max(hi, at + r)
		end
	end
	return hi - lo
end

local function movingParts(model)
	local loose = {}
	if not Props.find then
		return loose
	end
	for kind, names in { Spin = SPIN, Shake = SHAKE } do
		for _, name in names do
			for _, p in Props.find(model, name) do
				p:SetAttribute("Motion", kind)
				table.insert(loose, p)
			end
		end
	end
	return loose
end

-- Puts prop `name` on anchor, centered on ground (a ground-level CFrame whose LookVector is the way the belt flows),
-- standing on the ground. fallback is the part-built model the mesh replaces. turn rotates the mesh first; when
-- turn is nil the mesh is turned so its long side runs along the flow. Returns the mesh model, or nil.
function Skins.dress(name, anchor, fallback, ground, turn)
	if not Props or not Props.has(name) then
		return nil
	end
	local ok, model = pcall(function()
		local m = Props.make(name, ground, nil, turn)
		if m and not turn and length(m, ground.RightVector) > length(m, ground.LookVector) then
			m:Destroy()
			m = Props.make(name, ground, nil, CFrame.Angles(0, math.pi / 2, 0))
		end
		return m
	end)
	if not ok or not model then
		return nil
	end
	Props.restOn(model, ground.Position.Y)
	local loose = movingParts(model)
	Props.weldTo(model, anchor, fallback, loose)
	for _, p in loose do
		p.Anchored = true
		CollectionService:AddTag(p, "PropMotion")
	end
	return model
end

return Skins
