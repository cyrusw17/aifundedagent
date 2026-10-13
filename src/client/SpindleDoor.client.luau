--!nonstrict
-- Opens the Spindle door on this screen only, for a player holding all twelve shards (SpindleDoor.luau publishes
-- SpindleShards). The local character's physics run here, so a door that is not solid on this client lets them in
-- while it stays shut for everyone else. StreamingEnabled-safe: the door is found by its tag whenever it streams in.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local SLOTS = 12

local function apply(door)
	local open = (player:GetAttribute("SpindleShards") or 0) >= SLOTS
	door.CanCollide = not open
	door.Transparency = open and 0.8 or 0
end

local function applyAll()
	for _, door in CollectionService:GetTagged("SpindleDoor") do
		apply(door)
	end
end

CollectionService:GetInstanceAddedSignal("SpindleDoor"):Connect(apply)
player:GetAttributeChangedSignal("SpindleShards"):Connect(applyAll)
applyAll()
