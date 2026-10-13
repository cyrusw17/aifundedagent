--!nonstrict
-- Fall safety (map #22): a player or truck that drops through the world (a hole in the terrain, off a cliff edge the
-- sea doesn't catch, a glitch under a building) is caught below KILL_Y and set back on the nearest road, facing along
-- it, never sent all the way back to camp. A truck comes back with its hitched trailer (Vehicles.recover "rescue").
-- Roblox would destroy anything below FallenPartsDestroyHeight (-500); the catch is far above that.
--
-- FallSafety.target(position) is the landing spot for any point, and the offline map check (tools/mapcheck) asks it
-- for points all over the map to prove every landing is dry with headroom.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)
local WorldShape = require(script.Parent.WorldShape)
local Data = require(script.Parent.Data)
local Vehicles = require(script.Parent.Vehicles)

local FallSafety = {}

FallSafety.KILL_Y = Map.SeaFloor - 40 -- below the deepest sea floor: nothing should ever be down here
local STEP = 12 -- studs between candidate road points
local CHECK_EVERY = 0.5
local DRY = Map.SeaLevel + 1 -- a landing must stand this far above the sea

-- Every road point (Meadow's roads and the isles' roads), with the road's name and its direction.
local points = nil
local function roadPoints()
	if points then
		return points
	end
	points = {}
	for _, list in { Meadow.Roads, Map.Roads } do
		for _, road in list do
			for i = 1, #road.points - 1 do
				local a, b = road.points[i], road.points[i + 1]
				local dir = (b - a).Unit
				local n = math.max(1, math.ceil((b - a).Magnitude / STEP))
				for k = 0, n do
					local p = a:Lerp(b, k / n)
					local y = WorldShape.heightAt(p.X, p.Y)
					if y > DRY then
						table.insert(points, { x = p.X, z = p.Y, y = y, dir = dir, name = road.name })
					end
				end
			end
		end
	end
	return points
end
FallSafety.roadPoints = roadPoints

-- The landing for a fall at position: the nearest dry road point, standing on it, facing along the road.
-- Returns a ground CFrame (feet on the road) and the road's name.
function FallSafety.target(position)
	local best, bestD = nil, math.huge
	for _, p in roadPoints() do
		local d = (p.x - position.X) ^ 2 + (p.z - position.Z) ^ 2
		if d < bestD then
			best, bestD = p, d
		end
	end
	if not best then
		local camp = Vector3.new(0, 0, 14)
		return CFrame.new(camp), "camp"
	end
	local at = Vector3.new(best.x, best.y, best.z)
	return CFrame.lookAt(at, at + Vector3.new(best.dir.X, 0, best.dir.Y)), best.name
end

local function roadLabel(name)
	if name == "camp" then
		return "base camp"
	end
	return ("the %s"):format(name)
end

local busy = {}

local function catchPlayer(player, root)
	busy[player] = true
	local ground, name = FallSafety.target(root.Position)
	pcall(player.RequestStreamAroundAsync, player, ground.Position, 5)
	local character = player.Character
	if character and character.Parent and root.Parent then
		character:PivotTo(ground * CFrame.new(0, 4, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		if Data.get(player) then
			Data.toast(player, ("You fell through the world. Back on %s."):format(roadLabel(name)))
		end
	end
	busy[player] = nil
end

local function catchTruck(player, truck)
	busy[truck] = true
	local ground, name = FallSafety.target(truck.PrimaryPart.Position)
	pcall(player.RequestStreamAroundAsync, player, ground.Position, 5)
	if truck.Parent and truck.PrimaryPart then
		local ok = Vehicles.recover(player, "rescue", ground)
		if ok and Data.get(player) then
			Data.toast(player, ("Your truck fell through the world. It's back on %s."):format(roadLabel(name)))
		end
	end
	busy[truck] = nil
end

-- One pass: anyone or any player truck below the kill floor is put back on a road.
function FallSafety.step()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- A seated driver goes with the truck below.
		if root and not busy[player] and root.Position.Y < FallSafety.KILL_Y and not (humanoid and humanoid.SeatPart) then
			task.spawn(catchPlayer, player, root)
		end
	end
	for model, owner in Vehicles.all() do
		local chassis = model.PrimaryPart
		if chassis and not busy[model] and model:GetAttribute("TruckId") and chassis.Position.Y < FallSafety.KILL_Y then
			task.spawn(catchTruck, owner, model)
		end
	end
end

local started = false
function FallSafety.start()
	if started then
		return
	end
	started = true
	task.spawn(roadPoints)
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			local ok, err = pcall(FallSafety.step)
			if not ok then
				warn("[Needlewood] fall safety: " .. tostring(err))
			end
		end
	end)
end

return FallSafety
