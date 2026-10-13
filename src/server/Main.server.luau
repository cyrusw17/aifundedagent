--!nonstrict
-- Server entry point. Every scoop, sale and save goes through the services so the server owns the truth.
local Services = script.Parent.Services

-- First of all, sweep anything Studio's Import 3D left in the Workspace into ServerStorage (Props.luau does that on
-- its first lookup). Done before anything yields, so a joining player never sees the imports piled up at spawn.
require(Services.Props).has("hay_bale")

local Data = require(Services.Data)
local Bank = require(Services.Bank)
local World = require(Services.World)
local Avatar = require(Services.Avatar)
local GloveLooks = require(Services.GloveLooks)
local Tutorial = require(Services.Tutorial)
local Settings = require(Services.Settings)
local Announce = require(Services.Announce)
local Codex = require(Services.Codex)
local NameTags = require(Services.NameTags)
local TruckSpots = require(Services.TruckSpots)

Data.start()
Bank.start()
Tutorial.start()
Settings.start()
Announce.start()
Codex.start()
NameTags.start()
TruckSpots.start()
Avatar.start()
GloveLooks.start()
require(Services.GildedSorters).start()
World.build()

print("[Needlewood] server started. Base camp is ready.")

-- Part budget. StreamingEnabled is on (default.project.json), but the server still holds every part and a client
-- streams in everything within the target radius; past this many, phones stutter and slow PCs take long to join. The count prints at start and again once the meadow has settled.
local PART_BUDGET = 40000
local function countParts(when)
	local parts = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	local line = ("[Needlewood] %d parts in the Workspace %s (budget %d)"):format(parts, when, PART_BUDGET)
	if parts > PART_BUDGET then
		warn(line .. ": over budget. Merge decor into meshes or cut decor parts.")
	else
		print(line)
	end
end
countParts("at start")
task.delay(60, countParts, "a minute in")

-- Studio only: set the Workspace attribute RunSelfTests = true and every suite in src/server/SelfTests runs.
require(Services.SelfTest).start()
