--!nonstrict
-- Hay tool checks (Finish hay tool interactions). The first part needs no player: bales, strands, hay looks, the
-- rake and the config. The rest uses the first player in the game and puts their position, carried hay and
-- first-bale flag back afterwards: lift, set down, stack, break (the first-bale needle), scoop with the combo, sell
-- at the pad, a pocket needle, and the wheelbarrow. A sale made here is real money in the player's slot.
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
local Finds = require(Services.Finds)
local Wheelbarrow = require(Services.Wheelbarrow)
local NeedleModule = Services:FindFirstChild("Needle")
local Needle = NeedleModule and require(NeedleModule)

local BALE = Vector3.new(4.6, 2.6, 3.2)

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
	clearBales()
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
		local strands, needles = 0, 0
		for _, p in strandsNear(burst, 14) do
			if Hay.isNeedle(p) then
				needles += 1
			else
				strands += 1
			end
		end
		t.check("a broken bale spills strands", strands >= Config.PiecesPerBale * 0.8, strands)
		t.check("the first bale broken spills a needle", needles >= 1, needles)
		t.check("breaking it used up the first-bale promise", Gloves.firstBaleBroken(player))

		-- Scoop three times quickly: each scoop picks up hay and the third is bigger (the combo).
		local shovel = player.Backpack:FindFirstChild("Shovel") or character:FindFirstChild("Shovel")
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
			humanoid:UnequipTools()
		else
			t.skip("wheelbarrow", "the barrow tool was not given")
		end
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
	Gloves.setFirstBaleBroken(player, keepFirst)
	state.loadHay, state.loadNeedles, state.loadWeight, state.loadTier = keepHay, keepNeedles, keepWeight, keepTier
	Data.sync(player)
	Avatar.refreshSpeed(player)
	root.CFrame = home
	clearBales()
end

return function(SelfTest)
	SelfTest.register("Hay", function(t)
		noPlayerChecks(t)
		local player = t.player(10)
		if player then
			withPlayer(t, player)
		else
			t.skip("player checks", "no player joined")
		end
	end)
end
