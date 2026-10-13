--!nonstrict
-- Hay tool checks (Finish hay tool interactions). The first part needs no player: bales, strands, hay looks, the
-- rake and the config. The rest uses the first player in the game and puts their position, carried hay and
-- first-bale flag back afterwards: lift, set down, stack, break (the first-bale needle), scoop with the combo, sell
-- at the pad, a pocket needle, and the wheelbarrow. A sale made here is real money in the player's slot.
-- Edge cases: leaving mid-carry, two players after one bale, a bale set down into a truck bed (and a barrow tipped
-- into one), selling with nothing to sell, throwing a bale, carrying two, and a flood of loose hay staying under its caps without leaking.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent.Parent.Services
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared.Config.Game)
local Prices = require(Shared.Config.Prices)
local HayLooks = require(Shared.Config.HayLooks)
local GloveConfig = require(Shared.Config.Gloves)
local FindsConfig = require(Shared.Config.Finds)
local Data = require(Services.Data)
local Avatar = require(Services.Avatar)
local Bales = require(Services.Bales)
local Hay = require(Services.Hay)
local Gloves = require(Services.Gloves)
local ToolGuide = require(game:GetService("ReplicatedStorage").Shared.ToolGuide)
local GloveLooks = require(Services.GloveLooks)
local Finds = require(Services.Finds)
local Wheelbarrow = require(Services.Wheelbarrow)
local Tools = require(Services.Tools)
local Weather = require(Services.Weather)
local Feedback = require(Services.Feedback)
local ToolSkins = require(Services.ToolSkins)
local SkinConfig = require(Shared.Config.ToolSkins)
local Bank = require(Services.Bank)
local Vehicles = require(Services.Vehicles)
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local NeedleModule = Services:FindFirstChild("Needle")
local Needle = NeedleModule and require(NeedleModule)

local BALE = Vector3.new(4.6, 2.6, 3.2)
local KEEP_TEAMMATE = Bales.isTeammate -- the hand-off checks swap it; it is always put back
local DOUBLE_CARRY_TIER = Config.DoubleCarryTier -- the double-carry checks change it; it is always put back

-- Bales made by a test, consumed at the end so Bales' own tables forget them too.
local made = {}
local function bale(at, hayType)
	local b = Bales.spawn(at.Position, false, false, hayType)
	table.insert(made, b)
	return b
end
local function clearBales()
	for _, b in made do
		if not b.gone and not b.carriedBy then
			Bales.consume(b)
		end
	end
	table.clear(made)
end

local function strandsNear(position, radius)
	local list = {}
	for _, p in Hay.near(position, radius, 500) do
		table.insert(list, p)
	end
	return list
end

local function noPlayerChecks(t)
	-- Config sanity.
	for id in GloveConfig.HayTypes do
		t.check(("hay look for %s"):format(id), HayLooks[id] ~= nil)
	end
	for _, def in FindsConfig.Items do
		t.check(("find %s has a reward and odds"):format(def.id), (def.reward or 0) > 0 and def.oneIn >= 1, def.reward)
		t.check(("find %s known to Finds"):format(def.id), Finds.info(def.id) ~= nil)
	end
	t.check("pocket needle share is set", typeof(Prices.HandFoundNeedleShare) == "number")
	t.check("wheelbarrow price is set", (Prices.Wheelbarrow or 0) > 0, Prices.Wheelbarrow)

	-- A bale: canonical size, physics, meadow by default, its hay named in the prompt.
	local spot = t.place()
	local b = bale(spot)
	t.check("bale is the canonical 4.6 x 2.6 x 3.2", (b.body.Size - BALE).Magnitude < 0.01, tostring(b.body.Size))
	t.equal("bale hay type defaults to meadow", b.body:GetAttribute("HayType"), "meadow")
	local prompt = b.body:FindFirstChildOfClass("ProximityPrompt")
	t.check("bale has a Pick up button", prompt ~= nil and prompt.ActionText == "Pick up")

	-- A pine bale looks like pine.
	local pine = bale(t.place(), "pine")
	local c = HayLooks.pine.colors[1]
	t.check(
		"pine bale takes the pine color",
		(Vector3.new(pine.body.Color.R, pine.body.Color.G, pine.body.Color.B) * 255 - Vector3.new(c[1], c[2], c[3])).Magnitude < 2
	)
	t.check("pine bale is named in its prompt", prompt ~= nil and pine.body:FindFirstChildOfClass("ProximityPrompt").ObjectText:find("Pine") ~= nil)

	-- A golden field bale: marked, glinting, named in its button, and rare.
	local gold = bale(t.place())
	Bales.makeGolden(gold, false)
	t.check("a golden bale is marked golden", gold.body:GetAttribute("GoldenField") == true)
	t.check("...glints", gold.body:FindFirstChildOfClass("Sparkles") ~= nil)
	t.check("...and says so in its button", gold.prompt.ObjectText:sub(1, 6) == "Golden", gold.prompt.ObjectText)
	t.check("golden bales are rare and hold more needles", Config.GoldenBaleOneIn >= 50 and Config.GoldenBaleNeedles > 1)

	-- Wet hay: a soaked bale is heavier and darker, spills wet strands, and dries back to exactly how it was.
	local soaked = bale(t.place())
	local dryWeight = Gloves.baleWeight(soaked.body)
	local dryColor = soaked.body.Color
	t.check("a bale soaks", Bales.wet(soaked) and soaked.body:GetAttribute("Wet") == true)
	t.near("a wet bale weighs WetWeightFactor more", Gloves.baleWeight(soaked.body) / dryWeight, Config.WetWeightFactor, 0.01)
	t.check("...and looks darker", soaked.body.Color.R < dryColor.R)
	t.check("...and drips", soaked.body:FindFirstChild("WetDrips") ~= nil)
	t.check("drying it clears the wet", Bales.dry(soaked) and soaked.body:GetAttribute("Wet") == nil)
	t.check("...restores its color", (Vector3.new(soaked.body.Color.R, soaked.body.Color.G, soaked.body.Color.B) - Vector3.new(dryColor.R, dryColor.G, dryColor.B)).Magnitude < 0.01)
	t.check("...and its weight", math.abs(Gloves.baleWeight(soaked.body) - dryWeight) < 0.01)
	t.check("drying a dry bale does nothing", not Bales.dry(soaked))
	-- Rain falls on open sky in a rainy region, never under a roof, and never in clear weather.
	local sky = Vector3.new(0, 150, 0) -- over Meadow Farm, above everything built there
	local keepWeather = Weather.get("meadow")
	Weather.set("meadow", "rain")
	t.check("rain falls on the open meadow", Bales.rainingOn(sky, {}))
	local roof = Instance.new("Part")
	roof.Anchored = true
	roof.Size = Vector3.new(20, 1, 20)
	roof.Position = sky + Vector3.new(0, 10, 0)
	roof.Parent = workspace
	t.cleanup(roof)
	t.check("a roof keeps the rain off", not Bales.rainingOn(sky, {}))
	roof:Destroy()
	Weather.set("meadow", "clear")
	t.check("no rain in clear weather", not Bales.rainingOn(sky, {}))
	Weather.set("meadow", keepWeather)

	-- The glove ladder: every tier up carries faster, takes more of the hay-weight slowdown away, and looks different
	-- on the hands (its own cuff color and material, with or without the Blender mesh).
	local tiers = GloveConfig.Tiers
	local baleLoad = Gloves.baleWeight(gold.body)
	local heavy = Config.PiecesPerBale * Config.HayPerPiece * GloveConfig.HayTypes.sky.weight * GloveConfig.BaleWeightFactor
	for i = 2, #tiers do
		local lo, hi = tiers[i - 1], tiers[i]
		local label = ("%s beats %s"):format(hi.name, lo.name)
		t.check(label .. " at carry speed", (hi.carrySpeed or 0) > (lo.carrySpeed or 0), hi.carrySpeed)
		t.check(label .. " at the hay-weight slowdown", hi.relief > lo.relief, hi.relief)
		local slowLo, slowHi = Gloves.speedFor(lo, 16, baleLoad, 0), Gloves.speedFor(hi, 16, baleLoad, 0)
		t.check(label .. " carrying a meadow bale", slowHi > slowLo, ("%.2f -> %.2f"):format(slowLo, slowHi))
		local heavyLo, heavyHi = Gloves.speedFor(lo, 16, heavy, 5), Gloves.speedFor(hi, 16, heavy, 5)
		-- Both can bottom out at the minimum walk speed with hay this far above them; then neither may be slower.
		local better = heavyHi > heavyLo or (heavyLo <= GloveConfig.MinWalkSpeed and heavyHi >= heavyLo)
		t.check(label .. " carrying a cloud hay bale", better, ("%.2f -> %.2f"):format(heavyLo, heavyHi))
	end
	local dummy = Instance.new("Model")
	dummy.Name = "GloveDummy"
	for _, side in { "Right", "Left" } do
		local hand = Instance.new("Part")
		hand.Name = side .. "Hand"
		hand.Anchored = true
		hand.Size = Vector3.new(0.3, 0.3, 0.3)
		hand.CFrame = t.place() * CFrame.new(side == "Right" and 1 or -1, 3, 0)
		hand.Parent = dummy
	end
	dummy.Parent = workspace
	t.cleanup(dummy)
	local seen = {}
	for _, def in tiers do
		GloveLooks.dress(dummy, def.id)
		local worn = dummy.RightHand:FindFirstChild("WornGlove")
		local wornLeft = dummy.LeftHand:FindFirstChild("WornGlove")
		if def.id == "bare" then
			t.check("bare hands wear nothing", worn == nil and wornLeft == nil)
		else
			local cuff = worn and worn:FindFirstChild("Cuff")
			t.check(("%s show on both hands"):format(def.name), worn ~= nil and wornLeft ~= nil and cuff ~= nil)
			if cuff then
				local key = ("%s/%s"):format(tostring(cuff.Color), cuff.Material.Name)
				t.check(("%s look unlike any lower tier"):format(def.name), not seen[key], key)
				seen[key] = true
				t.check(("%s cuff rides the hand"):format(def.name), not cuff.Anchored and cuff:FindFirstChildOfClass("Weld") ~= nil)
			end
		end
	end
	GloveLooks.dress(dummy, "bare")
	t.check("taking gloves off clears the hands", dummy.RightHand:FindFirstChild("WornGlove") == nil)

	-- Strands take their hay's shape.
	local strand = Hay.spawnPiece(spot.Position + Vector3.new(10, 2, 0), Vector3.zero, 0, nil, "pine")
	t.check("a pine strand is thin like pine straw", strand.Size.Y <= HayLooks.pine.thick[2] + 0.001, strand.Size.Y)
	Hay.remove(strand)

	-- The rake pulls loose strands toward where it gathers them.
	local rakeAt = t.place().Position
	local gather = rakeAt + Vector3.new(0, 0, 3)
	local pieces = {}
	for i = 1, 16 do
		local angle = i / 16 * math.pi * 2
		local p = Hay.spawnPiece(rakeAt + Vector3.new(math.cos(angle) * 4, 0.5, math.sin(angle) * 4), Vector3.zero, 0)
		table.insert(pieces, p)
	end
	t.wait(0.6) -- let them settle on the pad
	local function meanDistance()
		local sum = 0
		for _, p in pieces do
			sum += (Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(gather.X, 0, gather.Z)).Magnitude
		end
		return sum / #pieces
	end
	local before = meanDistance()
	Hay.rake(rakeAt, gather, Config.RakeRadius, 0)
	t.wait(Config.RakeStrokeSeconds + 0.6)
	local after = meanDistance()
	t.check("rake gathers strands toward the player", after < before * 0.8, ("%.1f -> %.1f studs"):format(before, after))
	for _, p in pieces do
		if p.Parent then
			Hay.remove(p)
		end
	end

	-- Raking onto a belt: the strands go up onto the belt (it stands well off the ground), ride it, and no pile forms.
	local beltAt = t.place()
	local belt = Instance.new("Part")
	belt.Name = "Belt"
	belt.Anchored = true
	belt.Size = Vector3.new(30, 1, 3)
	belt.CFrame = beltAt * CFrame.new(8, 3, 0)
	belt.AssemblyLinearVelocity = Vector3.new(6, 0, 0)
	CollectionService:AddTag(belt, "ConveyorBelt")
	belt.Parent = workspace
	t.cleanup(belt)
	local loose = {}
	for i = 1, 16 do
		local angle = i / 16 * math.pi * 2
		table.insert(loose, Hay.spawnPiece(beltAt.Position + Vector3.new(math.cos(angle) * 2.5, 0.5, 6 + math.sin(angle) * 2.5), Vector3.zero, 0))
	end
	t.wait(0.6)
	local found, beltSpot = Hay.beltNear(beltAt.Position + Vector3.new(0, 1, 1.5), Config.RakeBeltReach)
	t.check("a belt in reach is found", found == belt)
	local sent = found and Hay.rakeOntoBelt(beltAt.Position + Vector3.new(0, 0, 6), belt, beltSpot, Config.RakeRadius, 0) or 0
	t.equal("the rake flicks every strand toward the belt", sent, #loose)
	t.wait(0.9)
	local onBelt, startX = 0, 0
	for _, p in loose do
		local localPos = belt.CFrame:PointToObjectSpace(p.Position)
		if p.Parent and math.abs(localPos.Z) <= 2 and localPos.Y > 0 then
			onBelt += 1
			startX += p.Position.X
		end
	end
	t.check("raked strands land on the belt", onBelt >= #loose * 0.75, ("%d of %d"):format(onBelt, #loose))
	t.wait(1)
	local endX, still = 0, 0
	for _, p in loose do
		local localPos = belt.CFrame:PointToObjectSpace(p.Position)
		if p.Parent and math.abs(localPos.Z) <= 2 and localPos.Y > 0 then
			still += 1
			endX += p.Position.X
		end
	end
	t.check("...and ride it along", still > 0 and onBelt > 0 and endX / still - startX / onBelt > 2, ("%.1f studs"):format(still > 0 and onBelt > 0 and endX / still - startX / onBelt or 0))
	local pileMade = false
	for _, p in Hay.near(belt.Position, 20, nil) do
		if Hay.isPile(p) then
			pileMade = true
		end
	end
	t.check("raking onto a belt makes no pile", not pileMade)
	for _, p in loose do
		if p.Parent then
			Hay.remove(p)
		end
	end

	-- Tool juice: the Juice remote exists for the client's hit-stop and shake, and the rake's dust puff appears.
	local juice = ReplicatedStorage:FindFirstChild("Juice")
	t.check("the Juice event is there for hit-stop and shake", juice ~= nil and juice:IsA("RemoteEvent"))
	local dustAt = t.place().Position + Vector3.new(0, 0.5, 0)
	local terrainBefore = #workspace.Terrain:GetChildren()
	Feedback.dust(dustAt)
	local puffed = false
	for _, a in workspace.Terrain:GetChildren() do
		if a:IsA("Attachment") and (a.WorldPosition - dustAt).Magnitude < 0.01 and a:FindFirstChildOfClass("ParticleEmitter") then
			puffed = true
		end
	end
	t.check("a rake stroke kicks up dust", puffed and #workspace.Terrain:GetChildren() > terrainBefore)

	-- Earned tool skins: a page unlocks only when complete, and a skin recolors the tool and comes off cleanly.
	local commonFinds = {}
	for _, id in SkinConfig.CommonFinds do
		commonFinds[id] = 1
	end
	t.check("no skin for an empty book", not ToolSkins.pageDone({ finds = {}, codex = {} }, "finds_common"))
	t.check("the common finds page completes the Driftwood Rake", ToolSkins.pageDone({ finds = commonFinds }, "finds_common"))
	t.check("...but not the whole finds page", not ToolSkins.pageDone({ finds = commonFinds }, "finds"))
	local allHay = {}
	for id in GloveConfig.HayTypes do
		allHay[id] = true
	end
	t.check("every hay type broken completes the hay page", ToolSkins.pageDone({ codex = { hay = allHay } }, "hay"))
	allHay.meadow = nil
	t.check("one missing hay type leaves it open", not ToolSkins.pageDone({ codex = { hay = allHay } }, "hay"))
	local tool = Instance.new("Tool")
	tool.Name = "Shovel"
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Color = Color3.fromRGB(100, 100, 100)
	blade.Material = Enum.Material.Metal
	blade.Parent = tool
	t.cleanup(tool)
	ToolSkins.dress(tool, "golden_shovel")
	t.check("a skin recolors the tool", blade.Color ~= Color3.fromRGB(100, 100, 100) and tool:GetAttribute("Skin") == "golden_shovel")
	t.check("...and the golden one glints", tool:FindFirstChild("SkinGlint", true) ~= nil)
	ToolSkins.dress(tool, nil)
	t.check("taking it off puts the tool's own look back", blade.Color == Color3.fromRGB(100, 100, 100) and blade.Material == Enum.Material.Metal and tool:FindFirstChild("SkinGlint", true) == nil)
	for _, def in SkinConfig.Skins do
		t.check(("%s is cosmetic only (no stats)"):format(def.name), def.speed == nil and def.scoopBonus == nil and def.reach == nil)
	end

	-- A flood of loose hay: far more strands and needles than the caps. The counts stay at the caps, every piece
	-- the module tracks is a real one, spawning stays cheap, and when it is all gone the counts come back down.
	local base = Hay.stats()
	local floodAt = t.place().Position + Vector3.new(0, 3, 0)
	local flood = {}
	local started = os.clock()
	local strandsWanted = Config.MaxLoosePieces + 150
	for i = 1, strandsWanted do
		table.insert(flood, Hay.spawnPiece(floodAt + Vector3.new(i % 20, 0, math.floor(i / 20) % 20), Vector3.zero, 0))
	end
	local perStrand = (os.clock() - started) / strandsWanted * 1000
	started = os.clock()
	for i = 1, Config.MaxLooseNeedles + 30 do
		table.insert(flood, Hay.spawnPiece(floodAt + Vector3.new(i % 20, 1, 0), Vector3.zero, 0, "Needle"))
	end
	local perNeedle = (os.clock() - started) / (Config.MaxLooseNeedles + 30) * 1000
	local stats = Hay.stats()
	t.check("loose strands stay at the cap in a flood", stats.strands <= Config.MaxLoosePieces, stats.strands)
	t.check("loose needles stay at the cap in a flood", stats.needles <= Config.MaxLooseNeedles, stats.needles)
	t.equal("every tracked piece is counted (no leak)", stats.tracked, stats.strands + stats.needles)
	t.check("a strand spawns in under 1 ms at the cap", perStrand < 1, ("%.3f ms"):format(perStrand))
	t.check("a needle spawns in under 2 ms at the cap", perNeedle < 2, ("%.3f ms"):format(perNeedle))
	local alive = 0
	for _, p in flood do
		if p.Parent then
			alive += 1
			p:Destroy() -- destroyed from outside, as a clicked-up needle is: Hay must still forget it
		end
	end
	t.wait(0.1)
	local cleared = Hay.stats()
	t.check("trimmed pieces really left the world", alive <= Config.MaxLoosePieces + Config.MaxLooseNeedles, alive)
	t.equal("destroyed pieces are forgotten (strands)", cleared.strands, base.strands)
	t.equal("destroyed pieces are forgotten (needles)", cleared.needles, base.needles)
	t.equal("destroyed pieces are forgotten (tracked)", cleared.tracked, base.tracked)
	clearBales()
end

-- A stand-in truck bed on the test pad: an anchored floor with its top at 3.5 like the pickup's, in a model carrying
-- the same CargoOffset / CargoSize attributes the real trucks do.
local function truckBed(t, at)
	local model = Instance.new("Model")
	model.Name = "SelfTestTruckBed"
	local floor = Instance.new("Part")
	floor.Name = "Bed"
	floor.Anchored = true
	floor.Size = Vector3.new(10, 1, 14)
	floor.CFrame = at * CFrame.new(0, 3, 0)
	floor.Parent = model
	model.PrimaryPart = floor
	model:SetAttribute("CargoOffset", CFrame.new(0, 2.5, 0))
	model:SetAttribute("CargoSize", Vector3.new(9.6, 4, 13.6))
	model.Parent = workspace
	t.cleanup(model)
	return { model = model, floor = floor, top = floor.Position.Y + 0.5 }
end

local function inBed(bed, b)
	local localPos = bed.floor.CFrame:PointToObjectSpace(b.body.Position)
	return math.abs(localPos.X) <= 5 and math.abs(localPos.Z) <= 7 and b.body.Position.Y > bed.top
end

-- Loose: not anchored and not joined to anything, so it slides and tips like real cargo.
local function isLoose(b)
	if b.body.Anchored or b.body.AssemblyRootPart ~= b.body then
		return false
	end
	for _, j in b.body:GetJoints() do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			return false
		end
	end
	return true
end

-- Two bales stacked in a real pickup's bed ride a drive and a hard stop: they stay in the bed, the top one stays on
-- the bottom one, and neither jitters or flies off (no speed spike against the truck, no fast spin).
local function stackedRide(t)
	local truck = Vehicles.build(Vehicles.get("rusty_pickup"), t.place(), workspace)
	t.cleanup(truck)
	Vehicles.makeDrivable(truck, { Name = "SelfTest", UserId = -1 })
	Vehicles.release(truck, nil)
	t.wait(1.5)
	local chassis = truck.PrimaryPart
	local box, size = Wheelbarrow.cargoOf(chassis)
	if not box then
		t.skip("stacked bales in a moving pickup", "the pickup has no cargo box")
		return
	end
	local bottom = bale(box)
	local top = bale(box)
	local floor = box * CFrame.new(0, -size.Y / 2 + BALE.Y / 2 + 0.05, 0)
	Bales.releaseAt(bottom, floor)
	Bales.releaseAt(top, floor * CFrame.new(0, BALE.Y + 0.05, 0))
	t.wait(1)

	local drive, steer = chassis:FindFirstChild("Drive"), chassis:FindFirstChild("Steer")
	if not drive or not steer then
		t.skip("stacked bales in a moving pickup", "no Drive / Steer on the pickup")
		return
	end
	local heading = (chassis.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	local worstSlip, worstSpin = 0, 0
	local function watch()
		for _, b in { bottom, top } do
			local slip = (b.body.AssemblyLinearVelocity - chassis:GetVelocityAtPosition(b.body.Position)).Magnitude
			worstSlip = math.max(worstSlip, slip)
			worstSpin = math.max(worstSpin, (b.body.AssemblyAngularVelocity - chassis.AssemblyAngularVelocity).Magnitude)
		end
	end
	local speed = 30
	local connection = RunService.Heartbeat:Connect(function()
		steer.CFrame = CFrame.fromMatrix(Vector3.zero, heading:Cross(Vector3.yAxis), Vector3.yAxis, -heading)
		drive.PlaneVelocity = Vector2.new(0, -speed)
		watch()
	end)
	t.wait(3)
	speed = 0 -- a hard stop
	t.wait(1.5)
	connection:Disconnect()
	drive.PlaneVelocity = Vector2.zero

	local function inBox(b)
		local p = (chassis.CFrame * chassis.Parent:GetAttribute("CargoOffset")):PointToObjectSpace(b.body.Position)
		return math.abs(p.X) <= size.X / 2 + 0.5 and math.abs(p.Z) <= size.Z / 2 + 0.5 and p.Y > -size.Y / 2 - 0.5
	end
	t.check("stacked bales stay in the bed through a drive and a hard stop", inBox(bottom) and inBox(top))
	t.near("the top bale stays on the bottom one", top.body.Position.Y - bottom.body.Position.Y, BALE.Y, 0.7)
	-- A hard stop can slide a bale forward at up to the truck's speed; an explosion or jitter flings it far faster.
	t.check("neither bale jitters or flies off (slip vs the bed)", worstSlip < 30 + 15, ("worst %.1f studs/s"):format(worstSlip))
	t.check("neither bale spins out", worstSpin < 8, ("worst %.1f rad/s"):format(worstSpin))
	t.check("both bales are still loose (never welded)", isLoose(bottom) and isLoose(top))
end

local function edgeCases(t, player, state, root, stand)
	local spot = t.place()

	-- Two players after one bale: whoever holds it first keeps it; nobody else can lift, barrow or break it.
	stand(spot)
	local contested = bale(spot * CFrame.new(0, 0, -4))
	t.wait(0.2)
	local other = { Name = "SelfTestOther", UserId = -1 } -- stands in for a second player already holding it
	contested.carriedBy = other
	Bales.pickup(player, contested)
	t.check("a bale someone else holds can't be lifted", state.carryBale ~= contested and contested.carriedBy == other)
	Bales.breakOpen(player, contested)
	t.check("...or broken open", not contested.breaking and not contested.gone)
	contested.carriedBy = nil
	Bales.pickup(player, contested)
	t.check("once free, the first to grab it holds it", state.carryBale == contested)
	t.check("...and a second grab is refused", not Bales.stow(player, contested, root, CFrame.new()))
	Bales.drop(player)

	-- Leaving the game mid-carry: the held bale goes away and nothing stays stuck to the player.
	local leaving = bale(spot * CFrame.new(0, 0, -4))
	t.wait(0.2)
	Bales.pickup(player, leaving)
	local held = state.carryBale == leaving
	Bales.playerLeft(player)
	t.check("leaving mid-carry removes the carried bale", held and leaving.gone and leaving.body.Parent == nil)
	t.check("...and frees the hands", state.carryBale == nil)
	Avatar.clearCarry(player)

	-- Set a bale down into a truck bed: it lands on the bed floor, loose, never welded to the truck.
	local bedSpot = t.place()
	local bed = truckBed(t, bedSpot)
	local cargo = bale(spot * CFrame.new(10, 0, -4))
	stand(spot * CFrame.new(10, 0, 0))
	Bales.pickup(player, cargo)
	-- Two studs off the bed's back end, facing in; the set-down spot lands about 4 studs ahead, inside the bed.
	stand(bedSpot * CFrame.new(0, 0, 9))
	Bales.drop(player)
	t.wait(1)
	t.near("a bale set down into a truck bed rests on the bed floor", cargo.body.Position.Y - bed.top, BALE.Y / 2, 0.6)
	t.check("...inside the bed", inBed(bed, cargo))
	t.check("...loose, never welded", isLoose(cargo))

	-- Pour: hay in your arms goes into a truck bed as loose strands; sorted hay stays sorted, and the needles rolled
	-- for it come back out of your load with it. The ground is never a pour target.
	local pourBed = truckBed(t, t.place())
	stand(pourBed.model.PrimaryPart.CFrame * CFrame.new(0, -3, 9))
	t.check("a truck bed in reach is a pour target", Tools.pourTarget({ part = pourBed.floor, position = pourBed.floor.Position }, root) ~= nil)
	t.check("the plain ground is not", Tools.pourTarget({ part = workspace.Terrain, position = root.Position }, root) == nil)
	-- A bed across the map is never a target, even if the click claims a spot right beside you.
	local farBed = truckBed(t, t.place())
	farBed.model:PivotTo(farBed.model:GetPivot() + Vector3.new(0, 0, 150))
	t.check("a truck bed out of reach is not a pour target", Tools.pourTarget({ part = farBed.floor, position = root.Position }, root) == nil)
	local farBelt = Instance.new("Part")
	farBelt.Anchored = true
	farBelt.Size = Vector3.new(6, 1, 3)
	farBelt.CFrame = root.CFrame + Vector3.new(0, 0, 150)
	CollectionService:AddTag(farBelt, "ConveyorBelt")
	farBelt.Parent = workspace
	t.cleanup(farBelt)
	t.check("a far belt named with a spot beside you is refused", Tools.pourTarget({ part = farBelt, position = root.Position + Vector3.new(0, 0, -3) }, root) == nil)
	local before = #Hay.near(pourBed.floor.Position, 12, nil)
	state.loadHay, state.loadSortedHay, state.loadNeedles, state.loadType = 30, 10, 4, "meadow"
	state.loadWeight, state.loadTier = 30, 0
	local box, size = Wheelbarrow.cargoOf(pourBed.floor)
	local poured = Tools.pour(player, root, { box = box, size = size })
	t.equal("a pour takes up to PourStrands from your arms", poured, math.min(30, Config.PourStrands))
	t.equal("...and empties them", state.loadHay, 30 - poured * Config.HayPerPiece)
	t.equal("...with the needles rolled for it", state.loadNeedles, 0)
	t.wait(Config.PourFlightSeconds + poured * Config.PourStagger + 1)
	local landed, sorted = 0, 0
	for _, p in Hay.near(pourBed.floor.Position, 12, nil) do
		local localPos = pourBed.floor.CFrame:PointToObjectSpace(p.Position)
		if math.abs(localPos.X) <= 5 and math.abs(localPos.Z) <= 7 and p.Position.Y > pourBed.top - 0.2 then
			landed += 1
			if p:GetAttribute("Sorted") then
				sorted += 1
			end
		end
	end
	t.check("the poured strands land in the bed", landed - before >= poured * 0.85, ("%d of %d"):format(landed - before, poured))
	t.equal("hay scooped from sorted bales pours out sorted", sorted, 10)

	-- Wet strands from a wet bale.
	local soaked = bale(spot * CFrame.new(-12, 0, 6))
	Bales.wet(soaked)
	local wetSpill = soaked.body.Position
	Bales.breakOpen(player, soaked)
	t.wait(1.2)
	local wetStrands, allStrands = 0, 0
	for _, p in strandsNear(wetSpill, 12) do
		if not Hay.isNeedle(p) then
			allStrands += 1
			if p:GetAttribute("Wet") then
				wetStrands += 1
			end
		end
	end
	t.check("a wet bale spills wet strands", allStrands > 0 and wetStrands == allStrands, ("%d of %d"):format(wetStrands, allStrands))
	local wetPiece = strandsNear(wetSpill, 12)[1]
	if wetPiece then
		local wetW = Gloves.pieceWeight(wetPiece)
		wetPiece:SetAttribute("Wet", nil)
		t.near("a wet strand weighs WetWeightFactor more", wetW / Gloves.pieceWeight(wetPiece), Config.WetWeightFactor, 0.01)
	end
	for _, p in strandsNear(wetSpill, 12) do
		Hay.remove(p)
	end

	-- Throw: a full-charge toss lobs the bale about TossRange studs, loose; a tiny charge just sets it down.
	local throwSpot = t.place()
	stand(throwSpot)
	local thrown = bale(throwSpot * CFrame.new(0, 0, -4))
	t.wait(0.2)
	Bales.pickup(player, thrown)
	local from = root.Position
	Bales.toss(player, 1)
	t.check("a throw lets go of the bale", state.carryBale == nil and thrown.carriedBy == nil)
	t.wait(2)
	local flew = (Vector3.new(thrown.body.Position.X, 0, thrown.body.Position.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude
	t.check("a full throw lands well out in front", flew > Config.TossRange * 0.6 and flew < Config.TossRange * 1.6, ("%.1f studs"):format(flew))
	t.check("a thrown bale is loose", isLoose(thrown))
	local tapped = bale(throwSpot * CFrame.new(12, 0, -4))
	stand(throwSpot * CFrame.new(12, 0, 0))
	Bales.pickup(player, tapped)
	Bales.toss(player, Config.TossMinPower / 2)
	t.wait(0.8)
	local near = (Vector3.new(tapped.body.Position.X, 0, tapped.body.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
	t.check("a tiny charge just sets the bale down", near < 5, ("%.1f studs"):format(near))

	-- A finder's reward pays once per kind for good: trading the find away and finding another pays nothing more.
	local keepFinds, keepPaid = table.clone(state.finds or {}), table.clone(state.findsPaid or {})
	state.finds = state.finds or {}
	state.findsPaid = state.findsPaid or {}
	state.finds.boot, state.findsPaid.boot = nil, nil
	local reward = Finds.info("boot").reward
	local cash0 = Bank.wallet(state)
	Finds.keepForTest(player, "boot")
	local paidFirst = Bank.wallet(state) - cash0
	t.equal("the first boot marks its reward paid", state.findsPaid.boot, 1)
	-- A bank loan can take its share of any earning, so the wallet rises by the reward or a little less.
	t.check("the first boot pays its finder's reward", paidFirst > 0 and paidFirst <= reward, ("+$%d of $%d"):format(paidFirst, reward))
	state.finds.boot = nil -- traded away (Trade.luau takes it off the shelf)
	local cash1 = Bank.wallet(state)
	Finds.keepForTest(player, "boot")
	t.equal("finding another after trading it away pays nothing", Bank.wallet(state) - cash1, 0)
	t.equal("...and the reward stays marked paid", state.findsPaid.boot, 1)
	t.equal("...though it is kept", state.finds.boot, 1)
	-- The test's reward is not real money: put the wallet back where it was.
	if Config.InfiniteMoney then
		state.savedCash = cash0
	else
		state.cash = cash0
	end
	Data.sync(player)
	state.finds, state.findsPaid = keepFinds, keepPaid

	-- Crew hand-off: a bale thrown by a teammate that flies close to bare hands is caught; a stranger's is not.
	local catchSpot = t.place()
	stand(catchSpot)
	local keepTeammate = Bales.isTeammate
	local thrower = { Name = "SelfTestThrower", UserId = -2 }
	local function lob(b)
		-- From 8 studs off, arcing in to land at the player's feet.
		Bales.releaseAt(b, CFrame.new(root.Position + Vector3.new(0, 2, 8)))
		local flight = 0.6
		local target = root.Position
		b.body.AssemblyLinearVelocity = (target - b.body.Position - 0.5 * Vector3.new(0, -workspace.Gravity, 0) * flight * flight) / flight
		Bales.watchForCatch(b, thrower)
	end
	Bales.isTeammate = function(fromPlayer, toPlayer)
		return fromPlayer == thrower and toPlayer == player
	end
	local passed = bale(catchSpot * CFrame.new(0, 0, 20))
	lob(passed)
	t.wait(1)
	t.check("a teammate's thrown bale is caught", state.carryBale == passed and passed.carriedBy == player)
	Bales.drop(player)
	Bales.isTeammate = function()
		return false
	end
	stand(catchSpot * CFrame.new(10, 0, 0))
	local stranger = bale(catchSpot * CFrame.new(10, 0, 20))
	lob(stranger)
	t.wait(1)
	t.check("a stranger's thrown bale is not caught", state.carryBale == nil and stranger.carriedBy == nil)
	Bales.isTeammate = keepTeammate

	-- Double carry: two bales with good enough gloves, one without; both go down as a stack of two.
	local carrySpot = t.place()
	stand(carrySpot)
	local a1 = bale(carrySpot * CFrame.new(0, 0, -4))
	local a2 = bale(carrySpot * CFrame.new(3, 0, -4))
	t.wait(0.2)
	Config.DoubleCarryTier = 99 -- gloves can't reach this
	Bales.pickup(player, a1)
	Bales.pickup(player, a2)
	t.check("weak gloves carry one bale only", state.carryBale == a1 and state.carryExtra == nil and a2.carriedBy == nil)
	Config.DoubleCarryTier = 0 -- any gloves
	Bales.pickup(player, a2)
	t.check("good gloves carry a second bale", state.carryExtra == a2 and a2.carriedBy == player)
	local a3 = bale(carrySpot * CFrame.new(-3, 0, -4))
	t.wait(0.2)
	Bales.pickup(player, a3)
	t.check("...but never a third", a3.carriedBy == nil)
	Config.DoubleCarryTier = DOUBLE_CARRY_TIER
	stand(carrySpot * CFrame.new(0, 0, 8))
	Bales.drop(player)
	t.check("putting down frees both hands", state.carryBale == nil and state.carryExtra == nil)
	t.wait(1)
	t.near("the second bale lands on top of the first", a2.body.Position.Y - a1.body.Position.Y, BALE.Y, 0.6)
end

local function withPlayer(t, player)
	local state = Data.get(player)
	local root = Avatar.getRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not state or not root or not humanoid then
		t.skip("player checks", "the player has not picked a save slot or has no character yet")
		return
	end
	local home = root.CFrame
	local keepHay, keepNeedles, keepWeight, keepTier = state.loadHay, state.loadNeedles, state.loadWeight, state.loadTier
	local keepSorted, keepType = state.loadSortedHay, state.loadType
	local keepFirst = Gloves.firstBaleBroken(player)
	local ok, err = pcall(function()
		humanoid:UnequipTools()
		local spot = t.place()
		-- Stand on the pad facing -Z, with a bale 4 studs in front.
		local function stand(at)
			root.CFrame = CFrame.lookAt(at.Position + Vector3.new(0, 3, 0), at.Position + Vector3.new(0, 3, -10))
			root.AssemblyLinearVelocity = Vector3.zero
			t.wait(0.3)
		end
		stand(spot)
		local first = bale(spot * CFrame.new(0, 0, -4))
		t.wait(0.2)

		-- Lift and set down.
		Bales.pickup(player, first)
		t.check("bare hands lift a bale", state.carryBale == first and first.carriedBy == player)
		t.check("carrying a bale slows you", humanoid.WalkSpeed < 16, humanoid.WalkSpeed)
		Bales.drop(player)
		t.check("the bale sets down", state.carryBale == nil and first.carriedBy == nil)
		t.wait(0.8)
		t.near("it rests on the ground", first.body.Position.Y - spot.Position.Y, BALE.Y / 2, 0.6)

		-- Stack: set a second bale down onto the first.
		local second = bale(spot * CFrame.new(8, 0, 0))
		stand(spot * CFrame.new(8, 0, 4))
		Bales.pickup(player, second)
		stand(spot)
		Bales.drop(player)
		t.wait(1)
		t.near("a set-down bale stacks on the one in front", second.body.Position.Y - first.body.Position.Y, BALE.Y, 0.6)

		-- Break with the shovel: the first bale ever always spills a needle.
		Gloves.setFirstBaleBroken(player, false)
		local third = bale(spot * CFrame.new(-10, 0, -4))
		Bales.breakOpen(player, third)
		t.wait(1.6)
		local burst = (spot * CFrame.new(-10, 0, -4)).Position
		local strands, needles, parts = 0, 0, 0
		for _, p in strandsNear(burst, 14) do
			if Hay.isNeedle(p) then
				needles += 1
			elseif not Hay.isPile(p) then
				strands += Hay.strandsIn(p)
				parts += 1
			end
		end
		t.check("a broken bale spills strands", strands >= Config.PiecesPerBale * 0.8, strands)
		-- Part budget (Hay #24): the strands come out in clumps, a third of the parts for the same hay.
		local perClump = Config.StrandsPerClump or 1
		t.check("a broken bale spills clumps, not single strands", parts <= math.ceil(Config.PiecesPerBale / perClump), parts)
		t.check("the first bale broken spills a needle", needles >= 1, needles)
		t.check("breaking it used up the first-bale promise", Gloves.firstBaleBroken(player))

		-- Scoop three times quickly: each scoop picks up hay and the third is bigger (the combo).
		local shovel = player.Backpack:FindFirstChild("Shovel") or character:FindFirstChild("Shovel")
		-- Hotbar tooltips come from the configs (ToolGuide, Hay #25), so they never drift from the real numbers.
		local rake = player.Backpack:FindFirstChild("Rake") or character:FindFirstChild("Rake")
		if shovel and rake then
			t.equal("the shovel's tooltip is ToolGuide's", shovel.ToolTip, ToolGuide.tool("Shovel"))
			t.equal("the rake's tooltip is ToolGuide's", rake.ToolTip, ToolGuide.tool("Rake"))
		end
		if shovel and Avatar.onToolActivated then
			humanoid:EquipTool(shovel)
			stand(CFrame.new(burst) * CFrame.new(0, 0, 3))
			state.loadHay, state.loadWeight, state.loadTier = 0, 0, 0
			local gains = {}
			for i = 1, 3 do
				local had = state.loadHay
				Avatar.onToolActivated(player, "Shovel")
				t.wait(Config.ScoopCooldownSeconds + 0.1)
				gains[i] = state.loadHay - had
			end
			t.check("each scoop picks up hay", gains[1] > 0 and gains[2] > 0 and gains[3] > 0, table.concat(gains, ", "))
			t.check("the third quick scoop is bigger (combo)", gains[3] > gains[1], table.concat(gains, ", "))
			-- Clumps count as every strand in them, and a scoop never takes more strands than the scoop size allows.
			local most = (Gloves.scoopSize(player, 0) + Config.ComboMaxBonus) * Config.HayPerPiece
			t.check("no scoop of clumps tops the scoop size", math.max(gains[1], gains[2], gains[3]) <= most, table.concat(gains, ", "))
			humanoid:UnequipTools()
		else
			t.skip("scoop combo", "no shovel in the backpack")
		end

		-- Sell at the pad by the shop.
		local world = workspace:FindFirstChild("Needlewood")
		local pad = world and world:FindFirstChild("SellPad")
		if pad then
			if state.loadHay <= 0 then
				state.loadHay = 10
			end
			local pocketOk = false
			if Needle and Needle.collect then
				local n = Needle.make(CFrame.new(pad.Position + Vector3.new(0, 3, 0)), player.UserId)
				Needle.collect(player, n)
				pocketOk = Needle.heldCount(player) >= 1
				t.check("a clicked-up needle goes in the pocket", pocketOk, Needle.heldCount(player))
			else
				t.skip("pocket needle", "the shared Needle module is not in this build")
			end
			root.CFrame = pad.CFrame + Vector3.new(0, 3, 0)
			t.wait(1.2)
			t.equal("the sell pad buys your hay", state.loadHay, 0)
			if pocketOk then
				t.equal("the sell pad buys pocket needles too", Needle.heldCount(player), 0)
			end
			-- Standing on the pad with an empty load and an empty pocket pays nothing and breaks nothing.
			local before = Bank.wallet(state)
			t.wait(2.2)
			t.equal("selling with nothing to sell pays nothing", Bank.wallet(state), before)
			t.equal("...and leaves the load empty", state.loadHay, 0)
		else
			t.skip("sell pad", "no Needlewood.SellPad in the world")
		end

		-- The wheelbarrow: load three bales, then set them down.
		stand(spot * CFrame.new(20, 0, 0))
		state.gear = state.gear or {}
		local hadBarrow = table.find(state.gear, "wheelbarrow") ~= nil
		if not hadBarrow then
			table.insert(state.gear, "wheelbarrow")
		end
		Wheelbarrow.give(player)
		local tool = player.Backpack:FindFirstChild("Wheelbarrow")
		if tool then
			humanoid:EquipTool(tool)
			t.wait(0.3)
			t.check("the barrow rolls out in front", Wheelbarrow.isOut(player))
			local loaded = 0
			for i = 1, 4 do
				local b = bale(spot * CFrame.new(20 + i * 6, 0, -8))
				if Wheelbarrow.load(player, b) then
					loaded += 1
				end
			end
			t.equal("the barrow holds 3 bales", loaded, Config.WheelbarrowBales)
			t.equal("unloading sets all 3 down", Wheelbarrow.unload(player), Config.WheelbarrowBales)

			-- Tip a full barrow into a truck bed: every bale lands inside the box, loose.
			local bed = truckBed(t, t.place())
			local tipped = {}
			for i = 1, Config.WheelbarrowBales do
				local b = bale(spot * CFrame.new(20 + i * 6, 0, 8))
				Wheelbarrow.load(player, b)
				table.insert(tipped, b)
			end
			t.equal("a full barrow tips into a truck bed", Wheelbarrow.tipInto(player, bed.floor), Config.WheelbarrowBales)
			t.wait(1.5)
			local inside = 0
			for _, b in tipped do
				if inBed(bed, b) and isLoose(b) then
					inside += 1
				end
			end
			t.equal("every tipped bale is in the bed and loose", inside, Config.WheelbarrowBales)
			humanoid:UnequipTools()
		else
			t.skip("wheelbarrow", "the barrow tool was not given")
		end
		edgeCases(t, player, state, root, stand)
		if not hadBarrow then
			table.remove(state.gear, table.find(state.gear, "wheelbarrow"))
			local left = player.Backpack:FindFirstChild("Wheelbarrow")
			if left then
				left:Destroy()
			end
		end
	end)
	if not ok then
		t.check("player checks ran without an error", false, err)
	end
	-- Put the player back as they were.
	if state.carryBale then
		Bales.drop(player)
	end
	Bales.isTeammate = KEEP_TEAMMATE
	Config.DoubleCarryTier = DOUBLE_CARRY_TIER
	Gloves.setFirstBaleBroken(player, keepFirst)
	state.loadHay, state.loadNeedles, state.loadWeight, state.loadTier = keepHay, keepNeedles, keepWeight, keepTier
	state.loadSortedHay, state.loadType = keepSorted, keepType
	Data.sync(player)
	Avatar.refreshSpeed(player)
	root.CFrame = home
	clearBales()
end

return function(SelfTest)
	SelfTest.register("Hay", function(t)
		noPlayerChecks(t)
		local ok, err = pcall(stackedRide, t)
		if not ok then
			t.check("stacked bales in a moving pickup ran without an error", false, err)
		end
		clearBales()
		local player = t.player(10)
		if player then
			withPlayer(t, player)
		else
			t.skip("player checks", "no player joined")
		end
	end)
end
