--!nonstrict
-- The Trading Post window (needles, foreign objects, thatch, materials and cash). Press E at the stall to see who is standing at the post and ask one of them to trade. Once
-- they say yes, both of you get a two-column window: your offer on the left (with your pocket underneath to add from),
-- theirs on the right. Both press ACCEPT and a 5 second countdown runs; any change to either offer stops it. The
-- server (Trade.luau) checks every number and does the swap; this only shows it and sends requests.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local remotes = ReplicatedStorage:WaitForChild("Trade")
local requestRemote = remotes:WaitForChild("Request")
local respondRemote = remotes:WaitForChild("Respond")
local offerRemote = remotes:WaitForChild("Offer")
local acceptRemote = remotes:WaitForChild("Accept")
local cancelRemote = remotes:WaitForChild("Cancel")
local updateRemote = remotes:WaitForChild("Update")

local Kit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Kit"))
local Theme = Kit.Theme
local C, F, T = Theme.Colors, Theme.Fonts, Theme.Text

local gui = Kit.screen("TradeGui", 12, true)

-- Calls a remote function safely. Returns ok and the server's message.
local function call(remote, ...)
	local okCall, ok, message = pcall(remote.InvokeServer, remote, ...)
	if not okCall then
		return false, "Couldn't reach the Trading Post. Try again."
	end
	return ok, message
end

local function clear(list)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A row in a list: a label on the left and up to a few small buttons on the right.
local function row(list, order, text, color, buttons)
	local card = Kit.card(list, 30)
	card.LayoutOrder = order
	local width = 0
	for i = #(buttons or {}), 1, -1 do
		local def = buttons[i]
		local b = Kit.button(card, def.text, def.style or "wood", UDim2.fromOffset(def.width or 44, 24))
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -4 - width, 0.5, 0)
		b.TextSize = T.Small
		b.Activated:Connect(def.onClick)
		width += (def.width or 44) + 4
	end
	local label = Kit.label(card, text, { size = T.Small + 1, color = color or C.Ink, wrap = false })
	label.Position = UDim2.fromOffset(8, 0)
	label.Size = UDim2.new(1, -12 - width, 1, 0)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	return card
end

-- Picking who to trade with ------------------------------------------------------------------------------------------

local picker, pickerBody = Kit.panel(gui, {
	name = "TradePicker",
	title = "TRADING POST",
	width = 320,
	height = 360,
	onClose = function()
		gui.TradePicker.Visible = false
	end,
})
picker.Visible = false
local pickerHint = Kit.label(pickerBody, "Players at the post. Pick one to ask them to trade.", { size = T.Small + 1, height = 34 })
local pickerFrame = Instance.new("Frame")
pickerFrame.BackgroundTransparency = 1
pickerFrame.Position = UDim2.fromOffset(0, 40)
pickerFrame.Size = UDim2.new(1, 0, 1, -76)
pickerFrame.Parent = pickerBody
local pickerList = Kit.list(pickerFrame, 6)
local pickerMessage = Kit.label(pickerBody, "", { size = T.Small + 1, color = C.Red, height = 30 })
pickerMessage.Position = UDim2.new(0, 0, 1, -30)

local function showPicker(players)
	clear(pickerList)
	pickerMessage.Text = ""
	if #players == 0 then
		pickerHint.Text = "Nobody else is at the post. Trades need both players within a few steps of the stall."
	else
		pickerHint.Text = "Players at the post. Pick one to ask them to trade."
	end
	for i, p in players do
		row(pickerList, i, p.name .. (p.busy and "  (trading)" or ""), C.Ink, {
			{
				text = "ASK",
				style = p.busy and "muted" or "go",
				width = 60,
				onClick = function()
					pickerMessage.Text = "..."
					local ok, message = call(requestRemote, p.userId)
					pickerMessage.TextColor3 = ok and C.Green or C.Red
					pickerMessage.Text = message or ""
				end,
			},
		})
	end
	picker.Visible = true
end

-- An invite from someone else ----------------------------------------------------------------------------------------

local invitePanel, inviteBody = Kit.panel(gui, {
	name = "TradeInvite",
	title = "TRADE INVITE",
	width = 300,
	height = 160,
	anchor = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, 80),
})
invitePanel.Visible = false
local inviteText = Kit.label(inviteBody, "", { size = T.Body, height = 44 })
local inviteFrom = nil
local yesButton = Kit.button(inviteBody, "ACCEPT", "go", UDim2.new(0.5, -4, 0, 34))
yesButton.Position = UDim2.new(0, 0, 1, -36)
local noButton = Kit.button(inviteBody, "DECLINE", "stop", UDim2.new(0.5, -4, 0, 34))
noButton.Position = UDim2.new(0.5, 4, 1, -36)

local function answer(yes)
	local from = inviteFrom
	inviteFrom = nil
	invitePanel.Visible = false
	if from then
		local ok, message = call(respondRemote, from, yes)
		if not ok and message then
			pickerMessage.Text = message
		end
	end
end
yesButton.Activated:Connect(function()
	answer(true)
end)
noButton.Activated:Connect(function()
	answer(false)
end)

-- The trade window -----------------------------------------------------------------------------------------------------

local window, body, windowTitle = Kit.panel(gui, {
	name = "TradeWindow",
	title = "TRADE",
	width = 640,
	height = 520,
	onClose = function()
		call(cancelRemote)
	end,
})
window.Visible = false

local COL = 300 -- width of each column; the body is 616 wide

local function column(x, title)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.fromOffset(x, 0)
	frame.Size = UDim2.new(0, COL, 1, -86)
	frame.Parent = body
	local heading = Kit.label(frame, title, { size = T.Heading, font = F.Bold, height = 22 })
	heading.Position = UDim2.fromOffset(0, 0)
	return frame, heading
end

local function listIn(parent, y, height)
	local holder = Instance.new("Frame")
	holder.BackgroundColor3 = C.CardDim
	holder.BorderSizePixel = 0
	holder.Position = UDim2.fromOffset(0, y)
	holder.Size = UDim2.new(1, 0, 0, height)
	holder.Parent = parent
	Kit.corner(holder, 6)
	Kit.pad(holder, 4)
	return Kit.list(holder, 4)
end

-- Left: your offer, the cash and thatch boxes, and your pocket to add from.
local mineCol, mineHeading = column(0, "YOUR OFFER")
local mineList = listIn(mineCol, 24, 100)

local function numberBox(parent, y, caption)
	local label = Kit.label(parent, caption, { size = T.Small + 1, font = F.Bold, height = 28 })
	label.Position = UDim2.fromOffset(0, y)
	label.Size = UDim2.fromOffset(120, 28)
	local box = Instance.new("TextBox")
	box.Position = UDim2.fromOffset(124, y)
	box.Size = UDim2.new(1, -124, 0, 28)
	box.BackgroundColor3 = C.Card
	box.TextColor3 = C.Ink
	box.PlaceholderText = "0"
	box.Text = ""
	box.Font = F.Bold
	box.TextSize = T.Body
	box.ClearTextOnFocus = false
	box.Parent = parent
	Kit.corner(box, 6)
	Kit.stroke(box, C.Ink, 1).Transparency = 0.5
	return box, label
end
local cashBox, cashLabel = numberBox(mineCol, 130, "Cash ($)")
local thatchBox, thatchLabel = numberBox(mineCol, 162, "Thatch")

local pocketHeading = Kit.label(mineCol, "ADD FROM YOUR POCKET", { size = T.Small + 1, font = F.Bold, height = 20 })
pocketHeading.Position = UDim2.fromOffset(0, 196)
local pocketList = listIn(mineCol, 218, 150)

-- Right: their offer and whether they have accepted.
local theirsCol, theirsHeading = column(COL + 16, "THEIR OFFER")
local theirsList = listIn(theirsCol, 24, 262)
local theirStatus = Kit.label(theirsCol, "", { size = T.Body, font = F.Bold, height = 24 })
theirStatus.Position = UDim2.fromOffset(0, 290)
local lockNote = Kit.label(
	theirsCol,
	"Mythic items (the rarest needle type, mutated needles, the rarest find) you get in a trade are locked for 24 hours before you can trade them on.",
	{ size = T.Small, color = C.InkSoft, height = 56 }
)
lockNote.Position = UDim2.fromOffset(0, 316)

-- Bottom: countdown and status, ACCEPT and CANCEL.
local status = Kit.label(body, "", { size = T.Heading, font = F.Bold, align = "center", height = 26 })
status.Position = UDim2.new(0, 0, 1, -80)
local message = Kit.label(body, "", { size = T.Small + 1, color = C.Red, align = "center", height = 18 })
message.Position = UDim2.new(0, 0, 1, -56)
local acceptButton = Kit.button(body, "ACCEPT", "go", UDim2.new(0.5, -6, 0, 36))
acceptButton.Position = UDim2.new(0, 0, 1, -36)
local cancelButton = Kit.button(body, "CANCEL", "stop", UDim2.new(0.5, -6, 0, 36))
cancelButton.Position = UDim2.new(0.5, 6, 1, -36)

-- Trade state from the server -------------------------------------------------------------------------------------------

local current = nil -- the last "state" payload
local desired = nil -- the offer as this player wants it: { needles = { [key] = n }, finds = { [id] = n }, cash, thatch, materials }
local sending = false

local function offerFromView(view)
	local offer = { needles = {}, finds = {}, cash = view.cash or 0, thatch = view.thatch or 0, materials = {} }
	for _, line in view.needles do
		offer.needles[line.key] = line.count
	end
	for _, line in view.finds or {} do
		offer.finds[line.id] = line.count
	end
	for _, line in view.materials do
		offer.materials[line.id] = line.count
	end
	return offer
end

local render -- forward
local dirty = false -- changed again while a send was on its way

local function sendOffer()
	if not desired then
		return
	end
	if sending then
		dirty = true
		return
	end
	sending = true
	dirty = false
	message.Text = ""
	task.spawn(function()
		local ok, why = call(offerRemote, desired)
		sending = false
		if not ok then
			message.TextColor3 = C.Red
			message.Text = why or ""
			-- Back to the offer the server has.
			dirty = false
			if current then
				desired = offerFromView(current.mine)
				render()
			end
		elseif dirty and desired then
			sendOffer()
		end
	end)
end

local function change(fn)
	if not desired then
		return
	end
	fn(desired)
	render()
	sendOffer()
end

local function offerLines(list, view, editable)
	clear(list)
	local order = 0
	local function add(text, color, buttons)
		order += 1
		row(list, order, text, color, buttons)
	end
	for _, line in view.needles do
		local text = ("%dx %s"):format(line.count, line.label)
		local color = line.mythic and C.Red or C.Ink
		if editable then
			add(text, color, {
				{
					text = "-1",
					onClick = function()
						change(function(o)
							local n = (o.needles[line.key] or 0) - 1
							o.needles[line.key] = n > 0 and n or nil
						end)
					end,
				},
				{
					text = "X",
					style = "stop",
					width = 28,
					onClick = function()
						change(function(o)
							o.needles[line.key] = nil
						end)
					end,
				},
			})
		else
			add(text, color)
		end
	end
	for _, line in view.finds or {} do
		local text = ("%dx %s"):format(line.count, line.label)
		local color = line.mythic and C.Red or C.WoodLight
		if editable then
			add(text, color, {
				{
					text = "X",
					style = "stop",
					width = 28,
					onClick = function()
						change(function(o)
							o.finds[line.id] = nil
						end)
					end,
				},
			})
		else
			add(text, color)
		end
	end
	for _, line in view.materials do
		local text = ("%d %s"):format(line.count, line.label)
		if editable then
			add(text, C.Blue, {
				{
					text = "X",
					style = "stop",
					width = 28,
					onClick = function()
						change(function(o)
							o.materials[line.id] = nil
						end)
					end,
				},
			})
		else
			add(text, C.Blue)
		end
	end
	if not editable then
		if (view.cash or 0) > 0 then
			add(Kit.money(view.cash) .. " cash", C.Green)
		end
		if (view.thatch or 0) > 0 then
			add(("%d thatch"):format(view.thatch), C.InkSoft)
		end
	end
	if order == 0 then
		add(editable and "Nothing yet. Add from your pocket below." or "Nothing yet.", C.InkSoft)
	end
end

local function pocketLines(inventory)
	clear(pocketList)
	local order = 0
	for _, line in inventory.needles do
		order += 1
		local inOffer = desired and desired.needles[line.key] or 0
		local left = line.count - inOffer
		local text = ("%s  (%d)"):format(line.label, left)
		if line.locked > 0 then
			text ..= ("  +%d locked"):format(line.locked)
		end
		row(pocketList, order, text, line.mythic and C.Red or C.Ink, left > 0 and {
			{
				text = "+1",
				style = "go",
				onClick = function()
					change(function(o)
						o.needles[line.key] = math.min(line.count, (o.needles[line.key] or 0) + 1)
					end)
				end,
			},
			{
				text = "ALL",
				style = "go",
				onClick = function()
					change(function(o)
						o.needles[line.key] = line.count
					end)
				end,
			},
		} or nil)
	end
	for _, line in inventory.finds or {} do
		order += 1
		local inOffer = desired and desired.finds[line.id] or 0
		local left = line.count - inOffer
		local text = ("%s  (%d)"):format(line.label, left)
		if line.locked > 0 then
			text ..= ("  +%d locked"):format(line.locked)
		end
		row(pocketList, order, text, line.mythic and C.Red or C.WoodLight, left > 0 and {
			{
				text = "+1",
				style = "go",
				onClick = function()
					change(function(o)
						o.finds[line.id] = math.min(line.count, (o.finds[line.id] or 0) + 1)
					end)
				end,
			},
		} or nil)
	end
	for _, line in inventory.materials do
		order += 1
		local inOffer = desired and desired.materials[line.id] or 0
		local left = line.count - inOffer
		row(pocketList, order, ("%s  (%d)"):format(line.label, left), C.Blue, left > 0 and {
			{
				text = "+10",
				style = "go",
				onClick = function()
					change(function(o)
						o.materials[line.id] = math.min(line.count, (o.materials[line.id] or 0) + 10)
					end)
				end,
			},
			{
				text = "ALL",
				style = "go",
				onClick = function()
					change(function(o)
						o.materials[line.id] = line.count
					end)
				end,
			},
		} or nil)
	end
	if order == 0 then
		order += 1
		row(pocketList, order, "No needles, finds or materials on you.", C.InkSoft)
	end
end

render = function()
	if not current or not desired then
		return
	end
	local inventory = current.inventory
	windowTitle.Text = "TRADE WITH " .. string.upper(current.partner or "?")
	-- Each side pays the trading post fee on what it gives; the server works it out (Bank.tradeFee).
	mineHeading.Text = ("YOUR OFFER  fee %s%s"):format(Kit.money(current.myFee or 0), current.myAccept and "  (accepted)" or "")
	theirsHeading.Text = ("%s'S OFFER  fee %s"):format(string.upper(current.partner or "THEIR"), Kit.money(current.theirFee or 0))
	offerLines(mineList, {
		needles = (function()
			local list = {}
			for _, line in inventory.needles do
				local n = desired.needles[line.key]
				if n then
					table.insert(list, { key = line.key, count = n, label = line.label, mythic = line.mythic })
				end
			end
			-- Keys the server still has in the offer but the pocket no longer shows.
			for _, line in current.mine.needles do
				local listed = false
				for _, l in list do
					listed = listed or l.key == line.key
				end
				if not listed and desired.needles[line.key] then
					table.insert(list, line)
				end
			end
			return list
		end)(),
		finds = (function()
			local list = {}
			for _, line in inventory.finds or {} do
				local n = desired.finds[line.id]
				if n then
					table.insert(list, { id = line.id, count = n, label = line.label, mythic = line.mythic })
				end
			end
			return list
		end)(),
		materials = (function()
			local list = {}
			for _, line in inventory.materials do
				local n = desired.materials[line.id]
				if n then
					table.insert(list, { id = line.id, count = n, label = line.label })
				end
			end
			return list
		end)(),
	}, true)
	offerLines(theirsList, current.theirs, false)
	pocketLines(inventory)

	cashBox.Visible = inventory.cashAllowed
	cashLabel.Text = inventory.cashAllowed and ("Cash (have %s)"):format(Kit.money(inventory.cash)) or "Cash: not tradable"
	cashLabel.Size = inventory.cashAllowed and UDim2.fromOffset(120, 28) or UDim2.new(1, 0, 0, 28)
	if not cashBox:IsFocused() then
		cashBox.Text = desired.cash > 0 and tostring(desired.cash) or ""
	end
	thatchLabel.Text = ("Thatch (have %d)"):format(inventory.thatch)
	if not thatchBox:IsFocused() then
		thatchBox.Text = desired.thatch > 0 and tostring(desired.thatch) or ""
	end

	theirStatus.TextColor3 = current.theirAccept and C.Green or C.InkSoft
	theirStatus.Text = current.theirAccept and (current.partner .. " has accepted.") or (current.partner .. " hasn't accepted yet.")
	if current.myAccept then
		acceptButton.Text = "UNACCEPT"
		Kit.setStyle(acceptButton, "picked")
	else
		acceptButton.Text = "ACCEPT"
		Kit.setStyle(acceptButton, "go")
	end
end

local function boxNumber(box, max)
	local n = tonumber((box.Text:gsub("[,%$%s]", "")))
	if not n or n ~= n or n < 0 then
		return 0
	end
	return math.clamp(math.floor(n), 0, max)
end

cashBox.FocusLost:Connect(function()
	if not current then
		return
	end
	local n = boxNumber(cashBox, current.inventory.cash)
	change(function(o)
		o.cash = n
	end)
end)
thatchBox.FocusLost:Connect(function()
	if not current then
		return
	end
	local n = boxNumber(thatchBox, current.inventory.thatch)
	change(function(o)
		o.thatch = n
	end)
end)

acceptButton.Activated:Connect(function()
	if not current then
		return
	end
	local ok, why = call(acceptRemote, not current.myAccept)
	if not ok and why then
		message.TextColor3 = C.Red
		message.Text = why
	end
end)
cancelButton.Activated:Connect(function()
	call(cancelRemote)
end)

-- The countdown runs on the server's clock, so both players see the same number.
RunService.Heartbeat:Connect(function()
	if not window.Visible or not current then
		return
	end
	if current.endsAt then
		local left = math.max(0, current.endsAt - Workspace:GetServerTimeNow())
		status.TextColor3 = C.Green
		status.Text = ("Both accepted. Trading in %d..."):format(math.ceil(left))
	elseif current.myAccept and not current.theirAccept then
		status.TextColor3 = C.InkSoft
		status.Text = "Waiting for " .. (current.partner or "them") .. " to accept."
	elseif current.theirAccept then
		status.TextColor3 = C.InkSoft
		status.Text = (current.partner or "They") .. " accepted. Check their offer and accept."
	else
		status.TextColor3 = C.InkSoft
		status.Text = "Put in your offer, then both press ACCEPT."
	end
end)

updateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.kind == "nearby" then
		showPicker(payload.players or {})
	elseif payload.kind == "invite" then
		inviteFrom = payload.from
		inviteText.Text = ("%s wants to trade with you."):format(payload.name or "Someone")
		invitePanel.Visible = true
		local mine = payload.from
		task.delay(payload.seconds or 20, function()
			if inviteFrom == mine then
				inviteFrom = nil
				invitePanel.Visible = false
			end
		end)
	elseif payload.kind == "state" then
		local opening = not window.Visible
		current = payload
		-- While a send is on its way, keep what the player typed; otherwise follow the server.
		if not sending or opening then
			desired = offerFromView(payload.mine)
		end
		picker.Visible = false
		invitePanel.Visible = false
		if opening then
			message.Text = ""
		end
		window.Visible = true
		render()
	elseif payload.kind == "closed" then
		current, desired = nil, nil
		window.Visible = false
		message.Text = "" -- the server shows why as a toast
	end
end)
