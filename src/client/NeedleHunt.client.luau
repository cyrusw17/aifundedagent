--!nonstrict
-- Needle hunt: a needle that spilled from a bale (one with a "Glint" from Hay.luau) glints faster and brighter the
-- closer you walk to it, a hot/cold shimmer that makes searching a spill by hand a small game. Local look only.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local FAR = 24 -- studs: beyond this a needle keeps its faint base glint
local NEAR = 3 -- studs: at this distance or closer it shimmers at full strength
local BASE_RATE, HOT_RATE = 1.2, 14
local BASE_SIZE, HOT_SIZE = 0.35, 0.8
local CHECK_EVERY = 0.15

local glints = {} -- needle part -> its Glint emitter

local function track(part)
	if not part:IsA("BasePart") then
		return
	end
	local glint = part:FindFirstChild("Glint") or part:WaitForChild("Glint", 2)
	if glint and glint:IsA("ParticleEmitter") then
		glints[part] = glint
	end
end

local function untrack(part)
	glints[part] = nil
end

CollectionService:GetInstanceAddedSignal("Needle"):Connect(track)
CollectionService:GetInstanceRemovedSignal("Needle"):Connect(untrack)
for _, part in CollectionService:GetTagged("Needle") do
	task.spawn(track, part)
end
-- Needles from hay when the shared needle module is not in the build are marked with a Needle attribute instead.
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("BasePart") and d:GetAttribute("Needle") == true then
		task.spawn(track, d)
	end
end)

local function sizeSequence(peak)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, peak),
		NumberSequenceKeypoint.new(1, 0),
	})
end

local elapsed = 0
local lastHeat = setmetatable({}, { __mode = "k" }) -- glint -> last heat step applied, so properties are only set when they change
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < CHECK_EVERY then
		return
	end
	elapsed = 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for part, glint in glints do
		if not part.Parent or not glint.Parent then
			glints[part] = nil
			lastHeat[glint] = nil
			continue
		end
		local distance = (part.Position - root.Position).Magnitude
		local heat = math.clamp((FAR - distance) / (FAR - NEAR), 0, 1)
		local step = math.floor(heat * 10 + 0.5)
		if lastHeat[glint] ~= step then
			lastHeat[glint] = step
			local t = step / 10
			glint.Rate = BASE_RATE + (HOT_RATE - BASE_RATE) * t * t
			glint.Size = sizeSequence(BASE_SIZE + (HOT_SIZE - BASE_SIZE) * t)
		end
	end
end)
