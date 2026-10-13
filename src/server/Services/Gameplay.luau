--!nonstrict
-- Selling hay at the shop. Every sale is decided here, never on the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Game)
local Economy = require(Shared.Economy)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)

local Gameplay = {}

local rng = Random.new()

function Gameplay.wireShop(prompt)
	prompt.Triggered:Connect(function(player)
		local state = Data.get(player)
		if not state then
			return
		end

		-- A barrel in your arms is sold along with the hay you scooped.
		local barrelHay = state.carry and state.carry * Config.ShovelHayPerScoop or 0
		if state.loadHay <= 0 and barrelHay <= 0 then
			Data.toast(player, "You have no hay to sell. Scoop some or pick up a barrel.")
			return
		end

		local hay = state.loadHay + barrelHay
		local needles = state.loadNeedles + Economy.rollNeedles(rng, barrelHay, Config.NeedleChancePerHay)
		local value = Economy.rawLoadValue(hay, needles)

		state.cash += value
		state.loadHay = 0
		state.loadNeedles = 0
		if state.carry then
			state.carry = nil
			Avatar.clearCarry(player)
		end
		Data.sync(player)
		Data.toast(
			player,
			("Sold %d hay for $%d. The shop found %d needles in it and paid $1 each."):format(hay, value, needles)
		)
	end)
end

return Gameplay
