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
			if #parts > 0 and meshesReady(parts) then
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
