--!nonstrict
-- Swaps a part-built look for its Rustic Blender mesh once the mesh has actually loaded on this client. Until then
-- the parts stay visible, so a freshly imported mesh that Roblox is still processing ("content representation is
-- being generated") never leaves an invisible bale or an empty hand. The server tags each such mesh (Props.weldTo).
-- Everything here is local: it only changes what this player sees.
local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")

local RETRY_SECONDS = 3
local MAX_TRIES = 40 -- about two minutes, then the parts simply stay

local function meshPartsOf(model)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

-- True once every mesh in the model has downloaded. Textures may still be on their way; that only looks plain.
local function meshesReady(parts)
	local ids = {}
	local failed = false
	local meshes = {}
	for _, part in parts do
		if part:IsA("MeshPart") and part.MeshId ~= "" then
			ids[part.MeshId] = true
			table.insert(meshes, part)
		end
	end
	local ran = pcall(function()
		ContentProvider:PreloadAsync(meshes, function(contentId, status)
			-- PreloadAsync returns once everything was tried; a mesh that reports anything but success is not ready.
			if ids[contentId] and status ~= Enum.AssetFetchStatus.Success then
				failed = true
			end
		end)
	end)
	return ran and not failed
end

-- The box around the mesh parts, in world axes: its center and longest side.
local function measure(parts)
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
	local size = high - low
	return (low + high) / 2, math.max(size.X, size.Y, size.Z)
end

-- True if the mesh sits where the server put it on its anchor and is close to its intended size. A mesh that
-- ended up somewhere else or came out tiny would leave the fallback hidden and nothing visible, so it is refused
-- and the parts stay. The first refusal per model is logged with what was measured.
local warned = {}
local function inPlace(model, parts)
	local link = model:FindFirstChild("Anchor")
	local anchor = link and link.Value
	local expectedOffset = model:GetAttribute("MeshOffset")
	local expectedLength = model:GetAttribute("MeshLength")
	if not (anchor and anchor:IsA("BasePart") and expectedOffset and expectedLength) then
		return true -- an older server that does not say where the mesh belongs
	end
	local center, length = measure(parts)
	local offset = anchor.CFrame:PointToObjectSpace(center)
	local drift = (offset - expectedOffset).Magnitude
	local ok = drift <= 1.5 + expectedLength * 0.25 and length >= expectedLength * 0.5
	if not ok and not warned[model] then
		warned[model] = true
		warn(
			`[Needlewood] {model.Name} mesh kept hidden: it sits {string.format("%.1f", drift)} studs from where it`
				.. ` belongs on {anchor:GetFullName()} and is {string.format("%.2f", length)} long`
				.. ` (expected {string.format("%.2f", expectedLength)}). Showing the part look instead.`
		)
	end
	return ok
end

-- Keeps a fallback part hidden here even if the server changes its transparency (a bale fading in, say).
local function hide(part)
	part.Transparency = 1
	part:GetPropertyChangedSignal("Transparency"):Connect(function()
		if part.Transparency < 1 then
			part.Transparency = 1
		end
	end)
end

local function swap(model, parts)
	local link = model:FindFirstChild("Fallback")
	local root = link and link.Value
	for _, part in parts do
		part.Transparency = part:GetAttribute("MeshTransparency") or 0
	end
	if not root then
		return
	end
	local list = { root }
	for _, d in root:GetDescendants() do
		table.insert(list, d)
	end
	for _, part in list do
		if part:IsA("BasePart") and not part:IsDescendantOf(model) then
			hide(part)
		end
	end
end

local function watch(model)
	task.spawn(function()
		-- The fallback link and the mesh parts replicate with the model, but give them a moment to arrive.
		model:WaitForChild("Fallback", 5)
		for _ = 1, MAX_TRIES do
			if not model.Parent then
				return
			end
			local parts = meshPartsOf(model)
			if #parts > 0 and meshesReady(parts) and inPlace(model, parts) then
				swap(model, parts)
				return
			end
			task.wait(RETRY_SECONDS)
		end
	end)
end

CollectionService:GetInstanceAddedSignal("PropMesh"):Connect(watch)
for _, model in CollectionService:GetTagged("PropMesh") do
	watch(model)
end
