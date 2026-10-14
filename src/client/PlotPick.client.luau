--!nonstrict
-- Where your farm goes, asked each time you join with land (Land.luau onLoaded). The server sets the player attribute
-- PlotChoice to the suggested plot (your old one when it is free) while it waits; picking a free plot answers through
-- the Land.Settle remote. Nobody picking within the server's wait puts the farm on the suggested plot.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LandConfig = require(Shared:WaitForChild("Config"):WaitForChild("Land"))
local Kit = require(Shared:WaitForChild("UI"):WaitForChild("Kit"))
local state = ReplicatedStorage:WaitForChild("Land")
local settle = state:WaitForChild("Settle")

local player = Players.LocalPlayer
local Theme = Kit.Theme
local C, F, T = Theme.Colors, Theme.Fonts, Theme.Text

local gui = nil
local busy = false

local function close()
	if gui then
		gui:Destroy()
		gui = nil
	end
end

local function ownerOf(index)
	local info = state:FindFirstChild("Plot" .. index)
	return info and info:GetAttribute("OwnerId") or 0
end

local function open()
	close()
	local suggested = player:GetAttribute("PlotChoice")
	if typeof(suggested) ~= "number" then
		return
	end
	gui = Kit.screen("PlotPickGui", 50, true)
	local _, body = Kit.panel(gui, { title = "WHERE DOES YOUR FARM GO?", width = 420, height = 520 })
	local title = Kit.label(body, "Pick a free plot. Your farm is rebuilt there, exactly as you left it.", { size = T.Body, font = F.Medium, color = C.InkSoft, height = 40 })
	title.Position = UDim2.fromOffset(0, 0)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(0, 46)
	holder.Size = UDim2.new(1, 0, 1, -100)
	holder.Parent = body
	local list = Kit.list(holder, 6)
	local message = Kit.label(body, "", { size = T.Small, color = C.Red, height = 40 })
	message.AnchorPoint = Vector2.new(0, 1)
	message.Position = UDim2.new(0, 0, 1, 0)

	for index, def in LandConfig.Plots do
		local owner = ownerOf(index)
		local taken = owner ~= 0 and owner ~= player.UserId
		local card = Kit.card(list, 56)
		card.LayoutOrder = index
		local name = Kit.label(card, index == suggested and (def.name .. "  ·  your last spot") or def.name, { size = T.Heading, font = F.Bold, wrap = false })
		name.Position = UDim2.fromOffset(12, 4)
		name.Size = UDim2.new(1, -130, 0, 22)
		local where = def.open == "S" and "south of the lane" or "north of the lane"
		local info = Kit.label(card, taken and (where .. "  ·  taken") or (where .. "  ·  free"), { size = T.Small, color = C.InkSoft })
		info.Position = UDim2.fromOffset(12, 28)
		info.Size = UDim2.new(1, -130, 0, 18)
		local b
		if taken then
			b = Kit.button(card, "TAKEN", "muted", UDim2.fromOffset(100, 34))
			b.AutoButtonColor = false
		else
			b = Kit.button(card, "FARM HERE", "go", UDim2.fromOffset(100, 34))
			b.Activated:Connect(function()
				if busy then
					return
				end
				busy = true
				message.TextColor3 = C.Ink
				message.Text = "Setting up..."
				local ok, chosen, reply = pcall(function()
					return settle:InvokeServer(index)
				end)
				busy = false
				if ok and chosen then
					close()
				else
					message.TextColor3 = C.Red
					message.Text = ok and (reply or "Couldn't use that plot.") or "Couldn't reach the server. Try again."
				end
			end)
		end
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -10, 0.5, 0)
	end
end

player:GetAttributeChangedSignal("PlotChoice"):Connect(function()
	if player:GetAttribute("PlotChoice") then
		open()
	else
		close()
	end
end)
if player:GetAttribute("PlotChoice") then
	open()
end
