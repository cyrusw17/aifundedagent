--!nonstrict
-- Player state. The server owns it. Attributes mirror what the HUD needs to show.
-- Saves are session-locked: a profile records which server has it open (_lock), every write goes through UpdateAsync
-- and refuses to land if another live server holds the lock, and each save carries a version (_v) that migrations
-- bring up to date on load. The copy loaded at the start of each session is kept under a backup key, and a profile
-- whose main copy has gone missing loads from it.
--
-- Every player has one profile, loaded on joining and saved every Config.AutosaveSeconds and on leaving. There is no
-- picker: Data.get(player) is nil until the profile has loaded, then Data.loaded fires and the player attribute
-- "SaveSlot" is set to 1 (clients read it as "your game is loaded"). A profile keeps cash, owned trucks and trailers,
-- gloves, the needles in your pocket, the land plot with everything built on it (and the needles in its bin), the
-- bank account (balance, loans and history, see Bank.luau), and quest progress (Quests.luau). The farm goes back on
-- its old plot when that is free on this server, else on another free one (Land.luau).
-- Profiles started before this replaced the three save slots: the first load copies over the slot played last.
-- Players listed in Config/Land.luau Presets start a new profile as their preset farm instead of from nothing.
-- Players listed in Config/Game DevFreshStart start from nothing on every join (see justReborn for the one exception).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local LandConfig = require(ReplicatedStorage.Shared.Config.Land)
local Alloys = require(ReplicatedStorage.Shared.Config.Alloys)
local NeedleIndex = require(ReplicatedStorage.Shared.NeedleIndex)

local Data = {}

Data.loaded = Instance.new("BindableEvent") -- (player) once the profile is loaded
Data.beforeSave = nil -- optional function(player), called just before a save is written (Land keeps its plot current)

local states = {}
local loading = {} -- player -> true while the profile is loading
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

local function profileKey(player)
	return ("Player_%d_Profile"):format(player.UserId)
end

local function backupKey(player)
	return profileKey(player) .. "_Backup"
end

-- The old three-slot saves, read only to move a player onto a profile.
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
-- Lets go of a profile this server locked but never loaded (the player left mid-load, or the copy couldn't be used),
-- so a rejoin isn't refused until the lock goes stale. Only our own lock is cleared.
local function releaseLock(player)
	task.spawn(update, profileKey(player), function(current)
		if typeof(current) == "table" and typeof(current._lock) == "table" and current._lock.job == JOB then
			current._lock = nil
			return current
		end
		return nil
	end)
end

local function heldElsewhere(saved)
	local lock = typeof(saved) == "table" and saved._lock
	return typeof(lock) == "table" and lock.job ~= JOB and typeof(lock.at) == "number" and os.time() - lock.at < LOCK_TTL
end

-- Save versions. MIGRATIONS[v] turns a version v save into version v + 1. Saves from before versions are version 0.
local SAVE_VERSION = 2
local MIGRATIONS = {
	[0] = function(saved)
		return saved -- version 1 is the shape version 0 already had; stateFrom fills anything missing
	end,
	[1] = function(saved)
		return saved -- version 2 adds rebirth (Rebirth.luau); a save without it has never been reborn
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
	bank.sold = typeof(saved.sold) == "number" and saved.sold == saved.sold and saved.sold or bank.earned
	if typeof(saved.loans) == "table" then
		for kind, loan in saved.loans do
			if typeof(kind) == "string" and typeof(loan) == "table" and num(loan.owed) > 0 then
				bank.loans[kind] = { owed = num(loan.owed), principal = num(loan.principal), held = math.max(0, num(loan.held)), item = typeof(loan.item) == "string" and loan.item or nil, takenAt = num(loan.takenAt) }
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
		-- price hold for needle bins: an index into Machines' HOLD_STEPS, nil when off (Machines.needleBin)
		needleHold = typeof(saved.needleHold) == "number" and math.clamp(math.floor(saved.needleHold), 1, 4) or nil,
		-- the needle index (NeedleIndex.luau): { found = { [entry] = true }, paid = { [milestone] = true } }
		needleIndex = NeedleIndex.clean(saved.needleIndex),
		finds = countMap(saved.finds), -- foreign objects kept, { [findId] = count } (Finds.luau)
		-- finder's rewards already paid in this profile, { [findId] = 1 }: paid once per kind, ever, even if the find is
		-- later traded away (Finds.luau)
		findsPaid = countMap(saved.findsPaid),
		-- earned tool skins (ToolSkins.luau): { owned = { id, ... }, worn = { Shovel = id?, Rake = id? } }
		skins = {
			owned = stringList(typeof(saved.skins) == "table" and saved.skins.owned or nil),
			worn = typeof(saved.skins) == "table" and typeof(saved.skins.worn) == "table" and {
				Shovel = typeof(saved.skins.worn.Shovel) == "string" and saved.skins.worn.Shovel or nil,
				Rake = typeof(saved.skins.worn.Rake) == "string" and saved.skins.worn.Rake or nil,
			} or {},
		},
		secrets = countMap(saved.secrets), -- region secrets found, { [secretId] = 1 } (Wilds.luau)
		discovered = countMap(saved.discovered), -- regions and landmarks visited, { [id] = 1 } (Discoveries.luau)
		festivals = countMap(saved.festivals), -- festival ribbons earned, { ["<week>:<region>"] = 1 } (Festival.luau)
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
		-- contracts: today's daily contracts, { day, tier, n = { [i] = count }, paid = { [i] = true }, bonus } (Orders.luau)
		contracts = typeof(saved.contracts) == "table" and saved.contracts or nil,
		-- rebirth: { count, at, soldAt = Bank sold at the last rebirth } (Rebirth.luau), nil before the first
		rebirth = typeof(saved.rebirth) == "table" and typeof(saved.rebirth.count) == "number" and saved.rebirth or nil,
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
		needleHold = state.needleHold,
		needleIndex = state.needleIndex and NeedleIndex.toSave(state.needleIndex),
		finds = state.finds,
		findsPaid = state.findsPaid,
		skins = state.skins,
		secrets = state.secrets,
		discovered = state.discovered,
		festivals = state.festivals,
		gloves = state.gloves,
		land = state.land,
		land2 = state.land2,
		bank = state.bank,
		tutorial = state.tutorial,
		settings = state.settings,
		codex = state.codex,
		quests = state.quests,
		contracts = state.contracts,
		rebirth = state.rebirth,
		tradeLocks = state.tradeLocks,
	}
end

-- For SelfTests: the save shape without a DataStore.
Data.test = { stateFrom = stateFrom, toSave = toSave }

-- True when this player's profile is being written: loaded, the store reachable, and the save not set aside (read
-- failed on join, or another server took the profile's lock). Trades need it, so nothing traded can be lost.
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
	local owed, held = 0, 0
	for _, loan in (bank and bank.loans or {}) do
		owed += loan.owed
		held += loan.held or 0
	end
	-- Cash also counts loan money the bank holds for purchases (Bank.held), since shops can spend it.
	player:SetAttribute("Cash", if Config.InfiniteMoney then state.cash else state.cash + balance + held)
	player:SetAttribute("Wallet", if Config.InfiniteMoney then state.savedCash or 0 else state.cash)
	player:SetAttribute("BankBalance", balance)
	player:SetAttribute("LoanOwed", owed)
	player:SetAttribute("LoadHay", state.loadHay)
	player:SetAttribute("LoadCap", Config.CarryCapacity)
	player:SetAttribute("Carrying", state.carryBale ~= nil)
	player:SetAttribute("OwnedTrucks", table.concat(state.trucks, ","))
	player:SetAttribute("OwnedTrailers", table.concat(state.trailers, ","))
	player:SetAttribute("Gear", table.concat(state.gear or {}, ",")) -- bought gear such as "wheelbarrow" (goal bar)
	local inPocket = 0
	for _, count in state.pocket do
		inPocket += count
	end
	player:SetAttribute("NeedlesHeld", inPocket)
	player:SetAttribute("Thatch", state.thatch or 0)
	-- Every alloy, so none is left unset.
	for _, alloy in Alloys do
		player:SetAttribute("Material_" .. alloy.id, (state.materials or {})[alloy.id] or 0)
	end
end

function Data.toast(player, text)
	player:SetAttribute("ToastText", text)
	player:SetAttribute("ToastId", (player:GetAttribute("ToastId") or 0) + 1)
end

-- The used slots in an old slot index ({ ["1"] = { savedAt, ... }, ... }), the one saved last first.
local function newestSlots(index)
	local order = {}
	for slot = 1, 3 do
		local entry = index[tostring(slot)]
		if typeof(entry) == "table" then
			table.insert(order, { slot = slot, at = typeof(entry.savedAt) == "number" and entry.savedAt or 0 })
		end
	end
	table.sort(order, function(a, b)
		return a.at > b.at
	end)
	local out = {}
	for _, entry in order do
		table.insert(out, entry.slot)
	end
	return out
end
Data.test.newestSlots = newestSlots

-- The old slot save to move onto a new profile: the slot saved last by the slot index, or the save from before slots
-- (which the index never listed). ok is false when the store couldn't be read, so nothing is started over it.
local function oldSave(player)
	local ok, index = read(indexKey(player))
	if not ok then
		return false, nil
	end
	if typeof(index) ~= "table" then
		local okOld, old = read(legacyKey(player))
		return okOld, typeof(old) == "table" and old or nil
	end
	-- Newest first; a slot whose main copy is gone falls back to its backup, then to the next slot.
	for _, slot in newestSlots(index) do
		for _, key in { slotKey(player, slot), slotKey(player, slot) .. "_Backup" } do
			local okSlot, saved = read(key)
			if not okSlot then
				return false, nil
			end
			if typeof(saved) == "table" then
				saved._lock = nil
				return true, saved
			end
		end
	end
	return true, nil
end

-- Reads the profile, taking its session lock. Returns ok, saved (nil for a new player), restored (loaded from the
-- backup), and why it failed. When another server still holds the lock (the player just left it and its last save
-- is landing) it waits and tries again.
local function readProfile(player)
	local saved, locked = nil, false
	for try = 1, 10 do
		local seen = nil
		local ok = update(profileKey(player), function(current)
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
			return false, nil, false, "read"
		end
		saved = seen
		if not locked or not player.Parent then
			break
		end
		if try < 10 then
			task.wait(3)
		end
	end
	if locked then
		return false, nil, false, "locked"
	end
	if saved then
		return true, saved, false
	end
	-- No profile: its backup (the main copy went missing), else the old slot save it replaces.
	local okBackup, backup = read(backupKey(player))
	if not okBackup then
		return false, nil, false, "read"
	end
	if typeof(backup) == "table" then
		backup._lock = nil
		return true, backup, true
	end
	local okOld, old = oldSave(player)
	if not okOld then
		return false, nil, false, "read"
	end
	return true, old, false
end

-- True for a save written by a rebirth in the last few minutes (Rebirth.luau sets rebirth.at, then rejoins).
local function justReborn(saved)
	local rebirth = typeof(saved) == "table" and saved.rebirth
	return typeof(rebirth) == "table" and typeof(rebirth.at) == "number" and os.time() - rebirth.at < 300
end
Data.test.justReborn = justReborn

-- Loads the player's profile and starts the game for them. Runs once, on joining.
function Data.load(player)
	if states[player] or loading[player] then
		return false
	end
	loading[player] = true
	local saved, restored, why = nil, false, nil
	if store then
		local ok
		ok, saved, restored, why = readProfile(player)
		if not ok then
			offline[player] = true -- still plays, but nothing is written over the save it couldn't read
			saved, restored = nil, false
		end
	else
		offline[player] = true
	end
	-- A developer fresh start (Config/Game DevFreshStart) drops what was saved, except straight after a rebirth, whose
	-- rejoin must come back to the reset game it saved.
	local devFresh = table.find(Config.DevFreshStart or {}, player.UserId) ~= nil
	if devFresh and not justReborn(saved) then
		saved, restored = nil, false
	end
	if saved then
		saved = migrate(saved)
		if not saved then
			offline[player] = true
			why = "newer"
		else
			-- The copy that loaded is a known good one: keep it as the backup.
			local good = copy(saved)
			good._lock = nil
			task.spawn(write, backupKey(player), good)
		end
	end
	-- Services hand out tools and move the player when the profile loads, so wait for the first character (the old
	-- slot picker only loaded once the player was standing in the world).
	local waited = 0
	while player.Parent and not (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) and waited < 30 do
		waited += task.wait(0.1)
	end
	if not player.Parent then
		loading[player] = nil
		if not offline[player] then
			releaseLock(player)
		end
		return false
	end
	local fresh = saved == nil
	if fresh and not devFresh then
		local preset = presetFor(player)
		saved = preset and copy({ cash = preset.cash, trucks = preset.trucks, trailers = preset.trailers, land = preset.land })
		-- A preset farm's pieces were free, so removing them refunds nothing.
		for _, item in (saved and saved.land and saved.land.items or {}) do
			item.paid = 0
		end
	end
	local state = stateFrom(saved)
	state.fresh = fresh
	states[player] = state
	loading[player] = nil
	player:SetAttribute("SavesOnline", not offline[player])
	player:SetAttribute("SaveSlot", 1)
	Data.sync(player)
	Data.loaded:Fire(player)
	-- Write the profile straight away, so a new, restored or moved-over save is the main copy from now on.
	task.spawn(Data.save, player)
	local note = nil
	if why == "locked" then
		note = "Your save is still open on another server, so this game won't be saved. Rejoin in a minute."
	elseif why == "newer" then
		note = "Your save is from a newer version of the game, so this one won't save. Rejoin to get the update."
	elseif offline[player] then
		note = "Your save couldn't be loaded, so this game won't be saved. Rejoin to try again."
			.. (game:GetService("RunService"):IsStudio() and " In Studio, turn on Game Settings > Security > Enable Studio Access to API Services." or "")
	elseif restored then
		note = "Your save's main copy couldn't be found, so it was loaded from its backup."
	end
	if note then
		task.delay(3, function()
			if player.Parent then
				Data.toast(player, note)
			end
		end)
	end
	return true
end

-- One write per player at a time, so an older snapshot can never land after a newer one. A save asked for while one
-- is writing waits for it, and the writer then saves once more with the newest state.
local saving, saveAgain, saveFinal = {}, {}, {}
local saveOnce
-- final (on leaving) also gives up the profile's session lock.
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
	if not state or not store or offline[player] then
		return
	end
	-- state.skipBeforeSave: a rebirth (Rebirth.luau) saves a reset profile, and Land must not copy the old farm back in.
	if Data.beforeSave and not state.skipBeforeSave then
		pcall(Data.beforeSave, player)
	end
	local saved = toSave(state)
	saved._v = SAVE_VERSION
	saved._lock = if final then nil else { job = JOB, at = os.time() }
	local lost = false
	update(profileKey(player), function(current)
		lost = heldElsewhere(current)
		if lost then
			return nil
		end
		return saved
	end)
	if lost then
		-- Another server opened this profile (this one stopped refreshing its lock): its copy wins, and this server
		-- stops writing so the two never overwrite each other.
		offline[player] = true
		warn(("[Needlewood] the save for %d is open on another server; this server stopped saving it"):format(player.UserId))
		Data.toast(player, "This save was opened on another server, so this server has stopped saving it.")
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
	offline[player] = nil
end

local function onPlayerAdded(player)
	local ok, err = pcall(Data.load, player)
	if not ok then
		loading[player] = nil
		warn("[Needlewood] profile load failed: " .. tostring(err))
	end
end

function Data.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
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
