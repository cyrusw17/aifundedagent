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

return function(SelfTest)
	registerSaves(SelfTest)
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
			now = 2
			local again = fn(spammer)
			RateLimit.clock = clock
			RateLimit.report = report
			t.check("a burst of remote calls is cut off at the bucket size", calls == 3, ("got %d calls through"):format(calls))
			t.check("a refused call says to slow down", ok == false and why == RateLimit.BUSY)
			t.check("the bucket refills over time", again == true and calls == 4)
		else
			t.check("Land.test exposes its rate limits", false)
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

		local before = #mine.list
		local placed = L.onPlace(player, "belt", spot[1], spot[2], "N")
		t.check("place builds a belt", placed and #mine.list == before + 1)
		local undone = L.onUndo(player)
		t.check("undo takes it away again", undone and #mine.list == before)
	end)
end
