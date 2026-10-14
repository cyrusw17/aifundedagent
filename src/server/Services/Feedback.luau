--!nonstrict
-- Sounds and the Cash leaderstat. Sounds come from Config/Sounds. A sound played here at a part or a spot is heard
-- by everyone nearby; a sale is heard only by the seller (the client plays it when the Sale event fires).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local Feedback = {}

local saleRemote = nil
local juiceRemote = nil

local function makeSound(def, pitch)
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume or 0.5
	sound.PlaybackSpeed = pitch or def.pitch or 1
	sound.RollOffMaxDistance = def.distance or 60
	sound.RollOffMinDistance = 6
	return sound
end

-- Plays the named sound at a part or a position. pitchScale multiplies its pitch.
function Feedback.play(name, at, pitchScale)
	local def = Sounds[name]
	if not def or not at or def.id == "" then
		return
	end
	local parent = at
	if typeof(at) == "Vector3" then
		local holder = Instance.new("Attachment")
		holder.WorldPosition = at
		holder.Parent = Workspace.Terrain
		Debris:AddItem(holder, 4)
		parent = holder
	elseif typeof(at) ~= "Instance" or not at.Parent then
		return
	end
	local sound = makeSound(def, (def.pitch or 1) * (pitchScale or 1))
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 4)
end

-- How high a needle worth this much dings, relative to the base ding.
function Feedback.needlePitch(value)
	local ratio = math.max(value or Sounds.NeedleBaseValue, 1) / Sounds.NeedleBaseValue
	return math.clamp(1 + Sounds.NeedlePitchPerTenfold * math.log10(ratio), 0.8, 2.2)
end

-- A needle ding at a part or spot, pitched by what the needle is worth.
function Feedback.needle(at, value)
	Feedback.play("NeedleDing", at, Feedback.needlePitch(value))
end

-- The cash register, for the seller only. Call it on every sale.
function Feedback.sale(player, amount)
	if saleRemote and player and player.Parent then
		saleRemote:FireClient(player, amount or 0)
	end
end

-- A little game feel for one player's own screen (Juice.client.luau): "burst" (a bale smashed: a 40 ms hit-stop and
-- a jolt), "combo" (a third quick scoop and up: a tiny shake, stronger with amount).
function Feedback.juice(player, kind, amount)
	if juiceRemote and player and typeof(player) == "Instance" and player.Parent then
		juiceRemote:FireClient(player, kind, amount or 1)
	end
end

-- A puff of dust off the ground at a spot (the rake dragging, hay landing). Everyone nearby sees it.
function Feedback.dust(at, color, amount)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = at
	holder.Parent = Workspace.Terrain
	local puff = Instance.new("ParticleEmitter")
	puff.Rate = 0
	puff.Lifetime = NumberRange.new(0.5, 1.1)
	puff.Speed = NumberRange.new(1.5, 4)
	puff.SpreadAngle = Vector2.new(70, 70)
	puff.Acceleration = Vector3.new(0, 1.5, 0)
	puff.Drag = 3
	puff.Color = ColorSequence.new(color or Color3.fromRGB(196, 178, 140))
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.8) })
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	puff.LightInfluence = 1
	puff.Parent = holder
	puff:Emit(amount or 10)
	Debris:AddItem(holder, 1.5)
end

-- The Cash column in the player list, kept in step with the Cash attribute Data publishes.
local function addLeaderstats(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	local function update()
		local value = player:GetAttribute("Cash")
		cash.Value = typeof(value) == "number" and math.floor(value) or 0
	end
	update()
	player:GetAttributeChangedSignal("Cash"):Connect(update)
	cash.Parent = stats
	stats.Parent = player
end

function Feedback.init()
	saleRemote = Instance.new("RemoteEvent")
	saleRemote.Name = "Sale"
	saleRemote.Parent = ReplicatedStorage
	juiceRemote = Instance.new("RemoteEvent")
	juiceRemote.Name = "Juice"
	juiceRemote.Parent = ReplicatedStorage
	Players.PlayerAdded:Connect(addLeaderstats)
	for _, player in Players:GetPlayers() do
		if not player:FindFirstChild("leaderstats") then
			addLeaderstats(player)
		end
	end
end

return Feedback
