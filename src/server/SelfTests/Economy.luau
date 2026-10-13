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
		local HayMarket = require(Services.HayMarket)
		local Bales = require(Services.Bales)

		-- Hay Market prices sit below what each rare bale is worth on a conveyor sorter, so it's a bonus for a line.
		local badMarket = {}
		for kindId in Prices.HayMarket.Kinds do
			for hayType in Prices.HayMarket.HayTypes do
				local price, value = HayMarket.priceOf(kindId, hayType), HayMarket.valueOf(kindId, hayType)
				if not (price > 0 and price < value) then
					table.insert(badMarket, ("%s %s: $%s for $%s"):format(kindId, hayType, tostring(price), tostring(value)))
				end
			end
		end
		t.check("every Hay Market price is under its bale's value", #badMarket == 0, #badMarket > 0 and table.concat(badMarket, "; ") or nil)

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
				t.equal("taking a loan charges the down payment", Bank.wallet(state), 0)
				t.equal("loan money doesn't land in the bank balance", Bank.account(state).balance, 0)
				t.equal("so it earns no savings interest", Bank.interestOn(Bank.account(state).balance), 0)
				t.equal("the bank holds the whole price for purchases", Bank.held(state), truck.price)
				t.equal("so shops can spend the price", Bank.spendable(state), truck.price)
				t.equal("but it isn't your own money", Bank.liquid(state), 0)
				t.check("loan money can't be withdrawn", not Bank.withdraw(player, "all"))
				t.equal("payback is principal plus the fee", loan.owed, math.ceil(principal * (1 + terms.interest)))
				t.check("a second truck loan is refused", not Bank.takeLoan(player, "truck", truck.id))
				t.check("loan money buys the truck", (Bank.charge(player, truck.price, "SelfTest truck")))
				t.equal("which spends what the bank held", Bank.held(state), 0)
				t.equal("and none of your own", Bank.liquid(state), 0)
				local owedBefore = loan.owed
				local got, paid = Bank.earn(player, 1000, "SelfTest sale")
				t.equal("a sale repays the loan's share", paid, math.floor(1000 * terms.repayShare + 0.5))
				t.equal("and the rest reaches the wallet", got, 1000 - paid)
				t.equal("the loan shrinks by the repayment", loan.owed, owedBefore - paid)
				local walletBefore, owedNow = Bank.wallet(state), loan.owed
				Bank.give(player, 100, "SelfTest refund")
				t.equal("a refund pays the loan down first", loan.owed, owedNow - 100)
				t.equal("so none of it reaches the wallet", Bank.wallet(state), walletBefore)
				local sales = 0
				while Bank.account(state).loans.truck and sales < 1000 do
					Bank.earn(player, 1000, "SelfTest sale")
					sales += 1
				end
				t.check("sales pay the loan off", Bank.account(state).loans.truck == nil, ("%d more sales"):format(sales))
				t.equal("nothing is owed afterwards", Bank.owed(state), 0)
			end

			-- Paying a loan off early: loan money not yet spent goes back first.
			reset(0, 10000)
			Bank.give(player, down, "SelfTest down payment")
			if Bank.takeLoan(player, "truck", truck.id) then
				local owed = Bank.account(state).loans.truck.owed
				t.check("pay off early with the unspent loan money", (Bank.payLoan(player, "truck")))
				t.equal("an early payoff clears the loan", Bank.account(state).loans.truck, nil)
				t.equal("what the loan held beyond the payback comes back to you", Bank.liquid(state), truck.price - owed)
			end

			-- One-time rewards count as earnings but not as selling (the trade cash gate).
			reset(0)
			Bank.earn(player, 500, "Hay shop")
			Bank.earn(player, 2000, "Secret: SelfTest")
			Bank.earn(player, 300, "Discovered SelfTest")
			t.equal("all of it counts as earned", Bank.account(state).earned, 2800)
			t.equal("only sales count as sold", Bank.account(state).sold, 500)

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
					if left > 1 then
						-- A part-full sorted bale pays for the hay it holds.
						local mid = Bank.wallet(state)
						took += Orders.fill(player, offer.kind, 1, 0.1)
						t.equal(("%s order pays a tenth for a tenth-full bale"):format(offer.kind), Bank.wallet(state) - mid, math.floor(offer.rate * 0.1 + 0.5))
					end
					local rest = Orders.fill(player, offer.kind, offer.amount + 50)
					t.equal(("%s order stops at its amount"):format(offer.kind), took + rest, math.max(0, left))
					t.equal(("%s order is full"):format(offer.kind), Orders.fill(player, offer.kind, 1), 0)
				end
				Orders.setProgress(player, progress)
			end

			-- Daily contracts: deliveries pay their normal price, a finished contract pays the tier's reward once. The
			-- all-three bonus is marked paid first so the test doesn't count a real streak day; the player's own contracts
			-- are put back afterwards.
			local savedContracts = state.contracts
			state.contracts = nil
			reset(0)
			local c, list = Orders.contracts(player)
			t.check("today's contracts exist", c ~= nil and #list == 3)
			if c then
				c.bonus = true
				local tier = Prices.DailyContracts.Tiers[c.tier]
				local def = list[1]
				local unit = def.kind == "needles" and Prices.Needles[def.needle]
					or def.kind == "sorted" and Prices.HayPerBale * Prices.HayPrice
					or Prices.HayPerBale * Prices.HayPrice + Prices.NeedlesPerBale.meadow * Prices.RawNeedlePrice
				local before = Bank.wallet(state)
				t.equal("a contract takes what it asks for", Orders.fillContract(player, def.kind, def.amount + 5), def.amount)
				t.equal("pays the goods' price plus the reward", Bank.wallet(state) - before, math.floor(unit * def.amount + 0.5) + tier.reward)
				t.check("and is marked done", c.paid[1] == true and string.find(player:GetAttribute("Contracts") or "", "(done)", 1, true) ~= nil)
				local after = Bank.wallet(state)
				local more = Orders.fillContract(player, def.kind, 3) -- goes to another contract of the same kind, if any
				t.equal("a done contract never pays its reward twice", Bank.wallet(state) - after, math.floor(unit * more + 0.5))
				t.check("the reset countdown is set", (game:GetService("ReplicatedStorage"):GetAttribute("ContractsResetAt") or 0) > os.time() or #Orders.current() == 0)
			end
			state.contracts = savedContracts
			Orders.contracts(player)

			-- The Hay Market: a purchase charges the price, takes one from stock, hands over a marked bale, and stops at
			-- the per-restock cap. A restock afterwards puts the stall back for real players.
			local stall = HayMarket.slots()
			if #stall == 0 then
				t.skip("hay market", "the stall hasn't been built")
			else
				HayMarket.restock()
				t.equal("a restock fills every slot", stall[1].stock, Prices.HayMarket.StockPerSlot)
				t.check("and sets the countdown", (game:GetService("ReplicatedStorage"):GetAttribute("HayMarketRestockAt") or 0) > workspace:GetServerTimeNow())
				reset(1000000)
				local slot = stall[1]
				local price, stock = slot.price, slot.stock
				local okBuy, buyMsg, bale = HayMarket.buy(player, 1)
				t.check("buying a rare bale works", okBuy, buyMsg)
				t.equal("it charges the price", 1000000 - Bank.spendable(state), price)
				t.equal("it takes one from stock", slot.stock, stock - 1)
				t.check("the bale is marked with its kind", bale ~= nil and bale.body:GetAttribute("RareBale") == slot.kindId)
				t.equal("and belongs to the buyer", bale and bale.ownerId, player.UserId)
				local spent = { bale }
				for _ = 2, Prices.HayMarket.PerPlayer do
					local _, _, more = HayMarket.buy(player, 1)
					spent[#spent + 1] = more
				end
				t.check("the per-restock cap holds", not HayMarket.buy(player, 2))
				for i = 1, Prices.HayMarket.PerPlayer do
					if spent[i] then
						Bales.consume(spent[i])
					end
				end
				HayMarket.restock()
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
