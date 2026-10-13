--!nonstrict
-- Player state. The server owns it. Attributes mirror what the HUD needs to show.
-- Saves are session-locked: a slot records which server has it open (_lock), every write goes through UpdateAsync and
-- refuses to land if another live server holds the lock, and each save carries a version (_v) that migrations bring
-- up to date on load. The copy loaded at the start of each session is kept under a backup key, and a slot whose main
-- copy has gone missing loads from it.
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
local Alloys = require(ReplicatedStorage.Shared.Config.Alloys)

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

local function backupKey(player, slot)
	return slotKey(player, slot) .. "_Backup"
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

-- Read-modify-write. transform gets the stored value and returns the new one, or nil to leave it alone. ok is false
-- when the store couldn't be reached.
local function update(key, transform)
	if not store then
		return false
	end
	local ok, err = pcall(function()
		store:UpdateAsync(key, transform)
	end)
	if not ok then
		warn("[Needlewood] save failed for " .. key .. ": " .. tostring(err))
	end
	return ok
end

-- Session locks. In Studio every session has the same empty JobId, so a Studio test never locks itself out.
local JOB = game.JobId
local LOCK_TTL = math.max(Config.AutosaveSeconds * 3, 180) -- a lock no server refreshed for this long is stale
local function heldElsewhere(saved)
	local lock = typeof(saved) == "table" and saved._lock
	return typeof(lock) == "table" and lock.job ~= JOB and typeof(lock.at) == "number" and os.time() - lock.at < LOCK_TTL
end

-- Save versions. MIGRATIONS[v] turns a version v save into version v + 1. Saves from before versions are version 0.
local SAVE_VERSION = 1
local MIGRATIONS = {
	[0] = function(saved)
		return saved -- version 1 is the shape version 0 already had; stateFrom fills anything missing
	end,
}
-- The save brought up to SAVE_VERSION, or nil when it is from a newer version of the game than this server runs.
local function migrate(saved)
	local v = typeof(saved._v) == "number" and saved._v or 0
	if v > SAVE_VERSION then
		return nil
	end
	while v < SAVE_VERSION do
		saved = MIGRATIONS[v](saved)
		v += 1
	end
	saved._v = v
	return saved
end
Data.SAVE_VERSION = SAVE_VERSION
Data.migrate = migrate
Data.heldElsewhere = heldElsewhere

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

-- A farm from a save (Land.luau): { owned, plot, items, needles, crew, expansions, binSorted, binPolisher, theme, name, savedAt }.
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
		binPolisher = land.binPolisher == true or nil, -- the needle bin has a polishing wheel
		theme = typeof(land.theme) == "string" and land.theme or nil, -- plot theme id
		name = typeof(land.name) == "string" and #land.name <= 40 and land.name or nil, -- the farm's name, already filtered
		savedAt = typeof(land.savedAt) == "number" and land.savedAt or nil, -- os.time() of the last save
	}
end

-- Trade locks (Trade.luau): { [needleKey] = { { count, untilTime }, ... } } for mythic needles received in a trade.
-- Locks that have run out are dropped on load.
local function tradeLocksFrom(saved)
	local out = {}
	if typeof(saved) ~= "table" then
		return out
	end
	local now = os.time()
	for key, list in saved do
		if typeof(key) == "string" and typeof(list) == "table" then
			local locks = {}
			for _, lock in list do
				if typeof(lock) == "table" and typeof(lock.count) == "number" and lock.count >= 1 and typeof(lock.untilTime) == "number" and lock.untilTime > now then
					table.insert(locks, { count = math.floor(lock.count), untilTime = lock.untilTime })
				end
			end
			if #locks > 0 then
				out[key] = locks
			end
		end
	end
	return out
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
		-- named line presets, { { name, list } } (Blueprints.luau checks every entry when it reads them)
		lineBlueprints = typeof(saved.lineBlueprints) == "table" and saved.lineBlueprints or {},
		finds = countMap(saved.finds), -- foreign objects kept, { [findId] = count } (Finds.luau)
		secrets = countMap(saved.secrets), -- region secrets found, { [secretId] = 1 } (Wilds.luau)
		discovered = countMap(saved.discovered), -- regions and landmarks visited, { [id] = 1 } (Discoveries.luau)
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
		-- codex: { needles = { [id] = true }, hay = { [id] = true } } for the collection book (Codex.luau)
		codex = typeof(saved.codex) == "table" and saved.codex or {},
		-- quests: steps, finished quests, earned quest rewards and today's bounties (Quests.luau owns the shape).
		quests = typeof(saved.quests) == "table" and saved.quests or nil,
		tradeLocks = tradeLocksFrom(saved.tradeLocks), -- mythic needles received in a trade can't be traded on for a day
	}
	state.savedCash = state.cash
	state.land = landFrom(saved.land)
	state.land2 = landFrom(saved.land2) -- a second farm, bought once the first one is outgrown
	return state
end

-- The table a state saves as. With infinite money on, the save keeps the balance the player had before, not the test
-- cash.
local function toSave(state)
	return {
		cash = if Config.InfiniteMoney then state.savedCash or 0 else state.cash,
		trucks = state.trucks,
		trailers = state.trailers,
		gear = state.gear,
		pocket = state.pocket,
		thatch = state.thatch,
		materials = state.materials,
		lineBlueprints = state.lineBlueprints,
		finds = state.finds,
		secrets = state.secrets,
		discovered = state.discovered,
		gloves = state.gloves,
		land = state.land,
		land2 = state.land2,
		bank = state.bank,
		tutorial = state.tutorial,
		settings = state.settings,
		codex = state.codex,
		quests = state.quests,
		tradeLocks = state.tradeLocks,
	}
end

-- For SelfTests: the save shape without a DataStore.
Data.test = { stateFrom = stateFrom, toSave = toSave }

-- True when this player's slot is being written: loaded, the store reachable, and the save not set aside (read
-- failed on join, or another server took the slot's lock). Trades need it, so nothing traded can be lost.
function Data.isSaving(player)
	return states[player] ~= nil and store ~= nil and not offline[player]
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
	player:SetAttribute("Gear", table.concat(state.gear or {}, ",")) -- bought gear such as "wheelbarrow" (goal bar)
	local held = 0
	for _, count in state.pocket do
		held += count
	end
	player:SetAttribute("NeedlesHeld", held)
	player:SetAttribute("Thatch", state.thatch or 0)
	-- Every alloy, so a slot switch never leaves the last slot's numbers showing.
	for _, alloy in Alloys do
		player:SetAttribute("Material_" .. alloy.id, (state.materials or {})[alloy.id] or 0)
	end
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
	-- Wait for the slot list, so offline is known before anything can be written.
	while summaries[player] == nil and player.Parent do
		task.wait(0.1)
	end
	-- Always read the slot itself: the index can miss a slot whose index write failed, and a slot that looks empty
	-- must never be started fresh over real progress. Reading takes the slot's session lock; when another server still
	-- holds it (the player just left it and its last save is landing), wait a little and try again.
	local saved, restored = nil, false
	if not offline[player] then
		local locked = false
		for try = 1, 4 do
			locked = false
			local seen = nil
			local ok = update(slotKey(player, slot), function(current)
				seen, locked = nil, false
				if typeof(current) ~= "table" then
					return nil
				end
				if heldElsewhere(current) then
					locked = true
					return nil
				end
				current._lock = { job = JOB, at = os.time() }
				seen = current
				return current
			end)
			if not ok then
				choosing[player] = nil
				return false, "Couldn't read that save. Try again."
			end
			saved = seen
			if not locked or try == 4 or not player.Parent then
				break
			end
			task.wait(3)
		end
		if locked then
			choosing[player] = nil
			return false, "That save is still open on another server. Try again in a minute."
		end
		-- The slot is listed but its main copy is gone: load the backup.
		if saved == nil and summaries[player] and summaries[player][slot] ~= nil then
			local okBackup, backup = read(backupKey(player, slot))
			if okBackup and typeof(backup) == "table" then
				saved, restored = backup, true
			end
		end
		if saved then
			saved = migrate(saved)
			if not saved then
				choosing[player] = nil
				return false, "That save is from a newer version of the game. Rejoin to get the update."
			end
			-- The copy that loaded is a known good one: keep it as the backup.
			local good = copy(saved)
			good._lock = nil
			task.spawn(write, backupKey(player, slot), good)
		end
	end
	local used = saved ~= nil
	local fresh = saved == nil
	if fresh then
		local preset = presetFor(player)
		saved = preset and copy({ cash = preset.cash, trucks = preset.trucks, trailers = preset.trailers, land = preset.land })
		-- A preset farm's pieces were free, so removing them refunds nothing.
		for _, item in (saved and saved.land and saved.land.items or {}) do
			item.paid = 0
		end
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
	if fresh or restored then
		task.spawn(Data.save, player) -- so the slot shows as used next time, or the restored copy is the main one again
	end
	if restored then
		task.delay(3, function()
			if player.Parent then
				Data.toast(player, "Your save's main copy couldn't be found, so it was loaded from its backup.")
			end
		end)
	end
	return true, used and ("Loaded save %d."):format(slot) or ("Started save %d."):format(slot)
end

-- One write per player at a time, so an older snapshot can never land after a newer one. A save asked for while one
-- is writing waits for it, and the writer then saves once more with the newest state.
local saving, saveAgain, saveFinal = {}, {}, {}
local saveOnce
-- final (on leaving) also gives up the slot's session lock.
function Data.save(player, final)
	if final then
		saveFinal[player] = true
	end
	if saving[player] then
		saveAgain[player] = true
		while saving[player] do
			task.wait(0.1)
		end
		return
	end
	saving[player] = true
	repeat
		saveAgain[player] = nil
		local ok, err = pcall(saveOnce, player, saveFinal[player] == true)
		if not ok then
			warn("[Needlewood] save failed: " .. tostring(err))
		end
	until not saveAgain[player]
	saving[player] = nil
	saveFinal[player] = nil
end

saveOnce = function(player, final)
	local state = states[player]
	if not state or not store or not state.slot or offline[player] then
		return
	end
	if Data.beforeSave then
		pcall(Data.beforeSave, player)
	end
	local saved = toSave(state)
	saved._v = SAVE_VERSION
	saved._lock = if final then nil else { job = JOB, at = os.time() }
	local lost = false
	local ok = update(slotKey(player, state.slot), function(current)
		lost = heldElsewhere(current)
		if lost then
			return nil
		end
		return saved
	end)
	if lost then
		-- Another server opened this slot (this one stopped refreshing its lock): its copy wins, and this server stops
		-- writing so the two never overwrite each other.
		offline[player] = true
		warn(("[Needlewood] save %d for %d is open on another server; this server stopped saving it"):format(state.slot, player.UserId))
		Data.toast(player, "This save was opened on another server, so this server has stopped saving it.")
		return
	end
	if ok then
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

-- Saves every player in list at once (each a final save) and returns when all are done or after deadline seconds,
-- whichever is first, with how many finished. Shutdown has 30 seconds in all, so one at a time could run out of time
-- on a full server. save is for SelfTests; it defaults to a final Data.save.
function Data.saveAll(list, deadline, save)
	save = save or function(player)
		Data.save(player, true)
	end
	local left, done = #list, 0
	for _, player in list do
		task.spawn(function()
			local ok, err = pcall(save, player)
			if not ok then
				warn("[Needlewood] shutdown save failed: " .. tostring(err))
			end
			left -= 1
			done += 1
		end)
	end
	local stop = os.clock() + deadline
	while left > 0 and os.clock() < stop do
		task.wait(0.1)
	end
	return done
end

function Data.release(player)
	Data.save(player, true)
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
		local list = {}
		for player in states do
			table.insert(list, player)
		end
		Data.saveAll(list, 25)
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
