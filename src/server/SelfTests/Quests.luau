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
local Regions = require(Services.Regions)
local WorldShape = require(Services.WorldShape)
local CollectionService = game:GetService("CollectionService")

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
		t.check(
			("%d quests name only real spots, rewards and quests"):format(#QuestConfig.List),
			#bad == 0,
			table.concat(bad, "; ")
		)

		-- Steps that send you to a building say which one (so GO works), and every find step has a hint.
		local noWay = {}
		for _, def in QuestConfig.List do
			for i, step in def.steps do
				if (step.kind == "own" and not step.place) or (step.kind == "find" and not step.hint) then
					table.insert(noWay, ("%s step %d"):format(def.id, i))
				end
			end
		end
		t.check("ownership steps have a place and find steps a hint", #noWay == 0, table.concat(noWay, ", "))

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
		t.check(
			"the alien offering unlocks the Alien Collector and Starbeam Collector",
			unlocks.alien_collector and unlocks.starbeam_collector
		)

		-- Every quest place is built, tagged, and above the sea.
		local missing, wet = {}, {}
		for id, def in QuestConfig.Spots do
			local spot = Quests.spot(id)
			local built = spot and spot.model and spot.model.Parent and spot.base
			local expected = def.pos or def.fallback or def.world or def.wander or def.inMaze
			if def.npc then
				for _, model in CollectionService:GetTagged("QuestGiver") do
					expected = expected or model:GetAttribute("QuestGiver") == def.npc
				end
			elseif def.pedestal then
				expected = #CollectionService:GetTagged("MasterNeedlePedestal") > 0
			end
			if not built and (expected or (def.sea and #Regions.fields > 0)) then
				table.insert(missing, id)
			elseif built and spot.base.Position.Y < MapConfig.SeaLevel then
				table.insert(wet, ("%s (y %.0f)"):format(id, spot.base.Position.Y))
			end
		end
		t.check("every quest place is built", #missing == 0, table.concat(missing, ", "))
		t.check("no quest place is under the sea", #wet == 0, table.concat(wet, ", "))

		-- The Corn Night Maze: corn walls, and three keys in different dead ends inside it.
		local maze = Quests.spot("corn_maze")
		local corn = 0
		for _, p in (maze and maze.model and maze.model:GetChildren()) or {} do
			if p.Name == "Corn" then
				corn += 1
			end
		end
		t.check("the corn maze has its walls", corn >= 20, ("%d corn walls"):format(corn))
		local keysOk, keyDetail = maze ~= nil, {}
		for i = 1, 3 do
			local key = Quests.spot("maze_key_" .. i)
			local offset = key and maze and key.position - maze.position
			if not offset or math.abs(offset.X) > 36 or math.abs(offset.Z) > 36 then
				keysOk = false
			end
			table.insert(keyDetail, offset and ("(%.0f, %.0f)"):format(offset.X, offset.Z) or "missing")
		end
		t.check("three corn keys sit inside the maze", keysOk, table.concat(keyDetail, " "))

		-- The Straw Labyrinth: straw walls, a start line and a bell. Every run spot has a start line.
		local function countParts(spot, name)
			local n = 0
			for _, p in (spot and spot.model and spot.model:GetChildren()) or {} do
				if p.Name == name then
					n += 1
				end
			end
			return n
		end
		local lab = Quests.spot("straw_labyrinth")
		t.check(
			"the straw labyrinth has its walls",
			countParts(lab, "StrawWall") >= 20,
			("%d walls"):format(countParts(lab, "StrawWall"))
		)
		for id in QuestConfig.Runs do
			local spot = Quests.spot(id)
			if spot or id ~= "drowned_rows" or #Regions.fields > 0 then
				t.check(id .. " has a start line", spot ~= nil and spot.startAt ~= nil)
			end
		end
		-- The Drowned Rows: pilings standing in real water (only once the world map and its sea exist).
		local rows = Quests.spot("drowned_rows")
		if rows and rows.position then
			local _, floor, water = pcall(WorldShape.column, rows.position.X, rows.position.Z)
			t.check(
				"the drowned rows stand in the sea",
				water ~= nil and floor < water - 6,
				("floor %s, water %s"):format(tostring(floor), tostring(water))
			)
			t.check("the drowned rows' entrance faces the beach (north)", rows.startAt.Z < rows.position.Z)
			t.check(
				"the drowned rows have their pilings",
				countParts(rows, "Piling") >= 15,
				("%d pilings"):format(countParts(rows, "Piling"))
			)
		else
			t.skip("the drowned rows stand in the sea", "the world map is not built")
		end

		-- The Master Needle: twelve different shards in the collection, each a real relic, in the Spindle door's order.
		local shardIds, seenShard, shardBad = {}, {}, {}
		for _, entry in QuestConfig.Collection do
			if string.sub(entry.id, 1, 6) == "shard_" then
				table.insert(shardIds, entry.id)
				if seenShard[entry.id] or not QuestConfig.Rewards[entry.id] then
					table.insert(shardBad, entry.id)
				end
				seenShard[entry.id] = true
			end
		end
		t.equal("the collection holds twelve Master Needle shards", #shardIds, 12)
		t.check("every shard is a distinct relic", #shardBad == 0, table.concat(shardBad, ", "))
		local okDoor, SpindleDoor = pcall(require, Services.SpindleDoor)
		if okDoor then
			local sameOrder = #SpindleDoor.shards == #shardIds
			for i, id in shardIds do
				sameOrder = sameOrder and SpindleDoor.shards[i] == id
			end
			t.check("the Spindle door's sockets follow the collection's shards", sameOrder)
			local slots = {}
			for _, socket in CollectionService:GetTagged("ShardSocket") do
				slots[socket:GetAttribute("Slot") or 0] = true
			end
			local socketCount = 0
			for slot = 1, 12 do
				if slots[slot] then
					socketCount += 1
				end
			end
			if #CollectionService:GetTagged("ShardSocket") > 0 then
				t.equal("the Spindle door has a socket for each shard", socketCount, 12)
			else
				t.skip("the Spindle door has a socket for each shard", "the world map is not built")
			end
		else
			t.skip("the Spindle door's sockets follow the collection's shards", "no SpindleDoor service")
		end

		-- Every bounty board opens the quest log (it gets a prompt the quest system listens to).
		local boardsBad = {}
		for _, board in CollectionService:GetTagged("BountyBoard") do
			if
				board:IsA("BasePart")
				and not (board:GetAttribute("QuestHooked") and board:FindFirstChildWhichIsA("ProximityPrompt", true))
			then
				table.insert(boardsBad, board:GetFullName())
			end
		end
		t.check("every bounty board has a working prompt", #boardsBad == 0, table.concat(boardsBad, ", "))

		local remotes = ReplicatedStorage:FindFirstChild("Quests")
		t.check(
			"quest remotes exist",
			remotes
				and remotes:FindFirstChild("Get")
				and remotes:FindFirstChild("Action")
				and remotes:FindFirstChild("Changed")
		)

		-- The clock runs (a game day is Config/Quests Time.DayMinutes real minutes).
		local before = Lighting.ClockTime
		t.wait(1.5)
		local moved = (Lighting.ClockTime - before) % 24
		t.check("the day and night clock moves", moved > 0 and moved < 1, ("%.3f game hours in 1.5 s"):format(moved))

		local player = t.player(10)
		local state = player and Data.get(player)
		if not state then
			t.skip("quest and ritual play-through", "needs a player with a save slot picked")
			t.skip("quest progress survives a save", "needs a player with a save slot picked")
			return
		end
		local cashBefore = state.cash
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

			-- The Corn Night Maze: the keys can't be taken by day, then three keys and the heart at night.
			q.active.corn_maze = { step = 1, n = 0, seen = {} }
			Lighting.ClockTime = 12
			Quests.press(player, "maze_key_1")
			t.check("corn keys can't be taken by day", (q.active.corn_maze and q.active.corn_maze.n or 0) == 0)
			Lighting.ClockTime = 21
			for i = 1, 3 do
				Quests.press(player, "maze_key_" .. i)
			end
			Quests.press(player, "corn_maze")
			t.check("the corn maze completes at night", q.done.corn_maze == true and q.earned.corn_moon_charm == true)

			-- The Weaver, chapter 1: read the words, the spool only at midnight, wind it home for the Spindle shard.
			q.active.weaver_1 = { step = 1, n = 0, seen = {} }
			Quests.press(player, "weaver_words")
			t.equal("reading the words moves the Weaver on", q.active.weaver_1 and q.active.weaver_1.step, 2)
			Lighting.ClockTime = 12
			Quests.press(player, "weaver_spool")
			t.equal("the spool can't be taken at noon", q.active.weaver_1 and q.active.weaver_1.step, 2)
			Lighting.ClockTime = 23.8
			Quests.press(player, "weaver_spool")
			Quests.press(player, "weaver_words")
			t.check("chapter 1 gives the Spindle shard", q.done.weaver_1 == true and q.earned.shard_spindle == true)
			if okDoor then
				SpindleDoor.refresh()
				t.check("the door counts the new shard", SpindleDoor.count(player) >= 1)
				local slot = table.find(SpindleDoor.shards, "shard_spindle")
				for _, socket in CollectionService:GetTagged("ShardSocket") do
					if socket:GetAttribute("Slot") == slot then
						t.check("the Spindle shard's socket lights up", socket:GetAttribute("Lit") == true)
					end
				end
			end

			-- The Weaver, chapters 2 to 6 and the finale (each where its places are built: the isles, Old Wren, the
			-- Loom Room's pedestal).
			local function chapter(id, fn)
				q.active[id] = { step = 1, n = 0, seen = {} }
				fn(q.active[id])
				t.check(id .. " gives its reward", q.done[id] == true)
			end
			local function built(...)
				for _, spotId in { ... } do
					if not Quests.spot(spotId) then
						return false
					end
				end
				return true
			end
			if built("tailor_note", "shore_glint") then
				chapter("weaver_2", function()
					Quests.press(player, "tailor_note")
					Lighting.ClockTime = 22
					Quests.press(player, "shore_glint")
				end)
			end
			if built("stitched_pine") then
				chapter("weaver_3", function()
					Events.fire(player, "bale_broken", 15, { position = Vector3.new(0, -500, 0), hayType = "pine" })
					t.wait(0.3)
					Lighting.ClockTime = 12
					Quests.press(player, "stitched_pine")
					t.check("the stitched pine waits for dusk", q.active.weaver_3 ~= nil)
					Lighting.ClockTime = 18
					Quests.press(player, "stitched_pine")
				end)
			end
			if built("old_wren", "well_glint") then
				chapter("weaver_4", function()
					Quests.press(player, "old_wren")
					Lighting.ClockTime = 23.8
					Quests.press(player, "well_glint")
				end)
			else
				t.skip("weaver_4 gives its reward", "Old Wren or the hub well is not built")
			end
			if built("sunken_stone") then
				chapter("weaver_5", function(entry)
					entry.step = 2 -- the breathing reed is a rare find; the offer is what is tested here
					pocket.bog = 20
					Lighting.ClockTime = 22
					Quests.press(player, "sunken_stone")
					t.equal("the sunken stone takes 20 bog needles", pocket.bog, 0)
				end)
			end
			if built("keys_glint") then
				chapter("weaver_6", function(entry)
					entry.step = 2 -- the lanterns are touched by walking; the glint is tested here
					Lighting.ClockTime = 18.5
					Quests.press(player, "keys_glint")
				end)
			end
			if built("master_pedestal") then
				chapter("master_needle", function()
					Quests.press(player, "master_pedestal")
				end)
				t.check("the finale gives the Master Needle", q.earned.master_needle == true)
			else
				t.skip("master_needle gives its reward", "the Loom Room's pedestal is not built")
			end

			-- The sandbox keeps its events to itself: nothing else (the codex) hears them.
			local heard = false
			Events.on(function(who)
				if who == player then
					heard = true
				end
			end)
			Events.fire(player, "raked", 1, {})
			t.wait(0.2)
			t.check("sandbox events reach only the quest system", not heard)

			-- Timed mazes: a run moves the labyrinth quest on, a slow one doesn't pass the 45 second step, and the
			-- first finish of the day is recorded (paid outside a sandbox) once.
			q.active.straw_labyrinth = { step = 1, n = 0, seen = {} }
			Quests.run(player, "straw_labyrinth", 70)
			t.equal(
				"a labyrinth run moves the quest to the timed step",
				q.active.straw_labyrinth and q.active.straw_labyrinth.step,
				2
			)
			t.check(
				"the first run today is recorded",
				q.runs and q.runs.straw_labyrinth and q.runs.straw_labyrinth.day == os.time() // 86400
			)
			Quests.run(player, "straw_labyrinth", 60)
			t.check("a 60 second run doesn't pass the 45 second step", q.active.straw_labyrinth ~= nil)
			Quests.run(player, "straw_labyrinth", 30)
			t.check(
				"a 30 second run completes the labyrinth",
				q.done.straw_labyrinth == true and q.earned.straw_crown == true
			)
			t.near("the best time is kept", q.runs.straw_labyrinth.best, 30, 0.01)
			q.active.drowned_rows = { step = 1, n = 0, seen = {} }
			Quests.run(player, "drowned_rows", 80)
			t.check(
				"swimming the rows completes them",
				q.done.drowned_rows == true and q.earned.drowned_compass == true
			)

			-- The daily streak: a finished bounty counts the day once; a gap pauses it; 3 days earns the first rosette.
			local bounty = QuestConfig.Bounties
			local function finishABounty()
				q.bounty = {}
				for _, def in bounty do
					Events.fire(
						player,
						def.event,
						def.count,
						{ position = Vector3.new(0, -500, 0), center = Vector3.zero }
					)
				end
				t.wait(0.3)
			end
			finishABounty()
			local today = os.time() // 86400
			t.check(
				"finishing a bounty counts today for the streak",
				q.streak and q.streak.last == today and q.streak.days == 1
			)
			finishABounty()
			t.equal("a second bounty the same day does not count again", q.streak and q.streak.days, 1)
			q.streak.last = today - 4
			q.streak.days = 2
			finishABounty()
			t.check("after missed days the streak picks up (paused, not reset)", q.streak.days == 3)
			t.check("3 streak days earn the Bronze Rosette", q.earned.streak_rosette_bronze == true)

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
		t.equal("the sandbox left the player's cash alone", state.cash, cashBefore)

		-- The real quest progress survives the DataStore's JSON (string keys only, no mixed tables).
		local real = state.quests
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
