--!nonstrict
-- Rebirth (CEO H5; the server side is Services/Rebirth.luau, terms in Prices.Rebirth). This draws:
--   * a gold chip in the HUD column under the bank: "★ Rebirth ready" once RebirthReady, "♻ Rebirth 2 · sales +20%"
--     after your first one, and a teaser once you own the Farm Flatbed. Clicking it opens the card.
--   * the card: what you lose and keep, the "Rebirth (+10% forever)" button (a second click confirms), the hint while
--     it is not open yet, and the server's answer when it says no (loans not paid, the last rebirth reached).
--   * a "♻ Rebirth N" line over every reborn player's head, from their RebirthCount attribute, for show-off.
-- It reads only RebirthReady / RebirthCount / RebirthBonus and calls ReplicatedStorage.Rebirth (no arguments,
-- returns ok, message). The server decides everything; a yes saves the reset profile and sends you back through a rejoin.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Hud = require(UI:WaitForChild("Hud"))
local Menus = require(UI:WaitForChild("Menus"))
local WorldLabel = require(Shared:WaitForChild("WorldLabel"))
local Prices = require(Shared:WaitForChild("Config"):WaitForChild("Prices"))
local C, F, T = Kit.Theme.Colors, Kit.Theme.Fonts, Kit.Theme.Text

local player = Players.LocalPlayer
local Terms = Prices.Rebirth
local PERCENT = math.floor(Terms.Bonus * 100 + 0.5)
local GOLD = Color3.fromRGB(255, 206, 96)

local CONFIRM = "Start over with +%d%% on every sale? You lose cash, bank, trucks and everything built on your farm. "
	.. "You keep your plot, shovels, wheelbarrow, needle index, cosmetics and mutated needles."
local LOCKED = "Rebirth opens once you own the Semi."

local TEASE_AFTER = "farm_flatbed" -- the truck before the Semi in the goal ladder (UI/Catalog.luau)
local CONFIRM_FOR = 6 -- seconds the "Yes, start over" button stays armed

local function count()
	return player:GetAttribute("RebirthCount") or 0
end

-- The HUD chip ----------------------------------------------------------------------------------------------------

local chip = Kit.button(Hud.column(), "", "ink", UDim2.fromOffset(230, 28))
chip.Name = "Rebirth"
chip.LayoutOrder = Hud.Order.Rebirth
chip.TextSize = T.Small + 1
chip.TextColor3 = GOLD
chip.Visible = false
chip.Activated:Connect(function()
	Menus.toggle("Rebirth")
end)

-- The card ---------------------------------------------------------------------------------------------------------

local gui = Kit.screen("NeedlewoodRebirth", 7)
local panel, body, title = Kit.panel(gui, {
	title = "REBIRTH",
	name = "Rebirth",
	width = 380,
	height = 330,
	onClose = function()
		Menus.close()
	end,
})
panel.Visible = false

local standing = Kit.label(body, "", { size = T.Body, font = F.Bold, color = C.Wood, align = "center", wrap = false })
standing.Size = UDim2.new(1, 0, 0, 24)

local terms = Kit.label(body, CONFIRM:format(PERCENT), { size = T.Small + 1, color = C.Ink })
terms.Size = UDim2.new(1, 0, 0, 120)
terms.Position = UDim2.fromOffset(0, 30)

local status = Kit.label(body, "", { size = T.Small + 1, font = F.Bold, color = C.Red, align = "center" })
status.Size = UDim2.new(1, 0, 0, 40)
status.Position = UDim2.fromOffset(0, 154)

local go = Kit.button(body, ("Rebirth (+%d%% forever)"):format(PERCENT), "go", UDim2.fromOffset(240, 42))
go.AnchorPoint = Vector2.new(0.5, 1)
go.Position = UDim2.new(0.5, 0, 1, -4)

local busy = false
local armToken = 0
local armed = false -- the first click arms the button; the second, within CONFIRM_FOR seconds, rebirths
local answered = false -- the server's last answer stays up until the card is reopened

local function refresh()
	local n, ready = count(), player:GetAttribute("RebirthReady") == true
	local bonus = player:GetAttribute("RebirthBonus") or 1
	local extra = math.floor((bonus - 1) * 100 + 0.5)
	local owned = "," .. (player:GetAttribute("OwnedTrucks") or "") .. ","
	local tease = string.find(owned, "," .. TEASE_AFTER .. ",", 1, true) ~= nil
	if ready then
		chip.Text = "★ Rebirth ready"
	elseif n > 0 then
		chip.Text = ("♻ Rebirth %d  ·  sales +%d%%"):format(n, extra)
	else
		chip.Text = ("♻ Rebirth: +%d%% forever after the Semi"):format(PERCENT)
	end
	chip.Visible = player:GetAttribute("SaveSlot") ~= nil and (ready or n > 0 or tease)
	title.Text = n > 0 and ("REBIRTH  ·  %d OF %d"):format(n, Terms.Max) or "REBIRTH"
	if n >= Terms.Max then
		standing.Text = ("Every sale pays +%d%%. That was the last rebirth."):format(extra)
	elseif n > 0 then
		standing.Text = ("Every sale pays +%d%% now. Next: +%d%%"):format(extra, extra + PERCENT)
	else
		standing.Text = ("Every sale pays +%d%% after this"):format(PERCENT)
	end
	if not busy and not armed then
		go.Text = ("Rebirth (+%d%% forever)"):format(PERCENT)
		Kit.setStyle(go, ready and "go" or "muted")
		go.AutoButtonColor = ready
		if not answered then
			status.TextColor3 = C.Red
			if ready or n >= Terms.Max then
				status.Text = ""
			elseif (player:GetAttribute("LoanOwed") or 0) > 0 then
				status.Text = "Rebirth opens once you own the Semi and your loans are paid off."
			else
				status.Text = LOCKED
			end
		end
	end
end

Menus.register("Rebirth", function(open)
	panel.Visible = open
	armed = false
	if open then
		answered = false
		refresh()
	end
end)

go.Activated:Connect(function()
	if busy or player:GetAttribute("RebirthReady") ~= true then
		return
	end
	if not armed then
		armed = true
		armToken += 1
		local mine = armToken
		go.Text = "Yes, start over"
		Kit.setStyle(go, "stop")
		task.delay(CONFIRM_FOR, function()
			if armed and not busy and armToken == mine then
				armed = false
				refresh()
			end
		end)
		return
	end
	armed = false
	busy = true
	Kit.setStyle(go, "muted")
	status.TextColor3 = C.Ink
	status.Text = "Rebirthing..."
	local remote = ReplicatedStorage:FindFirstChild("Rebirth")
	local ok, message = false, "Rebirth isn't ready on this server yet. Try again in a moment."
	if remote and remote:IsA("RemoteFunction") then
		local called, a, b = pcall(remote.InvokeServer, remote)
		if called then
			ok, message = a == true, b
		end
	end
	status.TextColor3 = ok and C.Cash or C.Red
	status.Text = typeof(message) == "string" and message or (ok and "Rebirth done!" or "That didn't work.")
	answered = true
	busy = false
	refresh()
end)

for _, name in { "RebirthReady", "RebirthCount", "RebirthBonus", "SaveSlot", "LoanOwed", "OwnedTrucks" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
refresh()

-- Over every reborn player's head -------------------------------------------------------------------------------

local TAG = "RebirthTag"

local function draw(other)
	local character = other.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local n = other:GetAttribute("RebirthCount") or 0
	local gui = head:FindFirstChild(TAG)
	if n <= 0 then
		if gui then
			gui:Destroy()
		end
		return
	end
	local text = ("♻ Rebirth %d"):format(n)
	local label = gui and gui:FindFirstChild("Text")
	if not label then
		-- Above the best-needle tag (NameTags.luau, 3.1 studs up).
		label = WorldLabel.billboard(
			head,
			text,
			{ kind = "tag", offset = Vector3.new(0, 3.9, 0), distance = 80, color = GOLD }
		)
		label.Parent.Name = TAG
	end
	label.Text = text
end

local function watch(other)
	other:GetAttributeChangedSignal("RebirthCount"):Connect(function()
		draw(other)
	end)
	other.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		draw(other)
	end)
	draw(other)
end
Players.PlayerAdded:Connect(watch)
for _, other in Players:GetPlayers() do
	task.spawn(watch, other)
end
