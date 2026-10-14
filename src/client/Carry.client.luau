--!nonstrict
-- Carry feel: a heavy load bobs the camera with each step, and a load your gloves are not rated for makes you
-- stagger now and then, so the glove tier is felt and not just read. The server sets Strain (0 easy .. 1 crawling)
-- and UnderGeared on the player (Avatar.refreshSpeed). Only the camera moves; nothing here changes the game.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local MIN_STRAIN = 0.12 -- below this the load is easy and the camera stays still
local BOB_HEIGHT = 0.35 -- studs of up-and-down at full strain
local BOB_SWAY = 0.2 -- studs of side-to-side at full strain
local STAGGER_EVERY = { 2.5, 5 } -- seconds between staggers while under-geared
local STAGGER_SIZE = 0.6 -- studs the camera lurches sideways

local rng = Random.new()
local phase = 0
local nextStagger = os.clock() + 3
local stagger = Vector3.zero
local offset = Vector3.zero

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local strain = player:GetAttribute("Strain") or 0
	local moving = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.FloorMaterial ~= Enum.Material.Air

	local target = Vector3.zero
	if strain > MIN_STRAIN and moving then
		-- Heavier loads take slower, deeper steps.
		phase += dt * (9 - strain * 3)
		target = Vector3.new(math.sin(phase) * BOB_SWAY * strain, -math.abs(math.sin(phase)) * BOB_HEIGHT * strain, 0)
		if player:GetAttribute("UnderGeared") and os.clock() > nextStagger then
			nextStagger = os.clock() + rng:NextNumber(STAGGER_EVERY[1], STAGGER_EVERY[2])
			stagger = Vector3.new((rng:NextInteger(0, 1) * 2 - 1) * STAGGER_SIZE, -0.25, 0)
		end
	end
	stagger = stagger:Lerp(Vector3.zero, math.min(dt * 4, 1))
	offset = offset:Lerp(target + stagger, math.min(dt * 10, 1))
	if offset.Magnitude < 0.001 and target == Vector3.zero then
		offset = Vector3.zero
	end
	humanoid.CameraOffset = offset
end)
