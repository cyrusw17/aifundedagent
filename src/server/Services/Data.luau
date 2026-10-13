--!nonstrict
-- Player state. The server owns it. Attributes mirror what the HUD needs to show.
-- Saving uses a plain DataStore for now. We will swap in a session-locked store before launch.
--
-- Every player has three save slots. On joining, the client shows the slot picker (Save 1-3 for empty slots, Load 1-3
-- for used ones) and nothing is loaded until one is picked: Data.get(player) is nil until then, and Data.loaded fires
-- once it is ready. A slot keeps cash, owned trucks and trailers, gloves, the needles in your pocket, the land plot
-- with everything built on it (and the needles in its bin), the bank account (balance, loans and history, see
-- Bank.luau), and quest progress (Quests.luau).
-- Players listed in Config/Land.luau Presets start an empty slot as their preset farm instead of from nothing.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local LandConfig = require(ReplicatedStorage.Shared.Config.Land)

local Data = {}

Data.SLOTS = 3
Data.loaded = Instance.new("BindableEvent") -- (player) once a save slot is loaded
Data.beforeSave = nil -- optional function(player), called just before a save is written (Land keeps its plot current)

local states = {}
local summaries = {} -- player -> { [slot] = summary }, read once on join
local choosing = {} -- player -> true while a slot is loading
-- player -> true when their saves couldn't be read on join. They still play (Studio with API access off lands here),
-- but nothing is written for them, so an unreadable save is never overwritten by a fresh one.
local offline = {}
local INFINITE_CASH = 1e9 -- shown and spendable while Config.InfiniteMoney is on
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

local function legacyKey(player)
	return "Player_" .. player.UserId
end

local function slotKey(player, slot)
	return ("Player_%d_Slot%d"):format(player.UserId, slot)
end

local function indexKey(player)
	return ("Player_%d_Slots"):format(player.UserId)
end

local function read(key)
	if not store then
		return false, nil
	end
	local ok, result = pcall(function()
		return store:GetAsync(key)
	end)
	if not ok then
		warn("[Needlewood] load failed for " .. key .. ": " .. tostring(result))
	end
	return ok, result
end

local function write(key, value)
	if not store then
		return false
	end
	local ok, err = pcall(function()
		store:SetAsync(key, value)
	end)
	if not ok then
		warn("[Needlewood] save failed for " .. key .. ": " .. tostring(err))
	end
	return ok
end

local function copy(value)
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = copy(v)
	end
	return out
end

local function stringList(list)
	local out = {}
	if typeof(list) == "table" then
		for _, id in list do
			if typeof(id) == "string" then
				table.insert(out, id)
			end
		end
	end
	return out
end

-- { [needleId] = count } with only sane entries.
local function countMap(map)
	local out = {}
	if typeof(map) == "table" then
		for id, count in map do
			if typeof(id) == "string" and typeof(count) == "number" and count >= 1 then
				out[id] = math.floor(count)
			end
		end
	end
	return out
end
Data.countMap = countMap

local function presetFor(player)
	for _, preset in LandConfig.Presets do
		if table.find(preset.userIds, player.UserId) then
			return preset
		end
	end
	return nil
end

-- The bank account part of a save (Bank.luau), checked field by field.
local function bankFrom(saved)
	if typeof(saved) ~= "table" then
		return nil
	end
	local function num(v)
		return typeof(v) == "number" and v == v and v or 0
	end
	local bank = { balance = num(saved.balance), earned = num(saved.earned), loans = {}, history = {} }
	if typeof(saved.loans) == "table" then
		for kind, loan in saved.loans do
			if typeof(kind) == "string" and typeof(loan) == "table" and num(loan.owed) > 0 then
				bank.loans[kind] = { owed = num(loan.owed), principal = num(loan.principal), item = typeof(loan.item) == "string" and loan.item or nil, takenAt = num(loan.takenAt) }
			end
		end
	end
	if typeof(saved.history) == "table" then
		for _, h in saved.history do
			if typeof(h) == "table" and typeof(h.kind) == "string" then
				table.insert(bank.history, { t = num(h.t), kind = h.kind, amount = num(h.amount), note = typeof(h.note) == "string" and h.note or "" })
			end
		end
	end
	return bank
end

local function summarize(saved)
	local bank = bankFrom(saved.bank)
	return {
		cash = (typeof(saved.cash) == "number" and saved.cash or 0) + (bank and bank.balance or 0),
		plot = typeof(saved.land) == "table" and saved.land.owned and saved.land.plot or nil,
		trucks = #stringList(saved.trucks),
		savedAt = os.time(),
	}
end

-- A farm from a save (Land.luau): { owned, plot, items, needles, crew, expansions, binSorted, theme, savedAt }.
local function landFrom(land)
	if typeof(land) ~= "table" or typeof(land.items) ~= "table" then
		return nil
	end
	return {
		owned = land.owned == true,
		plot = typeof(land.plot) == "number" and land.plot or nil,
		items = land.items,
		needles = countMap(land.needles),
		crew = typeof(land.crew) == "table" and land.crew or {}, -- farm crew user ids
		expansions = typeof(land.expansions) == "number" and land.expansions or nil, -- rows bought
		binSorted = land.binSorted == true or nil, -- the needle bin has type dividers
		theme = typeof(land.theme) == "string" and land.theme or nil, -- plot theme id
		savedAt = typeof(land.savedAt) == "number" and land.savedAt or nil, -- os.time() of the last save
	}
end

-- A fresh state from a saved table (or an empty one).
local function stateFrom(saved)
	saved = typeof(saved) == "table" and saved or {}
	local state = {
		cash = typeof(saved.cash) == "number" and saved.cash or 0,
		loadHay = 0,
		loadNeedles = 0,
		carryBale = nil,
		trucks = stringList(saved.trucks),
		trailers = stringList(saved.trailers),
		gear = stringList(saved.gear), -- other things bought once and kept, like "wheelbarrow"
		pocket = countMap(saved.pocket), -- needles in the pocket (Needle.luau)
		thatch = typeof(saved.thatch) == "number" and math.max(0, math.floor(saved.thatch)) or 0, -- carried (Press.luau)
		materials = countMap(saved.materials), -- building material units carried, { [materialId] = units } (Mixer.luau)
		finds = countMap(saved.finds), -- foreign objects kept, { [findId] = count } (Finds.luau)
		-- gloves: { owned = { id, ... }, worn = id, brokeFirstBale = true? }, kept by Gloves.luau. nil in saves from
		-- before gloves were saved.
		gloves = typeof(saved.gloves) == "table" and {
			owned = stringList(saved.gloves.owned),
			worn = saved.gloves.worn,
			brokeFirstBale = saved.gloves.brokeFirstBale == true or nil,
		} or nil,
		-- bank: { balance, earned, loans = { truck|land = { owed, principal, item, takenAt } }, history } (Bank.luau)
		bank = bankFrom(saved.bank),
		-- land: { owned = true, plot = index, items = { { id, gx, gz, dir, stored }, ... }, needles = { [id] = count } }
		-- once a plot is bought. needles are the ones in the plot's bin.
		land = nil,
		-- tutorial: { done = bool, flags = { sold = true, ... } } (Tutorial.luau)
		tutorial = typeof(saved.tutorial) == "table" and saved.tutorial or {},
		-- settings: { effects, uiSize, shadows, labels } (Settings.luau checks each value)
		settings = typeof(saved.settings) == "table" and saved.settings or {},
		-- quests: steps, finished quests, earned quest rewards and today's bounties (Quests.luau owns the shape).
		quests = typeof(saved.quests) == "table" and saved.quests or nil,
	}
	state.savedCash = state.cash
	state.land = landFrom(saved.land)
	state.land2 = landFrom(saved.land2) -- a second farm, bought once the first one is outgrown
	return state
end

function Data.get(player)
	return states[player]
end

function Data.sync(player)
	local state = states[player]
	if not state then
		return
	end
	if Config.InfiniteMoney then
		state.cash = INFINITE_CASH -- topped back up after every purchase
	end
	-- Cash is what you can spend: wallet plus bank balance, since shops take from the bank once the wallet is empty.
	-- Wallet, BankBalance and LoanOwed are the real figures for the bank HUD (they stay real with InfiniteMoney on).
	local bank = state.bank
	local balance = bank and bank.balance or 0
	local owed = 0
	for _, loan in (bank and bank.loans or {}) do
		owed += loan.owed
	end
	player:SetAttribute("Cash", if Config.InfiniteMoney then state.cash else state.cash + balance)
	player:SetAttribute("Wallet", if Config.InfiniteMoney then state.savedCash or 0 else state.cash)
	player:SetAttribute("BankBalance", balance)
	player:SetAttribute("LoanOwed", owed)
	player:SetAttribute("LoadHay", state.loadHay)
	player:SetAttribute("LoadCap", Config.CarryCapacity)
	player:SetAttribute("Carrying", state.carryBale ~= nil)
	player:SetAttribute("OwnedTrucks", table.concat(state.trucks, ","))
	player:SetAttribute("OwnedTrailers", table.concat(state.trailers, ","))
	local held = 0
	for _, count in state.pocket do
		held += count
	end
	player:SetAttribute("NeedlesHeld", held)
	player:SetAttribute("Thatch", state.thatch or 0)
end

function Data.toast(player, text)
	player:SetAttribute("ToastText", text)
	player:SetAttribute("ToastId", (player:GetAttribute("ToastId") or 0) + 1)
end

-- Reads the slot summaries for the picker. A save from before slots existed becomes slot 1.
local function loadSummaries(player)
	local ok, index = read(indexKey(player))
	local list = {}
	if ok and typeof(index) == "table" then
		for slot = 1, Data.SLOTS do
			if typeof(index[tostring(slot)]) == "table" then
				list[slot] = index[tostring(slot)]
			end
		end
	elseif ok then
		local okOld, old = read(legacyKey(player))
		if not okOld then
			ok = false
		elseif typeof(old) == "table" then
			if write(slotKey(player, 1), old) and write(indexKey(player), { ["1"] = summarize(old) }) then
				list[1] = summarize(old)
			else
				ok = false -- keep the old save untouched until it can be moved
			end
		end
	end
	offline[player] = not ok or nil
	summaries[player] = list
	return ok
end

-- What the picker shows: one entry per slot.
function Data.listSlots(player)
	while summaries[player] == nil and player.Parent do
		task.wait(0.1)
	end
	local list = summaries[player] or {}
	local preset = presetFor(player)
	local out = {}
	for slot = 1, Data.SLOTS do
		local s = list[slot]
		out[slot] = s and { used = true, cash = s.cash, plot = s.plot, trucks = s.trucks, savedAt = s.savedAt }
			or { used = false, preset = preset ~= nil, plot = preset and preset.land and preset.land.plot or nil }
	end
	return out, store ~= nil and player:GetAttribute("SavesOnline") == true
end

-- Loads a slot and starts the game for this player. plot is the plot they picked in the picker (or nil): Land.luau
-- puts the save's farm there, or buys it for a save with no land yet. Returns ok and a message.
function Data.choose(player, slot, plot)
	if states[player] or choosing[player] then
		return false, "Already playing."
	end
	if typeof(slot) ~= "number" or slot < 1 or slot > Data.SLOTS or math.floor(slot) ~= slot then
		return false, "No such save."
	end
	choosing[player] = true
	local used = summaries[player] and summaries[player][slot] ~= nil and not offline[player]
	local saved = nil
	if used then
		local ok, result = read(slotKey(player, slot))
		if not ok then
			choosing[player] = nil
			return false, "Couldn't read that save. Try again."
		end
		saved = result
	end
	local fresh = saved == nil
	if fresh then
		local preset = presetFor(player)
		saved = preset and copy({ cash = preset.cash, trucks = preset.trucks, trailers = preset.trailers, land = preset.land })
	end
	if not player.Parent then
		choosing[player] = nil
		return false, nil
	end
	local state = stateFrom(saved)
	state.slot = slot
	state.fresh = fresh
	state.pickedPlot = typeof(plot) == "number" and plot or nil
	states[player] = state
	choosing[player] = nil
	player:SetAttribute("SaveSlot", slot)
	Data.sync(player)
	Data.loaded:Fire(player)
	if fresh then
		task.spawn(Data.save, player) -- so the slot shows as used next time
	end
	return true, used and ("Loaded save %d."):format(slot) or ("Started save %d."):format(slot)
end

function Data.save(player)
	local state = states[player]
	if not state or not store or not state.slot or offline[player] then
		return
	end
	if Data.beforeSave then
		pcall(Data.beforeSave, player)
	end
	-- With infinite money on, the save keeps the balance the player had before, not the test cash.
	local cash = if Config.InfiniteMoney then state.savedCash or 0 else state.cash
	local saved = {
		cash = cash,
		trucks = state.trucks,
		trailers = state.trailers,
		gear = state.gear,
		pocket = state.pocket,
		thatch = state.thatch,
		materials = state.materials,
		finds = state.finds,
		gloves = state.gloves,
		land = state.land,
		land2 = state.land2,
		bank = state.bank,
		tutorial = state.tutorial,
		settings = state.settings,
		quests = state.quests,
	}
	if write(slotKey(player, state.slot), saved) then
		local list = summaries[player] or {}
		list[state.slot] = summarize(saved)
		summaries[player] = list
		local index = {}
		for slot, s in list do
			index[tostring(slot)] = s
		end
		write(indexKey(player), index)
	end
end

function Data.release(player)
	Data.save(player)
	states[player] = nil
	summaries[player] = nil
	choosing[player] = nil
	offline[player] = nil
end

local function onPlayerAdded(player)
	local online = loadSummaries(player)
	player:SetAttribute("SavesOnline", online)
end

function Data.start()
	-- The slot picker's remotes (src/client/Saves.client.luau).
	local remotes = Instance.new("Folder")
	remotes.Name = "SaveSlots"
	local list = Instance.new("RemoteFunction")
	list.Name = "List"
	list.Parent = remotes
	local choose = Instance.new("RemoteFunction")
	choose.Name = "Choose"
	choose.Parent = remotes
	remotes.Parent = ReplicatedStorage
	list.OnServerInvoke = function(player)
		local ok, slots, online = pcall(Data.listSlots, player)
		if not ok then
			warn("[Needlewood] slot list failed: " .. tostring(slots))
			return {}, false
		end
		return slots, online
	end
	choose.OnServerInvoke = function(player, slot, plot)
		local ok, result, message = pcall(Data.choose, player, slot, plot)
		if not ok then
			choosing[player] = nil
			warn("[Needlewood] slot load failed: " .. tostring(result))
			return false, "Something went wrong loading that save."
		end
		return result, message
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(Data.release)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
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
