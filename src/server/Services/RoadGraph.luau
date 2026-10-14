--!strict
-- The road network as a graph (map #23): Meadow's roads, the isles' roads and the Longstitch Highway, sampled every
-- STEP studs, with a junction wherever two roads come within JOIN studs. RoadGraph.distances(from) gives the driving
-- distance from the road point nearest `from` to every other point; RoadGraph.distance(from, to) the one number.
-- Signposts print these (Regions.luau JUNCTIONS) so a sign can never drift from the roads it points down.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)

local RoadGraph = {}

local STEP = 16
local JOIN = 10 -- road points this close are one junction
local CELL = 64
local END_JOIN = 30 -- a road's end joins the nearest point of another road this close

type Node = { x: number, z: number, road: string, links: { [number]: number } }

local nodes: { Node }? = nil
local grid: { [string]: { number } } = {}

local function key(x: number, z: number): string
	return math.floor(x / CELL) .. "," .. math.floor(z / CELL)
end

local function build(): { Node }
	local list: { Node } = {}
	local function link(a: number, b: number)
		if a == b then
			return
		end
		local na, nb = list[a], list[b]
		local d = math.sqrt((na.x - nb.x) ^ 2 + (na.z - nb.z) ^ 2)
		if not na.links[b] or na.links[b] > d then
			na.links[b] = d
			nb.links[a] = d
		end
	end
	local roads = {}
	for _, road in Meadow.Roads do
		table.insert(roads, { name = road.name, points = road.points })
	end
	for _, road in Map.Roads do
		table.insert(roads, { name = road.name, points = road.points })
	end
	table.insert(roads, { name = "Longstitch Highway", points = { Map.Highway.from, Map.Highway.to } })
	local ends: { number } = {} -- each road's first and last point
	for _, road in roads do
		local prev: number? = nil
		local first = #list + 1
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			local n = math.max(1, math.ceil((b - a).Magnitude / STEP))
			for k = (i == 1 and 0 or 1), n do
				local p = a:Lerp(b, k / n)
				table.insert(list, { x = p.X, z = p.Y, road = road.name, links = {} })
				local index = #list
				local cell = key(p.X, p.Y)
				grid[cell] = grid[cell] or {}
				table.insert(grid[cell], index)
				if prev then
					link(prev, index)
				end
				prev = index
			end
		end
		table.insert(ends, first)
		table.insert(ends, #list)
	end
	-- Junctions: any two points of different roads within JOIN studs.
	for index, node in list do
		local cx, cz = math.floor(node.x / CELL), math.floor(node.z / CELL)
		for dx = -1, 1 do
			for dz = -1, 1 do
				for _, other in (grid[(cx + dx) .. "," .. (cz + dz)] or {}) :: { number } do
					local o = list[other]
					if o.road ~= node.road and (o.x - node.x) ^ 2 + (o.z - node.z) ^ 2 <= JOIN * JOIN then
						link(index, other)
					end
				end
			end
		end
	end
	-- A road that ends on another road (between its sample points) joins it at the nearest point.
	for _, e in ends do
		local node = list[e]
		local best, bestD = nil, END_JOIN * END_JOIN
		local cx, cz = math.floor(node.x / CELL), math.floor(node.z / CELL)
		for dx = -1, 1 do
			for dz = -1, 1 do
				for _, other in (grid[(cx + dx) .. "," .. (cz + dz)] or {}) :: { number } do
					local o = list[other]
					local d = (o.x - node.x) ^ 2 + (o.z - node.z) ^ 2
					if o.road ~= node.road and d < bestD then
						best, bestD = other, d
					end
				end
			end
		end
		if best then
			link(e, best)
		end
	end
	-- Roads that end on the same plaza or port (a flat zone) are joined across it.
	for _, zone in Map.Flat do
		local inside = {}
		for _, e in ends do
			local n = list[e]
			if n.x >= zone.min.X - JOIN and n.x <= zone.max.X + JOIN and n.z >= zone.min.Y - JOIN and n.z <= zone.max.Y + JOIN then
				table.insert(inside, e)
			end
		end
		for i = 1, #inside do
			for k = i + 1, #inside do
				link(inside[i], inside[k])
			end
		end
	end
	return list
end

function RoadGraph.nodes(): { Node }
	if not nodes then
		nodes = build()
	end
	return nodes :: { Node }
end

-- The index of the road point nearest a spot, and how far off the road the spot is.
function RoadGraph.nearest(at: Vector2): (number, number)
	local best, bestD = 1, math.huge
	for index, node in RoadGraph.nodes() do
		local d = (node.x - at.X) ^ 2 + (node.z - at.Y) ^ 2
		if d < bestD then
			best, bestD = index, d
		end
	end
	return best, math.sqrt(bestD)
end

-- Dijkstra from the road point nearest `from`: distance to every node (math.huge if unreachable by road).
function RoadGraph.distances(from: Vector2): { number }
	local list = RoadGraph.nodes()
	local start = RoadGraph.nearest(from)
	local dist = table.create(#list, math.huge)
	dist[start] = 0
	-- A small binary heap of { distance, node }.
	local heap: { { number } } = { { 0, start } }
	local function push(item: { number })
		table.insert(heap, item)
		local i = #heap
		while i > 1 do
			local parent = i // 2
			if heap[parent][1] <= heap[i][1] then
				break
			end
			heap[parent], heap[i] = heap[i], heap[parent]
			i = parent
		end
	end
	local function pop(): { number }
		local top = heap[1]
		local last = table.remove(heap) :: { number }
		if #heap > 0 then
			heap[1] = last
			local i = 1
			while true do
				local l, r, small = i * 2, i * 2 + 1, i
				if l <= #heap and heap[l][1] < heap[small][1] then
					small = l
				end
				if r <= #heap and heap[r][1] < heap[small][1] then
					small = r
				end
				if small == i then
					break
				end
				heap[small], heap[i] = heap[i], heap[small]
				i = small
			end
		end
		return top
	end
	while #heap > 0 do
		local item = pop()
		local d, index = item[1], item[2]
		if d <= dist[index] then
			for other, w in list[index].links do
				local nd = d + w
				if nd < dist[other] then
					dist[other] = nd
					push({ nd, other })
				end
			end
		end
	end
	return dist
end

-- Driving distance between two spots, by road (each snapped to its nearest road point).
function RoadGraph.distance(from: Vector2, to: Vector2): number
	local dist = RoadGraph.distances(from)
	local target = RoadGraph.nearest(to)
	return dist[target]
end

return RoadGraph
