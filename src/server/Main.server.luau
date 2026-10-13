--!nonstrict
-- Server entry point. Every scoop, sale and save goes through the services so the server owns the truth.
local Services = script.Parent.Services

local Data = require(Services.Data)
local World = require(Services.World)

Data.start()
World.build()

print("[Needlewood] server started. Base camp is ready.")
