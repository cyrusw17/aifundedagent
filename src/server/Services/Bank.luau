--!nonstrict
-- Meadow Savings & Loan. Every dollar a player earns or spends goes through here, so money works one way everywhere.
--
--   Wallet   Sales pay into your wallet. Buying anything takes from your wallet first, then from your bank balance,
--            like paying with a debit card, so money in the bank is always spendable.
--   Bank     Deposit and withdraw at the teller. The bank balance earns savings interest every 10 minutes you are
--            working (Config/Prices Bank).
--   Loans    A truck loan or a land loan for a named item. Put 20% of its price in yourself and the bank deposits the
--            rest. One flat fee is added up front, and a share of every sale repays it until it is gone. No due dates.
--   History  The last 40 transactions, saved with the slot.
--
-- All of it is saved per save slot in Data (state.bank). With Config.InfiniteMoney on, shops are free and the HUD shows
-- the test balance, but the wallet, bank balance, loans and history underneath are real and saved, so the bank can be
-- tested with real numbers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Game)
local Prices = require(Shared.Config.Prices)
local Trucks = require(Shared.Config.Trucks)
local Trailers = require(Shared.Config.Trailers)
local LandConfig = require(Shared.Config.Land)
local Rustic = require(Shared.Config.Rustic)
local Data = require(script.Parent.Data)

local Bank = {}

local Terms = Prices.Bank
local TELLER_REACH = 16
local MERGE_SECONDS = 30 -- sales with the same note this close together share one history line

local tellers = {} -- BaseParts players stand at to use the bank
local openRemote = nil

-- Accounts -----------------------------------------------------------------------------------------------------------

-- A slot's bank account, made on first use. Saved by Data as state.bank.
function Bank.account(state)
	local a = state.bank
	if typeof(a) ~= "table" then
		a = {}
		state.bank = a
	end
	a.balance = typeof(a.balance) == "number" and a.balance or 0
	a.earned = typeof(a.earned) == "number" and a.earned or 0
	a.loans = typeof(a.loans) == "table" and a.loans or {}
	a.history = typeof(a.history) == "table" and a.history or {}
	return a
end
local account = Bank.account

-- The real wallet. With InfiniteMoney on, state.cash holds the test balance and the real one is savedCash.
local function wallet(state)
	return if Config.InfiniteMoney then (state.savedCash or 0) else state.cash
end

local function setWallet(state, value)
	if Config.InfiniteMoney then
		state.savedCash = value
	else
		state.cash = value
	end
end

function Bank.wallet(state)
	return wallet(state)
end

function Bank.spendable(state)
	return wallet(state) + account(state).balance
end

function Bank.owed(state)
	local total = 0
	for _, loan in account(state).loans do
		total += loan.owed
	end
	return total
end

-- How much more the bank will lend: a base line of credit plus twice everything this slot has ever earned, less
-- what is already owed.
function Bank.creditLeft(state)
	local a = account(state)
	return math.max(0, Terms.CreditBase + Terms.CreditPerEarned * a.earned - Bank.owed(state))
end

local function record(state, kind, amount, note)
	local a = account(state)
	local top = a.history[1]
	if top and top.kind == kind and top.note == note and os.time() - top.t <= MERGE_SECONDS and kind == "earn" then
		top.amount += amount
		top.t = os.time()
	else
		table.insert(a.history, 1, { t = os.time(), kind = kind, amount = amount, note = note })
	end
	while #a.history > Terms.HistoryLength do
		table.remove(a.history)
	end
end

local function money(n)
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	out = out:gsub("^,", "")
	return (n < 0 and "-$" or "$") .. out
end
Bank.money = money

-- Earning and spending -----------------------------------------------------------------------------------------------

-- Pays a player for a sale. Running loans take their share first; the rest goes to the wallet. Returns what reached
-- the wallet and what went to loans.
function Bank.earn(player, amount, note)
	local state = player and Data.get(player)
	amount = math.floor(tonumber(amount) or 0)
	if not state or amount <= 0 then
		return 0, 0
	end
	local a = account(state)
	a.earned += amount
	state.lastEarnAt = os.clock()

	local net, repaid = amount, 0
	for _, kind in { "truck", "land" } do
		local loan = a.loans[kind]
		local terms = Terms.Loans[kind]
		if loan and terms and net > 0 then
			local pay = math.min(loan.owed, net, math.max(1, math.floor(amount * terms.repayShare + 0.5)))
			loan.owed -= pay
			net -= pay
			repaid += pay
			if loan.owed <= 0 then
				a.loans[kind] = nil
				record(state, "loan", 0, ("%s for the %s paid off"):format(terms.name, loan.item or "farm"))
				Data.toast(player, ("Your %s is paid off. Every sale is all yours again."):format(terms.name:lower()))
			end
		end
	end
	setWallet(state, wallet(state) + net)
	record(state, "earn", amount, note or "Sale")
	if repaid > 0 then
		record(state, "repay", -repaid, "Loan repayment")
		player:SetAttribute("LoanPaid", repaid)
		player:SetAttribute("LoanPaidId", (player:GetAttribute("LoanPaidId") or 0) + 1)
	end
	Data.sync(player)
	return net, repaid
end

-- Money that is not earnings (a refund, test cash): straight to the wallet, no loan share, no credit.
function Bank.give(player, amount, note)
	local state = player and Data.get(player)
	amount = math.floor(tonumber(amount) or 0)
	if not state or amount <= 0 then
		return
	end
	setWallet(state, wallet(state) + amount)
	record(state, "refund", amount, note or "Refund")
	Data.sync(player)
end

function Bank.canAfford(player, amount)
	local state = Data.get(player)
	if not state then
		return false
	end
	return Config.InfiniteMoney or Bank.spendable(state) >= amount
end

-- Pays for something: wallet first, then the bank balance. Returns ok and, when it fails, a message for the player.
function Bank.charge(player, amount, note)
	local state = player and Data.get(player)
	if not state then
		return false, "Pick a save first."
	end
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return true
	end
	if Config.InfiniteMoney then
		record(state, "test", -amount, (note or "Purchase") .. " (test money)")
		Data.sync(player)
		return true
	end
	local have = Bank.spendable(state)
	if have < amount then
		return false, ("You need %s more."):format(money(amount - have))
	end
	local a = account(state)
	local fromWallet = math.min(wallet(state), amount)
	setWallet(state, wallet(state) - fromWallet)
	a.balance -= amount - fromWallet
	record(state, "spend", -amount, note or "Purchase")
	Data.sync(player)
	return true
end

-- The teller ----------------------------------------------------------------------------------------------------------

local function nearTeller(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, teller in tellers do
		if teller.Parent and (root.Position - teller.Position).Magnitude <= TELLER_REACH then
			return true
		end
	end
	return false
end

local function amountFrom(value, max)
	if value == "all" then
		return math.floor(max)
	end
	local n = tonumber(value)
	if not n or n ~= n or n == math.huge then
		return nil
	end
	return math.floor(math.min(n, max))
end

function Bank.deposit(player, value)
	local state = Data.get(player)
	local amount = state and amountFrom(value, wallet(state))
	if not amount or amount <= 0 then
		return false, "Your wallet is empty."
	end
	setWallet(state, wallet(state) - amount)
	account(state).balance += amount
	record(state, "deposit", amount, "Deposit")
	Data.sync(player)
	return true, ("Deposited %s."):format(money(amount))
end

function Bank.withdraw(player, value)
	local state = Data.get(player)
	local amount = state and amountFrom(value, account(state).balance)
	if not amount or amount <= 0 then
		return false, "There is nothing in your account."
	end
	account(state).balance -= amount
	setWallet(state, wallet(state) + amount)
	record(state, "withdraw", -amount, "Withdrawal")
	Data.sync(player)
	return true, ("Withdrew %s."):format(money(amount))
end

-- What each loan can pay for. Truck loans cover trucks you can buy and trailers you don't own; land loans cover plots
-- while the slot owns none.
local function loanItems(state, kind)
	local items = {}
	if kind == "truck" then
		for _, def in Trucks do
			if def.available and not table.find(state.trucks, def.id) then
				table.insert(items, { id = def.id, name = def.name, price = def.price })
			end
		end
		for _, def in Trailers do
			if not table.find(state.trailers, def.id) then
				table.insert(items, { id = def.id, name = def.name, price = def.price })
			end
		end
	elseif kind == "land" and not (state.land and state.land.owned) then
		for _, def in LandConfig.Plots do
			table.insert(items, { id = def.zone, name = def.name, price = def.price })
		end
	end
	return items
end

-- The deal for one item: down payment, what the bank lends, and what you pay back.
local function offer(kind, item)
	local terms = Terms.Loans[kind]
	local down = math.ceil(item.price * Terms.DownPayment)
	local principal = item.price - down
	return down, principal, math.ceil(principal * (1 + terms.interest))
end

function Bank.takeLoan(player, kind, itemId)
	local state = Data.get(player)
	local terms = Terms.Loans[kind]
	if not state or not terms then
		return false, "The bank doesn't offer that."
	end
	local a = account(state)
	if a.loans[kind] then
		return false, ("Pay off your %s first."):format(terms.name:lower())
	end
	local item = nil
	for _, it in loanItems(state, kind) do
		if it.id == itemId then
			item = it
		end
	end
	if not item then
		return false, "You can't finance that right now."
	end
	local down, principal, payback = offer(kind, item)
	if Bank.spendable(state) < down then
		return false, ("Put %s of your own toward the %s first. You have %s."):format(money(down), item.name, money(Bank.spendable(state)))
	end
	if payback > Bank.creditLeft(state) then
		return false, ("The bank can lend you up to %s right now. Every sale you make raises it."):format(money(Bank.creditLeft(state)))
	end
	a.balance += principal
	a.loans[kind] = { owed = payback, principal = principal, item = item.name, takenAt = os.time() }
	record(state, "loan", principal, ("%s for the %s"):format(terms.name, item.name))
	Data.sync(player)
	return true,
		("Approved! %s is in your account for the %s. You pay back %s, %d%% of each sale until it's done."):format(
			money(principal),
			item.name,
			money(payback),
			math.round(terms.repayShare * 100)
		)
end

-- Pays off as much of a loan as the bank balance, then the wallet, can cover.
function Bank.payLoan(player, kind)
	local state = Data.get(player)
	local a = state and account(state)
	local loan = a and a.loans[kind]
	if not loan then
		return false, "You don't have that loan."
	end
	local pay = math.min(loan.owed, Bank.spendable(state))
	if pay <= 0 then
		return false, "You have no money to pay with."
	end
	local fromBank = math.min(a.balance, pay)
	a.balance -= fromBank
	setWallet(state, wallet(state) - (pay - fromBank))
	loan.owed -= pay
	record(state, "repay", -pay, "Early loan payment")
	local name = Terms.Loans[kind].name
	if loan.owed <= 0 then
		a.loans[kind] = nil
		Data.sync(player)
		return true, ("Your %s is paid off."):format(name:lower())
	end
	Data.sync(player)
	return true, ("Paid %s. You still owe %s."):format(money(pay), money(loan.owed))
end

-- Interest -----------------------------------------------------------------------------------------------------------

function Bank.interestOn(balance)
	local interest, floor = 0, 0
	for _, tier in Terms.InterestTiers do
		if balance > floor then
			interest += (math.min(balance, tier.upTo) - floor) * tier.rate
		end
		floor = tier.upTo
	end
	return math.floor(interest)
end

local function payInterest()
	for _, player in Players:GetPlayers() do
		local state = Data.get(player)
		if state then
			state.interestAt = state.interestAt or os.clock()
			if os.clock() - state.interestAt >= Terms.InterestSeconds then
				state.interestAt = os.clock()
				local working = state.lastEarnAt and os.clock() - state.lastEarnAt <= Terms.InterestSeconds
				local a = account(state)
				local interest = working and Bank.interestOn(a.balance) or 0
				if interest > 0 then
					a.balance += interest
					record(state, "interest", interest, "Savings interest")
					Data.sync(player)
					Data.toast(player, ("The bank paid you %s interest on your savings."):format(money(interest)))
				end
			end
		end
	end
end

-- What the bank panel shows.
function Bank.snapshot(player)
	local state = Data.get(player)
	if not state then
		return nil
	end
	local a = account(state)
	local loans = {}
	for kind, terms in Terms.Loans do
		local loan = a.loans[kind]
		local options = {}
		if not loan then
			for _, item in loanItems(state, kind) do
				local down, principal, payback = offer(kind, item)
				table.insert(options, { id = item.id, name = item.name, price = item.price, down = down, principal = principal, payback = payback })
			end
			table.sort(options, function(x, y)
				return x.price < y.price
			end)
		end
		table.insert(loans, {
			kind = kind,
			name = terms.name,
			blurb = terms.blurb,
			interest = terms.interest,
			repayShare = terms.repayShare,
			owed = loan and loan.owed or 0,
			item = loan and loan.item or nil,
			options = options,
		})
	end
	table.sort(loans, function(x, y)
		return x.kind > y.kind -- truck, then land
	end)
	return {
		wallet = wallet(state),
		balance = a.balance,
		owed = Bank.owed(state),
		creditLeft = Bank.creditLeft(state),
		nextInterest = Bank.interestOn(a.balance),
		interestMinutes = Terms.InterestSeconds / 60,
		tiers = Terms.InterestTiers,
		loans = loans,
		history = a.history,
		testMoney = Config.InfiniteMoney,
		now = os.time(),
	}
end

-- The building ---------------------------------------------------------------------------------------------------------

local function part(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(parent, text, offset, size)
	local gui = Instance.new("BillboardGui")
	gui.Size = size or UDim2.fromOffset(300, 70)
	gui.StudsOffset = offset
	gui.MaxDistance = 140
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
end

-- A small stone-and-plank bank on the main road, east of the plot road, its open front facing north to the road.
-- Bank.SITE matches the flat, clear rect "Bank" in Config/Meadow.
Bank.SITE = Vector3.new(46, 0, 52)

function Bank.build(worldFolder)
	local model = Instance.new("Model")
	model.Name = "Bank"
	model.Parent = worldFolder
	local center = Bank.SITE
	local function at(x, y, z)
		return CFrame.new(center + Vector3.new(x, y, z))
	end
	local W, D, H = 24, 16, 11
	part(model, "Steps", Vector3.new(W + 2, 0.6, D + 4), at(0, 0.3, -1), Rustic.StoneDark, Enum.Material.Cobblestone)
	part(model, "Floor", Vector3.new(W, 0.4, D), at(0, 0.8, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	part(model, "BackWall", Vector3.new(W, H, 1), at(0, H / 2 + 0.6, D / 2 - 0.5), Rustic.Stone, Enum.Material.Brick)
	for _, sx in { -1, 1 } do
		part(model, "SideWall", Vector3.new(1, H, D), at(sx * (W / 2 - 0.5), H / 2 + 0.6, 0), Rustic.Stone, Enum.Material.Brick)
		-- Two front pillars and a wall stub either side of the wide open front.
		part(model, "FrontWall", Vector3.new(6, H, 1), at(sx * (W / 2 - 3), H / 2 + 0.6, -D / 2 + 0.5), Rustic.Stone, Enum.Material.Brick)
		part(model, "Pillar", Vector3.new(1.6, H, 1.6), at(sx * 5.2, H / 2 + 0.6, -D / 2 - 0.6), Rustic.PaintCream, Enum.Material.Concrete)
	end
	part(model, "Lintel", Vector3.new(W + 1, 1.4, 2.4), at(0, H + 0.4, -D / 2), Rustic.PaintCream, Enum.Material.Concrete)
	local roof = part(model, "Roof", Vector3.new(W + 2, 1, D + 3), at(0, H + 1.6, -0.5), Rustic.PaintGreen, Enum.Material.Metal)

	-- Teller counter with brass-coloured bars, and the vault door on the back wall.
	part(model, "Counter", Vector3.new(14, 4, 1.6), at(0, 2.8, 2), Rustic.Wood, Enum.Material.WoodPlanks)
	part(model, "CounterTop", Vector3.new(14.4, 0.3, 2), at(0, 4.95, 2), Rustic.WoodDark, Enum.Material.Wood)
	for i = -3, 3 do
		part(model, "Bar", Vector3.new(0.15, 3, 0.15), at(i * 2, 6.6, 2.2), Rustic.PaintYellow, Enum.Material.Metal)
	end
	part(model, "BarRail", Vector3.new(14, 0.2, 0.2), at(0, 8.1, 2.2), Rustic.PaintYellow, Enum.Material.Metal)
	local vault = part(model, "VaultDoor", Vector3.new(6, 6, 0.6), at(0, 4.4, D / 2 - 1.2), Rustic.Metal, Enum.Material.DiamondPlate)
	vault.Shape = Enum.PartType.Block
	part(model, "VaultWheel", Vector3.new(0.4, 2.4, 2.4), at(0, 4.4, D / 2 - 1.6) * CFrame.Angles(0, math.pi / 2, 0), Rustic.PaintYellow, Enum.Material.Metal).Shape =
		Enum.PartType.Cylinder

	-- The teller window: stand at the counter and press E.
	local window = part(model, "TellerWindow", Vector3.new(4, 3, 0.2), at(0, 6.6, 1.4), Rustic.Glass, Enum.Material.Glass)
	window.Transparency = 0.6
	window.CanCollide = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Bank"
	prompt.ObjectText = "Teller"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = window
	prompt.Triggered:Connect(function(player)
		if openRemote then
			openRemote:FireClient(player)
		end
	end)
	table.insert(tellers, window)

	sign(roof, "MEADOW SAVINGS & LOAN\nSavings, truck loans, land loans", Vector3.new(0, 4, 0))
	return model
end

-- Remotes and the interest clock ---------------------------------------------------------------------------------------

function Bank.start()
	local remotes = Instance.new("Folder")
	remotes.Name = "BankRemotes"
	local request = Instance.new("RemoteFunction")
	request.Name = "Request"
	request.Parent = remotes
	openRemote = Instance.new("RemoteEvent")
	openRemote.Name = "Open"
	openRemote.Parent = remotes
	remotes.Parent = ReplicatedStorage

	local lastRequest = {}
	request.OnServerInvoke = function(player, action, a, b)
		if os.clock() - (lastRequest[player] or 0) < 0.15 then
			return false, nil, Bank.snapshot(player)
		end
		lastRequest[player] = os.clock()
		if not Data.get(player) then
			return false, "Pick a save first.", nil
		end
		local ok, result, message = true, true, nil
		if action ~= "view" then
			if not nearTeller(player) then
				return false, "Walk up to the teller window to do that.", Bank.snapshot(player)
			end
			if action == "deposit" then
				ok, result, message = pcall(Bank.deposit, player, a)
			elseif action == "withdraw" then
				ok, result, message = pcall(Bank.withdraw, player, a)
			elseif action == "loan" and typeof(a) == "string" and typeof(b) == "string" then
				ok, result, message = pcall(Bank.takeLoan, player, a, b)
			elseif action == "payoff" and typeof(a) == "string" then
				ok, result, message = pcall(Bank.payLoan, player, a)
			else
				result, message = false, nil
			end
		end
		if not ok then
			warn("[Needlewood] bank error: " .. tostring(result))
			return false, "The bank's ledger jammed. Try again.", Bank.snapshot(player)
		end
		return result, message, Bank.snapshot(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(15)
			local ok, err = pcall(payInterest)
			if not ok then
				warn("[Needlewood] interest error: " .. tostring(err))
			end
		end
	end)
end

return Bank
