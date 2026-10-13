--!nonstrict
-- UI thread's suite: the remotes the screens use exist, the goal bar's ladder moves on after each purchase, the shop
-- lists the prices in Config/Prices, settings are checked and stored, and tutorial flags fire on the right events.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent.Parent.Services
local Shared = ReplicatedStorage:WaitForChild("Shared")

-- Stands in for a player's attributes so the ladder can be walked without a real player.
local function fakePlayer(attrs)
	return {
		attrs = attrs,
		GetAttribute = function(self, name)
			return self.attrs[name]
		end,
	}
end

return function(SelfTest)
	SelfTest.register("UI", function(t)
		-- Remotes the client scripts wait on.
		for _, path in
			{
				{ "Tutorial", "Action" },
				{ "Tutorial", "Earned" },
				{ "Settings", "Set" },
				{ "Announce" },
			}
		do
			local node = ReplicatedStorage
			for _, name in path do
				node = node and node:FindFirstChild(name)
			end
			t.check(
				("remote ReplicatedStorage.%s exists"):format(table.concat(path, ".")),
				node ~= nil and node:IsA("RemoteEvent")
			)
		end

		local Prices = require(Shared.Config.Prices)
		local Catalog = require(Shared.UI.Catalog)
		local saved = Catalog.who

		-- The goal ladder moves on after each purchase.
		local who = fakePlayer({})
		Catalog.who = who
		local ok, err = pcall(function()
			local function goal()
				local step = Catalog.nextGoal()
				return step and step.name or "done"
			end
			-- Walk the ladder in ECONOMY.md order: each purchase moves the goal to the next step, at Prices' price.
			local A = who.attrs
			local walk = {
				{
					"Work Gloves",
					Prices.Gloves.work,
					function()
						A.GlovesOwned = "bare,work"
					end,
				},
				{
					"a Wheelbarrow",
					Prices.Wheelbarrow,
					function()
						A.Gear = "wheelbarrow"
					end,
				},
				{
					"the Rusty Pickup",
					Prices.Trucks.rusty_pickup,
					function()
						A.OwnedTrucks = "rusty_pickup"
					end,
				},
				{
					"a Wagon Trailer",
					Prices.Trailers.wagon_trailer,
					function()
						A.OwnedTrailers = "wagon_trailer"
					end,
				},
				{
					"your first plot",
					Prices.Plot,
					function()
						A.LandPlot = 2
					end,
				},
				{
					"a Hand Sieve",
					Prices.Pieces.hand_sieve,
					function()
						A.TutorialFlags = "built_hand_sieve,sorter"
					end,
				},
				{
					"a Shaker Table",
					Prices.Pieces.shaker_table,
					function()
						A.TutorialFlags = "built_hand_sieve,built_shaker_table,sorter"
					end,
				},
				{
					"Leather Gloves",
					Prices.Gloves.leather,
					function()
						A.GlovesOwned = "bare,work,leather"
					end,
				},
				{
					"the Farm Flatbed",
					Prices.Trucks.farm_flatbed,
					function()
						A.OwnedTrucks = "rusty_pickup,farm_flatbed"
					end,
				},
				{
					"a Conveyor Sorter",
					Prices.Pieces.conveyor_sorter,
					function()
						A.TutorialFlags = "built_conveyor_sorter,built_hand_sieve,built_shaker_table,sorter"
					end,
				},
				{
					"Reinforced Gloves",
					Prices.Gloves.reinforced,
					function()
						A.GlovesOwned = "bare,work,leather,reinforced"
					end,
				},
				{
					"Iron Gauntlets",
					Prices.Gloves.iron,
					function()
						A.GlovesOwned = "bare,work,leather,reinforced,iron"
					end,
				},
				{
					"Starlight Gloves",
					Prices.Gloves.starlight,
					function()
						A.GlovesOwned = "bare,work,leather,reinforced,iron,starlight"
					end,
				},
			}
			for i, step in walk do
				t.equal(("goal %d"):format(i), goal(), step[1])
				local now = Catalog.nextGoal()
				t.equal(("goal %d price (%s)"):format(i, step[1]), now and now.price, step[2])
				step[3]()
			end
			t.equal("everything bought", goal(), "done")

			-- Shop rows show the one price config, never a fallback.
			local function priceFor(tab, id)
				if tab == "Trucks" then
					return Prices.Trucks[id]
				elseif tab == "Gloves" then
					return Prices.Gloves[id]
				elseif tab == "Land" then
					return Prices.Plot
				elseif tab == "Build" then
					return Prices.Pieces[id]
				elseif tab == "Trailers" then
					return Prices.Trailers[id]
				end
				return nil
			end
			local wrong = {}
			local rows = 0
			for _, tab in Catalog.Tabs do
				if tab ~= "Robux" then
					for _, row in Catalog.items(tab) do
						rows += 1
						local want = priceFor(tab, row.id)
						if want == nil or row.price ~= want then
							table.insert(
								wrong,
								("%s/%s %s vs %s"):format(tab, row.id, tostring(row.price), tostring(want))
							)
						end
					end
				end
			end
			t.check(
				("%d shop rows match Config/Prices"):format(rows),
				#wrong == 0 and rows > 0,
				table.concat(wrong, "; ")
			)
			local PieceGuide = require(Shared.PieceGuide)
			local LandConfig = require(Shared.Config.Land)
			local blurbs = {}
			for _, def in LandConfig.Pieces do
				blurbs[def.id] = PieceGuide.line(def)
			end
			local drift = {}
			for _, row in Catalog.items("Build") do
				if row.blurb ~= blurbs[row.id] then
					table.insert(drift, row.id)
				end
			end
			t.check("Build tab lines come from PieceGuide", #drift == 0, table.concat(drift, ", "))
			for _, row in Catalog.items("Robux") do
				t.check(("Robux item %s is not for sale yet"):format(row.id), row.state == "soon")
			end
		end)
		Catalog.who = saved
		t.check("goal ladder and shop ran", ok, if ok then nil else tostring(err))

		-- Discoveries: the map stamps and the book's PLACES page use UI/DiscoveryList, which must list exactly what the
		-- server pays for (Discoveries.all), in the same order, each with a map position inside the world.
		local DiscoveryList = require(Shared.UI.DiscoveryList)
		local okD, server = pcall(function()
			return require(Services.Discoveries).all()
		end)
		if not okD then
			t.skip("discovery list matches the server", "Discoveries.luau is not in this build")
		else
			local mine = DiscoveryList.all()
			t.equal("discovery count", #mine, #server)
			local mismatched = {}
			for i, d in server do
				if not mine[i] or mine[i].id ~= d.id then
					table.insert(mismatched, ("%d: %s vs %s"):format(i, d.id, mine[i] and mine[i].id or "none"))
				end
			end
			t.check("discovery ids in the server's order", #mismatched == 0, table.concat(mismatched, "; "))
			local Map = require(Shared.Config.WorldMap)
			local outside = {}
			for _, d in mine do
				local at = d.at
				if
					typeof(at) ~= "Vector2"
					or at.X < Map.Bounds.min.X
					or at.X > Map.Bounds.max.X
					or at.Y < Map.Bounds.min.Y
					or at.Y > Map.Bounds.max.Y
				then
					table.insert(outside, d.id)
				end
			end
			t.check("every discovery has a map spot for its stamp", #outside == 0, table.concat(outside, ", "))
			local found = DiscoveryList.found(fakePlayer({ Discovered = "old_well,pine" }))
			t.check(
				"the Discovered attribute reads as found ids",
				found.old_well == true and found.pine == true and not found.snow
			)
		end

		-- Truck spots for the map: the server publishes where each owned truck is (streaming-safe).
		local TruckSpots = require(Services.TruckSpots)
		local okT, errT = pcall(TruckSpots.publish)
		t.check("TruckSpots publishes without error", okT, if okT then nil else tostring(errT))

		-- With a player in a loaded slot: settings and tutorial flags.
		local player = t.player(10)
		local Data = require(Services.Data)
		if not player or not Data.get(player) then
			t.skip("settings and tutorial flags", "needs a player with a save slot picked")
			return
		end
		local Settings = require(Services.Settings)
		local Tutorial = require(Services.Tutorial)

		local before = player:GetAttribute("SettingUiSize")
		Settings.set(player, "uiSize", "large")
		t.equal("Settings: UI size large", player:GetAttribute("SettingUiSize"), "large")
		Settings.set(player, "uiSize", "huge")
		t.equal("Settings: a bad UI size is ignored", player:GetAttribute("SettingUiSize"), "large")
		Settings.set(player, "effects", 5)
		t.equal("Settings: volume is clamped to 1", player:GetAttribute("SettingEffects"), 1)
		Settings.set(player, "nope", true)
		t.equal("Settings: unknown key leaves no attribute", player:GetAttribute("SettingNope"), nil)
		Settings.set(player, "uiSize", before or "normal")

		local function hasFlag(flag)
			return string.find("," .. (player:GetAttribute("TutorialFlags") or "") .. ",", "," .. flag .. ",", 1, true)
				~= nil
		end
		local had =
			{ sorter = hasFlag("sorter"), broke = hasFlag("broke"), built_hand_sieve = hasFlag("built_hand_sieve") }
		Tutorial.unmark(player, "sorter")
		Tutorial.placed(player, "belt")
		t.check("Tutorial: placing a belt is not a sorter", not hasFlag("sorter"))
		Tutorial.placed(player, "hand_sieve")
		t.check("Tutorial: placing a hand sieve marks sorter", hasFlag("sorter"))
		t.check("Tutorial: placing a hand sieve counts it for the goal bar", hasFlag("built_hand_sieve"))
		-- The real shovel path: a bale on this suite's pad, cut open as this player.
		local Bales = require(Services.Bales)
		Tutorial.unmark(player, "broke")
		local bale = Bales.spawn(t.place().Position + Vector3.new(0, 2, 0), nil, false, nil)
		t.cleanup(bale.body)
		Bales.breakOpen(player, bale)
		t.check("Tutorial: breaking a bale marks broke", hasFlag("broke"))
		-- Collection book: the event bus fills the needle and hay pages (steel and meadow are the starter ones, so
		-- marking them changes nothing a player would notice).
		local Events = require(Services.Events)
		Events.fire(player, "needle_found", 1, { needleId = "steel" })
		Events.fire(player, "bale_broken", 1, { hayType = "meadow" })
		task.wait(0.2)
		t.check(
			"Codex: a found steel needle fills its page",
			string.find(player:GetAttribute("CodexNeedles") or "", "steel", 1, true) ~= nil
		)
		t.check(
			"Codex: a broken meadow bale fills its page",
			string.find(player:GetAttribute("CodexHay") or "", "meadow", 1, true) ~= nil
		)

		for flag, was in had do
			if not was then
				Tutorial.unmark(player, flag)
			end
		end
	end)
end
