--!nonstrict
-- Conveyor belts made of square tiles on a grid. Every tile is TileSize x TileSize studs and points one of four ways.
-- A tile's belt is an anchored part with a velocity, so anything resting on it slides along. Rails are added
-- after a line is laid, so they go only where nothing feeds in from the side.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Factory = require(ReplicatedStorage.Shared.Config.Factory)

local Conveyors = {}

local T = Factory.TileSize
local RAIL = 0.3
local RAIL_HEIGHT = 1.2
-- Rustic palette (blender/lib/style.py): weathered wood frame, dark rubber belt, plain weathered metal rails and legs.
local FRAME = Color3.fromRGB(179, 153, 115)
local BELT = Color3.fromRGB(41, 33, 26)
local RAIL_COLOR = Color3.fromRGB(128, 117, 105)
local LEG = Color3.fromRGB(107, 94, 84)

Conveyors.TILE = T
Conveyors.Dirs = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}

local SLICK = PhysicalProperties.new(0.7, 0, 0, 100, 1) -- rails: no friction, so loads slide along them
local GRIP = PhysicalProperties.new(0.7, 1.5, 0, 100, 1) -- belt: grips the load

local function key(gx, gz)
	return gx .. "," .. gz
end

local function part(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A grid has an origin (the corner of cell 0,0 on the ground) and remembers every tile laid on it.
function Conveyors.newGrid(parent, origin)
	local folder = Instance.new("Folder")
	folder.Name = "Conveyors"
	folder.Parent = parent
	return { origin = origin, folder = folder, tiles = {} }
end

-- Ground point at the middle of a cell.
function Conveyors.cellCenter(grid, gx, gz)
	return grid.origin + Vector3.new((gx + 0.5) * T, 0, (gz + 0.5) * T)
end

-- Ground-level CFrame at the middle of a cell, facing dir. Machines.luau places its pieces with this.
function Conveyors.frame(grid, gx, gz, dir)
	local ground = Conveyors.cellCenter(grid, gx, gz)
	return CFrame.lookAt(ground, ground + Conveyors.Dirs[dir])
end

-- Lays one tile. dir is "N", "S", "E" or "W". openBack leaves the back end without a rail (for a loading dock).
function Conveyors.place(grid, gx, gz, dir, openBack)
	local d = Conveyors.Dirs[dir]
	local ground = Conveyors.cellCenter(grid, gx, gz)
	local top = ground + Vector3.new(0, Factory.BeltTop, 0)
	local facing = CFrame.lookAt(top, top + d)

	local model = Instance.new("Model")
	model.Name = ("Conveyor_%d_%d"):format(gx, gz)

	local belt = part(model, "Belt", Vector3.new(T, 0.4, T), facing * CFrame.new(0, -0.2, 0), BELT)
	belt.CustomPhysicalProperties = GRIP
	belt.AssemblyLinearVelocity = d * Factory.BeltSpeed
	belt:SetAttribute("Speed", Factory.BeltSpeed)
	CollectionService:AddTag(belt, "ConveyorBelt")

	part(model, "Frame", Vector3.new(T, 0.6, T - 0.2), facing * CFrame.new(0, -0.7, 0), FRAME, Enum.Material.WoodPlanks)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local legHeight = Factory.BeltTop - 1
			part(
				model,
				"Leg",
				Vector3.new(0.4, legHeight, 0.4),
				CFrame.new(ground + Vector3.new(sx * (T / 2 - 0.6), legHeight / 2, sz * (T / 2 - 0.6))),
				LEG,
				Enum.Material.Metal
			)
		end
	end

	model.PrimaryPart = belt
	model.Parent = grid.folder
	grid.tiles[key(gx, gz)] = { gx = gx, gz = gz, dir = dir, d = d, model = model, openBack = openBack }
	return belt
end

local function addRail(tile, side, top)
	local ground = top - Vector3.new(0, Factory.BeltTop, 0)
	local center = ground + side * (T / 2 - RAIL / 2) + Vector3.new(0, Factory.BeltTop + RAIL_HEIGHT / 2, 0)
	local size = side.X ~= 0 and Vector3.new(RAIL, RAIL_HEIGHT, T) or Vector3.new(T, RAIL_HEIGHT, RAIL)
	local rail = part(tile.model, "Rail", size, CFrame.new(center), RAIL_COLOR, Enum.Material.Metal)
	rail.CustomPhysicalProperties = SLICK
end

-- Adds rails once the whole line is laid. A side gets a rail unless a tile there feeds into this one.
-- The back gets a rail unless something feeds in from behind. The front is left open so loads move on.
function Conveyors.finish(grid)
	for _, tile in grid.tiles do
		local top = Conveyors.cellCenter(grid, tile.gx, tile.gz) + Vector3.new(0, Factory.BeltTop, 0)
		local sides = { Vector3.new(tile.d.Z, 0, -tile.d.X), Vector3.new(-tile.d.Z, 0, tile.d.X) }
		if not tile.openBack then
			table.insert(sides, -tile.d)
		end
		for _, side in sides do
			local n = grid.tiles[key(tile.gx + math.round(side.X), tile.gz + math.round(side.Z))]
			local feedsIn = n and (n.d + side).Magnitude < 0.01
			if not feedsIn then
				addRail(tile, side, top)
			end
		end
	end
end

-- Lays a straight run of tiles from (gx, gz) for count cells in dir.
function Conveyors.run(grid, gx, gz, dir, count)
	local d = Conveyors.Dirs[dir]
	for i = 0, count - 1 do
		Conveyors.place(grid, gx + d.X * i, gz + d.Z * i, dir)
	end
end

return Conveyors
