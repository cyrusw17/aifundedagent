--!nonstrict
-- "Best farm" likes. Visitors like a farm at its sign, once per farm per week. Counts are per week (Monday to
-- Monday, UTC) and kept in an OrderedDataStore per week, so the Land Office board can show the most liked farms.
-- Without DataStore access (Studio with API access off) likes still work for the server's lifetime.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Likes = {}

local WEEK = 7 * 86400
local MAX_GIVEN = 300 -- farms one player can like in a week

local given = nil -- DataStore: "W<week>_<liker>" -> { ownerId, ... }
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("NeedlewoodLikesGiven")
	end)
	if ok then
		given = result
	end
end

local cache = { week = -1, counts = {}, given = {}, top = {}, topAt = -math.huge }
local names = {}

-- Weeks start Monday 00:00 UTC (the Unix epoch was a Thursday).
function Likes.week()
	return math.floor((os.time() - 4 * 86400) / WEEK)
end

local function current()
	local week = Likes.week()
	if cache.week ~= week then
		cache = { week = week, counts = {}, given = {}, top = {}, topAt = -math.huge }
	end
	return cache
end

local function ordered(week)
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore("NeedlewoodFarmLikesW" .. week)
	end)
	return ok and result or nil
end

-- This week's likes for a farm owner.
function Likes.count(ownerId)
	local c = current()
	if c.counts[ownerId] == nil then
		c.counts[ownerId] = 0
		local store = ordered(c.week)
		if store then
			local ok, value = pcall(function()
				return store:GetAsync(tostring(ownerId))
			end)
			if ok and typeof(value) == "number" then
				c.counts[ownerId] = math.max(c.counts[ownerId], value)
			end
		end
	end
	return c.counts[ownerId]
end

-- liker likes ownerId's farm. Returns ok, a message for the liker, and the farm's new count.
function Likes.like(liker, ownerId)
	if liker.UserId == ownerId then
		return false, "Visitors can like your farm at this sign.", Likes.count(ownerId)
	end
	local c = current()
	local mine = c.given[liker.UserId]
	if mine and mine[ownerId] then
		return false, "You already liked this farm this week.", Likes.count(ownerId)
	end
	-- Recorded first, so a like is never counted twice even across servers.
	local fresh = true
	if given then
		local ok = pcall(function()
			given:UpdateAsync(("W%d_%d"):format(c.week, liker.UserId), function(list)
				list = typeof(list) == "table" and list or {}
				if table.find(list, ownerId) or #list >= MAX_GIVEN then
					fresh = false
					return nil
				end
				table.insert(list, ownerId)
				return list
			end)
		end)
		if not ok then
			fresh = true -- the store is off: fall back to this server's memory
		end
	end
	c.given[liker.UserId] = mine or {}
	c.given[liker.UserId][ownerId] = true
	if not fresh then
		return false, "You already liked this farm this week.", Likes.count(ownerId)
	end
	local count = Likes.count(ownerId) + 1
	local store = ordered(c.week)
	if store then
		local ok, value = pcall(function()
			return store:IncrementAsync(tostring(ownerId), 1)
		end)
		if ok and typeof(value) == "number" then
			count = value
		end
	end
	c.counts[ownerId] = count
	c.topAt = -math.huge -- the board refreshes on its next pass
	return true, "You liked this farm.", count
end

local function nameOf(userId)
	if names[userId] == nil then
		local online = Players:GetPlayerByUserId(userId)
		if online then
			names[userId] = online.DisplayName
		else
			local ok, name = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			names[userId] = ok and name or ("Farmer " .. userId)
		end
	end
	return names[userId]
end

-- The most liked farms this week, as { { userId, name, likes }, ... }, at most n. Reads the store at most once a minute.
function Likes.top(n)
	local c = current()
	if os.clock() - c.topAt > 60 then
		c.topAt = os.clock()
		local list = {}
		local store = ordered(c.week)
		local ok = store ~= nil and pcall(function()
			local page = store:GetSortedAsync(false, n):GetCurrentPage()
			for _, entry in page do
				local userId = tonumber(entry.key)
				if userId and entry.value > 0 then
					c.counts[userId] = math.max(c.counts[userId] or 0, entry.value)
					table.insert(list, { userId = userId, likes = entry.value })
				end
			end
		end)
		if not ok then
			for userId, likes in c.counts do
				if likes > 0 then
					table.insert(list, { userId = userId, likes = likes })
				end
			end
		end
		table.sort(list, function(a, b)
			return a.likes > b.likes
		end)
		for i = #list, n + 1, -1 do
			table.remove(list, i)
		end
		for _, entry in list do
			entry.name = nameOf(entry.userId)
		end
		c.top = list
	end
	return c.top
end

return Likes
