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
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Game)
local Prices = require(Shared.Config.Prices)
local Trucks = require(Shared.Config.Trucks)
local Trailers = require(Shared.Config.Trailers)
local LandConfig = require(Shared.Config.Land)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local Data = require(script.Parent.Data)
local Props = require(script.Parent.Props)

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
	-- Earned by selling, without one-time rewards (Bank.earn). Saves from before it existed count all their earnings.
	a.sold = typeof(a.sold) == "number" and a.sold or a.earned
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

-- Loan money the bank holds for purchases: a loan pays out the item's price (your down payment plus the principal)
-- as shop credit, so it can buy things but can't be withdrawn, traded or paid back into the loan as if it were yours.
function Bank.held(state)
	local total = 0
	for _, loan in account(state).loans do
		total += loan.held or 0
	end
	return total
end

-- Your own money: wallet plus bank balance. Trades, withdrawals, down payments and early loan payments use this.
function Bank.liquid(state)
	return wallet(state) + account(state).balance
end

-- What shops can take: your own money plus any loan money held for purchases.
function Bank.spendable(state)
	return Bank.liquid(state) + Bank.held(state)
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
Bank.record = record -- (state, kind, amount, note): a line in the account history (Rebirth uses it)

-- Earning and spending -----------------------------------------------------------------------------------------------

-- Pays a player for a sale. Running loans take their share first; the rest goes to the wallet. Returns what reached
-- the wallet and what went to loans.
-- One-time rewards (by their history note): they count as earnings for loans and credit, but not as selling, so a
-- fresh slot can't collect them and trade the cash away (Prices.Trade.MinSoldToGiveCash).
local ONE_TIME = { "Secret: ", "Discovered ", "Maze: ", "Quest: ", "Finder's reward" }
local function oneTime(note)
	for _, prefix in ONE_TIME do
		if typeof(note) == "string" and string.sub(note, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

function Bank.earn(player, amount, note)
	local state = player and Data.get(player)
	amount = math.floor(tonumber(amount) or 0)
	if not state or amount <= 0 then
		return 0, 0
	end
	local a = account(state)
	-- Rebirth (Prices.Rebirth): every sale pays Bonus more per rebirth. One-time rewards and test money don't.
	local reborn = typeof(state.rebirth) == "table" and tonumber(state.rebirth.count) or 0
	if reborn > 0 and not oneTime(note) and note ~= "SelfTest" then
		local Rebirth = Prices.Rebirth
		amount = math.floor(amount * (1 + Rebirth.Bonus * math.clamp(math.floor(reborn), 0, Rebirth.Max)) + 0.5)
	end
	a.earned += amount
	if not oneTime(note) then
		a.sold += amount
	end
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
				a.balance += loan.held or 0 -- anything it still held is yours once the loan is paid
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

-- Money that is not earnings (a refund, test cash): to the wallet, no loan share, no credit. While a loan is running,
-- a refund pays it down first: selling back something the bank financed repays the bank before it reaches you, so
-- loan money can't be turned into cash by buying and refunding.
function Bank.give(player, amount, note)
	local state = player and Data.get(player)
	amount = math.floor(tonumber(amount) or 0)
	if not state or amount <= 0 then
		return
	end
	local a = account(state)
	local left = amount
	for _, kind in { "truck", "land" } do
		local loan = a.loans[kind]
		if loan and left > 0 then
			local pay = math.min(loan.owed, left)
			loan.owed -= pay
			left -= pay
			if pay > 0 then
				record(state, "repay", -pay, "Refund toward your " .. Terms.Loans[kind].name:lower())
			end
			if loan.owed <= 0 then
				a.balance += loan.held or 0 -- anything it still held is yours once the loan is paid
				a.loans[kind] = nil
			end
		end
	end
	setWallet(state, wallet(state) + left)
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
	local left = amount
	-- Loan money first (it is only good for purchases), then the wallet, then the bank.
	for _, kind in { "truck", "land" } do
		local loan = a.loans[kind]
		if loan and (loan.held or 0) > 0 and left > 0 then
			local use = math.min(loan.held, left)
			loan.held -= use
			left -= use
		end
	end
	local fromWallet = math.min(wallet(state), left)
	setWallet(state, wallet(state) - fromWallet)
	a.balance -= left - fromWallet
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

-- What each loan can pay for. Truck loans cover trucks you can buy and trailers you don't own; a land loan covers a
-- plot while the slot owns none.
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
		-- Every plot is the same, so the loan is for "a plot" and you pick which one at the Land Office.
		table.insert(items, { id = "plot", name = "farm plot", price = LandConfig.Plots[1].price })
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
	if Bank.liquid(state) < down then
		return false, ("Put %s of your own toward the %s first. You have %s."):format(money(down), item.name, money(Bank.liquid(state)))
	end
	if payback > Bank.creditLeft(state) then
		return false, ("The bank can lend you up to %s right now. Every sale you make raises it."):format(money(Bank.creditLeft(state)))
	end
	-- The down payment leaves your own money, and the bank holds the whole price (down payment plus principal) for
	-- purchases only, so loan money can't be withdrawn or traded away. Real money even with InfiniteMoney on.
	local fromWallet = math.min(wallet(state), down)
	setWallet(state, wallet(state) - fromWallet)
	a.balance -= down - fromWallet
	a.loans[kind] = { owed = payback, principal = principal, held = item.price, item = item.name, takenAt = os.time() }
	record(state, "spend", -down, ("Down payment on the %s"):format(item.name))
	record(state, "loan", principal, ("%s for the %s"):format(terms.name, item.name))
	Data.sync(player)
	return true,
		("Approved! %s is set aside for the %s (your %s down plus the loan). You pay back %s, %d%% of each sale until it's done."):format(
			money(item.price),
			item.name,
			money(down),
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
	-- Loan money not yet spent goes back to the bank first.
	local unspent = math.min(loan.held or 0, loan.owed)
	if unspent > 0 then
		loan.held -= unspent
		loan.owed -= unspent
		record(state, "repay", -unspent, "Unspent loan money returned")
	end
	local pay = math.min(loan.owed, Bank.liquid(state))
	if pay <= 0 and unspent <= 0 then
		return false, "You have no money to pay with."
	end
	local fromBank = math.min(a.balance, pay)
	a.balance -= fromBank
	setWallet(state, wallet(state) - (pay - fromBank))
	loan.owed -= pay
	if pay > 0 then
		record(state, "repay", -pay, "Early loan payment")
	end
	local name = Terms.Loans[kind].name
	if loan.owed <= 0 then
		a.balance += loan.held or 0
		a.loans[kind] = nil
		Data.sync(player)
		return true, ("Your %s is paid off."):format(name:lower())
	end
	Data.sync(player)
	return true, ("Paid %s. You still owe %s."):format(money(pay + unspent), money(loan.owed))
end

-- Trades -------------------------------------------------------------------------------------------------------------

-- What one side of a trade pays the post: nothing for a side that only hands over items (so a new player can always
-- give a needle away), else the flat fee plus a share of the cash it gives. Free with InfiniteMoney on.
function Bank.tradeFee(cashGiven)
	cashGiven = math.max(0, tonumber(cashGiven) or 0)
	if Config.InfiniteMoney or cashGiven <= 0 then
		return 0
	end
	local t = Prices.Trade
	return math.floor(t.Fee + cashGiven * t.CashShare + 0.5)
end

-- Settles the money side of a trade both players have confirmed, and logs it in both histories. Land's trading post
-- calls it once, after the countdown and before it swaps the items:
--
--   local ok, why = Bank.settleTrade(a, b, { aGives = "3 Cosmic needles", bGives = "a Fossil", aCash = 0, bCash = 500 })
--   if not ok then cancel the trade and show why end
--
-- aGives / bGives describe the items for the history (cash is added to the line here). aCash / bCash are dollars each
-- side hands over (optional). Each side also pays Bank.tradeFee on what it gives. Nothing moves unless both sides can
-- pay, so on false the trade is cancelled with no money changed. Cash comes from the wallet first, then the bank, and
-- lands in the other side's wallet. It is not earnings: no loan share and no credit.
function Bank.settleTrade(a, b, terms)
	terms = terms or {}
	local sa, sb = a and Data.get(a), b and Data.get(b)
	if not sa or not sb or a == b then
		return false, "Both traders need a save loaded."
	end
	local function cash(v)
		v = tonumber(v) or 0
		if v ~= v or v == math.huge or v < 0 then
			return nil
		end
		return math.floor(v)
	end
	local aCash, bCash = cash(terms.aCash), cash(terms.bCash)
	if not aCash or not bCash then
		return false, "That amount of cash isn't valid."
	end
	local need = Prices.Trade.MinSoldToGiveCash or 0
	for _, side in { { a, sa, aCash }, { b, sb, bCash } } do
		if side[3] > 0 and not Config.InfiniteMoney and account(side[2]).sold < need then
			return false,
				("%s can trade items, but can't hand over cash until this farm has sold %s worth."):format(side[1].DisplayName, money(need))
		end
	end
	local aOwes, bOwes = aCash + Bank.tradeFee(aCash), bCash + Bank.tradeFee(bCash)
	-- Only your own money trades; loan money held for purchases doesn't (Bank.held).
	if Bank.liquid(sa) < aOwes then
		return false, ("%s needs %s more for this trade."):format(a.DisplayName, money(aOwes - Bank.liquid(sa)))
	end
	if Bank.liquid(sb) < bOwes then
		return false, ("%s needs %s more for this trade."):format(b.DisplayName, money(bOwes - Bank.liquid(sb)))
	end

	local function pay(state, amount)
		local fromWallet = math.min(wallet(state), amount)
		setWallet(state, wallet(state) - fromWallet)
		account(state).balance -= amount - fromWallet
	end
	pay(sa, aOwes)
	pay(sb, bOwes)
	setWallet(sa, wallet(sa) + bCash)
	setWallet(sb, wallet(sb) + aCash)

	local function side(gives, givesCash)
		local parts = {}
		if gives and gives ~= "" then
			table.insert(parts, gives)
		end
		if givesCash > 0 then
			table.insert(parts, money(givesCash))
		end
		return #parts > 0 and table.concat(parts, " + ") or "nothing"
	end
	local aSide, bSide = side(terms.aGives, aCash), side(terms.bGives, bCash)
	local function log(player, state, other, gave, got, delta, fee)
		record(state, "trade", delta, ("Trade with %s: gave %s, got %s"):format(other.DisplayName, gave, got))
		if fee > 0 then
			record(state, "spend", -fee, "Trading post fee")
		end
		Data.sync(player)
	end
	log(a, sa, b, aSide, bSide, bCash - aCash, aOwes - aCash)
	log(b, sb, a, bSide, aSide, aCash - bCash, bOwes - bCash)
	return true
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
		held = Bank.held(state), -- loan money set aside for purchases
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

-- Floating text goes through the shared WorldLabel helper.
local function sign(parent, text, offset)
	return WorldLabel.billboard(parent, text, { offset = offset, kind = "sign" })
end

-- Makes any part a teller window: press E there to open the bank panel. Other buildings (a Homestead branch, an ATM)
-- can call this with their own part; all tellers share the same accounts.
function Bank.addTeller(window)
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
	CollectionService:AddTag(window, "BankTeller")
	table.insert(tellers, window)
	return prompt
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
	local shell = {} -- the part-built bank the Blender mesh replaces; the counter and the teller window stay
	local function piece(...)
		local p = part(...)
		table.insert(shell, p)
		return p
	end
	piece(model, "Steps", Vector3.new(W + 2, 0.6, D + 4), at(0, 0.3, -1), Rustic.StoneDark, Enum.Material.Cobblestone)
	piece(model, "Floor", Vector3.new(W, 0.4, D), at(0, 0.8, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	piece(model, "BackWall", Vector3.new(W, H, 1), at(0, H / 2 + 0.6, D / 2 - 0.5), Rustic.Stone, Enum.Material.Brick)
	for _, sx in { -1, 1 } do
		piece(model, "SideWall", Vector3.new(1, H, D), at(sx * (W / 2 - 0.5), H / 2 + 0.6, 0), Rustic.Stone, Enum.Material.Brick)
		-- Two front pillars and a wall stub either side of the wide open front.
		piece(model, "FrontWall", Vector3.new(6, H, 1), at(sx * (W / 2 - 3), H / 2 + 0.6, -D / 2 + 0.5), Rustic.Stone, Enum.Material.Brick)
		piece(model, "Pillar", Vector3.new(1.6, H, 1.6), at(sx * 5.2, H / 2 + 0.6, -D / 2 - 0.6), Rustic.PaintCream, Enum.Material.Concrete)
	end
	piece(model, "Lintel", Vector3.new(W + 1, 1.4, 2.4), at(0, H + 0.4, -D / 2), Rustic.PaintCream, Enum.Material.Concrete)
	local roof = piece(model, "Roof", Vector3.new(W + 2, 1, D + 3), at(0, H + 1.6, -0.5), Rustic.PaintGreen, Enum.Material.Metal)

	-- Teller counter with brass-coloured bars, and the vault door on the back wall.
	part(model, "Counter", Vector3.new(14, 4, 1.6), at(0, 2.8, 2), Rustic.Wood, Enum.Material.WoodPlanks)
	part(model, "CounterTop", Vector3.new(14.4, 0.3, 2), at(0, 4.95, 2), Rustic.WoodDark, Enum.Material.Wood)
	for i = -3, 3 do
		part(model, "Bar", Vector3.new(0.15, 3, 0.15), at(i * 2, 6.6, 2.2), Rustic.PaintYellow, Enum.Material.Metal)
	end
	part(model, "BarRail", Vector3.new(14, 0.2, 0.2), at(0, 8.1, 2.2), Rustic.PaintYellow, Enum.Material.Metal)
	local vault = piece(model, "VaultDoor", Vector3.new(6, 6, 0.6), at(0, 4.4, D / 2 - 1.2), Rustic.Metal, Enum.Material.DiamondPlate)
	vault.Shape = Enum.PartType.Block
	piece(model, "VaultWheel", Vector3.new(0.4, 2.4, 2.4), at(0, 4.4, D / 2 - 1.6) * CFrame.Angles(0, math.pi / 2, 0), Rustic.PaintYellow, Enum.Material.Metal).Shape =
		Enum.PartType.Cylinder

	-- The teller window: stand at the counter and press E.
	local window = part(model, "TellerWindow", Vector3.new(4, 3, 0.2), at(0, 6.6, 1.4), Rustic.Glass, Enum.Material.Glass)
	window.Transparency = 0.6
	window.CanCollide = false
	Bank.addTeller(window)

	-- The Blender bank (Config/Props homestead_bank, hub.py: 26 x 20 walls 0.8 thick, a 5 x 8.5 front door, its
	-- own vault behind the left window), front facing -Z like this one, its steps where these steps start. It is
	-- only a look, so while it shows the walls you bump into are rebuilt to its shape (door, not the open front);
	-- each client keeps the part bank until the mesh has really loaded.
	local mesh = Props.make("homestead_bank", at(0, 13, 0))
	if mesh then
		for _, door in Props.find(mesh, "Door") do
			door:Destroy() -- the doorway stands open
		end
		local box, size = mesh:GetBoundingBox()
		mesh:PivotTo(mesh:GetPivot() + Vector3.new(center.X - box.X, 0, (center.Z - D / 2 - 3) - (box.Z - size.Z / 2)))
		Props.restOn(mesh, center.Y)
		mesh.Parent = model
		Props.weldTo(mesh, roof, shell)
		for _, p in shell do
			p.CanCollide = false
		end
		-- Its walls, centered 12.9 studs behind the front of its steps.
		local walls = Instance.new("Folder")
		walls.Name = "Walls"
		walls.Parent = model
		local function wall(size, x, y, z)
			local p = part(walls, "Wall", size, at(x, y, z + 2), Rustic.Stone)
			p.Transparency = 1
		end
		wall(Vector3.new(27, 0.8, 21), 0, 0.4, 0) -- floor slab
		wall(Vector3.new(10.5, 20, 0.8), -7.75, 10.8, -9.6) -- front, either side of the door
		wall(Vector3.new(10.5, 20, 0.8), 7.75, 10.8, -9.6)
		wall(Vector3.new(5, 11.5, 0.8), 0, 15.05, -9.6) -- over the door
		wall(Vector3.new(26, 20, 0.8), 0, 10.8, 9.6)
		wall(Vector3.new(0.8, 20, 20), -12.6, 10.8, 0)
		wall(Vector3.new(0.8, 20, 20), 12.6, 10.8, 0)
		for _, x in { -3.8, 3.8 } do
			wall(Vector3.new(1.2, 9, 1.2), x, 5.3, -12) -- the porch columns
		end
	end

	sign(roof, "MEADOW SAVINGS & LOAN\nSavings, truck loans, land loans", Vector3.new(0, mesh and 16 or 4, 0))
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

	-- Other bank buildings (the Homestead branch on the world map) tag their counter "BankCounter".
	for _, counter in CollectionService:GetTagged("BankCounter") do
		Bank.addTeller(counter)
	end
	CollectionService:GetInstanceAddedSignal("BankCounter"):Connect(Bank.addTeller)

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
