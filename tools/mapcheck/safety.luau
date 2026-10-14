-- Spawn and fall safety (#22): every spawn, ferry and zeppelin landing, tow spot and hay wagon stop stands on ground
-- with headroom, the kill floor is below every bit of ground, and the fall catch lands anywhere on the map on a dry
-- road with headroom.
do
	local Map = require({ __path = "Shared.Config.WorldMap" })
	local Meadow = require({ __path = "Shared.Config.Meadow" })
	local Shape = require({ __path = "Services.WorldShape" })
	local Ferry = require({ __path = "Services.Ferry" })
	local HayWagon = require({ __path = "Services.HayWagon" })
	local FallSafety = require({ __path = "Services.FallSafety" })
	local root = workspace:FindFirstChild("Needlewood")

	local solids = {}
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") and p.Anchored and p.CanCollide and p.Transparency < 1 then
			table.insert(solids, p)
		end
	end
	local function inside(p, at, pad)
		local o = p.CFrame:PointToObjectSpace(at)
		local s = p.Size
		return math.abs(o.X) <= s.X / 2 + pad and math.abs(o.Y) <= s.Y / 2 + pad and math.abs(o.Z) <= s.Z / 2 + pad
	end
	-- Feet at `at`: something to stand on within 3 studs below, nothing solid from knee to above the head.
	local function check(label, at)
		local ground = Shape.heightAt(at.X, at.Z)
		local standing = math.abs(ground - at.Y) <= 3
		local blocker = nil
		for _, p in solids do
			if not standing and (inside(p, at - Vector3.new(0, 0.4, 0), 0) or inside(p, at - Vector3.new(0, 2.5, 0), 0)) then
				standing = true
			end
			if not blocker then
				for _, o in { Vector3.new(0, 1.5, 0), Vector3.new(0, 4, 0), Vector3.new(0, 6.5, 0), Vector3.new(2, 3, 2), Vector3.new(-2, 3, -2), Vector3.new(2, 3, -2), Vector3.new(-2, 3, 2) } do
					if inside(p, at + o, -0.05) then
						blocker = p
						break
					end
				end
			end
		end
		local dry = at.Y > Map.SeaLevel + 0.5
		local ok = standing and not blocker and dry
		if not ok then
			print(("WARN unsafe %s at %d,%d,%d: %s"):format(label, at.X, at.Y, at.Z,
				not dry and "under the sea" or not standing and ("nothing to stand on (ground %d)"):format(ground) or ("blocked by " .. blocker:GetFullName())))
		end
		return ok
	end

	local points, bad = 0, 0
	local function add(label, at)
		points += 1
		if not check(label, at) then bad += 1 end
	end
	add("base camp spawn", Vector3.new(0, 1, 14))
	add("tow spot", Meadow.TowSpot + Vector3.new(0, Shape.heightAt(Meadow.TowSpot.X, Meadow.TowSpot.Z), 0))
	for _, shuttle in Ferry.all() do
		for _, stop in shuttle.stops or {} do
			local land = stop.edge + stop.inland * 20
			add(("%s landing at %s"):format(shuttle.def and shuttle.def.name or "ferry", stop.name), land)
		end
	end
	for _, leg in HayWagon.legs do
		local s = leg.samples[#leg.samples]
		add("hay wagon stop " .. leg.stop, Vector3.new(s.X, Shape.heightAt(s.X, s.Z), s.Z))
	end

	-- The kill floor sits below all ground (sampled every 64 studs).
	local lowest = math.huge
	for x = Map.Bounds.min.X, Map.Bounds.max.X, 64 do
		for z = Map.Bounds.min.Y, Map.Bounds.max.Y, 64 do
			lowest = math.min(lowest, Shape.heightAt(x, z))
		end
	end
	if lowest - 10 < FallSafety.KILL_Y then
		print("WARN the kill floor is not far enough below the lowest ground", FallSafety.KILL_Y, lowest)
		bad += 1
	end

	-- Falls anywhere (every 192 studs) land on a dry road with headroom; spot-check each landing once.
	local landings, seen = 0, {}
	for x = Map.Bounds.min.X, Map.Bounds.max.X, 192 do
		for z = Map.Bounds.min.Y, Map.Bounds.max.Y, 192 do
			local ground, name = FallSafety.target(Vector3.new(x, FallSafety.KILL_Y - 5, z))
			local key = math.floor(ground.Position.X) .. "," .. math.floor(ground.Position.Z)
			if not seen[key] then
				seen[key] = true
				landings += 1
				if not check("fall landing on " .. tostring(name), ground.Position) then bad += 1 end
			end
		end
	end
	print(("safety spawns %d, fall landings %d, lowest ground %.0f, kill floor %d, %s"):format(points, landings, lowest, FallSafety.KILL_Y, bad == 0 and "ok" or ("WARN " .. bad .. " unsafe")))
end
