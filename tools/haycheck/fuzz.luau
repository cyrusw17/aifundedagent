-- Fuzz of the hand loop, offline: the real Bales.luau, Hay.luau and Finds.luau (bundled by run.py with mapcheck's
-- mock), with a few fake players doing random things in a random order: lift (one or two bales), set down, throw,
-- barrow-style stow and release, leave the game and come back, bales consumed and spawned, loose hay spilled, finds
-- kept and traded away. After every step it checks:
--   no stuck bales      a bale is carried by a player exactly when that player's hands (or barrow) hold it, and a bale
--                        nobody holds is free physics (no carry weld, not massless, its button usable)
--   no orphaned owner   a bale's owner, once set, never changes, and a gone bale is gone everywhere
--   the loose caps hold loose strands and needles never pass MaxLoosePieces / MaxLooseNeedles
--   nothing pays twice  a finder's reward is paid at most once per kind per slot, whatever is traded
-- Physics (where a bale lands) is not simulated; this is about the bookkeeping.

-- More of the Roblox API than the map build needs ------------------------------------------------------------------
OverlapParams = { new = function() return {} end }
RaycastParams = { new = function() return {} end }
NumberSequence = { new = function(...) return { ... } end }
NumberSequenceKeypoint = { new = function(...) return { ... } end }
ColorSequence = { new = function(...) return { ... } end }
NumberRange = { new = function(...) return { ... } end }
TweenInfo = { new = function(...) return { ... } end }
workspace.Raycast = function() return nil end
workspace.GetPartBoundsInBox = function() return {} end
workspace.GetPartBoundsInRadius = function() return {} end
workspace.Gravity = 196.2
do
	-- Parts tell Hay when they are destroyed; here the hook is simply there.
	local mt = getmetatable(Instance.new("Part"))
	local index = mt.__index
	mt.__index = function(o, k)
		if k == "Destroying" or k == "MouseClick" then
			return { Connect = function() return { Disconnect = function() end } end }
		end
		if k == "Emit" or k == "SetNetworkOwner" then
			return function() end
		end
		if k == "AssemblyLinearVelocity" or k == "AssemblyAngularVelocity" then
			return rawget(o, "_props")[k] or Vector3.zero
		end
		return index(o, k)
	end
end

-- Fake services around the real modules -----------------------------------------------------------------------------
local states = {} -- player -> save state (nil while they are away)
local roots = {} -- player -> HumanoidRootPart
local gloveTier = {} -- player -> 0..5
local earned = {} -- player -> { [findId] = times paid }
local paidFinds = {}

MODULES["Services.Data"] = function()
	return {
		get = function(player) return states[player] end,
		sync = function() end,
		toast = function() end,
		save = function() end,
		loaded = { Event = { Connect = function() end } },
	}
end
MODULES["Services.Avatar"] = function()
	return {
		getRoot = function(player) return roots[player] end,
		equippedKind = function() return nil end,
		setCarry = function() end,
		clearCarry = function() end,
		refreshSpeed = function() end,
	}
end
MODULES["Services.Gloves"] = function()
	local Gloves = require({ __path = "Shared.Config.Gloves" })
	return {
		get = function(player) return Gloves.Tiers[(gloveTier[player] or 0) + 1] end,
		firstBaleBreak = function() return false end,
		baleWeight = function() return 1, 0 end,
	}
end
MODULES["Services.Bank"] = function()
	return {
		earn = function(player, amount, note)
			if note == "Finder's reward" then
				table.insert(paidFinds, player)
			end
			return amount, 0
		end,
	}
end
MODULES["Services.Needle"] = function()
	return {
		make = function(cframe, ownerId)
			local p = Instance.new("Part")
			p.Name = "Needle"
			p.CFrame = cframe
			p:SetAttribute("Needle", true)
			p:SetAttribute("OwnerId", ownerId)
			return p
		end,
		isNeedle = function(part) return part:GetAttribute("Needle") == true end,
		value = function() return 1 end,
	}
end
MODULES["Services.Weather"] = function() return { get = function() return "clear" end } end
MODULES["Shared.WorldRegions"] = function() return { at = function() return nil end } end
MODULES["Services.Props"] = function() return { has = function() return false end, make = function() return nil end, weldTo = function() end } end
for _, name in { "Groups", "Tutorial", "Feedback", "Events", "Announce" } do
	MODULES["Services." .. name] = function()
		return setmetatable({ Loose = "Loose" }, { __index = function() return function() end end })
	end
end

local Game = require({ __path = "Shared.Config.Game" })
local Hay = require({ __path = "Services.Hay" })
Hay.init(workspace)
local Bales = require({ __path = "Services.Bales" })
local folder = Instance.new("Folder")
folder.Parent = workspace
Bales.init(folder)
local Finds = require({ __path = "Services.Finds" })
local FindsConfig = require({ __path = "Shared.Config.Finds" })

-- The run ---------------------------------------------------------------------------------------------------------------
local rng = Random.new(tonumber(os.getenv and os.getenv("HAY_FUZZ_SEED") or "") or 1234)
local STEPS = 20000
local failed, passed = 0, 0
local firstFail = nil
local function check(name, ok)
	if ok then
		passed += 1
	else
		failed += 1
		if failed <= 20 then
			print("FAIL " .. name)
		end
		firstFail = firstFail or name
	end
end

local players = {}
for i = 1, 4 do
	local character = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(i * 20, 3, 0)
	root.Parent = character
	character.Parent = workspace
	local attributes = {}
	local player = {
		Name = "Fuzz" .. i,
		DisplayName = "Fuzz" .. i,
		UserId = 1000 + i,
		Character = character,
		SetAttribute = function(_, k, v) attributes[k] = v end,
		GetAttribute = function(_, k) return attributes[k] end,
		FindFirstChild = function() return nil end,
		FindFirstChildOfClass = function() return nil end,
	}
	players[i] = player
	roots[player] = root
end
local saved = {} -- player -> what Data saved when they left (finds and findsPaid survive a rejoin)
local function join(player)
	local old = saved[player]
	states[player] = { loadHay = 0, loadNeedles = 0, finds = old and old.finds or {}, findsPaid = old and old.findsPaid or {} }
end
for _, p in players do
	join(p)
end

local bales = {} -- every bale record ever spawned
local firstOwner = {} -- bale -> the first ownerId it had
local stowed = {} -- bale -> player (barrow)
local function spawnBale()
	local p = players[rng:NextInteger(1, #players)]
	local at = roots[p] and roots[p].Position or Vector3.new(0, 0, 0)
	local b = Bales.spawn(at + Vector3.new(rng:NextNumber(-3, 3), -3, rng:NextNumber(-3, 3)), false, false, "meadow")
	table.insert(bales, b)
	return b
end
for _ = 1, 12 do
	spawnBale()
end
local function anyBale()
	return bales[rng:NextInteger(1, #bales)]
end
-- Mostly a live bale within the player's reach (so lifts happen), sometimes any bale at all (gone, held, far).
local function baleFor(player)
	local root = roots[player]
	if root and rng:NextNumber() < 0.8 then
		local near = {}
		for _, b in bales do
			if not b.gone and (b.body.Position - root.Position).Magnitude <= Game.PickupReach then
				table.insert(near, b)
			end
		end
		if #near > 0 then
			return near[rng:NextInteger(1, #near)]
		end
	end
	return anyBale()
end
local function liveCount()
	local n = 0
	for _, b in bales do
		if not b.gone then
			n += 1
		end
	end
	return n
end
local function anyPlayer()
	return players[rng:NextInteger(1, #players)]
end

local heldBefore, extraBefore = {}, {}
local seen = { lifts = 0, doubles = 0, stows = 0, paid = 0, gone = 0 }
local function invariants(step)
	for _, b in bales do
		if b.gone then
			check(("step %d: a gone bale is forgotten"):format(step), Bales.fromPart(b.body) == nil)
		else
			local holder = b.carriedBy
			if holder then
				local s = states[holder]
				local inHands = s and (s.carryBale == b or s.carryExtra == b)
				check(("step %d: a carried bale is in its carrier's hands or barrow"):format(step), inHands or stowed[b] == holder)
				check(("step %d: a carried bale is welded to its carrier"):format(step), b.carryWeld ~= nil)
			else
				check(("step %d: a free bale has no carry weld"):format(step), b.carryWeld == nil)
				check(("step %d: a free bale is not massless"):format(step), b.body.Massless ~= true)
				check(("step %d: nobody's barrow holds a free bale"):format(step), stowed[b] == nil)
			end
			if b.ownerId ~= nil then
				firstOwner[b] = firstOwner[b] or b.ownerId
				check(("step %d: a bale's owner never changes"):format(step), b.ownerId == firstOwner[b])
			end
		end
	end
	for player, s in states do
		if s.carryBale and s.carryBale ~= heldBefore[player] then
			seen.lifts += 1
		end
		if s.carryExtra and s.carryExtra ~= extraBefore[player] then
			seen.doubles += 1
		end
		heldBefore[player], extraBefore[player] = s.carryBale, s.carryExtra
		if s.carryBale then
			check(("step %d: hands hold a live bale"):format(step), not s.carryBale.gone)
			check(("step %d: the bale in hand knows its carrier"):format(step), s.carryBale.carriedBy == player)
		end
		check(("step %d: a second bale only on top of a first"):format(step), s.carryExtra == nil or (s.carryBale ~= nil and s.carryExtra ~= s.carryBale))
		if s.carryExtra then
			check(("step %d: the second bale knows its carrier"):format(step), s.carryExtra.carriedBy == player and not s.carryExtra.gone)
		end
	end
	local stats = Hay.stats()
	check(("step %d: loose strands within the cap"):format(step), stats.strands <= Game.MaxLoosePieces)
	check(("step %d: loose needles within the cap"):format(step), stats.needles <= Game.MaxLooseNeedles)
	check(("step %d: every loose piece is counted"):format(step), stats.tracked == stats.strands + stats.needles)
end

local findIds = {}
for _, item in FindsConfig.Items do
	table.insert(findIds, item.id)
end

for step = 1, STEPS do
	local action = rng:NextInteger(1, 13)
	local p = anyPlayer()
	if action <= 3 then
		if states[p] then
			Bales.pickup(p, baleFor(p))
		end
	elseif action == 4 then
		if states[p] then
			Bales.drop(p)
		end
	elseif action == 5 then
		if states[p] then
			Bales.toss(p, rng:NextNumber())
		end
	elseif action == 6 then
		-- Barrow: stow a bale, or tip one back out.
		local b = baleFor(p)
		if states[p] and Bales.stow(p, b, roots[p], CFrame.new(0, 1, -3)) then
			stowed[b] = p
			seen.stows += 1
		end
		for other, owner in stowed do
			if owner == p and rng:NextNumber() < 0.5 then
				stowed[other] = nil
				if rng:NextNumber() < 0.5 then
					Bales.release(other, roots[p])
				else
					Bales.releaseAt(other, CFrame.new(0, 5, 0))
				end
			end
		end
	elseif action == 7 then
		-- Leave the game (what is held goes away, as the barrow's unload would), then maybe come back.
		if states[p] then
			for b, owner in stowed do
				if owner == p then
					stowed[b] = nil
					Bales.release(b, nil)
				end
			end
			Bales.playerLeft(p)
			saved[p] = states[p]
			states[p] = nil
		else
			join(p)
		end
	elseif action == 8 then
		-- A sell pad or machine takes a bale now and then.
		local b = anyBale()
		if not b.carriedBy and rng:NextNumber() < 0.25 then
			Bales.consume(b)
		end
	elseif action == 9 then
		-- Field regrowth, kept to about forty bales standing.
		if liveCount() < 40 then
			spawnBale()
		end
	elseif action == 10 then
		gloveTier[p] = rng:NextInteger(0, 5)
	elseif action == 11 then
		-- A spill of loose hay (and the odd needle), as a burst bale makes.
		for _ = 1, rng:NextInteger(10, 120) do
			Hay.spawnPiece(Vector3.new(rng:NextNumber(-50, 50), 1, rng:NextNumber(-50, 50)), Vector3.zero, p.UserId, rng:NextNumber() < 0.05 and "Needle" or nil, "meadow", rng:NextInteger(1, 3))
		end
	elseif action == 12 then
		-- Keep a find.
		if states[p] then
			local id = findIds[rng:NextInteger(1, #findIds)]
			local before = #paidFinds
			Finds.keepForTest(p, id)
			if #paidFinds > before then
				seen.paid += 1
				earned[p] = earned[p] or {}
				earned[p][id] = (earned[p][id] or 0) + 1
				check(("step %d: a find's reward pays once per kind"):format(step), earned[p][id] == 1)
			end
		end
	elseif action == 13 then
		-- Trade a find away (Trade.luau takes it off the shelf).
		local s = states[p]
		if s and s.finds then
			for id, count in s.finds do
				if count > 0 and rng:NextNumber() < 0.5 then
					s.finds[id] = count - 1
				end
			end
		end
	end
	invariants(step)
end

-- The part budget (Hay #24): a crew breaks ten bales at once. Count the parts and the strands they hold, with
-- clumps (Config.StrandsPerClump) and with single strands, and check the clumps keep every strand under the cap.
local function burstTen(perClump)
	for _, piece in Hay.folder:GetChildren() do
		Hay.remove(piece)
	end
	local keep = Game.StrandsPerClump
	Game.StrandsPerClump = perClump
	local spawn = task.spawn
	task.spawn = function(fn, ...)
		fn(...)
	end
	local breaker = players[1]
	states[breaker] = states[breaker] or { loadHay = 0, loadNeedles = 0, finds = {}, findsPaid = {} }
	for _ = 1, 10 do
		Bales.breakOpen(breaker, spawnBale())
	end
	task.spawn = spawn
	Game.StrandsPerClump = keep
	local parts, strands = 0, 0
	for _, piece in Hay.folder:GetChildren() do
		if Hay.isPiece(piece) and not Hay.isNeedle(piece) then
			parts += 1
			strands += Hay.strandsIn(piece)
		end
	end
	return parts, strands
end
local singleParts, singleStrands = burstTen(1)
local clumpParts, clumpStrands = burstTen(Game.StrandsPerClump)
local want = 10 * Game.PiecesPerBale
print(("ten bales at once: single strands %d parts holding %d of %d strands; clumps of %d: %d parts holding %d"):format(
	singleParts, singleStrands, want, Game.StrandsPerClump, clumpParts, clumpStrands))
check("ten bales of clumps fit the loose cap", clumpParts <= Game.MaxLoosePieces)
check("ten bales of clumps lose no hay", clumpStrands == want)
check("clumps cut the parts to a third or less", clumpParts * Game.StrandsPerClump <= want)

for _, b in bales do
	if b.gone then
		seen.gone += 1
	end
end
print(("exercised: %d lifts, %d double carries, %d barrow stows, %d finds paid, %d bales gone"):format(seen.lifts, seen.doubles, seen.stows, seen.paid, seen.gone))
-- A run that never lifts, doubles, stows or pays proves nothing: count it as a failure.
check("the fuzz lifted bales", seen.lifts > 100)
check("the fuzz double-carried", seen.doubles > 10)
check("the fuzz used the barrow", seen.stows > 10)
check("the fuzz paid finds", seen.paid > 0)
print(("hand loop fuzz: %d steps, %d bales, %d checks passed, %d failed"):format(STEPS, #bales, passed, failed))
if failed > 0 then
	error("hand loop fuzz failed first at: " .. tostring(firstFail))
end
