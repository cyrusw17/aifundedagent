-- Headless boot scenario: run Main.server.luau, let the world settle, have a player join (their profile loads by itself), play
-- for a minute of simulated time, leave, shut down. Then print a summary. run.py appends this after the mock and
-- the bundled sources; MOUNTS (the Rojo tree) and OPTIONS are defined by run.py.
local t0 = os.clock -- simulated clock; use the real one for timing
local realStart = H.realClock and H.realClock() or 0

local function phase(text)
	print(("\n== [t=%.1fs] %s"):format(H.now, text))
end

-- 1. The Rojo tree --------------------------------------------------------------------------------------------------
local mounted = {}
for _, m in MOUNTS do
	local names = string.split(m.name, ".")
	local parent = game:GetService(names[1])
	for i = 2, #names do
		local child = parent:FindFirstChild(names[i])
		if not child then
			local cls = i == #names and m.class or "Folder"
			child = H.rawNew(cls)
			rawset(child, "_name", names[i])
			child.Parent = parent
		end
		parent = child
	end
	mounted[m.name] = parent
end
for _, prop in OPTIONS.workspaceProps or {} do
	pcall(function()
		workspace[prop[1]] = prop[2]
	end)
end
workspace.Terrain.Decoration = false
workspace.Terrain.GrassLength = 0.1
if OPTIONS.selfTests then
	workspace:SetAttribute("RunSelfTests", true)
end
-- Self-tests that need physics (belts carry bales by AssemblyLinearVelocity, parts fall) read this and skip.
workspace:SetAttribute("Headless", true)

H.deferredSignals = OPTIONS.deferred
if OPTIONS.deferred then
	print("NOTE signal handlers run deferred (SignalBehavior.Deferred)")
end

-- 2. Boot -------------------------------------------------------------------------------------------------------------
phase("boot: ServerScriptService.Server.Main")
local mainThread = H.runScript(mounted["ServerScriptService.Server.Main"])
phase("advance 10 s")
H.advance(OPTIONS.settle or 10)
if coroutine.status(mainThread) ~= "dead" then
	print(("NOTE Main.server.luau is still running after %.0f s (parked: %s)"):format(H.now, tostring(H.parked[mainThread] or "task.wait")))
end

-- 3. A player joins and their profile loads ---------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LandConfig = require(ReplicatedStorage.Shared.Config.Land)
local toasts = {}
local function join()
	local p
	H.run(function()
		p = H.addPlayer(1001, "HeadlessTester")
	end, "PlayerAdded")
	p:GetAttributeChangedSignal("ToastText"):Connect(function()
		local text = tostring(p:GetAttribute("ToastText"))
		toasts[text] = (toasts[text] or 0) + 1
	end)
	H.advance(0.5)
	H.run(function()
		H.spawnCharacter(p)
	end, "CharacterAdded")
	H.advance(2)

	-- The profile loads by itself on joining (Data.luau). A new profile has no land, so buy the first plot nobody owns
	-- at the Land Office, like a new player would.
	local waited = 0
	while not p:GetAttribute("SaveSlot") and waited < 30 do
		H.advance(0.5)
		waited += 0.5
	end
	print("profile loaded:", p:GetAttribute("SaveSlot") == 1, "online:", p:GetAttribute("SavesOnline"), "plot:", p:GetAttribute("LandPlot"))
	if not p:GetAttribute("SaveSlot") then
		H.reportError("scenario: the player's profile didn't load within 30 s", "", "scenario")
		return p
	end
	-- An owner picks where the farm goes (src/client/PlotPick.client.luau): take the suggested plot.
	H.advance(1)
	local land = ReplicatedStorage:FindFirstChild("Land")
	local choice = p:GetAttribute("PlotChoice")
	local settle = land and land:FindFirstChild("Settle")
	if choice and settle then
		H.run(function()
			print("Land.Settle plot", choice, "->", H.invokeServer(settle, p, choice))
		end, "Land.Settle")
		H.advance(1)
	end
	local done = p:GetAttribute("LandPlot") ~= nil
	local buy = land and land:FindFirstChild("Buy")
	if not done and buy then
		H.run(function()
			local best
			for _, info in land:GetChildren() do
				if info:IsA("Configuration") then
					local owner = info:GetAttribute("OwnerId") or 0
					local index = info:GetAttribute("Index")
					if owner == 0 and index and (not best or index < best) then
						best = index
					end
				end
			end
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.CFrame = CFrame.new(LandConfig.OfficeCenter + Vector3.new(0, 3, 0))
			end
			local ok, message = H.invokeServer(buy, p, best)
			print("Land.Buy plot", best, "->", ok, message)
			if ok ~= true then
				H.reportError("scenario: buying plot " .. tostring(best) .. " failed: " .. tostring(message), "", "scenario")
			end
			done = true
		end, "Land.Buy")
	end
	waited = 0
	while not done and waited < 30 do
		H.advance(0.5)
		waited += 0.5
	end
	return p
end
phase("player joins: HeadlessTester (UserId 1001)")
local player = join()
local function teleport(position)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	end
end
H.advance(1)

-- 3b. Build: place one of every farm piece through the Land remotes, the way the build-mode client does
-- (src/client/Land.client.luau calls Place:InvokeServer(id, gx, gz, dir)), so machines and belts run during play.
local landRemotes = ReplicatedStorage:FindFirstChild("Land")
if OPTIONS.poke and landRemotes and landRemotes:FindFirstChild("Place") then
	phase("build: every farm piece, in batches that fit the plot")
	-- Land throttles build calls to one per 0.12 s (ownPlot), so calls are paced like a player clicking.
	local function call(remote, ...)
		task.wait(0.15)
		return H.invokeServer(remote, ...)
	end
	local function runToEnd(fn, name, limit)
		local finished = false
		H.run(function()
			fn()
			finished = true
		end, name)
		local waited = 0
		while not finished and waited < (limit or 600) do
			H.advance(1)
			waited += 1
		end
	end
	local LandConfig
	runToEnd(function()
		LandConfig = require(ReplicatedStorage.Shared.Config.Land)
		for _ = 1, 2 do
			print("Expand ->", call(landRemotes:FindFirstChild("Expand"), player))
		end
	end, "expand")
	local queue = {}
	for _, def in LandConfig and LandConfig.Pieces or {} do
		table.insert(queue, def)
	end
	local spots = {}
	for gz = 0, 30, 3 do
		for gx = 0, 11, 3 do
			table.insert(spots, { gx, gz })
		end
	end
	local Bales = nil
	local batch = 0
	local everPlaced, refused = {}, {}
	while #queue > 0 and batch < 8 do
		batch += 1
		local placed, models = {}, {}
		local conn = workspace.DescendantAdded:Connect(function(d)
			if d:IsA("Model") then
				table.insert(models, d)
			end
		end)
		runToEnd(function()
			local rest = {}
			for _, def in queue do
				local ok, message, at
				for _, dir in { "N", "E" } do
					for _, spot in spots do
						ok, message = call(landRemotes:FindFirstChild("Place"), player, def.id, spot[1], spot[2], dir)
						if ok then
							at = spot
							break
						elseif message and not string.find(message, "taken or off your land", 1, true) then
							break
						end
					end
					if ok or (message and not string.find(message, "taken or off your land", 1, true)) then
						break
					end
				end
				if ok then
					table.insert(placed, { id = def.id, gx = at[1], gz = at[2] })
					table.insert(everPlaced, def.id)
				elseif message and not string.find(message, "taken or off your land", 1, true) then
					table.insert(refused, ("%s (%s)"):format(def.id, tostring(message)))
				else
					table.insert(rest, def)
				end
			end
			queue = #placed > 0 and rest or {}
			if #placed == 0 then
				for _, def in rest do
					table.insert(refused, ("%s (no free spot)"):format(def.id))
				end
			end
		end, "build batch " .. batch)
		conn:Disconnect()
		local names = {}
		for _, p in placed do
			table.insert(names, p.id)
		end
		print(("batch %d placed %d: %s"):format(batch, #placed, table.concat(names, ", ")))
		-- Feed it: a bale on every belt and one dropped into every new model, then let the machines run.
		runToEnd(function()
			Bales = Bales or require(game:GetService("ServerScriptService").Server.Services.Bales)
			local n = 0
			for _, belt in game:GetService("CollectionService"):GetTagged("ConveyorBelt") do
				if n < 30 and belt:IsA("BasePart") then
					Bales.spawn(belt.Position + Vector3.new(0, belt.Size.Y / 2 + 1.6, 0))
					n += 1
				end
			end
			for _, m in models do
				if m.Parent and n < 60 then
					local cf, size = m:GetBoundingBox()
					Bales.spawn(cf.Position + Vector3.new(0, size.Y / 2 + 2, 0))
					n += 1
				end
			end
			print("bales dropped:", n)
		end, "feed batch " .. batch)
		H.advance(20)
		if #queue > 0 then
			-- clear the plot for the next batch (exercises Remove), then Undo the last removal
			runToEnd(function()
				for _, p in placed do
					local ok, message = call(landRemotes:FindFirstChild("Remove"), player, p.gx, p.gz)
					if not ok then
						print("Remove", p.id, "->", ok, message)
					end
				end
				print("Undo ->", call(landRemotes:FindFirstChild("Undo"), player))
				print("Remove again ->", call(landRemotes:FindFirstChild("Remove"), player, placed[#placed].gx, placed[#placed].gz))
			end, "clear batch " .. batch)
		end
	end
	print(("placed over all batches: %d pieces"):format(#everPlaced))
	if #refused > 0 then
		print("not placed: " .. table.concat(refused, "; "))
	end
end

-- 3c. Client actions: replay what the client scripts send (src/client/*.client.luau), with the character standing
-- where the server expects it.
if OPTIONS.poke then
	phase("client actions: tutorial, settings, bank, dealer, quests, scooping")
	local CollectionService = game:GetService("CollectionService")
	local function find(path)
		local x = ReplicatedStorage
		for name in string.gmatch(path, "[^%.]+") do
			x = x and x:FindFirstChild(name)
		end
		if not x then
			print("(no ReplicatedStorage." .. path .. ")")
		end
		return x
	end
	local function inv(path, ...)
		local r = find(path)
		if r then
			task.wait(0.25) -- most remotes rate-limit a player
			return H.invokeServer(r, player, ...)
		end
	end
	local function fire(path, ...)
		local r = find(path)
		if r then
			task.wait(0.25)
			H.fireServer(r, player, ...)
		end
	end
	local function standAt(tag)
		local x = CollectionService:GetTagged(tag)[1]
		local at = x and (x:IsA("BasePart") and x.Position or x:IsA("Model") and x:GetPivot().Position)
		if at then
			teleport(at + Vector3.new(0, 0, 3))
		else
			print("(nothing tagged " .. tag .. ")")
		end
	end
	local finished = false
	H.run(function()
		fire("Tutorial.Action", "replay")
		fire("Tutorial.Action", "done")
		for _, set in { { "effects", 0.35 }, { "uiSize", "large" }, { "shadows", false }, { "labels", false } } do
			fire("Settings.Set", set[1], set[2])
		end
		standAt("BankTeller")
		local Trucks = require(ReplicatedStorage.Shared.Config.Trucks)
		local Trailers = require(ReplicatedStorage.Shared.Config.Trailers)
		for _, call in { { "view" }, { "deposit", 100 }, { "withdraw", 50 }, { "deposit", "all" }, { "withdraw", "all" }, { "loan", "truck", (Trucks.List or Trucks)[2] and ((Trucks.List or Trucks)[2].id) or "farm_flatbed" }, { "payoff", "truck" }, { "loan", "land", "plot" } } do
			local ok, message = inv("BankRemotes.Request", call[1], call[2], call[3])
			print("Bank", call[1], call[2] or "", "->", ok, message)
		end
		fire("DealerRemotes.StudioCash")
		standAt("DealerCounter")
		local ids = {}
		for _, list in { Trucks, Trailers } do
			for _, def in list.List or list do
				if typeof(def) == "table" and def.id then
					table.insert(ids, def.id)
				end
			end
		end
		for _, id in ids do
			local ok, message = inv("DealerRemotes.Buy", id)
			print("Dealer buy", id, "->", ok, message)
		end
		local QuestConfig = require(ReplicatedStorage.Shared.Config.Quests)
		local log = inv("Quests.Get")
		print("Quests.Get ->", typeof(log))
		for id in QuestConfig.Rewards or {} do
			inv("Quests.Action", "wear", id)
		end
		for id in QuestConfig.Trucks or {} do
			local ok, message = inv("Quests.Action", "truck", typeof(id) == "string" and id or QuestConfig.Trucks[id].id)
			print("Quests truck", id, "->", ok, message)
			task.wait(6)
		end
		-- scoop: stand by a hay bale, aim at it (ToolAim) and swing the shovel
		local bale = CollectionService:GetTagged("HayBale")[1]
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local shovel = player.Backpack:FindFirstChild("Shovel") or (character and character:FindFirstChild("Shovel"))
		if bale and humanoid and shovel then
			for i = 1, 6 do
				teleport(bale.Position + Vector3.new(3, 0, 0))
				humanoid:EquipTool(shovel)
				fire("ToolAim", bale.Position, bale)
				H.fireEvent(shovel, "Activated")
				task.wait(1.5)
				if not bale.Parent then
					bale = CollectionService:GetTagged("HayBale")[1]
					if not bale then
						break
					end
				end
			end
			print("after scooping: LoadHay", player:GetAttribute("LoadHay"), "Carrying", player:GetAttribute("Carrying"))
		else
			print("(no bale / humanoid / shovel to scoop with)", bale, humanoid, shovel)
		end
		fire("DropBale")
		finished = true
	end, "client actions")
	local waited = 0
	while not finished and waited < 300 do
		H.advance(1)
		waited += 1
	end
end

-- 4. Play for a minute ----------------------------------------------------------------------------------------------
phase(("play %d s"):format(OPTIONS.play or 60))
H.advance(OPTIONS.play or 60)
local cash = player:GetAttribute("Cash")
print("player attributes: Cash", cash, "SaveSlot", player:GetAttribute("SaveSlot"), "SavesOnline", player:GetAttribute("SavesOnline"))

-- 4b. Poke: what a player can do by walking around. Swing every tool, then walk up to every enabled
-- ProximityPrompt / ClickDetector in the Workspace and use it (the character stands next to it first, so the
-- server's own distance checks pass like they would in play).
if OPTIONS.poke then
	phase("poke: swing every tool")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChild("Backpack")
	local tools = {}
	for _, holder in { character, backpack } do
		for _, t in holder and holder:GetChildren() or {} do
			if t:IsA("Tool") then
				table.insert(tools, t)
			end
		end
	end
	for _, tool in tools do
		H.run(function()
			if humanoid and tool.Parent then
				humanoid:EquipTool(tool)
			end
		end, "equip " .. tool.Name)
		H.advance(0.2)
		for _ = 1, 3 do
			H.run(function()
				H.fireEvent(tool, "Activated")
			end, "activate " .. tool.Name)
			H.advance(1)
		end
	end

	local prompts, clicks = {}, {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Enabled then
			table.insert(prompts, d)
		elseif d:IsA("ClickDetector") then
			table.insert(clicks, d)
		end
	end
	local function where(inst)
		local p = inst.Parent
		if p and p:IsA("Attachment") then
			return p.WorldPosition
		elseif p and p:IsA("BasePart") then
			return p.Position
		elseif p and p:IsA("Model") then
			return p:GetPivot().Position
		end
		return nil
	end
	local function byName(a, b)
		return a:GetFullName() < b:GetFullName()
	end
	table.sort(prompts, byName)
	table.sort(clicks, byName)
	phase(("poke: trigger %d prompts, click %d detectors"):format(#prompts, #clicks))
	local pps = game:GetService("ProximityPromptService")
	for _, prompt in prompts do
		if prompt.Parent and prompt.Enabled and player.Parent then
			local at = where(prompt)
			if at then
				H.run(function()
					teleport(at)
					if prompt.HoldDuration > 0 then
						H.fireEvent(prompt, "PromptButtonHoldBegan", player)
					end
					H.fireEvent(prompt, "Triggered", player)
					H.fireEvent(pps, "PromptTriggered", prompt, player)
					H.fireEvent(prompt, "TriggerEnded", player)
				end, "Triggered " .. prompt:GetFullName())
				H.advance(0.2)
			end
		end
	end
	for _, click in clicks do
		if click.Parent and player.Parent then
			local at = where(click)
			if at then
				H.run(function()
					teleport(at)
					H.fireEvent(click, "MouseClick", player)
				end, "MouseClick " .. click:GetFullName())
				H.advance(0.2)
			end
		end
	end
	H.advance(10)
	print("after poking: Cash", player:GetAttribute("Cash"))
end

-- 5. Leave and shut down --------------------------------------------------------------------------------------------
phase("player leaves")
H.run(function()
	H.removePlayer(player)
end, "PlayerRemoving")
H.advance(5)
-- 5b. Rejoin and load the save just written (rebuilds the farm from the DataStore).
phase("player rejoins and loads their profile")
player = join()
H.advance(20)
print("after reload: Cash", player:GetAttribute("Cash"), "SaveSlot", player:GetAttribute("SaveSlot"))
H.run(function()
	H.removePlayer(player)
end, "PlayerRemoving")
H.advance(5)

phase("server shutdown (BindToClose)")
for _, fn in H.bindToClose do
	H.run(fn, "BindToClose")
end
H.advance(5)

-- Every module gets required at least once, so top-level errors in modules nothing reached still show.
phase("require every remaining module")
for _, m in MOUNTS do
	if m.class == "ModuleScript" and m.preload then
		local inst = mounted[m.name]
		if not H.moduleState[inst] then
			H.run(function()
				pcall(require, inst)
			end, "require " .. m.name)
		end
	end
end
H.advance(2)

-- Summary -----------------------------------------------------------------------------------------------------------
print("\n================ SUMMARY ================")
print(("simulated time %.1f s, %d frames"):format(H.now, H.frame))
print(("modules loaded: %d"):format(H.modulesLoaded))
local parts, inWorld = 0, 0
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end
print(("BaseParts in Workspace: %d"):format(parts))
local byClass = {}
for cls, n in H.created do
	table.insert(byClass, { cls, n })
end
table.sort(byClass, function(a, b)
	return a[2] > b[2]
end)
local line = {}
for i, e in byClass do
	if i > 25 then
		break
	end
	table.insert(line, ("%s %d"):format(e[1], e[2]))
end
print(("instances created: %d (%s)"):format(H.createdTotal, table.concat(line, ", ")))
local stores = 0
for id, s in H.dataStores do
	local keys = {}
	for k in s.data do
		table.insert(keys, k)
	end
	table.sort(keys)
	print(("DataStore %s: %d keys (%s)"):format(id, #keys, table.concat(keys, ", ")))
	stores += 1
end
print(("DataStore calls: %d"):format(H.dataStoreCalls))
local stuck = 0
for co, why in H.parked do
	if coroutine.status(co) == "suspended" and not string.find(tostring(why), "^Wait on RunService") then
		stuck += 1
		print("WAITING " .. tostring(why))
		print(H.cleanTrace(debug.traceback(co)))
	end
end
if H.infiniteYields then
	for _, y in H.infiniteYields do
		print("STUCK " .. y.label)
		print(H.cleanTrace(y.trace))
	end
end
print(("threads still waiting on signals/WaitForChild/require: %d"):format(stuck))
local toastList = {}
for text, n in toasts do
	table.insert(toastList, n > 1 and ("%s (x%d)"):format(text, n) or text)
end
table.sort(toastList)
print(("toasts shown to the player: %d different"):format(#toastList))
for _, t in toastList do
	print("  TOAST " .. t)
end
print(("warnings: %d"):format(#H.warnings))
-- Game code that pcalls and warns (e.g. Land's remote guard, Data's save) hides errors; count those as errors.
local caught = 0
for _, w in H.warnings do
	local lower = string.lower(w.text)
	local isError = string.find(lower, "error") or string.find(lower, "failed") or string.find(lower, "went wrong")
	if isError then
		caught += 1
	end
	print(("  %s [t=%.1fs] %s"):format(isError and "CAUGHT" or "WARN", w.at, w.text))
end
local errorCount = 0
for _, e in H.errors do
	errorCount += 1
end
print(("errors: %d"):format(errorCount))
for i, e in H.errors do
	print(("  %d. [t=%.1fs]%s %s%s"):format(i, e.at, e.context and (" (" .. e.context .. ")") or "", e.message, e.count > 1 and (" (x" .. e.count .. ")") or ""))
end
print("HEADLESS_RESULT errors=" .. (errorCount + caught) .. " warnings=" .. #H.warnings)
