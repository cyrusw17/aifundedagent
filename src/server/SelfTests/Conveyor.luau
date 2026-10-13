--!nonstrict
-- Conveyor thread's suite: builds a throwaway line on the test pad (belt, two sorters in a row, a needle bin and a
-- hay buyer), runs three bales through it and checks that each is sorted once, the second sorter lets sorted hay pass,
-- the buyer leaves hay alone when its owner isn't here, and every part the line made is gone afterwards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent.Parent.Services
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Factory = require(Shared.Config.Factory)
local LineMath = require(Shared.LineMath)

local T2 = Factory.TileSize
local GHOST = -7357 -- an owner who is never in the game

return function(SelfTest)
	SelfTest.register("Conveyor", function(t)
		local Conveyors = require(Services.Conveyors)
		local Machines = require(Services.Machines)
		local Bales = require(Services.Bales)
		local Needle = require(Services.Needle)

		-- Pure line math (the same checks as tests/line_math.luau, run in the engine).
		t.equal("keyOf mutated polished", Needle.keyOf("steel", 12, true), "steel*12!")
		local id, mult, polished = Needle.parseKey("cosmic*3!")
		t.check("parseKey round trip", id == "cosmic" and mult == 3 and polished == true, ("%s %s %s"):format(id, mult, tostring(polished)))
		local whole, rest = LineMath.bundles(23, 10)
		t.check("23 needles pack as 2 bundles + 3", whole == 2 and rest == 3)
		t.near("optical sorter takes 2 s a bale", Machines.sortSeconds("optical_sorter", 90), 2, 0.01)

		-- Line blueprints keep good copies and refuse bad ones.
		local Blueprints = require(Services.Blueprints)
		t.check("a copied line is a valid preset", Blueprints._clean({ { id = "belt", dx = 0, dz = 0, dir = "E" }, { id = "hand_sieve", dx = 1, dz = 0, dir = "E" } }) ~= nil)
		t.check("a preset with an unknown piece is refused", Blueprints._clean({ { id = "gold_throne", dx = 0, dz = 0, dir = "E" } }) == nil)

		-- The line, flowing east: belt cells 0..7, sorter A over 1-2, sorter B over 4-5, buyer at 8, bin beside A.
		local box = t.center * CFrame.new(0, 20, 0)
		local boxSize = Vector3.new(190, 40, 190)
		local function partsHere()
			local n = 0
			for _, p in Workspace:GetPartBoundsInBox(box, boxSize) do
				if p.Name ~= "SelfTestPad" then
					n += 1
				end
			end
			return n
		end
		local baseline = partsHere()

		local folder = t.cleanup(Instance.new("Folder"))
		folder.Name = "ConveyorSelfTest"
		folder.Parent = Workspace
		local spot = t.place()
		local grid = Conveyors.newGrid(folder, spot.Position)
		Conveyors.run(grid, 0, 0, "E", 8)
		Conveyors.finish(grid)
		local bin = Machines.needleBin(folder, Conveyors.frame(grid, 1, -2, "E"))
		local function payTo()
			return GHOST
		end
		local a = Machines.sorter(folder, Conveyors.frame(grid, 1, 0, "E"), "optical_sorter", bin, payTo)
		local b = Machines.sorter(folder, Conveyors.frame(grid, 4, 0, "E"), "optical_sorter", bin, payTo)
		Machines.hayBuyer(folder, Conveyors.frame(grid, 8, 0, "E"), "TEST BUYER", payTo)

		local bales = {}
		for i = 1, 3 do
			local bale = Bales.spawn(Conveyors.cellCenter(grid, 0, 0) + Vector3.new(0, Factory.BeltTop + 2, 0), false, false, "meadow")
			bale.ownerId = GHOST
			bale.body.Anchored = false
			table.insert(bales, bale)
			t.wait(3)
		end

		-- Three bales through two optical sorters (optical so the suite fits the 120 s limit; a hand sieve takes 30 s a bale) and on to the buyer.
		local deadline = os.clock() + 40
		while os.clock() < deadline and (a:GetAttribute("Sorted") or 0) < 3 do
			t.wait(0.5)
		end
		t.wait(12)
		t.equal("first sorter sorted all 3 bales", a:GetAttribute("Sorted") or 0, 3)
		t.equal("second sorter sorted nothing twice", b:GetAttribute("Sorted") or 0, 0)

		-- Both sorted bales should have passed B and be waiting in the buyer, unpaid, because their owner is away.
		local atBuyer = 0
		local buyerAt = Conveyors.cellCenter(grid, 8, 0)
		for _, p in Workspace:GetPartBoundsInBox(CFrame.new(buyerAt + Vector3.new(0, 4, 0)), Vector3.new(8, 10, 8)) do
			local found = Bales.fromPart(p)
			if found and found.sorted and p == found.body and not found.gone then
				atBuyer += 1
			end
		end
		t.equal("sorted bales wait in the buyer while the owner is away", atBuyer, 3)

		local inBin = 0
		for _, n in bin.contents(GHOST) do
			inBin += n
		end
		t.check("bin counts its needles", inBin >= 0 and inBin <= 3 * 20, ("%d needles"):format(inBin))

		-- Needles thrown at the bin land in it and count (mid-throw too), and the SELL NEEDLES pad pays for them.
		bin.add(Conveyors.cellCenter(grid, 1, 0) + Vector3.new(0, 8, 0), GHOST - 1, 4, "steel")
		local function total(ownerId)
			local n = 0
			for _, c in bin.contents(ownerId) do
				n += c
			end
			return n
		end
		t.equal("needles in the air already count for saves", total(GHOST - 1), 4)
		t.wait(3)
		t.equal("4 thrown needles landed in the bin", total(GHOST - 1), 4)
		local player = t.player(2)
		if player and require(Services.Data).get(player) then
			bin.add(Conveyors.cellCenter(grid, 1, 0) + Vector3.new(0, 8, 0), player.UserId, 2, "steel")
			t.wait(3)
			bin.sell(player)
			t.equal("SELL NEEDLES takes the seller's needles", total(player.UserId), 0)
			t.equal("and leaves everyone else's", total(GHOST - 1), 4)
		else
			t.skip("SELL NEEDLES pays", "needs a player with a loaded save")
		end

		-- The hay baler packs 90 loose strands of one owner into one bale.
		local Baler = require(Services.Baler)
		local Hay = require(Services.Hay)
		local Config = require(Shared.Config.Game)
		local grid2 = Conveyors.newGrid(folder, t.place().Position)
		Conveyors.run(grid2, 0, 0, "E", 4)
		Conveyors.finish(grid2)
		local baler = Baler.build(folder, Conveyors.frame(grid2, 1, 0, "E"))
		local drop = Conveyors.cellCenter(grid2, 1, 0) + Vector3.new(0, Factory.BeltTop + 1.5, 0)
		for i = 1, Config.PiecesPerBale do
			Hay.spawnPiece(drop + Vector3.new(((i % 5) - 2) * 0.6, (i // 30) * 0.4, 0), Vector3.zero, GHOST, nil, "meadow")
			if i % 30 == 0 then
				t.wait(0.3)
			end
		end
		local balerDeadline = os.clock() + 10
		while os.clock() < balerDeadline and (baler:GetAttribute("Baled") or 0) < 1 do
			t.wait(0.25)
		end
		t.equal("baler packs 90 strands into one bale", baler:GetAttribute("Baled") or 0, 1)
		t.wait(1)
		local madeBale = false
		for _, p in Workspace:GetPartBoundsInBox(CFrame.new(Conveyors.cellCenter(grid2, 3, 0) + Vector3.new(0, 4, 0)), Vector3.new(T2 * 3, 10, T2 * 2)) do
			local found = Bales.fromPart(p)
			if found and found.ownerId == GHOST and not found.sorted then
				madeBale = true
			end
		end
		t.check("the baled bale rides out, owned by the strands' owner", madeBale)

		-- Region hay: Frozen hay is refused by a sorter until a thawing shed has thawed it.
		local Treat = require(Services.Treat)
		local thawLine = Conveyors.newGrid(folder, t.place().Position)
		Conveyors.run(thawLine, 0, 0, "E", 7)
		Conveyors.finish(thawLine)
		Treat.build(folder, Conveyors.frame(thawLine, 1, 0, "E"), "thawing_shed")
		local thawSorter = Machines.sorter(folder, Conveyors.frame(thawLine, 4, 0, "E"), "optical_sorter", nil, payTo)
		local frozenLine = Conveyors.newGrid(folder, t.place().Position)
		Conveyors.run(frozenLine, 0, 0, "E", 4)
		Conveyors.finish(frozenLine)
		local frozenSorter = Machines.sorter(folder, Conveyors.frame(frozenLine, 1, 0, "E"), "optical_sorter", nil, payTo)
		for _, line in { thawLine, frozenLine } do
			local bale = Bales.spawn(Conveyors.cellCenter(line, 0, 0) + Vector3.new(0, Factory.BeltTop + 2, 0), false, false, "snow")
			bale.ownerId = GHOST
			bale.body.Anchored = false
			table.insert(bales, bale)
		end
		local thawDeadline = os.clock() + 15
		while os.clock() < thawDeadline and (thawSorter:GetAttribute("Sorted") or 0) < 1 do
			t.wait(0.25)
		end
		t.equal("thawed Frozen hay gets sorted", thawSorter:GetAttribute("Sorted") or 0, 1)
		t.equal("Frozen hay that skipped the shed rides through unsorted", frozenSorter:GetAttribute("Sorted") or 0, 0)

		-- A plot loading dock leaves the belt in front of it open at the back and slides a load onto it.
		local Dock = require(Services.Dock)
		local dockLine = Conveyors.newGrid(folder, t.place().Position)
		local dockFrame = Conveyors.frame(dockLine, 1, 0, "E")
		local plotDock = Dock.plotDock(folder, dockFrame, Machines.Colors.pad, Machines.stepPad)
		Conveyors.setFeeder(dockLine, 1, 0, Conveyors.Dirs.E)
		Conveyors.run(dockLine, 2, 0, "E", 3)
		Conveyors.finish(dockLine)
		local rails = 0
		for _, child in Conveyors.tileAt(dockLine, 2, 0).model:GetChildren() do
			if child.Name == "Rail" then
				rails += 1
			end
		end
		t.equal("the belt in front of a dock has no back rail", rails, 2)
		t.check("plot dock built", plotDock.Parent ~= nil)

		-- Tear down and check nothing is left behind.
		for _, p in Workspace:GetPartBoundsInBox(box, boxSize) do
			local found = Bales.fromPart(p)
			if found and not found.gone then
				Bales.consume(found)
			elseif Hay.isPiece(p) and p.Parent then
				Hay.remove(p)
			end
		end
		for _, bale in bales do
			if not bale.gone then
				Bales.consume(bale)
			end
		end
		bin.clear()
		folder:Destroy()
		t.wait(3)
		t.equal("part count back to where it started", partsHere(), baseline)
	end)

	-- Load test (CEO #17): an optical line fed a bale every 2 s (30 bales a minute) for 60 s with the whole map
	-- loaded. Reports the server heartbeat and the Workspace part count, and fails below 45 Hz.
	SelfTest.register("ConveyorLoad", function(t)
		local RunService = game:GetService("RunService")
		local Conveyors = require(Services.Conveyors)
		local Machines = require(Services.Machines)
		local Bales = require(Services.Bales)

		local folder = t.cleanup(Instance.new("Folder"))
		folder.Name = "ConveyorLoadTest"
		folder.Parent = Workspace
		local grid = Conveyors.newGrid(folder, t.place().Position)
		Conveyors.run(grid, 0, 0, "E", 6)
		Conveyors.finish(grid)
		local bin = Machines.needleBin(folder, Conveyors.frame(grid, 1, -2, "E"))
		local sorter = Machines.sorter(folder, Conveyors.frame(grid, 1, 0, "E"), "optical_sorter", bin, function()
			return GHOST
		end)
		local sink = CFrame.new(Conveyors.cellCenter(grid, 6, 0) + Vector3.new(0, 4, 0)) -- just past the end of the belt

		local function countParts()
			local n = 0
			for _, d in Workspace:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			return n
		end

		local frames, worstHz, totalFrames = 0, math.huge, 0
		local beat = RunService.Heartbeat:Connect(function()
			frames += 1
		end)
		local startParts = countParts()
		local peakParts = startParts
		local started = os.clock()
		local nextBale, nextSecond, nextCount = started, started + 1, started + 5
		local fed = 0
		while os.clock() - started < 60 do
			local now = os.clock()
			if now >= nextBale then
				nextBale += 2
				local bale = Bales.spawn(Conveyors.cellCenter(grid, 0, 0) + Vector3.new(0, Factory.BeltTop + 2, 0), false, false, "meadow")
				bale.ownerId = GHOST
				bale.body.Anchored = false
				fed += 1
			end
			if now >= nextSecond then
				worstHz = math.min(worstHz, frames / (now - nextSecond + 1))
				totalFrames += frames
				frames = 0
				nextSecond = now + 1
				-- Sorted bales off the end of the line are sold, as a buyer would.
				for _, p in Workspace:GetPartBoundsInBox(sink, Vector3.new(12, 10, 12)) do
					local b = Bales.fromPart(p)
					if b and not b.gone and p == b.body then
						Bales.consume(b)
					end
				end
			end
			if now >= nextCount then
				nextCount = now + 5
				peakParts = math.max(peakParts, countParts())
			end
			task.wait()
		end
		beat:Disconnect()
		local avgHz = totalFrames / (os.clock() - started)
		t.check("optical line keeps up with 30 bales a minute", (sorter:GetAttribute("Sorted") or 0) >= fed - 3, ("fed %d, sorted %d"):format(fed, sorter:GetAttribute("Sorted") or 0))
		t.check("server heartbeat stays at 45 Hz or more", worstHz >= 45, ("worst second %.1f Hz, average %.1f Hz"):format(worstHz, avgHz))
		t.check("parts during the run", true, ("start %d, peak %d (+%d)"):format(startParts, peakParts, peakParts - startParts))

		for _, p in Workspace:GetPartBoundsInBox(t.center * CFrame.new(0, 20, 0), Vector3.new(190, 40, 190)) do
			local b = Bales.fromPart(p)
			if b and not b.gone then
				Bales.consume(b)
			end
		end
		bin.clear()
	end)
end
