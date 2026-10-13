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

Data.start()
Bank.start()
Tutorial.start()
Avatar.start()
GloveLooks.start()
World.build()

print("[Needlewood] server started. Base camp is ready.")
