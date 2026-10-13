--!nonstrict
-- Collision groups. Loose hay and barrel debris never collide with players, so a pile cannot trip or fling anyone.
local PhysicsService = game:GetService("PhysicsService")

local Groups = { Loose = "Loose", Players = "Players" }

for _, name in Groups do
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
end
local ok, err = pcall(function()
	PhysicsService:CollisionGroupSetCollidable(Groups.Loose, Groups.Players, false)
end)
if not ok then
	warn("[Needlewood] collision groups not set: " .. tostring(err))
end

return Groups
