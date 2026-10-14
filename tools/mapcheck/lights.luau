-- Night lights (#26): road lanterns, door lanterns and shop glows all follow the clock (WorldClock's naming rule),
-- no lantern post stands in a lane, every long road has lanterns, and the Spindle door carries its shard glow.
do
	local Map = require({ __path = "Shared.Config.WorldMap" })
	local Shape = require({ __path = "Services.WorldShape" })
	local SpindleDoorL = require({ __path = "Services.SpindleDoor" })
	local CS = game:GetService("CollectionService")
	local root = workspace:FindFirstChild("Needlewood")
	local ok, lamps, doors = true, 0, 0
	for _, d in root:GetDescendants() do
		if d.Name == "RoadLantern" or d.Name == "DoorLantern" or d.Name == "LampGlow" then
			lamps += 1
			if d.Name == "DoorLantern" then doors += 1 end
			if not d:FindFirstChildOfClass("PointLight") then ok = false print("WARN lamp with no light", d:GetFullName()) end
			if CS:HasTag(d, "AlwaysLit") then ok = false print("WARN night lamp tagged AlwaysLit", d:GetFullName()) end
		elseif d.Name == "LanternPost" then
			local dist = Shape.nearestRoad(d.Position.X, d.Position.Z)
			if dist and dist < Map.RoadWidth / 2 + 0.5 then ok = false print("WARN lantern post in a lane", math.floor(d.Position.X), math.floor(d.Position.Z)) end
		end
	end
	-- Long roads get lanterns.
	local RoadPolishL = require({ __path = "Services.RoadPolish" })
	for _, road in Map.Roads do
		local length = 0
		for i = 1, #road.points - 1 do length += (road.points[i + 1] - road.points[i]).Magnitude end
		local n = 0
		for _, at in RoadPolishL.lanterns do
			local d = Shape.nearestRoad(at.X, at.Z)
			for i = 1, #road.points - 1 do
				local a, b = road.points[i], road.points[i + 1]
				if Shape.segment(at.X, at.Z, a.X, a.Y, b.X, b.Y) < Map.RoadWidth / 2 + 4 then n += 1 break end
			end
		end
		if length >= 400 and n == 0 then ok = false print("WARN no lanterns on", road.name, math.floor(length)) end
	end
	SpindleDoorL.refresh()
	local glowOk = false
	for _, door in CS:GetTagged("SpindleDoor") do
		local glow = door:FindFirstChild("SpindleGlow")
		glowOk = glow ~= nil and CS:HasTag(glow, "AlwaysLit") and glow.Enabled == false
	end
	if not glowOk then ok = false print("WARN Spindle glow missing or lit with no shards") end
	print(("night lights %d lamps (%d road, %d door), %s"):format(lamps, #RoadPolishL.lanterns, doors, ok and "ok" or "WRONG"))
end
