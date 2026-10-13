-- Splitter and merger junctions (CEO #38), on the real Conveyors.luau: thousands of random little layouts of belts and
-- splitters on a 6 x 6 grid, finished the way Land finishes a plot, then checked tile by tile for anything that would
-- stop a bale at a junction: a rail across a side a neighbour pushes loads into, a splitter side railed shut while a
-- tile there takes loads, or a merger (a belt fed from both sides) not dressed as one.
local Conveyors = require({ __path = "Services.Conveyors" })

local failures, checked, merges, splits = 0, 0, 0, 0
local function check(name, ok, detail)
	checked += 1
	if not ok then
		failures += 1
		if failures <= 20 then
			print("FAIL " .. name .. (detail and (": " .. detail) or ""))
		end
	end
end

local DIRS = { "N", "S", "E", "W" }
local rng = Random.new(38)
local T = 6

-- Sides of a tile that have a rail, from the rails' positions against the tile's centre.
local function railedSides(grid, tile)
	local out = {}
	local c = Conveyors.cellCenter(grid, tile.gx, tile.gz)
	for _, child in tile.model:GetChildren() do
		if child.Name == "Rail" then
			local off = child.Position - c
			local s = math.abs(off.X) > math.abs(off.Z) and Vector3.new(math.sign(off.X), 0, 0) or Vector3.new(0, 0, math.sign(off.Z))
			out[#out + 1] = s
		end
	end
	return out
end
local function has(list, v)
	for _, x in list do
		if (x - v).Magnitude < 0.01 then
			return true
		end
	end
	return false
end

local folder = Instance.new("Folder")
for layout = 1, 3000 do
	local grid = Conveyors.newGrid(folder, Vector3.new(0, 0, 0))
	local placed = {}
	for _ = 1, rng:NextInteger(3, 14) do
		local gx, gz = rng:NextInteger(0, 5), rng:NextInteger(0, 5)
		local k = gx .. "," .. gz
		if not placed[k] then
			placed[k] = true
			local dir = DIRS[rng:NextInteger(1, 4)]
			Conveyors.place(grid, gx, gz, dir)
			if rng:NextNumber() < 0.25 then
				Conveyors.makeSplitter(grid, gx, gz)
			end
		end
	end
	Conveyors.finish(grid)
	for _, tile in grid.tiles do
		local rails = railedSides(grid, tile)
		local left, right = Conveyors.sides(tile.d)
		local fedSides = 0
		for _, side in { left, right, -tile.d } do
			local n = Conveyors.tileAt(grid, tile.gx + math.round(side.X), tile.gz + math.round(side.Z))
			local pushesIn = false
			if n then
				for _, out in n.outs do
					if (out + side).Magnitude < 0.01 then
						pushesIn = true
					end
				end
			end
			if pushesIn then
				if tile.kind == "splitter" and side ~= -tile.d then
					-- A load pushed into a splitter's side would fight its own push: Land allows it, but it is a wall.
					continue
				end
				check("a side a neighbour pushes into has no rail", not has(rails, side), ("layout %d tile %d,%d side %s"):format(layout, tile.gx, tile.gz, tostring(side)))
				if side ~= -tile.d then
					fedSides += 1
				end
			end
		end
		if tile.kind == "splitter" then
			splits += 1
			for _, side in { left, right } do
				local n = Conveyors.tileAt(grid, tile.gx + math.round(side.X), tile.gz + math.round(side.Z))
				local takes = n ~= nil and (n.d + side).Magnitude > 0.01 -- Machines.splitter open(): not running back at us
				if takes then
					check("a splitter side with a tile to take loads is open", not has(rails, side), ("layout %d splitter %d,%d"):format(layout, tile.gx, tile.gz))
				end
			end
			check("a splitter's front is railed", has(rails, tile.d), ("layout %d splitter %d,%d"):format(layout, tile.gx, tile.gz))
		elseif fedSides == 2 then
			merges += 1
			check("a belt fed from both sides is dressed as a merger", tile.mesh == "merger", ("layout %d tile %d,%d mesh %s"):format(layout, tile.gx, tile.gz, tostring(tile.mesh)))
		end
	end
	folder:ClearAllChildren()
end
print(("junctions: 3000 random layouts, %d splitters, %d mergers, %d checks, %d failures"):format(splits, merges, checked, failures))
if failures > 0 then
	print("FAIL junctions")
end
