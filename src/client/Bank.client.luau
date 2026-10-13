--!nonstrict
-- The bank: a small wallet / bank line under the HUD, and the teller panel (Account, Loans, History) that opens at the
-- Meadow Savings & Loan window. The server (Bank.luau) decides everything; this only shows it and sends requests.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("BankRemotes")
local request = remotes:WaitForChild("Request")
local openRemote = remotes:WaitForChild("Open")

-- Colors from the shared Rustic theme (UI/Theme.luau): a dark wood panel with cream text.
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Theme"))
local DARK = Theme.Colors.Ink
local PANEL = Theme.Colors.Wood
local ROW = Theme.Colors.WoodLight
local CREAM = Theme.Colors.Cream
local MUTED = Color3.fromRGB(214, 202, 172)
local GREEN = Theme.Colors.Cash
local RED = Color3.fromRGB(240, 150, 128)
local BRASS = Theme.Colors.Hay

local function money(n)
	n = math.floor(n or 0)
	local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (n < 0 and "-$" or "$") .. s
end

local gui = Instance.new("ScreenGui")
gui.Name = "Bank"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function label(parent, text, size, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color or CREAM
	l.Font = font or Enum.Font.GothamBold
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function button(parent, text, color)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = color or BRASS
	b.Text = text
	b.TextSize = 15
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = DARK
	b.AutoButtonColor = true
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

-- HUD line under the main panel ----------------------------------------------------------------------------------------

local Hud = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Hud"))
local chip = Instance.new("Frame")
chip.LayoutOrder = Hud.Order.Bank -- in the HUD column under the cash card (UI/Hud.luau)
chip.Size = UDim2.fromOffset(230, 26)
chip.BackgroundColor3 = DARK
chip.BackgroundTransparency = 0.25
chip.Visible = false
chip.Parent = Hud.column()
Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 8)
local chipText = label(chip, "", 13, MUTED)
chipText.Position = UDim2.fromOffset(10, 0)
chipText.Size = UDim2.new(1, -20, 1, 0)

-- Shows over the chip for a moment (inside it, so it never spills onto the goal bar below in the HUD column).
local flash = label(chip, "", 13, RED)
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = DARK
flash.BackgroundTransparency = 1
flash.ZIndex = 2
flash.TextTransparency = 1
Instance.new("UICorner", flash).CornerRadius = UDim.new(0, 8)
local flashPad = Instance.new("UIPadding")
flashPad.PaddingLeft = UDim.new(0, 10)
flashPad.Parent = flash

local function refreshChip()
	local wallet = player:GetAttribute("Wallet")
	if wallet == nil then
		chip.Visible = false
		return
	end
	chip.Visible = true
	local text = ("Wallet %s   Bank %s"):format(money(wallet), money(player:GetAttribute("BankBalance") or 0))
	local owed = player:GetAttribute("LoanOwed") or 0
	if owed > 0 then
		text ..= ("   Loan %s"):format(money(owed))
	end
	chipText.Text = text
end
for _, name in { "Wallet", "BankBalance", "LoanOwed" } do
	player:GetAttributeChangedSignal(name):Connect(refreshChip)
end
refreshChip()

player:GetAttributeChangedSignal("LoanPaidId"):Connect(function()
	flash.Text = ("%s went to your loan"):format(money(player:GetAttribute("LoanPaid") or 0))
	flash.TextTransparency = 0
	flash.BackgroundTransparency = 0
	TweenService
		:Create(flash, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, BackgroundTransparency = 1 })
		:Play()
end)

-- Teller panel ------------------------------------------------------------------------------------------------------

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(560, 440)
panel.BackgroundColor3 = PANEL
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = BRASS
stroke.Thickness = 2

local title = label(panel, "MEADOW SAVINGS & LOAN", 22, BRASS)
title.Position = UDim2.fromOffset(18, 10)
title.Size = UDim2.new(1, -80, 0, 30)
local close = button(panel, "X", RED)
close.Position = UDim2.new(1, -44, 0, 10)
close.Size = UDim2.fromOffset(32, 32)

local status = label(panel, "", 14, GREEN, Enum.Font.Gotham)
status.Position = UDim2.new(0, 18, 1, -34)
status.Size = UDim2.new(1, -36, 0, 26)

local tabs, pages = {}, {}
local function page(name, x)
	local tab = button(panel, name, ROW)
	tab.TextColor3 = CREAM
	tab.Position = UDim2.fromOffset(18 + x, 48)
	tab.Size = UDim2.fromOffset(120, 30)
	local frame = Instance.new("ScrollingFrame")
	frame.Position = UDim2.fromOffset(18, 88)
	frame.Size = UDim2.new(1, -36, 1, -128)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ScrollBarThickness = 6
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.CanvasSize = UDim2.new()
	frame.Visible = false
	frame.Parent = panel
	local layout = Instance.new("UIListLayout", frame)
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	tabs[name], pages[name] = tab, frame
	return frame
end
local accountPage = page("Account", 0)
local loansPage = page("Loans", 128)
local historyPage = page("History", 256)

local current = "Account"
local function show(name)
	current = name
	for n, frame in pages do
		frame.Visible = n == name
		tabs[n].BackgroundColor3 = n == name and BRASS or ROW
		tabs[n].TextColor3 = n == name and DARK or CREAM
	end
end
for n, tab in tabs do
	tab.Activated:Connect(function()
		show(n)
	end)
end

local function clear(frame)
	for _, c in frame:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local function row(frame, height, order)
	local r = Instance.new("Frame")
	r.Size = UDim2.new(1, -8, 0, height)
	r.BackgroundColor3 = ROW
	r.LayoutOrder = order
	r.Parent = frame
	Instance.new("UICorner", r).CornerRadius = UDim.new(0, 8)
	return r
end

local snapshot = nil
local render

local function send(action, a, b)
	local ok, result, message, snap = pcall(function()
		return request:InvokeServer(action, a, b)
	end)
	if not ok then
		status.TextColor3 = RED
		status.Text = "The bank didn't answer. Try again."
		return
	end
	if message then
		status.TextColor3 = result and GREEN or RED
		status.Text = message
	end
	if snap then
		snapshot = snap
		render()
	end
end

-- Account page
local amountBox
local function renderAccount()
	clear(accountPage)
	local s = snapshot
	local top = row(accountPage, 92, 1)
	local w = label(top, ("Wallet\n%s"):format(money(s.wallet)), 20, CREAM)
	w.Position = UDim2.fromOffset(14, 10)
	w.Size = UDim2.fromOffset(240, 60)
	local bankText = ("In the bank\n%s"):format(money(s.balance))
	if (s.held or 0) > 0 then
		bankText ..= ("  +%s loan to spend"):format(money(s.held))
	end
	local bal = label(top, bankText, 20, GREEN)
	bal.Position = UDim2.fromOffset(270, 10)
	bal.Size = UDim2.fromOffset(240, 60)

	local rates = {}
	local floor = 0
	for _, tier in s.tiers do
		table.insert(rates, ("%s%% on %s to %s"):format(tostring(tier.rate * 100), money(floor), money(tier.upTo)))
		floor = tier.upTo
	end
	local info = row(accountPage, 64, 2)
	local it = label(
		info,
		("Savings interest every %d minutes you're working: %s. Next payment: %s."):format(s.interestMinutes, table.concat(rates, ", "), money(s.nextInterest)),
		14,
		MUTED,
		Enum.Font.Gotham
	)
	it.Position = UDim2.fromOffset(14, 6)
	it.Size = UDim2.new(1, -28, 1, -12)

	local act = row(accountPage, 96, 3)
	amountBox = Instance.new("TextBox")
	amountBox.Position = UDim2.fromOffset(14, 12)
	amountBox.Size = UDim2.fromOffset(160, 32)
	amountBox.BackgroundColor3 = CREAM
	amountBox.TextColor3 = DARK
	amountBox.PlaceholderText = "Amount"
	amountBox.Text = ""
	amountBox.Font = Enum.Font.GothamBold
	amountBox.TextSize = 16
	amountBox.ClearTextOnFocus = false
	amountBox.Parent = act
	Instance.new("UICorner", amountBox).CornerRadius = UDim.new(0, 6)
	local function amount()
		return tonumber((amountBox.Text:gsub("[%$,%s]", "")))
	end
	local specs = {
		{ "Deposit", 186, 12, function()
			send("deposit", amount())
		end },
		{ "Withdraw", 344, 12, function()
			send("withdraw", amount())
		end },
		{ "Deposit all", 186, 52, function()
			send("deposit", "all")
		end },
		{ "Withdraw all", 344, 52, function()
			send("withdraw", "all")
		end },
	}
	for _, spec in specs do
		local b = button(act, spec[1])
		b.Position = UDim2.fromOffset(spec[2], spec[3])
		b.Size = UDim2.fromOffset(148, 32)
		b.Activated:Connect(spec[4])
	end

	if s.testMoney then
		local note = row(accountPage, 44, 4)
		local n = label(note, "Test money is on, so shops are free. The wallet, bank and loans here are your real, saved balances.", 13, BRASS, Enum.Font.Gotham)
		n.Position = UDim2.fromOffset(14, 4)
		n.Size = UDim2.new(1, -28, 1, -8)
	end
end

-- Loans page
local function renderLoans()
	clear(loansPage)
	local s = snapshot
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local head = row(loansPage, 40, nextOrder())
	local h = label(head, ("Put 20%% down and the bank lends the rest. It can lend you up to %s more."):format(money(s.creditLeft)), 14, CREAM, Enum.Font.Gotham)
	h.Position = UDim2.fromOffset(14, 4)
	h.Size = UDim2.new(1, -28, 1, -8)
	for _, loan in s.loans do
		local r = row(loansPage, 46, nextOrder())
		r.BackgroundColor3 = DARK
		local t = label(
			r,
			("%s  ·  %d%% fee  ·  repaid from %d%% of each sale\n%s"):format(loan.name:upper(), math.round(loan.interest * 100), math.round(loan.repayShare * 100), loan.blurb),
			14,
			BRASS
		)
		t.Position = UDim2.fromOffset(14, 4)
		t.Size = UDim2.new(1, -28, 1, -8)
		if loan.owed > 0 then
			local o = row(loansPage, 48, nextOrder())
			local ol = label(o, ("You owe %s for the %s."):format(money(loan.owed), loan.item or "farm"), 15, CREAM)
			ol.Position = UDim2.fromOffset(14, 0)
			ol.Size = UDim2.new(1, -170, 1, 0)
			local pay = button(o, "Pay it off")
			pay.Position = UDim2.new(1, -150, 0, 8)
			pay.Size = UDim2.fromOffset(136, 32)
			pay.Activated:Connect(function()
				send("payoff", loan.kind)
			end)
		elseif #loan.options == 0 then
			local o = row(loansPage, 36, nextOrder())
			local ol = label(o, "Nothing to finance here right now.", 14, MUTED, Enum.Font.Gotham)
			ol.Position = UDim2.fromOffset(14, 0)
			ol.Size = UDim2.new(1, -28, 1, 0)
		else
			for _, option in loan.options do
				local o = row(loansPage, 52, nextOrder())
				local ol = label(
					o,
					("%s  %s\n%s down, borrow %s, pay back %s"):format(option.name, money(option.price), money(option.down), money(option.principal), money(option.payback)),
					14,
					CREAM,
					Enum.Font.Gotham
				)
				ol.Position = UDim2.fromOffset(14, 4)
				ol.Size = UDim2.new(1, -170, 1, -8)
				local fin = button(o, "Finance")
				fin.Position = UDim2.new(1, -150, 0, 10)
				fin.Size = UDim2.fromOffset(136, 32)
				fin.Activated:Connect(function()
					send("loan", loan.kind, option.id)
				end)
			end
		end
	end
end

-- History page
local KIND_TEXT = {
	earn = "Earned",
	spend = "Spent",
	deposit = "Deposit",
	withdraw = "Withdrawal",
	loan = "Loan",
	repay = "Loan payment",
	interest = "Interest",
	refund = "Refund",
	test = "Test purchase",
	trade = "Trade",
}
local function ago(seconds)
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return ("%d min ago"):format(seconds // 60)
	elseif seconds < 86400 then
		return ("%d h ago"):format(seconds // 3600)
	end
	return ("%d days ago"):format(seconds // 86400)
end
local function renderHistory()
	clear(historyPage)
	local s = snapshot
	if #s.history == 0 then
		local r = row(historyPage, 36, 1)
		local l = label(r, "No transactions yet. Sell some hay!", 14, MUTED, Enum.Font.Gotham)
		l.Position = UDim2.fromOffset(14, 0)
		l.Size = UDim2.new(1, -28, 1, 0)
		return
	end
	for i, h in s.history do
		local r = row(historyPage, 30, i)
		local l = label(r, ("%s  ·  %s"):format(ago(math.max(0, s.now - h.t)), h.note ~= "" and h.note or (KIND_TEXT[h.kind] or h.kind)), 13, CREAM, Enum.Font.Gotham)
		l.Position = UDim2.fromOffset(12, 0)
		l.Size = UDim2.new(1, -140, 1, 0)
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.TextWrapped = false
		local amt = label(r, h.amount == 0 and "" or money(h.amount), 14, h.amount < 0 and RED or GREEN)
		amt.TextXAlignment = Enum.TextXAlignment.Right
		amt.Position = UDim2.new(1, -130, 0, 0)
		amt.Size = UDim2.fromOffset(118, 30)
	end
end

render = function()
	if not snapshot then
		return
	end
	renderAccount()
	renderLoans()
	renderHistory()
end

close.Activated:Connect(function()
	panel.Visible = false
end)

openRemote.OnClientEvent:Connect(function()
	status.Text = ""
	panel.Visible = true
	show(current)
	send("view")
end)

-- Walk away from the counter and the panel closes.
task.spawn(function()
	while true do
		task.wait(0.5)
		if panel.Visible then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local near = false
			for _, window in CollectionService:GetTagged("BankTeller") do
				if root and (root.Position - window.Position).Magnitude <= 22 then
					near = true
				end
			end
			if root and not near then
				panel.Visible = false
			end
		end
	end
end)
