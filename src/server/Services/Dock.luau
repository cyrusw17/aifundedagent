--!nonstrict
-- The loading dock at the start of the conveyor line. It works with any truck or trailer: back the open end of the
-- bed up to the dock (bed floor at or a little above the belt, Factory.BeltTop studs off the ground) and step on
-- UNLOAD. The dock then nudges every loose bale and hay piece in the dock zone toward the belt, like a walking
-- floor, so the cargo slides off the back. Nothing is welded: the cargo is ordinary physics before and after.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Factory = require(ReplicatedStorage.Shared.Config.Factory)
local Bales = require(script.Parent.Bales)
local Hay = require(script.Parent.Hay)

-- The shared trucks live in Vehicles.luau (Starting biome thread, PR #15). It is optional here so the base also runs
-- on branches without it.
local Vehicles = script.Parent:FindFirstChild("Vehicles") and require(script.Parent.Vehicles)

local Dock = {}

local ZONE_LENGTH = 30 -- how far from the dock edge a parked bed's cargo can reach
local ZONE_WIDTH = 9
local ZONE_HEIGHT = 14
local UNLOAD_SECONDS = 30 -- give up after this, so a stuck bale cannot hold the dock forever

local zone = nil -- CFrame of the zone box
local toward = nil -- direction from the bed onto the belt
local busy = false

-- dockPoint is the ground point at the back edge of the dock tile. out points away from the belt, toward where a
-- truck parks.
function Dock.init(dockPoint, out)
	toward = -out
	zone = CFrame.lookAt(dockPoint, dockPoint + out) * CFrame.new(0, ZONE_HEIGHT / 2 + 0.5, -ZONE_LENGTH / 2)
end

-- Loose cargo in the dock zone: bale bodies and hay pieces, not ones a player is carrying.
local function cargo()
	local found = {}
	for _, p in Workspace:GetPartBoundsInBox(zone, Vector3.new(ZONE_WIDTH, ZONE_HEIGHT, ZONE_LENGTH)) do
		local b = Bales.fromPart(p)
		local isBale = b and p == b.body and not b.gone and not b.carriedBy and not b.breaking
		if isBale or Hay.isPiece(p) then
			table.insert(found, p)
		end
	end
	return found
end

function Dock.hasCargo()
	return #cargo() > 0
end

function Dock.isBusy()
	return busy
end

local function inZone(position)
	local p = zone:PointToObjectSpace(position)
	return math.abs(p.X) <= ZONE_WIDTH / 2 and math.abs(p.Y) <= ZONE_HEIGHT / 2 and math.abs(p.Z) <= ZONE_LENGTH / 2
end

-- Opens the tailgate of every player truck parked in the dock zone (Vehicles.setTailgate). Trucks without that API
-- can tag their tailgate part "Tailgate" instead, and it is moved out of the way. Returns a function that closes them.
local function openTailgates()
	local trucks, tagged = {}, {}
	if Vehicles and Vehicles.all then
		for truck in Vehicles.all() do
			local chassis = truck.PrimaryPart
			if chassis and inZone(chassis.Position) and Vehicles.setTailgate(truck, true) then
				table.insert(trucks, truck)
			end
		end
	end
	for _, p in Workspace:GetPartBoundsInBox(zone, Vector3.new(ZONE_WIDTH, ZONE_HEIGHT, ZONE_LENGTH)) do
		if CollectionService:HasTag(p, "Tailgate") and not tagged[p] then
			tagged[p] = { canCollide = p.CanCollide, transparency = p.Transparency }
			p.CanCollide = false
			p.Transparency = 1
		end
	end
	return function()
		for _, truck in trucks do
			if truck.Parent then
				Vehicles.setTailgate(truck, false)
			end
		end
		for p, was in tagged do
			if p.Parent then
				p.CanCollide = was.canCollide
				p.Transparency = was.transparency
			end
		end
	end
end

-- Slides everything in the zone onto the belt. onDone runs when the zone is empty or time runs out.
function Dock.unload(onDone)
	if busy then
		return false
	end
	busy = true
	local closeTailgates = openTailgates()
	task.spawn(function()
		local started = os.clock()
		local nextScan, parts = 0, {}
		while os.clock() - started < UNLOAD_SECONDS do
			if os.clock() >= nextScan then
				parts = cargo()
				nextScan = os.clock() + 0.5
				for _, p in parts do
					-- The server takes over the cargo so its push is not overwritten by the driver's physics.
					pcall(function()
						p:SetNetworkOwner(nil)
					end)
				end
				if #parts == 0 then
					break
				end
			end
			for _, p in parts do
				if p.Parent and not p.Anchored then
					-- Set only the sideways speed toward the belt and keep gravity's pull, so loads still tip and fall.
					local v = p.AssemblyLinearVelocity
					local along = v:Dot(toward)
					if along < Factory.WalkingFloorSpeed then
						p.AssemblyLinearVelocity = v + toward * (Factory.WalkingFloorSpeed - along)
					end
				end
			end
			RunService.Heartbeat:Wait()
		end
		closeTailgates()
		busy = false
		if onDone then
			onDone()
		end
	end)
	return true
end

return Dock
