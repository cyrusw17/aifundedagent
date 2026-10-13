--!nonstrict
-- Sounds the client plays itself: the cash register when you sell, a ding when a needle goes into your pocket, and
-- the engine of every truck someone is driving (pitch climbs with speed). Ids and levels live in Config/Sounds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))
local player = Players.LocalPlayer

local function playFlat(def, pitch)
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume or 0.5
	sound.PlaybackSpeed = pitch or def.pitch or 1
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(5, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

task.spawn(function()
	local sale = ReplicatedStorage:WaitForChild("Sale", 30)
	if sale then
		sale.OnClientEvent:Connect(function()
			playFlat(Sounds.CashRegister)
		end)
	end
end)

-- A needle clicked into your pocket.
local lastHeld = player:GetAttribute("NeedlesHeld") or 0
player:GetAttributeChangedSignal("NeedlesHeld"):Connect(function()
	local held = player:GetAttribute("NeedlesHeld") or 0
	if held > lastHeld then
		playFlat(Sounds.NeedleDing)
	end
	lastHeld = held
end)

-- Truck engines: any VehicleSeat marked as a truck's seat hums while someone sits in it.
local engines = {} -- seat -> Sound

local function watchSeat(seat)
	if engines[seat] ~= nil or not seat:IsA("VehicleSeat") then
		return
	end
	local def = Sounds.TruckEngine
	local sound = Instance.new("Sound")
	sound.Name = "Engine"
	sound.SoundId = def.id
	sound.Volume = def.volume or 0.4
	sound.Looped = true
	sound.RollOffMaxDistance = def.distance or 90
	sound.RollOffMinDistance = 8
	sound.PlaybackSpeed = Sounds.EngineIdlePitch
	sound.Parent = seat
	engines[seat] = sound
	seat.AncestryChanged:Connect(function()
		if not seat:IsDescendantOf(Workspace) then
			engines[seat] = nil
			sound:Destroy()
		end
	end)
end

for _, d in Workspace:GetDescendants() do
	if d:IsA("VehicleSeat") then
		watchSeat(d)
	end
end
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("VehicleSeat") then
		watchSeat(d)
	end
end)

RunService.Heartbeat:Connect(function()
	for seat, sound in engines do
		if seat.Occupant then
			local speed = seat.AssemblyLinearVelocity.Magnitude
			local t = math.clamp(speed / Sounds.EngineTopSpeed, 0, 1)
			sound.PlaybackSpeed = Sounds.EngineIdlePitch + (Sounds.EngineTopPitch - Sounds.EngineIdlePitch) * t
			if not sound.IsPlaying then
				sound:Play()
			end
		elseif sound.IsPlaying then
			sound:Stop()
		end
	end
end)
