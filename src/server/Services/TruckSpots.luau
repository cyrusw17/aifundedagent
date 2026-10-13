--!nonstrict
-- Where each player's trucks are, for the map (Menus.client.luau). With streaming a client only has the trucks near
-- it, so the server, which has them all, publishes them every couple of seconds as the player attribute
-- "TruckSpots" = "x,z;x,z" (rounded studs). Trucks are models with TruckId and OwnerId attributes (Vehicles.luau).
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local TruckSpots = {}

local EVERY = 2 -- seconds

local trucks = {}
local function note(d)
	if d:IsA("Model") and d:GetAttribute("TruckId") then
		trucks[d] = true
	end
end

function TruckSpots.publish()
	local byOwner = {}
	for model in trucks do
		local owner = model.Parent and model:GetAttribute("OwnerId")
		if owner then
			local p = model:GetPivot().Position
			byOwner[owner] = byOwner[owner] or {}
			table.insert(byOwner[owner], ("%d,%d"):format(math.round(p.X), math.round(p.Z)))
		end
	end
	for _, player in Players:GetPlayers() do
		local list = byOwner[player.UserId]
		if list then
			table.sort(list)
		end
		local value = list and table.concat(list, ";") or ""
		if player:GetAttribute("TruckSpots") ~= value then
			player:SetAttribute("TruckSpots", value)
		end
	end
end

function TruckSpots.start()
	for _, d in Workspace:GetDescendants() do
		note(d)
	end
	Workspace.DescendantAdded:Connect(note)
	Workspace.DescendantRemoving:Connect(function(d)
		trucks[d] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(EVERY)
			pcall(TruckSpots.publish)
		end
	end)
end

return TruckSpots
