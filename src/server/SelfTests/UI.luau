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
			t.equal("first goal", goal(), "Work Gloves")
			t.equal("Work Gloves price", Catalog.nextGoal().price, Prices.Gloves.work)
			who.attrs.GlovesOwned = "bare,work"
			t.equal("after Work Gloves", goal(), "the Rusty Pickup")
			t.equal("pickup price", Catalog.nextGoal().price, Prices.Trucks.rusty_pickup)
			who.attrs.OwnedTrucks = "rusty_pickup"
			t.equal("after the pickup", goal(), "your first plot")
			t.equal("plot price", Catalog.nextGoal().price, Prices.Plot)
			who.attrs.LandPlot = 2
			t.equal("after the plot", goal(), "a Hand Sieve")
			who.attrs.TutorialFlags = "broke,sold,sorter"
			t.equal("after a sieve", goal(), "Leather Gloves")
			who.attrs.GlovesOwned = "bare,work,leather,reinforced,iron,starlight"
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
			for _, row in Catalog.items("Robux") do
				t.check(("Robux item %s is not for sale yet"):format(row.id), row.state == "soon")
			end
		end)
		Catalog.who = saved
		t.check("goal ladder and shop ran", ok, if ok then nil else tostring(err))

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
		local had = { sorter = hasFlag("sorter"), broke = hasFlag("broke") }
		Tutorial.unmark(player, "sorter")
		Tutorial.placed(player, "belt")
		t.check("Tutorial: placing a belt is not a sorter", not hasFlag("sorter"))
		Tutorial.placed(player, "hand_sieve")
		t.check("Tutorial: placing a hand sieve marks sorter", hasFlag("sorter"))
		-- The real shovel path: a bale on this suite's pad, cut open as this player.
		local Bales = require(Services.Bales)
		Tutorial.unmark(player, "broke")
		local bale = Bales.spawn(t.place().Position + Vector3.new(0, 2, 0), nil, false, nil)
		t.cleanup(bale.body)
		Bales.breakOpen(player, bale)
		t.check("Tutorial: breaking a bale marks broke", hasFlag("broke"))
		for flag, was in had do
			if not was then
				Tutorial.unmark(player, flag)
			end
		end
	end)
end
