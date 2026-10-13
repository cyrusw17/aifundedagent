--!nonstrict
-- Land's suites. "Land": claiming a plot, building every piece, saving and loading a farm onto a different plot (the turned
-- north row included), restoring bin needles, the mailbox, and a second farm. It works on free plots with a stand-in
-- owner, so it needs no player; place and undo run on a real player's own farm when one is loaded.
local HttpService = game:GetService("HttpService")

local Services = script.Parent.Parent.Services

local Land = require(Services.Land)
local Data = require(Services.Data)
local Needle = require(Services.Needle)

-- A stand-in owner: just enough of a Player for claim and release.
local function fakeOwner(userId)
	local attributes = {}
	local owner = { UserId = userId, DisplayName = "SelfTest" .. -userId, Name = "SelfTest", Parent = nil }
	function owner:SetAttribute(name, value)
		attributes[name] = value
	end
	function owner:GetAttribute(name)
		return attributes[name]
	end
	return owner
end

local function freePlots(L)
	local list = {}
	for _, plot in L.plots do
		if not plot.ownerId then
			table.insert(list, plot)
		end
	end
	table.sort(list, function(a, b)
		return a.index < b.index
	end)
	return list
end

local function blankLand()
	return { owned = true, items = {}, expansions = 2 }
end

-- Counts saved items by "id@gx,gz,dir".
local function itemSet(items)
	local set, n = {}, 0
	for _, s in items do
		local k = ("%s@%d,%d,%s"):format(s.id, s.gx, s.gz, s.dir)
		set[k] = (set[k] or 0) + 1
		n += 1
	end
	return set, n
end


-- One JSON string per value with keys sorted, so two tables compare equal exactly when their saves would.
local function canon(value)
	if typeof(value) ~= "table" then
		return HttpService:JSONEncode(value)
	end
	local keys = {}
	for k in value do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k) .. "=" .. canon(value[k]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- A save with something in every field, sized by rng. big fills both farms and the bin to their limits.
local function randomSave(rng, big)
	local pieceIds = {}
	for _, def in require(game:GetService("ReplicatedStorage").Shared.Config.Land).Pieces do
		table.insert(pieceIds, def.id)
	end
	local dirs = { "N", "E", "S", "W" }
	local function farm(n)
		local items = {}
		for i = 1, n do
			table.insert(items, {
				id = pieceIds[rng:NextInteger(1, #pieceIds)],
				gx = rng:NextInteger(0, 11),
				gz = rng:NextInteger(0, 9),
				dir = dirs[rng:NextInteger(1, 4)],
				stored = rng:NextNumber() < 0.3 and rng:NextInteger(1, 40) or nil,
				fill = rng:NextNumber() < 0.1 and "thatch" or nil,
				display = rng:NextNumber() < 0.1 and { { slot = 1, id = Needle.default.id, mult = 3 } } or nil,
			})
		end
		local needles = {}
		for i = 1, big and 40 or rng:NextInteger(0, 8) do
			needles[Needle.keyOf(Needle.default.id, i % 5 == 0 and i or nil, i % 3 == 0)] = rng:NextInteger(1, 300)
		end
		return {
			owned = true, plot = rng:NextInteger(1, 6), items = items, needles = needles, crew = { rng:NextInteger(1, 1e9) },
			expansions = rng:NextInteger(0, 2), binSorted = rng:NextNumber() < 0.5 or nil, binPolisher = rng:NextNumber() < 0.5 or nil,
			theme = "fieldstone", name = "Needle Acres", savedAt = os.time() - rng:NextInteger(0, 1e5),
		}
	end
	local pocket = {}
	for i = 1, big and 60 or rng:NextInteger(0, 10) do
		pocket[Needle.keyOf(Needle.default.id, i, i % 2 == 0)] = rng:NextInteger(1, 99)
	end
	local history = {}
	for i = 1, big and 50 or 5 do
		table.insert(history, { t = os.time() - i, kind = "earn", amount = rng:NextInteger(1, 5000), note = "Hay shop" })
	end
	return {
		cash = rng:NextInteger(0, 1e7),
		trucks = { "rusty_pickup" },
		trailers = { "flatbed" },
		gear = { "wheelbarrow" },
		pocket = pocket,
		thatch = rng:NextInteger(0, 500),
		materials = { bronze = rng:NextInteger(1, 50) },
		finds = { horseshoe = 2 },
		secrets = { ["secret_" .. rng:NextInteger(1, 9)] = 1, meadow_well = 1 },
		discovered = { ["region_" .. rng:NextInteger(1, 14)] = 1, old_mill = 1 },
		gloves = { owned = { "work", "leather" }, worn = "leather", brokeFirstBale = true },
		land = farm(big and 120 or rng:NextInteger(0, 30)),
		land2 = rng:NextNumber() < 0.5 and farm(big and 120 or rng:NextInteger(0, 30)) or nil,
		bank = { balance = rng:NextInteger(0, 1e6), earned = 5, loans = { truck = { owed = 300, principal = 1000, item = "rusty_pickup", takenAt = 1 } }, history = history },
		tutorial = { done = true, flags = { sold = true } },
		settings = { effects = true },
		quests = { earned = { alien_collector = true }, done = {}, active = {} },
	}
end

local COUNT_FIELDS, savesField = {}, {}

local function registerSaves(SelfTest)
	SelfTest.register("Saves", function(t)
		local D = Data.test
		if not D then
			t.check("Data.test hooks exist", false, "Data.luau has no Data.test table")
			return
		end
		-- Versions and locks.
		t.equal("a save from before versions migrates to the current version", Data.migrate({ cash = 5 })._v, Data.SAVE_VERSION)
		t.check("a save from a newer version is refused", Data.migrate({ _v = Data.SAVE_VERSION + 1 }) == nil)
		t.check("a fresh lock from another server holds the slot", Data.heldElsewhere({ _lock = { job = "elsewhere", at = os.time() } }))
		t.check("a lock nobody refreshed for an hour is stale", not Data.heldElsewhere({ _lock = { job = "elsewhere", at = os.time() - 3600 } }))
		t.check("this server's own lock never blocks it", not Data.heldElsewhere({ _lock = { job = game.JobId, at = os.time() } }))
		t.check("an unlocked save is free", not Data.heldElsewhere({ cash = 1 }))

		-- Shutdown saves run side by side: 12 two-second saves finish in about 2 seconds, and a stuck one can't hold
		-- shutdown past the deadline.
		local list = {}
		for i = 1, 12 do
			table.insert(list, i)
		end
		local started = os.clock()
		local finished = Data.saveAll(list, 10, function()
			task.wait(2)
		end)
		local took = os.clock() - started
		t.check(("12 shutdown saves run in parallel (%.1f s)"):format(took), finished == 12 and took < 4)
		started = os.clock()
		finished = Data.saveAll({ 1, 2 }, 1, function(i)
			task.wait(i == 1 and 0 or 30)
		end)
		took = os.clock() - started
		t.check(("a stuck save stops at the deadline (%.1f s, %d of 2 done)"):format(took, finished), finished == 1 and took < 2)

		-- Which per-slot sets this build saves at all.
		COUNT_FIELDS = { "secrets", "discovered" }
		savesField = {}
		for _, field in COUNT_FIELDS do
			local probe = D.toSave(D.stateFrom({ [field] = { probe = 1 } }))
			savesField[field] = typeof(probe[field]) == "table" and probe[field].probe == 1
			t.check(("the save keeps %s per slot"):format(field), savesField[field])
		end

		-- Round trips: save, JSON (what the DataStore keeps), load, save again. The second save must equal the first,
		-- and what the player had must survive.
		local rng = Random.new(1337)
		local bad, biggest = {}, 0
		for i = 1, 200 do
			local original = randomSave(rng, i == 1)
			local okRun, err = pcall(function()
				local json = HttpService:JSONEncode(original)
				biggest = math.max(biggest, #json)
				local first = D.toSave(D.stateFrom(Data.migrate(HttpService:JSONDecode(json))))
				local second = D.toSave(D.stateFrom(Data.migrate(HttpService:JSONDecode(HttpService:JSONEncode(first)))))
				if canon(first) ~= canon(second) then
					error("a second round trip changed the save")
				end
				for k, n in original.pocket do
					if first.pocket[k] ~= n then
						error("pocket needle " .. k .. " lost")
					end
				end
				for k, n in original.land.needles do
					if first.land.needles[k] ~= n then
						error("bin needle " .. k .. " lost")
					end
				end
				if #first.land.items ~= #original.land.items then
					error("farm pieces lost")
				end
				if (original.land2 ~= nil) ~= (first.land2 ~= nil) then
					error("second farm lost")
				end
				-- Map's per-slot sets: secrets found and regions/landmarks discovered. A field this build's Data doesn't
				-- save yet is skipped here and reported once below.
				for _, field in COUNT_FIELDS do
					if savesField[field] then
						for k, n in original[field] do
							if not first[field] or first[field][k] ~= n then
								error(field .. " " .. k .. " lost")
							end
						end
					end
				end
				if first.land.name ~= original.land.name then
					error("farm name lost")
				end
				if first.land.binPolisher ~= original.land.binPolisher or first.land.binSorted ~= original.land.binSorted then
					error("bin upgrades lost")
				end
				if first.thatch ~= original.thatch or first.gloves.worn ~= original.gloves.worn or first.bank.balance ~= original.bank.balance then
					error("thatch, gloves or bank lost")
				end
			end)
			if not okRun then
				table.insert(bad, ("#%d: %s"):format(i, tostring(err)))
				if #bad >= 5 then
					break
				end
			end
		end
		t.check("200 random saves survive two round trips", #bad == 0, #bad > 0 and table.concat(bad, "; ") or nil)
		-- DataStore values are capped at 4 MB; the fullest save should be far below that.
		t.check(("the fullest save is %d KB, under 1 MB"):format(math.ceil(biggest / 1024)), biggest < 1024 * 1024)
	end)
end

-- "PlayTogether" (CEO H17): away earnings (the cap and the double-pay guard), the +10% together bonus with its alt
-- guard ($25,000 sold), and JOIN FARM. Uses stand-in players and a free plot, so it needs no second player.
local function registerTogether(SelfTest)
	SelfTest.register("PlayTogether", function(t)
		local L = Land.test
		local Away = require(game:GetService("ReplicatedStorage").Shared.Away)
		local Prices = require(game:GetService("ReplicatedStorage").Shared.Config.Prices)
		local LandCfg = require(game:GetService("ReplicatedStorage").Shared.Config.Land)
		local Bales = require(Services.Bales)
		local RateLimit = require(game:GetService("ReplicatedStorage").Shared.RateLimit)

		-- Away earnings: pure arithmetic first, then the mailbox on a save.
		local now = 1000000
		t.check("away: under a minute pays nothing", Away.span(now - 59, now) == 0)
		t.check("away: a clock that went backwards pays nothing", Away.span(now + 500, now) == 0)
		t.check("away: no savedAt pays nothing", Away.span(nil, now) == 0 and Away.span(0 / 0, now) == 0)
		t.check("away: capped at 8 hours", Away.span(now - 72 * 3600, now) == Away.MAX_SECONDS and Away.MAX_SECONDS == 8 * 3600)
		t.check("away: 8 hours and 3 days pay the same", Away.bales(Away.span(now - 8 * 3600, now), 20, 1e9) == Away.bales(Away.span(now - 72 * 3600, now), 20, 1e9))
		t.check("away: half the line's rate", Away.bales(3600, 20, 1e9) == 600)
		t.check("away: never more bales than the silos hold", Away.bales(8 * 3600, 20, 37) == 37)
		t.check("away: no rate or no hay pays nothing", Away.bales(3600, 0, 50) == 0 and Away.bales(3600, 20, 0) == 0)

		local owner = fakeOwner(-931)
		local function land(stored, ago)
			return {
				owned = true,
				savedAt = os.time() - ago,
				items = {
					{ id = "silo", gx = 0, gz = 0, dir = "N", stored = stored },
					{ id = "hay_buyer", gx = 4, gz = 0, dir = "N" },
					{ id = "optical_sorter", gx = 3, gz = 0, dir = "N" },
				},
				needles = {},
			}
		end
		local a = land(1e6, 72 * 3600)
		local okA = pcall(L.mailbox, owner, a)
		local first = 1e6 - a.items[1].stored
		local b = land(1e6, 8 * 3600)
		pcall(L.mailbox, owner, b)
		t.check("mailbox: 3 days away pays the same as 8 hours", okA and first > 0 and first == 1e6 - b.items[1].stored, ("%s vs %s"):format(first, 1e6 - b.items[1].stored))
		local before = a.items[1].stored
		t.check("mailbox: a second load pays nothing", L.mailbox(owner, a) == nil and a.items[1].stored == before)
		local c = land(5, 8 * 3600)
		pcall(L.mailbox, owner, c)
		t.check("mailbox: takes no more than the silo holds", c.items[1].stored == 0)
		local d = land(10, 3600)
		d.savedAt = "yesterday"
		t.check("mailbox: a broken savedAt pays nothing", L.mailbox(owner, d) == nil and d.items[1].stored == 10)

		-- Together bonus: the alt guard at exactly $25,000 sold.
		local need = Prices.Trade.MinSoldToGiveCash
		t.check("together: the guard is $25,000 sold", need == 25000, need)
		t.check("together: a slot that sold $24,999 can't help", not L.seasonedState({ bank = { sold = need - 1 } }))
		t.check("together: a slot that sold $25,000 can help", L.seasonedState({ bank = { sold = need } }))
		t.check("together: one-time rewards don't count", not L.seasonedState({ bank = { earned = need * 4, sold = 0 } }))
		t.check("together: no save can't help", not L.seasonedState(nil))

		local function fakePlayer(userId, at)
			local root = { Position = at }
			return {
				UserId = userId,
				DisplayName = "P" .. userId,
				Character = {
					FindFirstChild = function(_, name)
						return name == "HumanoidRootPart" and root or nil
					end,
				},
			}
		end
		local host = fakePlayer(-932, Vector3.new(0, 0, 0))
		local plot = { owner = host, ownerId = -932, corner = Vector3.new(100, 0, 100), size = Vector3.new(72, 0, 72), crew = { [-933] = true } }
		local crew = fakePlayer(-933, Vector3.new(130, 3, 130))
		local friend = fakePlayer(-934, Vector3.new(110, 3, 160))
		local stranger = fakePlayer(-935, Vector3.new(120, 3, 120))
		local outside = fakePlayer(-936, Vector3.new(300, 3, 300))
		local friendsOf = { [-934] = true, [-936] = true }
		local isFriend = function(_, other)
			return friendsOf[other.UserId] == true
		end
		local sold = { [-933] = true, [-934] = true, [-935] = true, [-936] = true }
		local isSeasoned = function(p)
			return sold[p.UserId] == true
		end
		t.check("together: crew on the farm switches it on", L.helperOn(plot, { host, crew }, isFriend, isSeasoned) == crew)
		t.check("together: a friend on the farm switches it on", L.helperOn(plot, { host, friend }, isFriend, isSeasoned) == friend)
		t.check("together: a stranger doesn't", L.helperOn(plot, { host, stranger }, isFriend, isSeasoned) == nil)
		t.check("together: a friend off the farm doesn't", L.helperOn(plot, { host, outside }, isFriend, isSeasoned) == nil)
		t.check("together: the owner alone doesn't", L.helperOn(plot, { host }, isFriend, isSeasoned) == nil)
		sold[-933], sold[-934] = nil, nil
		t.check("together: a crew alt under $25,000 doesn't", L.helperOn(plot, { host, crew, friend }, isFriend, isSeasoned) == nil)
		t.check("together: an empty farm has no bonus", L.helperOn({ corner = plot.corner, size = plot.size }, { crew }, isFriend, isSeasoned) == nil)
		t.check("together: the bonus is +10%", LandCfg.TogetherBonus == 1.1)

		-- The boost on real bales on a free plot: once per bale, on top of a rich field's boost, never on sorted bales.
		local free = freePlots(L)[1]
		if free then
			local mid = free.corner + Vector3.new(free.size.X / 2, 3, free.size.Z / 2)
			local plain = Bales.spawn(mid, false)
			local rich = Bales.spawn(mid + Vector3.new(8, 0, 0), false)
			local done = Bales.spawn(mid + Vector3.new(-8, 0, 0), false)
			for _, bale in { plain, rich, done } do
				bale.body.Anchored = true
			end
			rich.body:SetAttribute("NeedleBoost", 2)
			done.sorted = true
			L.boostBales(free)
			L.boostBales(free)
			local function near(x, y)
				return typeof(x) == "number" and math.abs(x - y) < 1e-6
			end
			t.check("together: a bale on the farm gets 1.1x needles", near(plain.body:GetAttribute("NeedleBoost"), 1.1), plain.body:GetAttribute("NeedleBoost"))
			t.check("together: boosted once, not every second", plain.body:GetAttribute("TogetherBoost") == true)
			t.check("together: stacks on a rich field's 2x", near(rich.body:GetAttribute("NeedleBoost"), 2.2), rich.body:GetAttribute("NeedleBoost"))
			t.check("together: sorted bales are left alone", done.body:GetAttribute("NeedleBoost") == nil)
			for _, bale in { plain, rich, done } do
				pcall(Bales.consume, bale)
			end
		else
			t.skip("together: bale boost", "no free plot")
		end

		-- JOIN FARM: never your own farm, nobody's farm here, and rate-limited.
		local visitor = fakeOwner(-937)
		L.joinLimit:forget(visitor)
		local ok1, why1 = Land.joinFarm(visitor, visitor.UserId)
		t.check("join farm: refuses your own farm", ok1 == false and tostring(why1):find("own farm") ~= nil, why1)
		local ok2, why2 = Land.joinFarm(visitor, -999999)
		t.check("join farm: refuses a player with no farm here", ok2 == false and tostring(why2):find("don't have a farm") ~= nil, why2)
		local ok3, why3 = Land.joinFarm(visitor, -999999)
		t.check("join farm: rate-limited", ok3 == false and why3 == RateLimit.BUSY, why3)
		L.joinLimit:forget(visitor)
		t.check("join farm: hasFarm is false for nobody", Land.hasFarm(-999999) == false)
	end)
end

return function(SelfTest)
	registerSaves(SelfTest)
	registerTogether(SelfTest)
	SelfTest.register("Land", function(t)
		local L = Land.test
		if not L then
			t.check("Land.test hooks exist", false, "Land.luau has no Land.test table")
			return
		end

		-- Rate limits: every spammable Land remote is wrapped, and a burst past the bucket is refused with BUSY.
		if L.limits and L.limited then
			for _, name in { "Crew", "CrewAnswer", "Visit", "Buy", "Expand", "Paste" } do
				t.check(("the %s remote has a rate limit"):format(name), L.limits[name] ~= nil)
			end
			local RateLimit = require(game:GetService("ReplicatedStorage").Shared.RateLimit)
			local clock = RateLimit.clock
			local report = RateLimit.report
			local now = 0
			RateLimit.clock = function()
				return now
			end
			RateLimit.report = function() end
			local probe = RateLimit.new("Land.Probe", 1, 3)
			local calls = 0
			local fn = L.limited(probe, function()
				calls += 1
				return true
			end)
			local spammer = {}
			for _ = 1, 10 do
				fn(spammer)
			end
			local ok, why = fn(spammer)
			local burst = calls -- counted before the refill below lets one more through
			now = 2
			local again = fn(spammer)
			RateLimit.clock = clock
			RateLimit.report = report
			t.check("a burst of remote calls is cut off at the bucket size", burst == 3, ("got %d calls through"):format(burst))
			t.check("a refused call says to slow down", ok == false and why == RateLimit.BUSY)
			t.check("the bucket refills over time", again == true and calls == 4)
		else
			t.check("Land.test exposes its rate limits", false)
		end

		-- Silo fill for the HUD: SiloFullIn comes from the total fill of every silo and barn on the active farm.
		if L.siloTotals and L.siloFullIn then
			local fakePlot = { list = { { id = "silo", stored = 7 }, { id = "hay_barn", stored = 40 }, { id = "belt" } } }
			local fill, cap = L.siloTotals(fakePlot)
			local siloCap = L.pieces.silo.capacity or require(game:GetService("ReplicatedStorage").Shared.Config.Land).SiloCapacity
			t.check("silo fill sums every silo and barn", fill == 47, ("got %s"):format(tostring(fill)))
			t.check("silo cap sums their capacities", cap == siloCap + 150, ("got %s"):format(tostring(cap)))
			t.check("no farm means no silo capacity", select(2, L.siloTotals(nil)) == 0)
			local filling = { { at = 0, fill = 10, cap = 60 }, { at = 20, fill = 20, cap = 60 } }
			t.check("filling at 0.5 bales/s with 40 left is full in 80 s", L.siloFullIn(filling, 20) == 80)
			t.check("no estimate from under 10 s of history", L.siloFullIn({ { at = 0, fill = 1, cap = 60 }, { at = 5, fill = 9, cap = 60 } }, 5) == nil)
			t.check("an emptying silo has no countdown", L.siloFullIn({ { at = 0, fill = 30, cap = 60 }, { at = 30, fill = 20, cap = 60 } }, 30) == nil)
			t.check("no silo has no countdown", L.siloFullIn({ { at = 0, fill = 0, cap = 0 }, { at = 30, fill = 0, cap = 0 } }, 30) == nil)
			t.check("a full silo still filling reads 0", L.siloFullIn({ { at = 0, fill = 50, cap = 60 }, { at = 30, fill = 60, cap = 60 } }, 30) == 0)
		end

		-- Leaderboards: rarest needle is the most valuable type found, and the board merges stored and live scores.
		local okBoards, Boards = pcall(require, Services.Leaderboards)
		local B = okBoards and Boards and Boards.test
		if B then
			local top = B.byValue[#B.byValue]
			t.check("no needles found ranks 0", B.rarestRank({ codex = {} }) == 0)
			t.check("the rarest needle is the most valuable found", B.rarestRank({ codex = { needles = { steel = true, [top.id] = true } } }) == #B.byValue)
			t.check("unknown needle ids are ignored", B.rarestRank({ codex = { needles = { nonsense = true } } }) == 0)
			local list = B.merge({ [1] = 500, [2] = 900 }, { [1] = 1200, [3] = 0 }, 10)
			t.check("the board takes a player's higher score once", #list == 2 and list[1].userId == 1 and list[1].score == 1200)
			t.check("players with no score stay off the board", list[2].userId == 2)
			t.check("the board stops at its row count", #B.merge({ [1] = 1, [2] = 2, [3] = 3 }, {}, 2) == 2)
			t.check("money reads with commas", B.commas(1234567) == "1,234,567" and B.commas(999) == "999")
		else
			t.check("Leaderboards.test exists", false)
		end

		-- Showing off mutated needles: the name tag keeps the best needle ever held, and a trade announces a new
		-- mutated needle once.
		local okTags, NameTags = pcall(require, Services.NameTags)
		local okTrade, Trade = pcall(require, Services.Trade)
		if okTags and NameTags.test and okTrade and Trade.test then
			local NT = NameTags.test
			t.check("no needles means no tag", NT.bestOf(nil, {}) == nil and NT.tagFor(nil) == nil)
			t.check("the best needle is the most valuable in the pocket", NT.bestOf(nil, { steel = 3, cosmic = 1 }) == "cosmic")
			t.check("a mutated needle beats its plain type", NT.bestOf(nil, { ["steel*20"] = 1, steel = 9 }) == "steel*20")
			t.check("the saved best stays after the pocket empties", NT.bestOf("cosmic", {}) == "cosmic")
			t.check("an empty pocket stack doesn't count", NT.bestOf(nil, { cosmic = 0, steel = 1 }) == "steel")
			local text = NT.tagFor("cosmic*12")
			t.check("a mutated tag names it", typeof(text) == "string" and text:find("x12 MUTATED COSMIC") ~= nil, tostring(text))
			local mutatedNew = Trade.test.mutatedNew
			t.check("a plain offer announces nothing", mutatedNew(nil, { needles = { steel = 4 } }) == nil)
			t.check("a new mutated needle in an offer is announced", mutatedNew({ needles = { steel = 4 } }, { needles = { steel = 4, ["ice*7"] = 1 } }) == "ice*7")
			t.check("one already in the offer isn't announced again", mutatedNew({ needles = { ["ice*7"] = 1 } }, { needles = { ["ice*7"] = 2 } }) == nil)
		else
			t.check("NameTags.test and Trade.test exist", false)
		end

		-- Plots: six, all the same size and price, all with a bin and a mailbox.
		local count, sizes, prices = 0, {}, {}
		for _, plot in L.plots do
			count += 1
			sizes[("%dx%d"):format(plot.tiles.X, plot.tiles.Z)] = true
			prices[plot.def.price] = true
		end
		local function keys(map)
			local n = 0
			for _ in map do
				n += 1
			end
			return n
		end
		t.equal("plot count", count, 6)
		t.equal("every plot is the same size", keys(sizes), 1)
		t.equal("every plot has the same price", keys(prices), 1)
		local fixtures = true
		for _, plot in L.plots do
			fixtures = fixtures and plot.bin ~= nil and plot.mailLabel ~= nil and plot.model:FindFirstChild("SignPost") ~= nil
		end
		t.check("every plot has a needle bin, sign and mailbox", fixtures)

		-- Turning a north-row plot's cells is its own inverse.
		local north = nil
		for _, plot in L.plots do
			if plot.def.open ~= "S" then
				north = plot
			end
		end
		if north then
			local gx, gz, dir = L.turnFor(north, 2, 3, "E")
			local bx, bz, bdir = L.turnFor(north, gx, gz, dir)
			t.check("turnFor on a north plot round-trips", bx == 2 and bz == 3 and bdir == "E", ("%s %s %s"):format(bx, bz, bdir))
		else
			t.skip("turnFor on a north plot round-trips", "no north-row plot")
		end

		-- Grid numbers from clients: whole and finite only.
		local badCells = {}
		for _, n in { math.huge, -math.huge, 0 / 0, 0.5, "3", 1e9 } do
			if L.isCell(n) then
				table.insert(badCells, tostring(n))
			end
		end
		t.check("isCell rejects inf, nan, fractions, strings and huge numbers", #badCells == 0, table.concat(badCells, ", "))
		t.check("isCell accepts a plain cell", L.isCell(3) and L.isCell(0))

		local free = freePlots(L)
		if #free < 2 then
			t.skip("claim, save and load", ("needs 2 free plots, %d free"):format(#free))
			return
		end
		-- Prefer a north plot to build on and a south plot to load onto, so the turn is tested.
		local a, b = free[1], free[2]
		for _, plot in free do
			if plot.def.open ~= "S" then
				a = plot
			end
		end
		for _, plot in free do
			if plot ~= a and plot.def.open == "S" then
				b = plot
			end
		end

		local owner = fakeOwner(-424242)
		local ok, err = pcall(function()
			-- Claim an empty farm.
			L.claim(a, owner, blankLand())
			t.equal("claim sets the owner", a.ownerId, owner.UserId)
			t.check("claim makes it the active farm", L.plotOf[owner] == a)
			t.equal("claim sets LandPlot", owner:GetAttribute("LandPlot"), a.index)
			t.equal("an empty save builds nothing", #a.list, 0)

			-- Build every piece somewhere it fits.
			local built, failed = 0, {}
			for id, def in L.pieces do
				local placed = false
				for gz = 0, a.tiles.Z - 1 do
					for gx = 0, a.tiles.X - 1 do
						if not placed and L.fits(a, def, gx, gz, "N") then
							local okPiece, why = pcall(L.spawnItem, a, def, gx, gz, "N")
							if okPiece then
								built += 1
							else
								table.insert(failed, id .. ": " .. tostring(why))
							end
							placed = true
						end
					end
				end
				if not placed then
					table.insert(failed, id .. ": no room")
				end
			end
			t.check(("every piece builds (%d)"):format(built), #failed == 0, #failed > 0 and table.concat(failed, "; ") or nil)

			-- No two pieces share a cell on the same level.
			local clash = nil
			for k, item in a.taken do
				if not table.find(a.list, item) then
					clash = k
				end
			end
			t.check("every taken cell points at a built piece", clash == nil, clash)

			-- Save it, with needles in the bin.
			local id = Needle.default.id
			a.bin.fill(owner.UserId, { [id] = 12 })
			local saved = blankLand()
			L.writeLand(saved, a, owner.UserId)
			local want, wantN = itemSet(saved.items)
			t.equal("the save lists every piece", wantN, #a.list)
			t.equal("the save keeps the bin's needles", saved.needles and saved.needles[id], 12)
			t.equal("the save records the plot", saved.plot, a.index)

			-- Leaving frees the plot and empties it.
			L.release(a)
			t.check("release frees the plot", a.ownerId == nil)
			t.equal("release clears the pieces", #a.list, 0)
			t.equal("release empties the bin", a.bin.contents(nil)[id] or 0, 0)
			t.check("release clears the active farm", L.plotOf[owner] == nil)

			-- Load the same save onto another plot.
			L.claim(b, owner, saved)
			L.restoreNeedles(owner, b, saved)
			local again = blankLand()
			L.writeLand(again, b, owner.UserId)
			local got, gotN = itemSet(again.items)
			local missing = {}
			for k, n in want do
				if got[k] ~= n then
					table.insert(missing, k)
				end
			end
			t.equal("every piece comes back on another plot", gotN, wantN)
			t.check(("pieces keep their plot-local spots (%s to %s)"):format(a.def.open, b.def.open), #missing == 0, table.concat(missing, ", "))
			t.equal("the bin's needles come back", b.bin.contents(owner.UserId)[id] or 0, 12)

			-- A second farm on the plot that was just freed.
			L.claim(a, owner, blankLand(), "land2")
			t.check("the second farm is recorded", L.farms[owner] and L.farms[owner].land2 == a)
			t.check("the first farm stays active", L.plotOf[owner] == b)
			t.equal("FarmCount is 2", owner:GetAttribute("FarmCount"), 2)
			L.release(a)
			t.check("releasing the second farm keeps the first", L.plotOf[owner] == b)
			t.equal("FarmCount is 1", owner:GetAttribute("FarmCount"), 1)

			-- Remote guards (Conveyor audit 24/25).
			local before = #b.list
			local pasted, why = L.onPaste(owner, { { id = "belt", dx = math.huge, dz = 0, dir = "N" } }, 0, 0)
			t.check("paste refuses an infinite offset", not pasted and #b.list == before, why)
			local bought, buyWhy = L.onBuyRemote(owner, 1)
			t.check("buying away from the Land Office is refused", not bought and tostring(buyWhy):find("Land Office") ~= nil, buyWhy)
			local expanded = L.onExpandRemote(owner)
			t.check("expanding away from the farm and the office is refused", not expanded)

			-- Crew hand-offs: owner and crew of one farm are teammates, an outsider is not.
			local mateA, mateB, outsider = fakeOwner(-525252), fakeOwner(-626262), fakeOwner(-727272)
			b.crew[mateA.UserId], b.crew[mateB.UserId] = true, true
			local isTeammate = (require(Services.Bales) :: any).isTeammate
			if isTeammate then
				t.check("two crew of the same farm are teammates", isTeammate(mateA, mateB))
				t.check("the owner and their crew are teammates", isTeammate(owner, mateA))
				t.check("an outsider is not a teammate", not isTeammate(owner, outsider))
			else
				t.skip("crew teammates", "Bales.isTeammate isn't set")
			end
			b.crew[mateA.UserId], b.crew[mateB.UserId] = nil, nil

			-- Crew needs the invited player's yes.
			local Players = game:GetService("Players")
			local guest = Players:GetPlayers()[1]
			if guest then
				local asked = L.onCrew(owner, guest.UserId, true)
				t.check("adding crew only sends an invite", asked and b.crew[guest.UserId] == nil and guest:GetAttribute("CrewInvite") ~= nil)
				L.onCrewAnswer(guest, owner.UserId, false)
				t.check("saying no leaves the crew unchanged", b.crew[guest.UserId] == nil and guest:GetAttribute("CrewInvite") == nil)
			else
				t.skip("crew invites need a yes", "needs a player in the server")
			end
		end)
		-- Always hand the plots back.
		for _, plot in { a, b } do
			if plot.owner == owner then
				pcall(L.release, plot)
			end
		end
		L.farms[owner] = nil
		L.plotOf[owner] = nil
		t.check("claim, save and load ran", ok, err)

		-- The mailbox, on a save alone (it runs before the plot is built).
		local function mailLand(withBuyer)
			local land = { owned = true, savedAt = os.time() - 3600, items = { { id = "silo", gx = 0, gz = 0, dir = "N", stored = 10 } }, needles = {} }
			if withBuyer then
				table.insert(land.items, { id = "hay_buyer", gx = 4, gz = 0, dir = "N" })
				table.insert(land.items, { id = "optical_sorter", gx = 3, gz = 0, dir = "N" })
			end
			return land
		end
		local noBuyer = mailLand(false)
		local letter = L.mailbox(owner, noBuyer)
		t.check("mailbox without a hay buyer says so and sells nothing", letter ~= nil and letter:find("no hay buyer") ~= nil and noBuyer.items[1].stored == 10, letter)
		local withBuyer = mailLand(true)
		letter = L.mailbox(owner, withBuyer)
		local left = withBuyer.items[1].stored
		t.check("mailbox an hour away drains the silo", letter ~= nil and left < 10, ("%s bales left: %s"):format(left, tostring(letter)))
		t.check("mailbox pays once: a second load straight after pays nothing", L.mailbox(owner, withBuyer) == nil and withBuyer.savedAt >= os.time() - 1)
		local long = mailLand(true)
		long.savedAt = os.time() - 72 * 3600
		long.items[1].stored = 1e6
		L.mailbox(owner, long)
		local sorted = 1e6 - long.items[1].stored
		t.check("mailbox stops at 8 hours at half speed", sorted > 0 and sorted <= 8 * 60 * 30 / 2, sorted)
		local recent = mailLand(true)
		recent.savedAt = os.time() - 10
		t.check("mailbox after 10 seconds stays empty", L.mailbox(owner, recent) == nil)

		-- Place and undo on a real player's own farm.
		local player = t.player(5)
		local mine = player and L.plotOf[player]
		if not mine then
			t.skip("place and undo", "needs a player with a loaded farm")
			return
		end
		local def = L.pieces.belt
		local spot = nil
		for gz = 0, mine.tiles.Z - 1 do
			for gx = 0, mine.tiles.X - 1 do
				if not spot and L.fits(mine, def, gx, gz, "N") then
					spot = { gx, gz }
				end
			end
		end
		if not spot then
			t.skip("place and undo", "no free cell on the player's farm")
			return
		end
		-- Visiting can't carry hay across the map.
		local state = Data.get(player)
		if state then
			local had = state.loadHay
			state.loadHay = 1
			local visited = L.onVisit(player, mine.index)
			state.loadHay = had
			t.check("visiting a farm is refused while carrying hay", not visited)
		end

		-- Build actions are debounced (ownPlot: 0.12 s between a player's actions), so wait between them like a
		-- player's clicks would.
		local before = #mine.list
		task.wait(0.2)
		local placed, placeWhy = L.onPlace(player, "belt", spot[1], spot[2], "N")
		t.check("place builds a belt", placed and #mine.list == before + 1, placeWhy)
		task.wait(0.2)
		local undone, undoWhy = L.onUndo(player)
		t.check("undo takes it away again", undone and #mine.list == before, undoWhy)
	end)
end
