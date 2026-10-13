--!nonstrict
-- NPC buyer orders (backlog Econ 4). A board at base camp shows three orders from local buyers, for example "Miller
-- Joe wants 20 sorted bales, pays 2x". Bring what they want to the ORDERS pad beside the board: set bales on it, or
-- step on it with needles in your pocket. Each one pays the order's rate straight away, up to the order's amount per
-- player, so nothing delivered is ever lost when the orders change. New orders come every Prices.Orders.RotateSeconds.
-- The numbers, buyers and kinds of order are in Config/Prices (Orders).
--
-- Daily contracts (CEO H9, Prices.DailyContracts) use the same pad: three a day, the same for everyone, reset at
-- midnight UTC. Anything delivered counts toward today's contract of its kind, and a contract with no order open for
-- its goods takes them at their normal price. Each finished contract pays a reward, all three a bonus and a streak
-- day (Quests.countStreak). The board's back face lists them; each player's progress is the player attribute
-- Contracts (one line each), and ReplicatedStorage attribute ContractsResetAt is the next reset (unix time, the same
-- clock as workspace:GetServerTimeNow()) for the HUD countdown.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Game)
local Prices = require(Shared.Config.Prices)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Bales = require(script.Parent.Bales)
local Needle = require(script.Parent.Needle)
local Props = require(script.Parent.Props)
local NeedleTypes = require(Shared.Config.Needles)

local Orders = {}

local Terms = Prices.Orders
local rng = Random.new()
local offers = {} -- the current orders: { buyer, kind, needle?, amount, mult, rate, label }
local delivered = {} -- [offerIndex] = { [userId] = count }, cleared when the orders change
local rotateAt = 0
local board = nil

-- What one unit of each kind is worth at its normal place of sale, before the order's bonus.
local function baseRate(kind, needleId)
	if kind == "needles" then
		return Prices.Needles[needleId] or 100
	elseif kind == "sorted" then
		return Prices.HayPerBale * Prices.HayPrice -- a sorted bale is all hay
	end
	-- A raw bale at the public shop: its hay plus the shop's $1 for each hidden needle.
	return Prices.HayPerBale * Prices.HayPrice + Prices.NeedlesPerBale.meadow * Prices.RawNeedlePrice
end

local function newOffer(kind)
	local spec = Terms.Kinds[kind]
	local buyer = Terms.Buyers[rng:NextInteger(1, #Terms.Buyers)]
	local amount = rng:NextInteger(spec.amount[1], spec.amount[2])
	local needleId = kind == "needles" and "steel" or nil
	local rate = math.floor(baseRate(kind, needleId) * spec.mult + 0.5)
	local what = kind == "needles" and "steel needles" or kind == "sorted" and "sorted bales" or "hay bales"
	return {
		buyer = buyer,
		kind = kind,
		needle = needleId,
		amount = amount,
		mult = spec.mult,
		rate = rate,
		label = ("%s wants %d %s\n$%d each (%sx)"):format(buyer, amount, what, rate, tostring(spec.mult)),
	}
end

local function rotate()
	table.clear(offers)
	table.clear(delivered)
	for i, kind in { "bales", "sorted", "needles" } do
		offers[i] = newOffer(kind)
		delivered[i] = {}
	end
	rotateAt = os.clock() + Terms.RotateSeconds
end

local function boardText()
	local lines = { "TODAY'S ORDERS" }
	for _, offer in offers do
		table.insert(lines, offer.label)
	end
	local left = math.max(0, rotateAt - os.clock())
	table.insert(lines, ("New orders in %d min"):format(math.ceil(left / 60)))
	return table.concat(lines, "\n\n")
end

-- The open order of this kind for a player, with how many more it takes.
local function openOrder(userId, kind)
	for i, offer in offers do
		if offer.kind == kind then
			local done = delivered[i][userId] or 0
			if done < offer.amount then
				return i, offer, offer.amount - done
			end
		end
	end
	return nil
end

-- fill (0..1) scales the pay for a part-full sorted bale; it still counts as one bale toward the order.
local function credit(player, i, offer, count, fill)
	delivered[i][player.UserId] = (delivered[i][player.UserId] or 0) + count
	local pay = math.floor(offer.rate * count * math.clamp(fill or 1, 0, 1) + 0.5)
	Bank.earn(player, pay, ("Order: %s"):format(offer.buyer))
	local done = delivered[i][player.UserId]
	if done >= offer.amount then
		Data.toast(player, ("%s's order is filled! +$%d"):format(offer.buyer, pay))
	else
		Data.toast(player, ("%s: %d / %d delivered. +$%d"):format(offer.buyer, done, offer.amount, pay))
	end
end

-- Daily contracts ---------------------------------------------------------------------------------------------------

local Contract = Prices.DailyContracts
local DAY = 86400

local function today()
	return os.time() // DAY
end

local function tierFor(sold)
	local pick = 1
	for i, tier in Contract.Tiers do
		if sold >= tier.fromSold then
			pick = i
		end
	end
	return pick
end

local function needleName(id)
	for _, n in NeedleTypes do
		if n.id == id then
			return n.name
		end
	end
	return id
end

local function what(kind, needleId)
	return kind == "needles" and (needleName(needleId):lower() .. " needles") or kind == "sorted" and "sorted bales" or "hay bales"
end

-- Today's contracts at a tier: { buyer, kind, needle?, amount }. Seeded by the day, so every server agrees.
function Orders.contractsFor(tierIndex, day)
	local tier = Contract.Tiers[tierIndex]
	local r = Random.new((day or today()) * 104729 + 7)
	local out = {}
	for i, kind in tier.kinds or { "bales", "sorted", "needles" } do
		local range = Contract.Kinds[kind].amount
		out[i] = {
			buyer = Terms.Buyers[r:NextInteger(1, #Terms.Buyers)],
			kind = kind,
			needle = kind == "needles" and tier.needle or nil,
			amount = r:NextInteger(range[1], range[2]),
		}
	end
	return out
end

-- A player's contract state for today, started fresh (tier fixed for the day) when the day has turned.
local function contractState(player)
	local state = Data.get(player)
	if not state then
		return nil
	end
	local c = state.contracts
	if typeof(c) ~= "table" or c.day ~= today() or not Contract.Tiers[c.tier] then
		-- Sales since the last rebirth, so a reborn slot starts again at the first tier (Rebirth.luau).
		local since = typeof(state.rebirth) == "table" and tonumber(state.rebirth.soldAt) or 0
		c = { day = today(), tier = tierFor(Bank.account(state).sold - since), n = {}, paid = {} }
		state.contracts = c
	end
	c.n = typeof(c.n) == "table" and c.n or {}
	c.paid = typeof(c.paid) == "table" and c.paid or {}
	return c, Orders.contractsFor(c.tier, c.day)
end

local function publishContracts(player)
	local c, list = contractState(player)
	if not c then
		return
	end
	local lines = {}
	for i, def in list do
		table.insert(lines, ("%s: %d / %d %s%s"):format(def.buyer, math.min(c.n[i] or 0, def.amount), def.amount, what(def.kind, def.needle), c.paid[i] and " (done)" or ""))
	end
	local tier = Contract.Tiers[c.tier]
	table.insert(lines, ("$%d each, $%d more for all three"):format(tier.reward, tier.bonus))
	player:SetAttribute("Contracts", table.concat(lines, "\n"))
end

-- The open contract for these goods: index, def, how many more it takes.
local function openContract(player, kind, needleId)
	local c, list = contractState(player)
	if not c then
		return nil
	end
	for i, def in list do
		if def.kind == kind and (kind ~= "needles" or def.needle == needleId) and (c.n[i] or 0) < def.amount then
			return i, def, def.amount - (c.n[i] or 0)
		end
	end
	return nil
end

local Quests -- required on first use: Quests is a big service, and Orders loads early
local function countContract(player, i, count)
	local c, list = contractState(player)
	local def = c and list[i]
	if not def then
		return
	end
	c.n[i] = math.min(def.amount, (c.n[i] or 0) + count)
	if c.n[i] >= def.amount and not c.paid[i] then
		c.paid[i] = true
		local tier = Contract.Tiers[c.tier]
		Bank.earn(player, tier.reward, ("Contract: %s"):format(def.buyer))
		Data.toast(player, ("Contract done for %s! +$%d"):format(def.buyer, tier.reward))
		local all = true
		for j in list do
			all = all and c.paid[j] == true
		end
		if all and not c.bonus then
			c.bonus = true
			Bank.earn(player, tier.bonus, "Contract: all three today")
			Data.toast(player, ("All three contracts done! +$%d bonus"):format(tier.bonus))
			Quests = Quests or require(script.Parent.Quests)
			Quests.countStreak(player)
		end
	end
	publishContracts(player)
end

local function contractsText()
	local list = Orders.contractsFor(2) -- the board shows the usual three kinds
	local lines = { "DAILY CONTRACTS", "Finish all three for a bonus and a streak day" }
	for _, def in list do
		table.insert(lines, ("%s wants %s"):format(def.buyer, def.kind == "needles" and "needles from your best field" or what(def.kind)))
	end
	local left = (today() + 1) * DAY - os.time()
	table.insert(lines, ("New contracts in %dh %02dm"):format(left // 3600, left % 3600 // 60))
	return table.concat(lines, "\n\n")
end

-- A bale set on the pad goes to its owner's open order, sorted or plain. Bales nobody ordered stay where they are.
local warned = setmetatable({}, { __mode = "k" }) -- bales already told "nobody wants this"
local function deliverBale(b)
	if b.gone or b.carriedBy or b.breaking or not b.ownerId then
		return
	end
	local player = Players:GetPlayerByUserId(b.ownerId)
	if not player or not Data.get(player) then
		return
	end
	local kind = b.sorted and "sorted" or "bales"
	local i, offer = openOrder(player.UserId, kind)
	local ci = openContract(player, kind)
	if not i and not ci then
		if not warned[b] then
			warned[b] = true
			Data.toast(player, b.sorted and "Nobody here wants more sorted bales right now." or "Nobody here wants more hay bales right now.")
		end
		return
	end
	-- A sorted bale pays for the hay it holds: a sorter can wrap a few loose strands into a full-size sorted bale.
	local fill = b.sorted and math.min(1, (b.sortedHay or Prices.HayPerBale) / Prices.HayPerBale) or 1
	Bales.consume(b)
	if i then
		credit(player, i, offer, 1, fill)
	else
		Bank.earn(player, math.floor(baseRate(kind) * fill + 0.5), "Contract: delivery")
	end
	if ci then
		countContract(player, ci, 1)
	end
end

-- Standing on the pad hands over matching needles from your pocket. Mutated needles stay in your pocket.
local lastStep = {}
local function deliverNeedles(player)
	if os.clock() - (lastStep[player] or 0) < 1 then
		return
	end
	lastStep[player] = os.clock()
	local i, offer, want = openOrder(player.UserId, "needles")
	if i then
		-- Any grade or polish of the type counts, cheapest first (Needle.take).
		local count = math.min(Needle.plainCount(player, offer.needle), want)
		if count > 0 and Needle.take(player, offer.needle, count) then
			credit(player, i, offer, count)
			local ci = openContract(player, "needles", offer.needle)
			if ci then
				countContract(player, ci, count)
			end
		end
	end
	-- Then today's needle contract, if it wants a type the order didn't take (or more than it took).
	local c, list = contractState(player)
	if not c then
		return
	end
	for _, def in list do
		if def.kind == "needles" then
			local ci, _, more = openContract(player, "needles", def.needle)
			local count = ci and math.min(Needle.plainCount(player, def.needle), more) or 0
			if count > 0 and Needle.take(player, def.needle, count) then
				Bank.earn(player, baseRate("needles", def.needle) * count, "Contract: delivery")
				countContract(player, ci, count)
			end
			break
		end
	end
end

-- Credits up to count units of a kind ("bales", "sorted" or "needles") to a player's open order, as the pad does once
-- it has taken the goods. fill (0..1, default 1) is how full a sorted bale is; the pay scales with it. Returns how many the order took. The pad uses the same rules; SelfTests/Economy calls this.
function Orders.fill(player, kind, count, fill)
	local i, offer, want = openOrder(player.UserId, kind)
	if not i or not Data.get(player) then
		return 0
	end
	local take = math.min(math.floor(count or 0), want)
	if take <= 0 then
		return 0
	end
	credit(player, i, offer, take, fill)
	return take
end

-- Credits count units of a kind to today's contract for that kind (needles: the contract's type), paying their normal
-- price, as the pad does when no order wants them. Returns how many it took. SelfTests/Economy calls this.
function Orders.fillContract(player, kind, count)
	local _, list = contractState(player)
	local needleId
	for _, def in list or {} do
		if def.kind == kind then
			needleId = def.needle
			break
		end
	end
	local ci, _, more = openContract(player, kind, needleId)
	local take = ci and math.min(math.floor(count or 0), more) or 0
	if take <= 0 then
		return 0
	end
	Bank.earn(player, baseRate(kind, needleId) * take, "Contract: delivery")
	countContract(player, ci, take)
	return take
end

-- Today's contracts and this player's progress: state ({ day, tier, n, paid, bonus }) and the list. Also sets the
-- player's Contracts attribute.
function Orders.contracts(player)
	publishContracts(player)
	return contractState(player)
end

function Orders.build(parent, position)
	rotate()
	local model = Instance.new("Model")
	model.Name = "OrderBoard"
	model.Parent = parent

	local post = Instance.new("Part")
	post.Name = "Board"
	post.Size = Vector3.new(8, 10, 0.6)
	post.CFrame = CFrame.new(position + Vector3.new(0, 5, 0)) * CFrame.Angles(0, math.rad(90), 0)
	post.Anchored = true
	post.Material = Enum.Material.WoodPlanks
	post.Color = Color3.fromRGB(120, 98, 72)
	post.Parent = model
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(320, 400)
		gui.Parent = post
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(236, 226, 200)
		label.Parent = gui
	end
	board = post
	-- The Blender bounty board (Config/Props bounty_board) when it has been imported. The plank part stays as the
	-- surface the text is drawn on, just in front of the mesh's board, and is the fallback look: each client hides it
	-- only once the mesh has really loaded (Props.weldTo), so the board is never invisible.
	local mesh = Props.make("bounty_board", post.CFrame, Vector3.new(8, 9, 1.5))
	if mesh then
		post.CFrame = post.CFrame * CFrame.new(0, 0, -0.8)
		Props.weldTo(mesh, post, post)
	end

	-- The delivery pad, east of the board (toward camp).
	local pad = Instance.new("Part")
	pad.Name = "OrdersPad"
	pad.Size = Vector3.new(9, 0.4, 9)
	pad.CFrame = CFrame.new(position + Vector3.new(7, 0.2, 0))
	pad.Anchored = true
	pad.Material = Enum.Material.WoodPlanks
	pad.Color = Color3.fromRGB(150, 128, 92)
	pad.Parent = model
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 50)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.MaxDistance = 90
	gui.Parent = pad
	local sign = Instance.new("TextLabel")
	sign.Size = UDim2.fromScale(1, 1)
	sign.BackgroundTransparency = 1
	sign.Font = Enum.Font.GothamBold
	sign.TextScaled = true
	sign.TextColor3 = Color3.new(1, 1, 1)
	sign.TextStrokeTransparency = 0.4
	sign.Text = "DELIVER ORDERS\nSet bales here, or step on with needles"
	sign.Parent = gui

	task.spawn(function()
		local lastText = 0
		while model.Parent do
			task.wait(0.3)
			if os.clock() >= rotateAt then
				rotate()
				lastText = 0
			end
			if os.clock() - lastText > 5 then
				lastText = os.clock()
				local text, back = boardText(), contractsText()
				for _, g in board:GetChildren() do
					if g:IsA("SurfaceGui") then
						g.TextLabel.Text = g.Face == Enum.NormalId.Back and back or text
					end
				end
				-- The contract countdown, and each player's contract lines (new players, and everyone when the day turns).
				ReplicatedStorage:SetAttribute("ContractsResetAt", (today() + 1) * DAY)
				for _, player in Players:GetPlayers() do
					if Data.get(player) and player:GetAttribute("ContractsDay") ~= today() then
						player:SetAttribute("ContractsDay", today())
						publishContracts(player)
					end
				end
			end
			local seenBales, seenPlayers = {}, {}
			for _, part in Workspace:GetPartBoundsInBox(pad.CFrame * CFrame.new(0, 3.5, 0), Vector3.new(9, 7, 9)) do
				local b = Bales.fromPart(part)
				if b and not seenBales[b] then
					seenBales[b] = true
					deliverBale(b)
				end
				local player = part.Parent and Players:GetPlayerFromCharacter(part.Parent)
				if player and not seenPlayers[player] then
					seenPlayers[player] = true
					deliverNeedles(player)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastStep[player] = nil
	end)
	return model
end

-- The current orders (read by SelfTests/Economy).
function Orders.current()
	return offers
end

-- How much of each current order a player has delivered, as { [orderIndex] = count }, and putting it back. The self
-- test uses these so a test run leaves the player's real orders untouched.
function Orders.progress(player)
	local out = {}
	for i in offers do
		out[i] = delivered[i] and delivered[i][player.UserId] or 0
	end
	return out
end

function Orders.setProgress(player, progress)
	for i, count in progress do
		if delivered[i] then
			delivered[i][player.UserId] = count > 0 and count or nil
		end
	end
end

-- Config.PiecesPerBale is the bale size the rest of the game uses; warn if Prices disagrees.
if Config.PiecesPerBale * Config.HayPerPiece ~= Prices.HayPerBale then
	warn("[Needlewood] Prices.HayPerBale doesn't match Config/Game's bale size")
end

return Orders
