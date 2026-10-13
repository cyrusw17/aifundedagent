--!nonstrict
-- The Trading Post, a little wooden stall on the grass between the Homestead Motors lot and base camp. Two players
-- swap needles (bundles are just counts in the pocket), foreign objects, thatch, building materials and cash. Trucks
-- and land never trade. All cash, and each side's fee (Bank.tradeFee), goes through Bank.settleTrade, which also writes
-- the trade into both bank histories. This file never moves cash itself.
--
-- How a trade goes:
--   1. Press E at the stall: a list of players standing near the post comes up. Pick one to ask them.
--   2. They get an invite and press ACCEPT: both see the trade window.
--   3. Each side puts things in their offer. Both press ACCEPT and a 5 second countdown starts. Any change to either
--      offer (or either player taking their accept back) stops the countdown and clears both accepts.
--   4. When the countdown ends the server checks everything again against both saves and swaps it all in one step.
--
-- Mythic items that a player RECEIVED in a trade are locked for 24 hours: they can be sold or used, but not traded on
-- until the lock runs out. Mythic means the top needle type in Config/Needles, any mutated needle, and the rarest
-- foreign object in Config/Finds. Locks are saved with the slot as
-- state.tradeLocks = { [needleKey or "find:" .. findId] = { { count = n, untilTime = os.time() }, ... } }.
--
--   Trade.build(worldFolder)   -- the stall and the remotes (ReplicatedStorage.Trade)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Needles = require(Shared.Config.Needles)
local Alloys = require(Shared.Config.Alloys)
local FindsConfig = require(Shared.Config.Finds)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Props = require(script.Parent.Props)
local Needle = require(script.Parent.Needle)
local Avatar = require(script.Parent.Avatar)
local Events = require(script.Parent.Events)
local Machines = require(script.Parent.Machines)
local MeadowTerrain = require(script.Parent.MeadowTerrain)

local Trade = {}

-- The stall stands on the flat grass east of the dealer's lot (the lot ends at x -62) and west of the bounty board at
-- x -34, just north of the main road (z 19..33). Its counter faces south, onto the road.
Trade.SITE = Vector3.new(-52, 0, 2)

local REACH = 20 -- studs from the post to start, change or finish a trade
local LEAVE_REACH = 30 -- walk this far away and an open trade is called off
local COUNTDOWN = 5
local INVITE_SECONDS = 20
local LOCK_SECONDS = 24 * 60 * 60
local MAX_LINES = 12 -- different needle keys (or materials) in one offer
local MAX_AMOUNT = 1e9

local part = Machines.part
local post = nil -- the counter part distances are measured from
local updateRemote = nil

local sessions = {} -- player -> session (both players point at the same table)
local invites = {} -- target player -> { from = player, at = os.clock() }

-- Mythic needles ------------------------------------------------------------------------------------------------------

-- Config/Needles has no rarity field, so the top rarity is the most valuable needle type (Cosmic today).
local topNeedle = Needles[1]
for _, n in Needles do
	if n.sortedValue > topNeedle.sortedValue then
		topNeedle = n
	end
end

local function isMythic(key)
	local id, mult = Needle.parseKey(key)
	return id == topNeedle.id or mult > 1
end
Trade.isMythic = isMythic

local function needleLabel(key)
	local id, mult, polished = Needle.parseKey(key)
	local name = Needle.info(id).name
	if mult > 1 then
		name = ("%s x%d mutated"):format(name, mult)
	end
	if polished then
		name ..= ", polished"
	end
	return name
end

-- Foreign objects (Config/Finds). It has no rarity field either, so the top rarity is the one with the longest odds
-- (the Fossil today). Their locks are kept under "find:" .. id so they never mix with needle keys.
local findNames = {}
local topFind = FindsConfig.Items[1]
for _, def in FindsConfig.Items do
	findNames[def.id] = def.name
	if def.oneIn > topFind.oneIn then
		topFind = def
	end
end
local function findLockKey(id)
	return "find:" .. id
end
local function isMythicFind(id)
	return id == topFind.id
end

local materialNames = {}
for _, alloy in Alloys do
	materialNames[alloy.id] = alloy.name
end

-- How many needles of this key are still locked, dropping locks that have run out.
local function lockedCount(state, key)
	local locks = state.tradeLocks and state.tradeLocks[key]
	if not locks then
		return 0
	end
	local now, total = os.time(), 0
	for i = #locks, 1, -1 do
		if locks[i].untilTime <= now then
			table.remove(locks, i)
		else
			total += locks[i].count
		end
	end
	if #locks == 0 then
		state.tradeLocks[key] = nil
	end
	return total
end

-- Needles of a key this player may put in a trade: what they hold less what is locked.
local function tradable(state, key)
	local have = state.pocket and state.pocket[key] or 0
	return math.max(0, have - lockedCount(state, key))
end

-- Offers ---------------------------------------------------------------------------------------------------------------

local function emptyOffer()
	return { needles = {}, finds = {}, cash = 0, thatch = 0, materials = {} }
end

local function isWhole(n)
	return typeof(n) == "number" and n == n and n >= 1 and n <= MAX_AMOUNT and math.floor(n) == n
end

-- Cash a player can put in: wallet plus bank, the same money Bank.settleTrade takes it from (loan money held for
-- purchases can't be traded).
local function cashAvailable(state)
	return math.max(0, math.floor(Bank.liquid(state)))
end

-- Cleans an offer from the client: whole positive amounts, no more than the player can trade right now. Returns the
-- clean offer, or nil and why.
local function cleanOffer(player, state, raw)
	if typeof(raw) ~= "table" then
		return nil, "That offer didn't make sense."
	end
	local offer = emptyOffer()
	local lines = 0
	if raw.needles ~= nil then
		if typeof(raw.needles) ~= "table" then
			return nil, "That offer didn't make sense."
		end
		for key, count in raw.needles do
			if typeof(key) ~= "string" or #key > 40 or not isWhole(count) then
				return nil, "Needle amounts must be whole numbers."
			end
			lines += 1
			if lines > MAX_LINES then
				return nil, ("Up to %d kinds of needle in one trade."):format(MAX_LINES)
			end
			local can = tradable(state, key)
			if count > can then
				local locked = lockedCount(state, key)
				if locked > 0 and count <= (state.pocket[key] or 0) then
					return nil, ("%d of your %s needles came from a trade and are locked for a day."):format(locked, needleLabel(key))
				end
				return nil, ("You only have %d %s to trade."):format(can, needleLabel(key))
			end
			offer.needles[key] = count
		end
	end
	if raw.finds ~= nil then
		if typeof(raw.finds) ~= "table" then
			return nil, "That offer didn't make sense."
		end
		local kinds = 0
		for id, count in raw.finds do
			if typeof(id) ~= "string" or not findNames[id] or not isWhole(count) then
				return nil, "That offer didn't make sense."
			end
			kinds += 1
			if kinds > MAX_LINES then
				return nil, ("Up to %d kinds of find in one trade."):format(MAX_LINES)
			end
			local have = state.finds and state.finds[id] or 0
			local locked = lockedCount(state, findLockKey(id))
			if count > have - locked then
				if locked > 0 and count <= have then
					return nil, ("%d of your %s came from a trade and are locked for a day."):format(locked, findNames[id])
				end
				return nil, ("You only have %d %s to trade."):format(math.max(0, have - locked), findNames[id])
			end
			offer.finds[id] = count
		end
	end
	if raw.cash ~= nil and raw.cash ~= 0 then
		if not isWhole(raw.cash) then
			return nil, "Cash must be a whole number of dollars."
		end
		local have = cashAvailable(state)
		local fee = Bank.tradeFee(raw.cash)
		if raw.cash + fee > have then
			return nil, ("You have $%d. Giving $%d costs $%d with the $%d fee."):format(have, raw.cash, raw.cash + fee, fee)
		end
		offer.cash = raw.cash
	end
	if raw.thatch ~= nil and raw.thatch ~= 0 then
		if not isWhole(raw.thatch) then
			return nil, "Thatch must be a whole number."
		end
		if raw.thatch > (state.thatch or 0) then
			return nil, ("You only carry %d thatch."):format(state.thatch or 0)
		end
		offer.thatch = raw.thatch
	end
	if raw.materials ~= nil then
		if typeof(raw.materials) ~= "table" then
			return nil, "That offer didn't make sense."
		end
		local mats = 0
		for id, units in raw.materials do
			if typeof(id) ~= "string" or #id > 40 or not isWhole(units) then
				return nil, "Material amounts must be whole numbers."
			end
			mats += 1
			if mats > MAX_LINES then
				return nil, ("Up to %d materials in one trade."):format(MAX_LINES)
			end
			local have = state.materials and state.materials[id] or 0
			if units > have then
				return nil, ("You only carry %d %s."):format(have, materialNames[id] or id)
			end
			offer.materials[id] = units
		end
	end
	return offer
end

local function offerIsEmpty(offer)
	return next(offer.needles) == nil and next(offer.finds) == nil and offer.cash == 0 and offer.thatch == 0 and next(offer.materials) == nil
end

-- "3 Cosmic needles", "a Fossil", "2 Old boots".
local function counted(count, name, noun)
	if count == 1 then
		local article = string.find(name, "^[AEIOUaeiou]") and "an" or "a"
		return ("%s %s%s"):format(article, name, noun and " " .. noun or "")
	end
	return if noun then ("%d %s %ss"):format(count, name, noun) else ("%d %ss"):format(count, name)
end

-- What an offer hands over, in words: "3 Cosmic needles, a Fossil and 20 thatch" for the bank history and the log.
-- Cash is left out for the bank (it adds the amount itself).
local function describe(offer, withoutCash)
	local parts = {}
	local keys = {}
	for key in offer.needles do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		table.insert(parts, counted(offer.needles[key], needleLabel(key), "needle"))
	end
	for id, count in offer.finds do
		table.insert(parts, counted(count, findNames[id] or id))
	end
	if offer.thatch > 0 then
		table.insert(parts, offer.thatch .. " thatch")
	end
	for id, units in offer.materials do
		table.insert(parts, ("%d %s"):format(units, materialNames[id] or id))
	end
	if offer.cash > 0 and not withoutCash then
		table.insert(parts, "$" .. offer.cash)
	end
	if #parts > 1 then
		local last = table.remove(parts)
		return table.concat(parts, ", ") .. " and " .. last
	end
	if #parts == 0 then
		return if withoutCash then "" else "nothing"
	end
	return table.concat(parts, ", ")
end

-- Distance ------------------------------------------------------------------------------------------------------------

local function distance(player)
	local root = Avatar.getRoot(player)
	if not root then
		local character = player.Character
		root = character and character:FindFirstChild("HumanoidRootPart")
	end
	if not root or not post then
		return math.huge
	end
	return (root.Position - post.Position).Magnitude
end

local function near(player, reach)
	return player.Parent ~= nil and distance(player) <= (reach or REACH)
end

-- Sending state to clients ---------------------------------------------------------------------------------------------

local function send(player, payload)
	if updateRemote and player.Parent then
		updateRemote:FireClient(player, payload)
	end
end

local function toast(player, text)
	if player.Parent then
		Data.toast(player, text)
	end
end

-- An offer as the client shows it: a list of lines with labels.
local function offerView(offer)
	local needles = {}
	for key, count in offer.needles do
		table.insert(needles, { key = key, count = count, label = needleLabel(key), mythic = isMythic(key) })
	end
	table.sort(needles, function(a, b)
		return a.label < b.label
	end)
	local materials = {}
	for id, units in offer.materials do
		table.insert(materials, { id = id, count = units, label = materialNames[id] or id })
	end
	table.sort(materials, function(a, b)
		return a.label < b.label
	end)
	local finds = {}
	for id, count in offer.finds do
		table.insert(finds, { id = id, count = count, label = findNames[id] or id, mythic = isMythicFind(id) })
	end
	table.sort(finds, function(a, b)
		return a.label < b.label
	end)
	return { needles = needles, finds = finds, cash = offer.cash, thatch = offer.thatch, materials = materials }
end

-- What this player has that could go in a trade, for the add list.
local function inventory(player)
	local state = Data.get(player)
	local out = { needles = {}, finds = {}, materials = {}, cash = 0, thatch = 0, cashAllowed = true }
	if not state then
		return out
	end
	for key, count in Needle.held(player) do
		local locked = math.min(count, lockedCount(state, key))
		table.insert(out.needles, { key = key, count = count - locked, locked = locked, label = needleLabel(key), mythic = isMythic(key) })
	end
	table.sort(out.needles, function(a, b)
		return a.label < b.label
	end)
	for id, count in state.finds or {} do
		if count > 0 and findNames[id] then
			local locked = math.min(count, lockedCount(state, findLockKey(id)))
			table.insert(out.finds, { id = id, count = count - locked, locked = locked, label = findNames[id], mythic = isMythicFind(id) })
		end
	end
	table.sort(out.finds, function(a, b)
		return a.label < b.label
	end)
	for id, units in state.materials or {} do
		if units > 0 then
			table.insert(out.materials, { id = id, count = units, label = materialNames[id] or id })
		end
	end
	table.sort(out.materials, function(a, b)
		return a.label < b.label
	end)
	out.cash = cashAvailable(state)
	out.thatch = state.thatch or 0
	return out
end

local function otherOf(session, player)
	return if session.a == player then session.b else session.a
end

local function push(session)
	for _, player in { session.a, session.b } do
		local other = otherOf(session, player)
		send(player, {
			kind = "state",
			partner = other.DisplayName,
			mine = offerView(session.offers[player]),
			theirs = offerView(session.offers[other]),
			-- Each side's trading post fee on what it gives (Bank.tradeFee; $0 with test money on).
			myFee = Bank.tradeFee(session.offers[player].cash),
			theirFee = Bank.tradeFee(session.offers[other].cash),
			myAccept = session.accepted[player] == true,
			theirAccept = session.accepted[other] == true,
			endsAt = session.endsAt, -- server time (Workspace:GetServerTimeNow) the countdown finishes, or nil
			inventory = inventory(player),
		})
	end
end

local function close(session, why)
	if session.closed then
		return
	end
	session.closed = true
	for _, player in { session.a, session.b } do
		if sessions[player] == session then
			sessions[player] = nil
		end
		send(player, { kind = "closed", reason = why })
		if why and not session.done then
			toast(player, why)
		end
	end
end

-- Any change to either offer clears both accepts and stops a running countdown.
local function resetAccepts(session)
	session.accepted = {}
	session.endsAt = nil
	session.version += 1
end

-- The swap ------------------------------------------------------------------------------------------------------------

-- Takes everything in the offer out of `from`'s state and puts it into `to`'s. No yields: the caller checked it all.
-- Cash is not moved here: Bank.settleTrade did that just before (see finish).
local function move(fromState, toState, offer)
	for key, count in offer.needles do
		fromState.pocket[key] -= count
		if fromState.pocket[key] <= 0 then
			fromState.pocket[key] = nil
		end
		toState.pocket[key] = (toState.pocket[key] or 0) + count
		if isMythic(key) then
			toState.tradeLocks = toState.tradeLocks or {}
			toState.tradeLocks[key] = toState.tradeLocks[key] or {}
			table.insert(toState.tradeLocks[key], { count = count, untilTime = os.time() + LOCK_SECONDS })
		end
	end
	for id, count in offer.finds do
		fromState.finds[id] -= count
		if fromState.finds[id] <= 0 then
			fromState.finds[id] = nil
		end
		toState.finds = toState.finds or {}
		toState.finds[id] = (toState.finds[id] or 0) + count
		if isMythicFind(id) then
			local key = findLockKey(id)
			toState.tradeLocks = toState.tradeLocks or {}
			toState.tradeLocks[key] = toState.tradeLocks[key] or {}
			table.insert(toState.tradeLocks[key], { count = count, untilTime = os.time() + LOCK_SECONDS })
		end
	end
	if offer.thatch > 0 then
		fromState.thatch -= offer.thatch
		toState.thatch = (toState.thatch or 0) + offer.thatch
	end
	for id, units in offer.materials do
		fromState.materials[id] -= units
		if fromState.materials[id] <= 0 then
			fromState.materials[id] = nil
		end
		toState.materials = toState.materials or {}
		toState.materials[id] = (toState.materials[id] or 0) + units
	end
end

-- The "Finds" attribute the collection book reads, the same way Finds.luau writes it.
local function publishFinds(player, state)
	local list = {}
	for id, count in state.finds or {} do
		table.insert(list, ("%s:%d"):format(id, count))
	end
	table.sort(list)
	player:SetAttribute("Finds", table.concat(list, ","))
end

-- Runs when the countdown ends. Checks everything once more, then swaps both offers in one step.
local function finish(session)
	local a, b = session.a, session.b
	if not (a.Parent and b.Parent) then
		close(session, "The other player left.")
		return
	end
	if not (near(a) and near(b)) then
		close(session, "Both players need to stay at the Trading Post.")
		return
	end
	local stateA, stateB = Data.get(a), Data.get(b)
	if not stateA or not stateB then
		close(session, "A save isn't loaded. Trade called off.")
		return
	end
	-- Pocket needles picked up before the slot loaded join it now, so the check below sees the real pocket.
	Needle.held(a)
	Needle.held(b)
	stateA.pocket = stateA.pocket or {}
	stateB.pocket = stateB.pocket or {}
	stateA.materials = stateA.materials or {}
	stateB.materials = stateB.materials or {}
	stateA.finds = stateA.finds or {}
	stateB.finds = stateB.finds or {}
	local offerA, whyA = cleanOffer(a, stateA, session.offers[a])
	local offerB, whyB = cleanOffer(b, stateB, session.offers[b])
	if not offerA or not offerB then
		resetAccepts(session)
		push(session)
		toast(a, not offerA and whyA or (b.DisplayName .. "'s offer changed. Check it and accept again."))
		toast(b, not offerB and whyB or (a.DisplayName .. "'s offer changed. Check it and accept again."))
		return
	end
	if offerIsEmpty(offerA) and offerIsEmpty(offerB) then
		resetAccepts(session)
		push(session)
		return
	end

	-- The swap itself: nothing from here to the end of the item moves yields, so no other request can land between
	-- the take and the give. Cash and fees first, through the bank; if it refuses, the trade is called off before
	-- anything has moved and both players see why (close toasts it).
	local paid, why = Bank.settleTrade(a, b, {
		aGives = describe(offerA, true),
		bGives = describe(offerB, true),
		aCash = offerA.cash,
		bCash = offerB.cash,
	})
	if not paid then
		close(session, why or "The bank couldn't settle the trade. Nothing was traded.")
		return
	end
	move(stateA, stateB, offerA)
	move(stateB, stateA, offerB)

	session.done = true
	close(session, "Trade complete.")
	Data.sync(a)
	Data.sync(b)
	publishFinds(a, stateA)
	publishFinds(b, stateB)
	task.spawn(Data.save, a)
	task.spawn(Data.save, b)
	print(("[Trade] %s -> %s: %s | %s -> %s: %s"):format(a.Name, b.Name, describe(offerA), b.Name, a.Name, describe(offerB)))
	Events.fire(a, "trade", 1, { partner = b.UserId })
	Events.fire(b, "trade", 1, { partner = a.UserId })
	toast(a, ("Trade with %s complete."):format(b.DisplayName))
	toast(b, ("Trade with %s complete."):format(a.DisplayName))
end

local function startCountdown(session)
	session.endsAt = Workspace:GetServerTimeNow() + COUNTDOWN
	local version = session.version
	push(session)
	task.delay(COUNTDOWN, function()
		if session.closed or session.version ~= version then
			return -- something changed during the countdown
		end
		if not (session.accepted[session.a] and session.accepted[session.b]) then
			return
		end
		local ok, err = pcall(finish, session)
		if not ok then
			warn("[Needlewood] trade failed: " .. tostring(err))
			close(session, "Something went wrong. Nothing was traded.")
		end
	end)
end

-- Remote handlers -----------------------------------------------------------------------------------------------------

-- Players near the post who could be asked to trade.
local function nearbyFor(player)
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and near(other) and Data.get(other) then
			table.insert(list, { userId = other.UserId, name = other.DisplayName, busy = sessions[other] ~= nil })
		end
	end
	return list
end

local function onRequest(player, userId)
	if typeof(userId) ~= "number" then
		return false, "Pick a player."
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target then
		return false, "That player isn't here any more."
	end
	if target == player then
		return false, "You can't trade with yourself."
	end
	if not Data.get(player) or not Data.get(target) then
		return false, "Both players need a save loaded."
	end
	if not near(player) then
		return false, "Walk up to the Trading Post first."
	end
	if not near(target) then
		return false, target.DisplayName .. " needs to be at the Trading Post."
	end
	if sessions[player] then
		return false, "Finish your current trade first."
	end
	if sessions[target] then
		return false, target.DisplayName .. " is already trading."
	end
	invites[target] = { from = player, at = os.clock() }
	send(target, { kind = "invite", from = player.UserId, name = player.DisplayName, seconds = INVITE_SECONDS })
	return true, ("Asked %s to trade."):format(target.DisplayName)
end

local function onRespond(player, fromUserId, yes)
	local invite = invites[player]
	if not invite or typeof(fromUserId) ~= "number" or invite.from.UserId ~= fromUserId then
		return false, "That invite is gone."
	end
	invites[player] = nil
	local from = invite.from
	if os.clock() - invite.at > INVITE_SECONDS or not from.Parent then
		return false, "That invite ran out."
	end
	if yes ~= true then
		toast(from, player.DisplayName .. " said no to trading.")
		return true, nil
	end
	if sessions[player] or sessions[from] then
		return false, "One of you is already trading."
	end
	if not Data.get(player) or not Data.get(from) then
		return false, "Both players need a save loaded."
	end
	if not (near(player) and near(from)) then
		return false, "Both players need to be at the Trading Post."
	end
	local session = {
		a = from,
		b = player,
		offers = { [from] = emptyOffer(), [player] = emptyOffer() },
		accepted = {},
		version = 0,
		endsAt = nil,
	}
	sessions[from] = session
	sessions[player] = session
	push(session)
	return true, nil
end

local function onOffer(player, raw)
	local session = sessions[player]
	if not session then
		return false, "You're not trading."
	end
	local state = Data.get(player)
	if not state then
		return false, "Pick a save first."
	end
	Needle.held(player)
	local offer, why = cleanOffer(player, state, raw)
	if not offer then
		push(session) -- puts the client's window back to the offer the server has
		return false, why
	end
	session.offers[player] = offer
	resetAccepts(session)
	push(session)
	return true, nil
end

local function onAccept(player, yes)
	local session = sessions[player]
	if not session then
		return false, "You're not trading."
	end
	if yes ~= true then
		resetAccepts(session)
		push(session)
		return true, nil
	end
	if not near(player) then
		return false, "Walk back to the Trading Post to accept."
	end
	if offerIsEmpty(session.offers[session.a]) and offerIsEmpty(session.offers[session.b]) then
		return false, "Put something in the trade first."
	end
	if session.accepted[player] then
		return true, nil
	end
	session.accepted[player] = true
	if session.accepted[session.a] and session.accepted[session.b] then
		startCountdown(session)
	else
		push(session)
	end
	return true, nil
end

local function onCancel(player)
	local session = sessions[player]
	if session then
		close(session, player.DisplayName .. " cancelled the trade.")
	end
	return true, nil
end

-- Rate limits: a small bucket of calls per player that refills a few times a second.
local buckets = {}
local BUCKET_SIZE, REFILL_PER_SECOND = 6, 4
local function allow(player)
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { tokens = BUCKET_SIZE, at = now }
		buckets[player] = b
	end
	b.tokens = math.min(BUCKET_SIZE, b.tokens + (now - b.at) * REFILL_PER_SECOND)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function guarded(name, handler)
	return function(player, ...)
		if not allow(player) then
			return false, "Slow down a little."
		end
		local ok, result, message = pcall(handler, player, ...)
		if not ok then
			warn(("[Needlewood] trade %s error: %s"):format(name, tostring(result)))
			return false, "Something went wrong at the Trading Post."
		end
		return result, message
	end
end

-- The stall -----------------------------------------------------------------------------------------------------------

local function buildStall(parent)
	local model = Instance.new("Model")
	model.Name = "TradingPost"
	model.Parent = parent
	local ground = MeadowTerrain.groundAt(Trade.SITE.X, Trade.SITE.Z)
	local origin = CFrame.new(Trade.SITE.X, ground, Trade.SITE.Z) * CFrame.Angles(0, math.pi, 0) -- front (-Z) faces south
	local function at(x, y, z)
		return origin * CFrame.new(x, y, z)
	end
	local planks = Enum.Material.WoodPlanks
	local W, D, H = 12, 8, 8

	-- A plank deck a little proud of the grass, so a slight slope never shows under it.
	part(model, "Deck", Vector3.new(W + 2, 1.4, D + 4), at(0, -0.4, 0), Rustic.WoodDark, planks)
	-- Back wall, two side half-walls and four posts holding a striped cloth awning.
	part(model, "BackWall", Vector3.new(W, H, 0.6), at(0, H / 2 + 0.3, D / 2 - 0.3), Rustic.Wood, planks)
	for _, sx in { -1, 1 } do
		part(model, "SideWall", Vector3.new(0.6, 3.6, D), at(sx * (W / 2 - 0.3), 2.1, 0), Rustic.Wood, planks)
		part(model, "FrontPost", Vector3.new(0.7, H + 1, 0.7), at(sx * (W / 2 - 0.35), (H + 1) / 2 + 0.3, -D / 2 + 0.35), Rustic.WoodDark, Enum.Material.Wood)
		part(model, "BackPost", Vector3.new(0.7, H + 1, 0.7), at(sx * (W / 2 - 0.35), (H + 1) / 2 + 0.3, D / 2 - 0.35), Rustic.WoodDark, Enum.Material.Wood)
	end
	for i = 0, 5 do
		local stripe = part(
			model,
			"Awning",
			Vector3.new(W / 6, 0.3, D + 2),
			at(-W / 2 + W / 12 + i * W / 6, H + 1.6, -1) * CFrame.Angles(math.rad(-12), 0, 0),
			i % 2 == 0 and Rustic.PaintRed or Rustic.Cloth,
			Enum.Material.Fabric
		)
		stripe.CanCollide = false
	end

	-- The counter across the front, with a set of scales and a crate on it.
	local counter = part(model, "Counter", Vector3.new(W - 1.4, 3.4, 1.6), at(0, 2, -D / 2 + 1.4), Rustic.WoodDark, planks)
	part(model, "CounterTop", Vector3.new(W - 1, 0.3, 2), at(0, 3.85, -D / 2 + 1.4), Rustic.Wood, Enum.Material.Wood)
	part(model, "ScaleBase", Vector3.new(0.8, 0.3, 0.8), at(-2.5, 4.15, -D / 2 + 1.4), Rustic.Metal, Enum.Material.Metal)
	part(model, "ScalePost", Vector3.new(0.2, 1.6, 0.2), at(-2.5, 5, -D / 2 + 1.4), Rustic.Metal, Enum.Material.Metal)
	part(model, "ScaleBeam", Vector3.new(2.4, 0.15, 0.15), at(-2.5, 5.8, -D / 2 + 1.4), Rustic.Metal, Enum.Material.Metal)
	for _, sx in { -1, 1 } do
		part(model, "ScalePan", Vector3.new(0.9, 0.1, 0.9), at(-2.5 + sx * 1.1, 5.1, -D / 2 + 1.4), Rustic.PaintYellow, Enum.Material.Metal)
	end
	part(model, "Crate", Vector3.new(1.6, 1.2, 1.4), at(3, 4.6, -D / 2 + 1.4), Rustic.Wood, planks)

	-- The name board over the awning, readable from the main road and from camp.
	local board = part(model, "Sign", Vector3.new(W - 2, 2.4, 0.4), at(0, H + 3.4, -D / 2 - 0.2), Rustic.Wood, planks)
	board.CanCollide = false
	WorldLabel.surface(board, "TRADING POST", { Enum.NormalId.Front, Enum.NormalId.Back })
	WorldLabel.billboard(counter, "TRADING POST\nswap needles with other players", { offset = Vector3.new(0, 9, 0), kind = "sign" })

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Trade"
	prompt.ObjectText = "Trading Post"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	prompt.Triggered:Connect(function(player)
		if not allow(player) then
			return
		end
		if not Data.get(player) then
			toast(player, "Pick a save first.")
			return
		end
		if sessions[player] then
			push(sessions[player])
			return
		end
		send(player, { kind = "nearby", players = nearbyFor(player) })
	end)
	-- The Blender trading post (Config/Props trading_post, built facing -Z like this stall) when it has been imported.
	-- The part-built stall then hides but stays in place: the counter keeps the prompt and the sign keeps its text.
	local mesh = Props.make("trading_post", origin * CFrame.new(0, H / 2, 0), 24)
	if mesh then
		mesh.Parent = model
		Props.restOn(mesh, ground)
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p ~= board then
				p.Transparency = 1
				p.CanCollide = false
			end
		end
	end
	post = counter
	return model
end

function Trade.build(worldFolder)
	buildStall(worldFolder)

	local remotes = Instance.new("Folder")
	remotes.Name = "Trade"
	local function fn(name, handler)
		local r = Instance.new("RemoteFunction")
		r.Name = name
		r.OnServerInvoke = guarded(name, handler)
		r.Parent = remotes
	end
	fn("Nearby", function(player)
		return true, nearbyFor(player)
	end)
	fn("Request", onRequest)
	fn("Respond", onRespond)
	fn("Offer", onOffer)
	fn("Accept", onAccept)
	fn("Cancel", onCancel)
	updateRemote = Instance.new("RemoteEvent")
	updateRemote.Name = "Update"
	updateRemote.Parent = remotes
	remotes.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			close(session, player.DisplayName .. " left the server.")
		end
		invites[player] = nil
		buckets[player] = nil
	end)

	-- Walking away (or losing the save) calls an open trade off.
	task.spawn(function()
		while true do
			task.wait(1)
			local seen = {}
			for _, session in sessions do
				if not seen[session] then
					seen[session] = true
					for _, p in { session.a, session.b } do
						if not session.closed and (not near(p, LEAVE_REACH) or not Data.get(p)) then
							close(session, p.DisplayName .. " walked away from the Trading Post.")
						end
					end
				end
			end
			for target, invite in invites do
				if os.clock() - invite.at > INVITE_SECONDS then
					invites[target] = nil
				end
			end
		end
	end)
end

return Trade
