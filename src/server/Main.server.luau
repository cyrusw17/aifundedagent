--!strict
-- Server entry point. Every scoop, sale and save will go through here so the server owns the truth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)

print("[Needlewood] server started")
print(("[Needlewood] sample: 100 hay with 20 needles is worth $%d raw"):format(Economy.rawLoadValue(100, 20)))
