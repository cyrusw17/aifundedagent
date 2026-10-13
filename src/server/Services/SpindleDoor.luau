--!nonstrict
-- The Spindle's sealed door (Regions LANDMARKS.spindle builds it): twelve sockets in a ring, one per Master Needle
-- shard (Quests owns the shards; Config/Quests Collection lists them in order). A socket glows while anyone on this
-- server holds its shard, so the door shows the whole server's progress. Each player's own count is the attribute
-- SpindleShards; with all twelve the door lets that player through (SpindleDoor.client opens it on their screen
-- only) into the Loom Room carved into the mountain behind it, where the Master Needle's empty pedestal waits
-- (tagged MasterNeedlePedestal, for Quests to hook the ending on).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestConfig = require(ReplicatedStorage.Shared.Config.Quests)
local WorldTerrain = require(script.Parent.WorldTerrain)
local Data = require(script.Parent.Data)
local WorldClock = require(script.Parent.WorldClock)

local SpindleDoor = {}

SpindleDoor.SLOTS = 12
local CHECK_EVERY = 2
local GOLD = Color3.fromRGB(242, 183, 5)

-- Shard ids in slot order: the shards in the collection, in its order (more arrive as Quests adds them).
local shards = {}
for _, entry in QuestConfig.Collection do
	if string.sub(entry.id, 1, 6) == "shard_" and #shards < SpindleDoor.SLOTS then
		table.insert(shards, entry.id)
	end
end
SpindleDoor.shards = shards

local Quests = nil
local function has(player, id)
	if not Quests then
		local ok, module = pcall(require, script.Parent.Quests)
		Quests = ok and module or false
	end
	return Quests and Quests.has and Quests.has(player, id) == true
end

-- How many shards this player holds.
function SpindleDoor.count(player)
	local n = 0
	for _, id in shards do
		if has(player, id) then
			n += 1
		end
	end
	return n
end

local function setSocket(socket, lit)
	if socket:GetAttribute("Lit") == lit then
		return
	end
	socket:SetAttribute("Lit", lit)
	socket.Transparency = lit and 0 or 0.6
	local glow = socket:FindFirstChildOfClass("PointLight")
	if lit and not glow then
		glow = Instance.new("PointLight")
		glow.Color = GOLD
		glow.Range = 8
		glow.Brightness = 1.2
		glow.Parent = socket
	end
	if glow then
		glow.Enabled = lit
	end
end

-- Lights the sockets and publishes each player's count. Called every few seconds; tests call it directly.
function SpindleDoor.refresh()
	local held = {}
	for _, player in Players:GetPlayers() do
		local n = 0
		for slot, id in shards do
			if has(player, id) then
				held[slot] = true
				n += 1
			end
		end
		player:SetAttribute("SpindleShards", n)
	end
	local lit = 0
	for _, socket in CollectionService:GetTagged("ShardSocket") do
		setSocket(socket, held[socket:GetAttribute("Slot") or 0] == true)
		if socket:GetAttribute("Lit") then
			lit += 1
		end
	end
	-- The Spindle glows as its sockets fill (#26): a gold light on the door that grows with every lit socket, brighter
	-- at night so the mountain's face shows from the valley.
	for _, door in CollectionService:GetTagged("SpindleDoor") do
		local glow = door:FindFirstChild("SpindleGlow")
		if not glow then
			glow = Instance.new("PointLight")
			glow.Name = "SpindleGlow"
			glow.Color = GOLD
			glow.Shadows = false
			glow.Parent = door
			CollectionService:AddTag(glow, "AlwaysLit")
		end
		local night = WorldClock.isNight()
		glow.Enabled = lit > 0
		glow.Range = math.min(60, 16 + lit * 3.5)
		glow.Brightness = lit / SpindleDoor.SLOTS * (night and 5 or 2)
		door:SetAttribute("Glow", lit / SpindleDoor.SLOTS)
	end
end

local function part(parent, name, size, cframe, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.Parent = parent
	return p
end

-- The Loom Room behind the door: carved out of the Spindle once the terrain is down, floored and lit.
local function loomRoom(door)
	local folder = Instance.new("Folder")
	folder.Name = "LoomRoom"
	folder.Parent = door.Parent
	local base = door.CFrame * CFrame.new(0, -10, 0) -- the door's foot; its back (+Z) faces into the mountain
	local depth, width, height = 40, 12, 16
	local room = base * CFrame.new(0, height / 2, 2 + depth / 2)
	local waited = 0
	while not WorldTerrain.isReady() and waited < 600 do
		task.wait(5)
		waited += 5
	end
	pcall(function()
		workspace.Terrain:FillBlock(room, Vector3.new(width, height, depth), Enum.Material.Air)
	end)
	local stone = Color3.fromRGB(150, 142, 160)
	part(folder, "LoomFloor", Vector3.new(width, 1, depth), base * CFrame.new(0, -0.5, 2 + depth / 2), Color3.fromRGB(96, 86, 120), Enum.Material.Slate)
	for _, side in { -1, 1 } do
		part(folder, "LoomWall", Vector3.new(1, height, depth), room * CFrame.new(side * (width / 2 + 0.5), 0, 0), stone, Enum.Material.Slate)
	end
	part(folder, "LoomCeiling", Vector3.new(width + 2, 1, depth), room * CFrame.new(0, height / 2 + 0.5, 0), stone, Enum.Material.Slate)
	part(folder, "LoomBack", Vector3.new(width, height, 1), room * CFrame.new(0, 0, depth / 2 + 0.5), stone, Enum.Material.Slate)
	for i = 1, 3 do
		local lamp = part(folder, "LoomLamp", Vector3.new(0.8, 0.8, 0.8), room * CFrame.new(width / 2 - 0.8, 3, -depth / 2 + i * 10), GOLD, Enum.Material.Neon, false)
		CollectionService:AddTag(lamp, "AlwaysLit")
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 18
		light.Parent = lamp
	end
	local pedestal = part(folder, "MasterNeedlePedestal", Vector3.new(4, 4, 4), base * CFrame.new(0, 2, 2 + depth - 5), stone, Enum.Material.Marble)
	CollectionService:AddTag(pedestal, "MasterNeedlePedestal")
end

local started = false
function SpindleDoor.start()
	if started then
		return
	end
	started = true
	local door = CollectionService:GetTagged("SpindleDoor")[1]
	if door then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Inspect"
		prompt.ObjectText = "The Spindle Door"
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = door
		prompt.Triggered:Connect(function(player)
			local n = SpindleDoor.count(player)
			Data.toast(player, n >= SpindleDoor.SLOTS and "The door knows you. It opens." or ("Twelve sockets. You hold %d of the shards."):format(n))
		end)
		task.spawn(loomRoom, door)
	end
	task.spawn(function()
		while true do
			pcall(SpindleDoor.refresh)
			task.wait(CHECK_EVERY)
		end
	end)
end

return SpindleDoor
