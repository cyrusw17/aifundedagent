--!nonstrict
-- Land's suite: claiming a plot, building every piece, saving and loading a farm onto a different plot (the turned
-- north row included), restoring bin needles, the mailbox, and a second farm. It works on free plots with a stand-in
-- owner, so it needs no player; place and undo run on a real player's own farm when one is loaded.
local Services = script.Parent.Parent.Services

local Land = require(Services.Land)
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

return function(SelfTest)
	SelfTest.register("Land", function(t)
		local L = Land.test
		if not L then
			t.check("Land.test hooks exist", false, "Land.luau has no Land.test table")
			return
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
		local before = #mine.list
		local placed = L.onPlace(player, "belt", spot[1], spot[2], "N")
		t.check("place builds a belt", placed and #mine.list == before + 1)
		local undone = L.onUndo(player)
		t.check("undo takes it away again", undone and #mine.list == before)
	end)
end
