--!nonstrict
-- The daily contracts card (CEO H9) at the bottom of the HUD column: today's three contracts and their progress, as
-- the server writes them in the player attribute "Contracts" (Orders.luau: one line per contract, then a rewards
-- line). Click the header to fold it to one line. The reset countdown is on the top strip (Countdown.client.luau).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Hud = require(UI:WaitForChild("Hud"))
local C, F, T = Kit.Theme.Colors, Kit.Theme.Fonts, Kit.Theme.Text

local player = Players.LocalPlayer

local card = Instance.new("Frame")
card.Name = "Contracts"
card.LayoutOrder = Hud.Order.Contracts
card.Size = UDim2.fromOffset(230, 0)
card.AutomaticSize = Enum.AutomaticSize.Y
card.BackgroundColor3 = C.Wood
card.BackgroundTransparency = 0.1
card.Visible = false
card.Parent = Hud.column()
Kit.corner(card, 10)
Kit.stroke(card, C.Ink, 1.5)
Kit.pad(card, 8)
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 2)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = card

local header = Instance.new("TextButton")
header.Size = UDim2.new(1, 0, 0, 20)
header.BackgroundTransparency = 1
header.Font = F.Title
header.TextSize = T.Body
header.TextColor3 = C.Cream
header.TextXAlignment = Enum.TextXAlignment.Left
header.LayoutOrder = 0
header.Parent = card

local rows = {}
local folded = false

local function refresh()
	local text = player:GetAttribute("Contracts")
	local lines = {}
	if typeof(text) == "string" then
		for line in string.gmatch(text, "[^\n]+") do
			table.insert(lines, line)
		end
	end
	card.Visible = #lines > 0
	-- Contract lines first, then the rewards line (the server's last line).
	local done = 0
	for i = 1, #lines - 1 do
		if string.find(lines[i], "(done)", 1, true) then
			done += 1
		end
	end
	header.Text = ("%s CONTRACTS  %d / %d"):format(folded and "▸" or "▾", done, math.max(#lines - 1, 0))
	for i, line in lines do
		local row = rows[i]
		if not row then
			row = Kit.label(card, "", { size = T.Small, font = F.Medium, color = C.Cream })
			row.AutomaticSize = Enum.AutomaticSize.Y
			row.Size = UDim2.new(1, 0, 0, 0)
			row.LayoutOrder = i
			rows[i] = row
		end
		local isDone = string.find(line, "(done)", 1, true) ~= nil
		local isReward = i == #lines
		row.Text = line
		row.TextColor3 = isDone and C.Cash or isReward and C.Hay or C.Cream
		row.Font = isReward and F.Bold or F.Medium
		row.Visible = not folded
	end
	for i = #lines + 1, #rows do
		rows[i].Visible = false
	end
end

header.Activated:Connect(function()
	folded = not folded
	refresh()
end)
player:GetAttributeChangedSignal("Contracts"):Connect(refresh)
refresh()
