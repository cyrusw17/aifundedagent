--!nonstrict
-- The Rustic Blender props as Roblox meshes. Studio's Import 3D turns each .glb into a model; this finds those
-- models, scales and places copies, and welds them onto the parts the game already uses (the bale's hitbox, a
-- tool's handle). Nothing here changes how anything plays: gameplay keeps its own parts, the meshes only ride along.
-- Callers fall back to their part-built look when a prop is missing, so the game still runs before any import.
-- Rigged props (vehicles, trailers, conveyors, machines) keep their moving pieces as separate child meshes:
-- Wheel_L1, Wheel_R2, Tailgate, Coupler, Belt, Roller, Drum, Reel, Flywheel, Crank, Shaker. Copies keep that
-- hierarchy; Props.find picks the pieces out and Props.weldTo can leave them loose for a hinge or motor.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config.Props)

local Props = {}

local templates = nil -- normalized name -> imported model

-- hay_bale, HayBale, "Hay Bale" and HayBale_Node all name the same prop. Studio's importer wraps each file in a
-- <Name>_Node model and splits a mesh with two materials into <Name> and <Name>2, so a trailing "node" or number
-- is dropped too.
local function normalize(name)
	local key = string.lower((string.gsub(name, "[^%w]", "")))
	key = string.gsub(key, "node$", "")
	key = string.gsub(key, "%d+$", "")
	return key
end

local known = {}
for name in Config.Sizes do
	known[normalize(name)] = name
end

local function partsOf(instance)
	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, d in instance:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

-- The whole prop an imported instance belongs to: the outermost model up the tree that is still named after
-- the same prop (HayBale_Node holding HayBale and HayBale2), or the instance itself.
local function propRoot(instance, key, stop)
	local root = instance
	local parent = instance.Parent
	while parent and parent ~= stop and normalize(parent.Name) == key do
		root = parent
		parent = parent.Parent
	end
	return root
end

-- Finds the imported props anywhere under container, however the importer nested them (for example
-- Workspace.Scene.HayBale_Node.HayBale). skip is a folder to leave out.
local function collect(container, skip, found)
	for _, d in container:GetDescendants() do
		local name = known[normalize(d.Name)]
		if name and not found[name] and not (skip and d:IsDescendantOf(skip)) then
			local root = propRoot(d, normalize(d.Name), container)
			if #partsOf(root) > 0 then
				found[name] = root
			end
		end
	end
end

local function scan()
	templates = {}
	local folder = ServerStorage:FindFirstChild(Config.Folder)
	if folder then
		collect(folder, nil, templates)
	end
	local shared = ReplicatedStorage:FindFirstChild(Config.Folder)
	if shared then
		collect(shared, nil, templates)
	end

	-- A fresh import lands in the Workspace. Count it too, and take it out of the world so it is not left lying
	-- at the origin. The game's own world folder is left alone.
	local inWorld = {}
	collect(Workspace, Workspace:FindFirstChild("Needlewood"), inWorld)
	local function storage()
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = Config.Folder
			folder.Parent = ServerStorage
		end
		return folder
	end
	-- A prop found in the Workspace is the newest import (a re-export), so it replaces an older copy in storage.
	for name, root in inWorld do
		local old = templates[name]
		if old and old ~= root then
			old:Destroy()
		end
		root.Parent = storage()
		templates[name] = root
	end

	-- Everything else Import 3D left in the world goes too, even models no prop name matches yet. Left in the
	-- Workspace, a bulk import is dozens of models piled up at the spawn, all rendered and simulated.
	local scene = Workspace:FindFirstChild("Scene")
	for _, child in (scene and scene:GetChildren() or {}) do
		child.Parent = storage()
	end
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and string.match(child.Name, "_Node$") then
			child.Parent = storage()
		end
	end
	if scene and #scene:GetChildren() == 0 then
		scene:Destroy()
	end

	local missing = {}
	for name in Config.Sizes do
		if not templates[name] then
			table.insert(missing, name)
		end
	end
	table.sort(missing)
	local found = 0
	for _ in templates do
		found += 1
	end
	if #missing == 0 then
		print(`[Needlewood] Rustic props: all {found} meshes found.`)
	else
		print(`[Needlewood] Rustic props: {found} meshes found, using parts for: {table.concat(missing, ", ")}`)
	end
end

function Props.has(name)
	if not templates then
		scan()
	end
	return templates[name] ~= nil
end

-- The box around a set of parts, in world axes: its center and size.
local function bounds(parts)
	local low = Vector3.one * math.huge
	local high = -Vector3.one * math.huge
	for _, part in parts do
		local half = part.Size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local corner = part.CFrame * Vector3.new(half.X * x, half.Y * y, half.Z * z)
					low = low:Min(corner)
					high = high:Max(corner)
				end
			end
		end
	end
	return (low + high) / 2, high - low
end

-- How much a part stretches along its own axis when the prop stretches by scale along the world axes.
local function alongAxis(axis, scale)
	return math.abs(axis.X) * scale.X + math.abs(axis.Y) * scale.Y + math.abs(axis.Z) * scale.Z
end

-- A copy of the named prop with its box centered on cframe, or nil if it was never imported.
-- fit is a number (the longest side becomes that long, same shape) or a Vector3 (stretched to exactly that box).
-- turn rotates the prop in its own frame before it is placed. The copy is anchored and not parented.
function Props.make(name, cframe, fit, turn)
	if not Props.has(name) then
		return nil
	end
	local ok, copy = pcall(function()
		return templates[name]:Clone()
	end)
	if not ok or not copy then
		return nil
	end
	local model = copy
	if not copy:IsA("Model") then
		model = Instance.new("Model")
		copy.Parent = model
	end
	model.Name = name
	-- Any joints from the import would drag parts around as each one moves. The caller welds the copy itself.
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end

	local parts = partsOf(model)
	if #parts == 0 then
		model:Destroy()
		return nil
	end
	local center, size = bounds(parts)
	size = size:Max(Vector3.one * 0.01)
	-- When stretching, line the prop's long side up with the box's long side first.
	local pre = CFrame.identity
	if typeof(fit) == "Vector3" and (size.Z > size.X) ~= (fit.Z > fit.X) then
		pre = CFrame.Angles(0, math.pi / 2, 0)
		size = Vector3.new(size.Z, size.Y, size.X)
	end
	local scale
	if typeof(fit) == "Vector3" then
		scale = fit / size
	else
		fit = fit or Config.Sizes[name]
		scale = Vector3.one * (fit / math.max(size.X, size.Y, size.Z))
	end
	turn = turn or CFrame.identity

	for _, part in parts do
		local cf = pre * CFrame.new(part.Position - center) * part.CFrame.Rotation
		local offset = cf.Position * scale
		part.Size *= Vector3.new(alongAxis(cf.RightVector, scale), alongAxis(cf.UpVector, scale), alongAxis(cf.LookVector, scale))
		part.CFrame = cframe * turn * CFrame.new(offset) * cf.Rotation
		part.Anchored = true
	end
	return model
end

-- The moving pieces of a placed prop whose name starts with prefix: Props.find(truck, "Wheel") gives every wheel,
-- Props.find(truck, "Wheel_L") the left ones. A piece the importer wrapped in a <Name>_Node model, or split into
-- <Name> and <Name>2 by material, counts by its own name or the nearest model above it.
function Props.find(model, prefix)
	local found = {}
	for _, part in partsOf(model) do
		local node = part
		while node and node ~= model do
			local name = string.gsub(node.Name, "_Node$", "")
			if string.sub(name, 1, #prefix) == prefix then
				table.insert(found, part)
				break
			end
			node = node.Parent
		end
	end
	return found
end

-- Moves a placed prop up or down so its lowest point rests at height y.
function Props.restOn(model, y)
	local parts = partsOf(model)
	local center, size = bounds(parts)
	local lift = Vector3.new(0, y - (center.Y - size.Y / 2), 0)
	for _, part in parts do
		part.CFrame += lift
	end
end

-- Welds a placed prop onto anchor so it moves with it. The prop is only a look: it never collides, is never hit by
-- clicks (those go to the anchor) and weighs nothing.
-- fallback is the part-built look the mesh replaces (a bale body, a Tool, or a list of such parts). When given, the
-- mesh starts hidden and the fallback stays visible; each client swaps them once the mesh has actually loaded
-- (PropMeshes.client.luau), so a freshly imported mesh that Roblox is still processing never leaves an invisible bale or an empty hand.
-- loose is a list of the prop's own parts (from Props.find) to leave unwelded, so the caller can join them with a
-- hinge or Motor6D instead (spinning wheels, an opening tailgate). They are unanchored like the rest.
function Props.weldTo(model, anchor, fallback, loose)
	local skip = {}
	for _, part in loose or {} do
		skip[part] = true
	end
	for _, part in partsOf(model) do
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		if fallback then
			part:SetAttribute("MeshTransparency", part.Transparency)
			part.Transparency = 1
		end
		if not skip[part] then
			-- A Weld with its offset written out, not a WeldConstraint: a tool is built outside the Workspace, and a
			-- WeldConstraint there can take its offset later, after the handle has already moved to the hand.
			local weld = Instance.new("Weld")
			weld.Part0 = anchor
			weld.Part1 = part
			weld.C0 = anchor.CFrame:ToObjectSpace(part.CFrame)
			weld.Parent = part
		end
	end
	if fallback then
		-- Where the mesh should sit on its anchor and how big it is, so each client can check the mesh really
		-- landed there before it hides the fallback (PropMeshes.client.luau).
		local center, size = bounds(partsOf(model))
		local anchorLink = Instance.new("ObjectValue")
		anchorLink.Name = "Anchor"
		anchorLink.Value = anchor
		anchorLink.Parent = model
		model:SetAttribute("MeshOffset", anchor.CFrame:PointToObjectSpace(center))
		model:SetAttribute("MeshLength", math.max(size.X, size.Y, size.Z))
		for _, root in (typeof(fallback) == "table" and fallback or { fallback }) do
			local link = Instance.new("ObjectValue")
			link.Name = "Fallback"
			link.Value = root
			link.Parent = model
		end
		CollectionService:AddTag(model, "PropMesh")
	end
	model.Parent = anchor
end

-- The props with no job yet, set around base camp: a wheelbarrow by the bale drop-off, a crate and a small stack of
-- bales by the field bales, logs and spare tools by the hay shop. Skipped quietly if they were not imported.
local DRESSING = {
	{ "wheelbarrow", Vector3.new(-14, 0, -3), 30, true },
	{ "hay_crate", Vector3.new(-28, 0, -15), 10, true },
	{ "log", Vector3.new(9, 0, -19), 90, true },
	{ "log", Vector3.new(9, 0, -20.8), 92, true },
}

-- Spare tools lean on the outside of the shop's left wall (x = 14), blade down.
local LEANING = {
	{ "pitchfork", -16.5 },
	{ "wide_scoop", -18.5 },
}

function Props.dressBaseCamp(parent)
	local folder = Instance.new("Folder")
	folder.Name = "Props"
	folder.Parent = parent

	for _, def in DRESSING do
		local model = Props.make(def[1], CFrame.new(def[2]) * CFrame.Angles(0, math.rad(def[3]), 0))
		if model then
			Props.restOn(model, def[2].Y)
			for _, part in partsOf(model) do
				part.CanCollide = def[4]
			end
			model.Parent = folder
		end
	end

	local lean = math.rad(15)
	for _, def in LEANING do
		local length = Config.Sizes[def[1]]
		local x = 14 - 0.15 - math.sin(lean) * length / 2
		local model = Props.make(def[1], CFrame.new(x, 0, def[2]) * CFrame.Angles(0, 0, -lean))
		if model then
			Props.restOn(model, 0)
			for _, part in partsOf(model) do
				part.CanCollide = false
			end
			model.Parent = folder
		end
	end

	-- A small stack of square bales by the crate, the same size as the game's bales: two side by side, one on top.
	local bale = Vector3.new(4.6, 2.6, 3.2)
	for _, spot in { Vector3.new(-28, 1.3, -20.4), Vector3.new(-28, 1.3, -23.6), Vector3.new(-28, 3.9, -22) } do
		local model = Props.make("hay_bale", CFrame.new(spot), bale)
		if model then
			model.Parent = folder
		end
	end

	-- The hay hook lies on its side on the shop counter (its top is at y = 5).
	local hook = Props.make("hay_hook", CFrame.new(19.5, 5, -14) * CFrame.Angles(0, math.rad(20), math.pi / 2))
	if hook then
		Props.restOn(hook, 5)
		for _, part in partsOf(hook) do
			part.CanCollide = false
		end
		hook.Parent = folder
	end
end

return Props
