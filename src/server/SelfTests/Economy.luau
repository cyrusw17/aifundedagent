--!nonstrict
-- Economy and banking suite: prices are sane, money moves through the Bank correctly (earn, charge, give, deposit,
-- withdraw, loans and their repayment from sales), interest tiers, the needle market stays in its band, and NPC orders
-- pay and stop at their amount. The player tests borrow the first player's loaded save slot and put every balance back
-- afterwards, so a test run never changes a real save. They run with InfiniteMoney switched off for the duration.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent.Parent.Services
local Shared = ReplicatedStorage:WaitForChild("Shared")

-- Prices that are meant to be free.
local FREE = { ["Prices.Gloves.bare"] = true, ["Prices.Travel.barge"] = true }

local function deepCopy(v)
	if typeof(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

return function(SelfTest)
	SelfTest.register("Economy", function(t)
		local Prices = require(Shared.Config.Prices)
		local Config = require(Shared.Config.Game)
		local Data = require(Services.Data)
		local Bank = require(Services.Bank)
		local Market = require(Services.Market)
		local TruckConfig = require(Shared.Config.Trucks)
		local Orders = require(Services.Orders)

		-- Every price is a finite number above zero (the intentionally free ones may be zero).
		local bad = {}
		local function walk(tbl, path)
			for k, v in tbl do
				local here = path .. "." .. tostring(k)
				if typeof(v) == "number" then
					local finite = v == v and v ~= math.huge and v ~= -math.huge
					if not finite or v < 0 or (v == 0 and not FREE[here]) then
						table.insert(bad, here .. "=" .. tostring(v))
					end
				elseif typeof(v) == "table" then
					walk(v, here)
				end
			end
		end
		walk(Prices, "Prices")
		t.check("every Prices number is finite and positive", #bad == 0, #bad > 0 and table.concat(bad, ", ") or nil)
		for hay, n in Prices.NeedlesPerBale do
			local chance = Prices.needleChance(hay)
			t.check(("needleChance(%s) is a probability"):format(hay), chance > 0 and chance < 1, ("%s needles -> %s"):format(n, chance))
		end

		-- Interest tiers: 1% on the first $10k, 0.5% to $100k, nothing above.
		t.equal("interest on $0", Bank.interestOn(0), 0)
		t.equal("interest on $10,000", Bank.interestOn(10000), 100)
		t.equal("interest on $100,000", Bank.interestOn(100000), 550)
		t.equal("interest on $5,000,000 is capped", Bank.interestOn(5000000), 550)

		-- The needle market stays within list price +/- Swing, whatever is sold. A made-up id keeps real prices untouched.
		local swing = Prices.Market.Swing
		local id = "selftest_needle"
		t.near("an unsold type pays the top of the band", Market.multiplier(id), 1 + swing, 1e-6)
		local lowest, highest = math.huge, -math.huge
		for _, count in { 1, 5, 40, 500, 1e6 } do
			Market.sold(id, count)
			local m = Market.multiplier(id)
			lowest, highest = math.min(lowest, m), math.max(highest, m)
		end
		t.check(
			"market multiplier stays in band",
			lowest >= 1 - swing - 1e-9 and highest <= 1 + swing + 1e-9,
			("%.3f .. %.3f"):format(lowest, highest)
		)
		t.check("a flooded type pays less than an unsold one", lowest < 1, ("%.3f"):format(lowest))
		t.equal("multiplier of no id is 1", Market.multiplier(nil), 1)

		local player = t.player(10)
		if not player then
			t.skip("bank and orders", "no player joined")
			return
		end
		local deadline = os.clock() + 20
		while not Data.get(player) and os.clock() < deadline do
			task.wait(0.25)
		end
		local state = Data.get(player)
		if not state then
			t.skip("bank and orders", "the player hasn't picked a save slot")
			return
		end

		-- Borrow the slot: remember everything the tests touch and put it back at the end, even if a test errors.
		local saved = {
			cash = state.cash,
			savedCash = state.savedCash,
			bank = deepCopy(state.bank),
			lastEarnAt = state.lastEarnAt,
			interestAt = state.interestAt,
			trucks = deepCopy(state.trucks),
			trailers = deepCopy(state.trailers),
		}
		local infinite = Config.InfiniteMoney
		local function reset(cash, earned)
			state.cash = cash
			state.bank = nil
			Bank.account(state).earned = earned or 0
		end

		local ok, err = xpcall(function()
			Config.InfiniteMoney = false
			state.interestAt = os.clock() -- keep the interest loop from paying out mid-test
			reset(0)

			-- Earn, charge, give.
			local net, repaid = Bank.earn(player, 1000, "SelfTest sale")
			t.equal("earn with no loan pays it all", net, 1000)
			t.equal("earn with no loan repays nothing", repaid, 0)
			t.equal("wallet after earning $1,000", Bank.wallet(state), 1000)
			t.equal("lifetime earned counts the sale", Bank.account(state).earned, 1000)
			t.check("charge $400 succeeds", (Bank.charge(player, 400, "SelfTest buy")))
			t.equal("wallet after the charge", Bank.wallet(state), 600)
			Bank.give(player, 50, "SelfTest refund")
			t.equal("wallet after a $50 refund", Bank.wallet(state), 650)
			t.equal("a refund doesn't count as earnings", Bank.account(state).earned, 1000)
			t.equal("the Cash attribute is wallet + bank", player:GetAttribute("Cash"), 650)

			-- Charging more than you have is refused and takes nothing.
			local okShort, msg = Bank.charge(player, 10000, "SelfTest too much")
			t.check("charge refuses when funds are short", not okShort, msg)
			t.equal("a refused charge takes nothing", Bank.spendable(state), 650)
			t.check("canAfford agrees", not Bank.canAfford(player, 10000))

			-- Deposit and withdraw; a charge spends the wallet first, then the bank.
			t.check("deposit $500", (Bank.deposit(player, 500)))
			t.equal("wallet after depositing", Bank.wallet(state), 150)
			t.equal("bank after depositing", Bank.account(state).balance, 500)
			t.check("withdraw $200", (Bank.withdraw(player, 200)))
			t.equal("bank after withdrawing", Bank.account(state).balance, 300)
			t.check("deposit all", (Bank.deposit(player, "all")))
			t.equal("wallet is empty after deposit all", Bank.wallet(state), 0)
			t.check("withdrawing $0 is refused", not Bank.withdraw(player, 0))
			t.check("charge $100 from the bank", (Bank.charge(player, 100, "SelfTest bank buy")))
			t.equal("the bank paid it", Bank.account(state).balance, 550)
			t.check("bad amounts are refused", not Bank.deposit(player, "lots") and not Bank.deposit(player, 0 / 0))

			-- A truck loan: down payment from your own money, then repaid out of sales until it is gone.
			-- Some lifetime earnings so the bank's credit line covers the truck.
			reset(0, 10000)
			state.trucks = {}
			state.trailers = {}
			local truck = nil
			for _, def in TruckConfig do
				if def.available and (not truck or def.price < truck.price) then
					truck = { id = def.id, price = def.price }
				end
			end
			local terms = Prices.Bank.Loans.truck
			local down = math.ceil(truck.price * Prices.Bank.DownPayment)
			t.check("no loan without the down payment", not Bank.takeLoan(player, "truck", truck.id))
			Bank.give(player, down, "SelfTest down payment")
			local okLoan, loanMsg = Bank.takeLoan(player, "truck", truck.id)
			t.check(("truck loan for the %s is approved"):format(truck.id), okLoan, loanMsg)
			local loan = Bank.account(state).loans.truck
			if loan then
				local principal = truck.price - down
				t.equal("the loan puts the principal in the bank", Bank.account(state).balance, principal)
				t.equal("payback is principal plus the fee", loan.owed, math.ceil(principal * (1 + terms.interest)))
				t.check("a second truck loan is refused", not Bank.takeLoan(player, "truck", truck.id))
				local owedBefore = loan.owed
				local got, paid = Bank.earn(player, 1000, "SelfTest sale")
				t.equal("a sale repays the loan's share", paid, math.floor(1000 * terms.repayShare + 0.5))
				t.equal("and the rest reaches the wallet", got, 1000 - paid)
				t.equal("the loan shrinks by the repayment", loan.owed, owedBefore - paid)
				local sales = 0
				while Bank.account(state).loans.truck and sales < 1000 do
					Bank.earn(player, 1000, "SelfTest sale")
					sales += 1
				end
				t.check("sales pay the loan off", Bank.account(state).loans.truck == nil, ("%d more sales"):format(sales))
				t.equal("nothing is owed afterwards", Bank.owed(state), 0)
			end

			-- Paying a loan off early from the bank.
			reset(0, 10000)
			Bank.give(player, down, "SelfTest down payment")
			if Bank.takeLoan(player, "truck", truck.id) then
				Bank.give(player, truck.price * 2, "SelfTest cash")
				t.check("pay off early", (Bank.payLoan(player, "truck")))
				t.equal("an early payoff clears the loan", Bank.account(state).loans.truck, nil)
			end

			-- Trading post fees (a real two-player trade needs a second player, so only the rules are checked here).
			local trade = Prices.Trade
			t.equal("an items-only side pays no trade fee", Bank.tradeFee(0), 0)
			t.equal("trade fee on $1,000 cash", Bank.tradeFee(1000), math.floor(trade.Fee + 1000 * trade.CashShare + 0.5))
			reset(500)
			t.check("a player can't trade with themselves", not Bank.settleTrade(player, player, { aCash = 10 }))
			t.equal("a refused trade moves nothing", Bank.spendable(state), 500)

			-- NPC orders: each one pays its rate per unit and stops at its amount.
			reset(0)
			local offers = Orders.current()
			if #offers == 0 then
				t.skip("orders", "the order board hasn't been built")
			else
				local progress = Orders.progress(player)
				for i, offer in offers do
					local left = offer.amount - (progress[i] or 0)
					local before = Bank.wallet(state)
					local took = Orders.fill(player, offer.kind, 1)
					if left > 0 then
						t.equal(("%s order takes one"):format(offer.kind), took, 1)
						t.equal(("%s order pays its rate"):format(offer.kind), Bank.wallet(state) - before, offer.rate)
					end
					local rest = Orders.fill(player, offer.kind, offer.amount + 50)
					t.equal(("%s order stops at its amount"):format(offer.kind), took + rest, math.max(0, left))
					t.equal(("%s order is full"):format(offer.kind), Orders.fill(player, offer.kind, 1), 0)
				end
				Orders.setProgress(player, progress)
			end
		end, debug.traceback)
		if not ok then
			t.check("economy tests ran without errors", false, err)
		end

		-- Put the slot back exactly as it was.
		Config.InfiniteMoney = infinite
		state.cash = saved.cash
		state.savedCash = saved.savedCash
		state.bank = saved.bank
		state.lastEarnAt = saved.lastEarnAt
		state.interestAt = saved.interestAt
		state.trucks = saved.trucks
		state.trailers = saved.trailers
		Data.sync(player)
	end)
end
