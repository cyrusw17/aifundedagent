--!nonstrict
-- Scooping hay and selling it. Every scoop and sale is decided here, never on the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Game)
local Economy = require(Shared.Economy)
local Data = require(script.Parent.Data)

local Gameplay = {}

local rng = Random.new()

-- Hay hides needles the player cannot see. The count is rolled per scoop.
local function rollNeedles(hay)
	local count = 0
	for _ = 1, hay do
		if rng:NextNumber() < Config.NeedleChancePerHay then
			count += 1
		end
	end
	return count
end

function Gameplay.wireBarrel(barrel, prompt)
	local scoops = Config.BarrelScoops
	barrel:SetAttribute("Scoops", scoops)

	prompt.Triggered:Connect(function(player)
		local state = Data.get(player)
		if not state or scoops <= 0 then
			return
		end

		local hay = Config.ShovelHayPerScoop
		if state.loadHay + hay > Config.WheelbarrowCapacity then
			Data.toast(player, "Your wheelbarrow is full. Take it to the hay shop.")
			return
		end

		scoops -= 1
		state.loadHay += hay
		state.loadNeedles += rollNeedles(hay)
		barrel:SetAttribute("Scoops", scoops)
		Data.sync(player)

		if scoops <= 0 then
			prompt.Enabled = false
			task.delay(Config.BarrelRefillSeconds, function()
				scoops = Config.BarrelScoops
				barrel:SetAttribute("Scoops", scoops)
				prompt.Enabled = true
			end)
		end
	end)
end

function Gameplay.wireShop(prompt)
	prompt.Triggered:Connect(function(player)
		local state = Data.get(player)
		if not state then
			return
		end
		if state.loadHay <= 0 then
			Data.toast(player, "Your wheelbarrow is empty. Scoop some hay first.")
			return
		end

		local hay, needles = state.loadHay, state.loadNeedles
		local value = Economy.rawLoadValue(hay, needles)
		state.cash += value
		state.loadHay = 0
		state.loadNeedles = 0
		Data.sync(player)
		Data.toast(
			player,
			("Sold %d hay for $%d. The shop found %d needles in it and paid $1 each."):format(hay, value, needles)
		)
	end)
end

return Gameplay
