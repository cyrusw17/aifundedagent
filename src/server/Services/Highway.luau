--!nonstrict
-- The Longstitch Highway to Thimble Keys: a bridge off the desert coast with a toll gate, the Midway Rest Stop, then a
-- glass tube that dips under the sea and climbs onto the keys. All parts; the terrain under it stays sea, and
-- WorldShape keeps the tube's inside dry. Any truck can drive it, trailer and all. Heights: Config/WorldMap Highway.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local WorldShape = require(script.Parent.WorldShape)

local Highway = {}

local IRON = Color3.new(0.48, 0.48, 0.47)
local ASPHALT = Color3.fromRGB(78, 76, 72)
local STEP = 20 -- deck pieces along X
local SLAB = 1.2 -- deck thickness
local SEA = Map.SeaLevel

local function part(parent, name, size, cframe, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanTouch = false
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Where the highway's center line is at an X, on the deck top.
local function point(x)
	local hw = Map.Highway
	local t = (x - hw.from.X) / (hw.to.X - hw.from.X)
	local z = hw.from.Y + (hw.to.Y - hw.from.Y) * t
	return Vector3.new(x, WorldShape.highwayY(x), z)
end

local function sign(parent, cframe, text, width)
	local board = part(parent, "Sign", Vector3.new(width or 18, 4, 0.4), cframe, Rustic.PaintGreen, Enum.Material.WoodPlanks)
	WorldLabel.surface(board, text, { Enum.NormalId.Front, Enum.NormalId.Back }, { color = Color3.fromRGB(236, 230, 210) })
	return board
end

function Highway.build(worldFolder)
	local hw = Map.Highway
	local folder = Instance.new("Folder")
	folder.Name = "Longstitch Highway"
	folder.Parent = worldFolder
	local W = hw.width
	local x0, x1 = hw.from.X, hw.to.X

	for x = x0, x1 - STEP, STEP do
		local a, b = point(x), point(math.min(x + STEP, x1))
		local mid = (a + b) / 2
		local along = CFrame.lookAt(mid, b)
		local length = (b - a).Magnitude + 0.3
		local deck = part(folder, "Deck", Vector3.new(W, SLAB, length), along * CFrame.new(0, -SLAB / 2, 0), ASPHALT, Enum.Material.Asphalt)
		deck.CustomPhysicalProperties = PhysicalProperties.new(2, 0.8, 0, 1, 1)
		part(folder, "Stripe", Vector3.new(0.5, 0.05, length * 0.5), along * CFrame.new(0, 0.03, 0), Rustic.PaintCream, Enum.Material.SmoothPlastic)

		local underSea = math.max(a.Y, b.Y) < SEA + 1
		if underSea then
			-- The tube: glass walls and roof, a light strip down the middle of the ceiling.
			local top = hw.tubeTop
			for _, side in { -1, 1 } do
				part(folder, "TubeWall", Vector3.new(1, top, length), along * CFrame.new(side * (W / 2 + 0.5), top / 2, 0), Color3.fromRGB(150, 190, 200), Enum.Material.Glass, 0.45)
			end
			part(folder, "TubeRoof", Vector3.new(W + 2, 1, length), along * CFrame.new(0, top + 0.5, 0), Color3.fromRGB(150, 190, 200), Enum.Material.Glass, 0.45)
			if (x - x0) % (STEP * 2) == 0 then
				local lamp = part(folder, "TubeLight", Vector3.new(2, 0.3, length * 0.6), along * CFrame.new(0, top - 0.2, 0), Color3.fromRGB(255, 236, 200), Enum.Material.Neon)
				lamp.CanCollide = false
				local l = Instance.new("PointLight")
				l.Range = 30
				l.Brightness = 1.2
				l.Color = Color3.fromRGB(255, 230, 190)
				l.Parent = lamp
			end
		else
			-- Guard rails on the open bridge.
			for _, side in { -1, 1 } do
				part(folder, "Rail", Vector3.new(0.6, 1.6, length), along * CFrame.new(side * (W / 2 - 0.3), 0.8, 0), IRON, Enum.Material.Metal)
			end
		end

		-- Piers every 60 studs where the deck stands over the sea.
		local ground = WorldShape.heightAt(mid.X, mid.Z)
		if not underSea and (x - x0) % 60 == 0 and ground < mid.Y - 4 then
			local bottom = math.min(ground, SEA) - 6
			local height = mid.Y - SLAB - bottom
			for _, side in { -1, 1 } do
				part(folder, "Pier", Vector3.new(3, height, 3), along * CFrame.new(side * (W / 2 - 3), -SLAB - height / 2, 0), Rustic.Stone, Enum.Material.Concrete)
			end
			part(folder, "PierCap", Vector3.new(W, 1.6, 3.4), along * CFrame.new(0, -SLAB - 0.8, 0), Rustic.Stone, Enum.Material.Concrete)
		end
	end

	-- The toll gate (the toll in planks comes with the economy; for now the barrier stands open).
	local toll = point(hw.toll)
	local tollCF = CFrame.lookAt(toll, point(hw.toll + 10))
	part(folder, "TollBooth", Vector3.new(4, 7, 6), tollCF * CFrame.new(W / 2 + 2.6, 3.5, 0), Rustic.PaintCream, Enum.Material.WoodPlanks)
	part(folder, "TollRoof", Vector3.new(6, 0.6, 8), tollCF * CFrame.new(W / 2 + 2.6, 7.3, 0), Rustic.PaintRedDark, Enum.Material.WoodPlanks)
	part(folder, "TollArm", Vector3.new(0.5, 12, 0.5), tollCF * CFrame.new(W / 2 - 1, 7, 0) * CFrame.Angles(0, 0, math.rad(8)), Rustic.PaintRed, Enum.Material.SmoothPlastic)
	sign(folder, tollCF * CFrame.new(0, 13, -4), "LONGSTITCH HIGHWAY\nTHIMBLE KEYS 820 studs", 22)
	for _, side in { -1, 1 } do
		part(folder, "SignPost", Vector3.new(0.6, 13, 0.6), tollCF * CFrame.new(side * 10, 6.5, -4), IRON, Enum.Material.Metal)
	end

	-- The Midway Rest Stop: a wide platform beside the deck with a fuel pump and a trading stall.
	local rest = point(hw.restStop.x)
	local restCF = CFrame.lookAt(rest, point(hw.restStop.x + 10))
	local size = hw.restStop.size
	local pad = restCF * CFrame.new(W / 2 + size.Y / 2, 0, 0)
	part(folder, "RestStopDeck", Vector3.new(size.Y, SLAB, size.X), pad * CFrame.new(0, -SLAB / 2, 0), ASPHALT, Enum.Material.Asphalt)
	for _, dx in { -1, 1 } do
		for _, dz in { -1, 1 } do
			local height = rest.Y - SEA + 8
			part(folder, "RestPier", Vector3.new(3, height, 3), pad * CFrame.new(dx * (size.Y / 2 - 3), -SLAB - height / 2, dz * (size.X / 2 - 3)), Rustic.Stone, Enum.Material.Concrete)
		end
	end
	for _, z in { -size.X / 2 + 0.3, size.X / 2 - 0.3 } do
		part(folder, "RestRail", Vector3.new(size.Y, 1.6, 0.6), pad * CFrame.new(0, 0.8, z), IRON, Enum.Material.Metal)
	end
	part(folder, "RestRail", Vector3.new(0.6, 1.6, size.X), pad * CFrame.new(size.Y / 2 - 0.3, 0.8, 0), IRON, Enum.Material.Metal)
	part(folder, "FuelPump", Vector3.new(2.4, 5, 2), pad * CFrame.new(-6, 2.5, -10), Rustic.PaintRed, Enum.Material.Metal)
	part(folder, "PumpCanopy", Vector3.new(14, 0.6, 18), pad * CFrame.new(-6, 9, -10), Rustic.PaintCream, Enum.Material.Metal)
	for _, z in { -18, -2 } do
		part(folder, "CanopyPost", Vector3.new(0.6, 9, 0.6), pad * CFrame.new(-6, 4.5, z), IRON, Enum.Material.Metal)
	end
	part(folder, "Stall", Vector3.new(10, 4, 3), pad * CFrame.new(12, 2, 12), Rustic.WoodDark, Enum.Material.WoodPlanks)
	part(folder, "StallAwning", Vector3.new(12, 0.4, 7), pad * CFrame.new(12, 8, 13), Rustic.PaintBlue, Enum.Material.Fabric)
	sign(folder, pad * CFrame.new(0, 12, size.X / 2 - 1), "MIDWAY REST STOP", 18)

	-- Signs at the tube.
	local into = Map.Highway.Profile[3][1] + 40
	local signAt = point(into)
	sign(folder, CFrame.lookAt(signAt, point(into + 10)) * CFrame.new(0, 14, 0), "UNDERSEA TUBE\nHeadlights on", 18)
	return folder
end

return Highway
