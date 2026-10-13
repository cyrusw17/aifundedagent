--!nonstrict
-- Player state. The server owns it. Attributes mirror what the HUD needs to show.
-- Saving uses a plain DataStore for now. We will swap in a session-locked store before launch.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Game)

local Data = {}

local states = {}
local store = nil

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("NeedlewoodV1")
	end)
	if ok then
		store = result
	else
		warn("[Needlewood] DataStore unavailable, progress will not save: " .. tostring(result))
	end
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

function Data.get(player)
	return states[player]
end

function Data.sync(player)
	local state = states[player]
	if not state then
		return
	end
	player:SetAttribute("Cash", state.cash)
	player:SetAttribute("LoadHay", state.loadHay)
	player:SetAttribute("LoadCap", Config.CarryCapacity)
	player:SetAttribute("Carrying", state.carryBarrel ~= nil)
end

function Data.toast(player, text)
	player:SetAttribute("ToastText", text)
	player:SetAttribute("ToastId", (player:GetAttribute("ToastId") or 0) + 1)
end

function Data.load(player)
	local state = { cash = 0, loadHay = 0, loadNeedles = 0, carryBarrel = nil }
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			if typeof(saved) == "table" and typeof(saved.cash) == "number" then
				state.cash = saved.cash
			end
		else
			warn("[Needlewood] load failed for " .. player.Name .. ": " .. tostring(saved))
		end
	end
	states[player] = state
	Data.sync(player)
end

function Data.save(player)
	local state = states[player]
	if not state or not store then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(keyFor(player), { cash = state.cash })
	end)
	if not ok then
		warn("[Needlewood] save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

function Data.release(player)
	Data.save(player)
	states[player] = nil
end

function Data.start()
	Players.PlayerAdded:Connect(Data.load)
	Players.PlayerRemoving:Connect(Data.release)
	for _, player in Players:GetPlayers() do
		task.spawn(Data.load, player)
	end
	game:BindToClose(function()
		for player in states do
			Data.save(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for player in states do
				task.spawn(Data.save, player)
			end
		end
	end)
end

return Data
