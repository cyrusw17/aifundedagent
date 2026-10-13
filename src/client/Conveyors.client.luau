--!nonstrict
-- Makes conveyor belts look like they move: light slats slide along each belt at its speed.
-- Only visual and only on this client. The server's belt velocity is what actually carries loads.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SLATS = 3
local SLAT_COLOR = Color3.fromRGB(77, 64, 51)

local belts = {} -- belt part -> its slats

local function add(belt)
	if belts[belt] or not belt:IsA("BasePart") then
		return
	end
	local slats = {}
	for _ = 1, SLATS do
		local slat = Instance.new("Part")
		slat.Name = "BeltSlat"
		slat.Anchored = true
		slat.CanCollide = false
		slat.CanQuery = false
		slat.CanTouch = false
		slat.CastShadow = false
		slat.Size = Vector3.new(belt.Size.X - 0.8, 0.06, 0.35)
		slat.Color = SLAT_COLOR
		slat.Material = Enum.Material.SmoothPlastic
		slat.Parent = belt
		table.insert(slats, slat)
	end
	belts[belt] = slats
end

local function remove(belt)
	local slats = belts[belt]
	if slats then
		for _, slat in slats do
			slat:Destroy()
		end
		belts[belt] = nil
	end
end

CollectionService:GetInstanceAddedSignal("ConveyorBelt"):Connect(add)
CollectionService:GetInstanceRemovedSignal("ConveyorBelt"):Connect(remove)
for _, belt in CollectionService:GetTagged("ConveyorBelt") do
	add(belt)
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for belt, slats in belts do
		if not belt.Parent then
			remove(belt)
			continue
		end
		local length = belt.Size.Z
		local spacing = length / SLATS
		local travelled = now * (belt:GetAttribute("Speed") or 0)
		for i, slat in slats do
			local along = (travelled + i * spacing) % length
			-- Forward is the belt's -Z, so slats enter at +Z and leave at -Z.
			slat.CFrame = belt.CFrame * CFrame.new(0, belt.Size.Y / 2 + 0.03, length / 2 - along)
		end
	end
end)
