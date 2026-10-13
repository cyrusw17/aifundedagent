--!nonstrict
-- Server entry point. Every scoop, sale and save goes through the services so the server owns the truth.
local Services = script.Parent.Services

local Data = require(Services.Data)
local World = require(Services.World)
local Avatar = require(Services.Avatar)

Data.start()
Avatar.start()
World.build()

print("[Needlewood] server started. Base camp is ready.")
