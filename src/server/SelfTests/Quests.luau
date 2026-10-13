--!nonstrict
-- Quests and rituals: the config hangs together, every quest place is built and on dry ground, the clock runs, and
-- (with a player in a loaded save) a quest and a ritual play through in Quests.sandbox, which never touches the
-- player's real save, cash, gear or needles. Last, the real quest progress survives the DataStore's JSON.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local Services = script.Parent.Parent.Services
local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestConfig = require(Shared.Config.Quests)
local LandConfig = require(Shared.Config.Land)
local MapConfig = require(Shared.Config.WorldMap)
local Quests = require(Services.Quests)
local Events = require(Services.Events)
local Data = require(Services.Data)

local function spotIdsOf(step)
	return step.spots or (step.spot and { step.spot }) or {}
end

local function rewardIds(value)
	if typeof(value) == "table" then
		return value
	end
	return value and { value } or {}
end

return function(SelfTest)
	SelfTest.register("Quests", function(t)
		-- The config: every spot, reward and required quest a quest names exists.
		local ids, bad = {}, {}
		for _, def in QuestConfig.List do
			ids[def.id] = true
		end
		for _, def in QuestConfig.List do
			for _, need in def.requires or {} do
				if not ids[need] then
					table.insert(bad, def.id .. " requires " .. need)
				end
			end
			for _, step in def.steps do
				for _, id in spotIdsOf(step) do
					if not QuestConfig.Spots[id] then
						table.insert(bad, def.id .. " step spot " .. id)
					end
				end
			end
			for _, key in { "gear", "gloves", "truck", "relic", "unlock" } do
				for _, id in rewardIds((def.reward or {})[key]) do
					if not QuestConfig.Rewards[id] then
						table.insert(bad, def.id .. " reward " .. id)
					end
				end
			end
		end
		t.check(("%d quests name only real spots, rewards and quests"):format(#QuestConfig.List), #bad == 0, table.concat(bad, "; "))

		-- Quest-only land pieces are exactly the ids a quest unlocks, and cost nothing.
		local unlocks = {}
		for _, def in QuestConfig.List do
			for _, id in rewardIds((def.reward or {}).unlock) do
				unlocks[id] = true
			end
		end
		local pieceBad = {}
		for _, piece in LandConfig.Pieces do
			if piece.quest and (not unlocks[piece.id] or piece.price ~= 0) then
				table.insert(pieceBad, piece.id)
			end
		end
		t.check("quest land pieces are unlocked by a quest and free", #pieceBad == 0, table.concat(pieceBad, ", "))
		t.check("the alien offering unlocks the Alien Collector and Starbeam Collector", unlocks.alien_collector and unlocks.starbeam_collector)

		-- Every quest place is built, tagged, and above the sea.
		local missing, wet = {}, {}
		for id, def in QuestConfig.Spots do
			local spot = Quests.spot(id)
			local built = spot and spot.model and spot.model.Parent and spot.base
			if not built and (def.pos or def.fallback or def.world or def.wander) then
				table.insert(missing, id)
			elseif built and spot.base.Position.Y < MapConfig.SeaLevel then
				table.insert(wet, ("%s (y %.0f)"):format(id, spot.base.Position.Y))
			end
		end
		t.check("every quest place is built", #missing == 0, table.concat(missing, ", "))
		t.check("no quest place is under the sea", #wet == 0, table.concat(wet, ", "))

		local remotes = ReplicatedStorage:FindFirstChild("Quests")
		t.check(
			"quest remotes exist",
			remotes and remotes:FindFirstChild("Get") and remotes:FindFirstChild("Action") and remotes:FindFirstChild("Changed")
		)

		-- The clock runs (a game day is Config/Quests Time.DayMinutes real minutes).
		local before = Lighting.ClockTime
		t.wait(1.5)
		local moved = (Lighting.ClockTime - before) % 24
		t.check("the day and night clock moves", moved > 0 and moved < 1, ("%.3f game hours in 1.5 s"):format(moved))

		local player = t.player(10)
		if not player or not Data.get(player) then
			t.skip("quest and ritual play-through", "needs a player with a save slot picked")
			t.skip("quest progress survives a save", "needs a player with a save slot picked")
			return
		end
		local cashBefore = Data.get(player).cash
		local savedClock = Lighting.ClockTime

		local ok, err = Quests.sandbox(player, function(q, pocket)
			-- Accept: a fresh save starts the first quest on its own.
			t.check("a fresh save has First Haul active", q.active.first_haul ~= nil)

			-- Progress and complete: skip the lift step, then sell, break and pick up through the event bus.
			q.active.first_haul = { step = 2, n = 0, seen = {} }
			Events.fire(player, "bale_sold", 1, { hayType = "meadow" })
			t.wait(0.3)
			t.equal("selling a bale moves First Haul on", q.active.first_haul and q.active.first_haul.step, 3)
			Events.fire(player, "bale_broken", 1, { position = Vector3.new(0, -500, 0), hayType = "meadow" })
			t.wait(0.3)
			Events.fire(player, "needle_found", 1, {})
			t.wait(0.3)
			t.check("First Haul completes", q.done.first_haul == true)
			t.check("finishing First Haul starts Get a Grip", q.active.get_a_grip ~= nil)

			-- A ritual: the Midnight Needle refuses at noon and takes the needles at midnight.
			q.active.midnight_needle = { step = 1, n = 0, seen = {} }
			pocket.steel = 10
			Lighting.ClockTime = 12
			Quests.press(player, "old_well")
			t.check("the well refuses at noon", q.active.midnight_needle ~= nil and pocket.steel == 10)
			Lighting.ClockTime = 23.5
			Quests.press(player, "old_well")
			t.check("the well takes 10 steel needles at midnight", q.done.midnight_needle == true and pocket.steel == 0)
			t.check("the ritual gives the Lucky Thimble", q.earned.lucky_thimble == true)

			-- The alien offering grants exactly the land pieces' reward ids.
			q.active.alien_offering = { step = 1, n = 0, seen = {} }
			local def
			for _, d in QuestConfig.List do
				if d.id == "alien_offering" then
					def = d
				end
			end
			local each = def.steps[1].needlesEach
			for _, n in require(Shared.Config.Needles) do
				pocket[n.id] = each
			end
			Quests.press(player, "crop_circle")
			t.check("the alien offering completes", q.done.alien_offering == true)
			t.check(
				"the offering earns alien_collector and starbeam_collector",
				q.earned.alien_collector == true and q.earned.starbeam_collector == true
			)
		end)
		Lighting.ClockTime = savedClock
		t.check("the sandbox ran without errors", ok, not ok and tostring(err) or nil)
		t.equal("the sandbox left the player's cash alone", Data.get(player).cash, cashBefore)

		-- The real quest progress survives the DataStore's JSON (string keys only, no mixed tables).
		local real = Data.get(player).quests
		local okJson, decoded = pcall(function()
			return HttpService:JSONDecode(HttpService:JSONEncode(real or {}))
		end)
		local same = okJson
		if okJson and real then
			for _, field in { "done", "earned" } do
				for id, v in real[field] or {} do
					if (decoded[field] or {})[id] ~= v then
						same = false
					end
				end
			end
			for id, entry in real.active or {} do
				if not (decoded.active and decoded.active[id] and decoded.active[id].step == entry.step) then
					same = false
				end
			end
		end
		t.check("quest progress survives a save", same, not okJson and tostring(decoded) or nil)
	end)
end
