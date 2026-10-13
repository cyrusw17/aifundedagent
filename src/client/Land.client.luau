--!nonstrict
-- The land office panel and build mode. Stand on the rug at the land office counter to see every plot and buy one.
-- Once you own land, the BUILD button opens a bar of pieces: pick one, aim at your plot and click (or tap the spot
-- and press PLACE). R turns the piece; REMOVE takes pieces back for half their price. CREW lets other players on the
-- server drive your truck and run hay through your line for you. UNDO (Z) takes back the last action, MOVE (M) picks
-- a piece up and puts it somewhere else for free, COPY (C) copies an area and PASTE (V) builds it again. At the office, VISIT takes you to someone else's
-- farm, where you can like it at its sign. The server checks everything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LandConfig = require(Shared:WaitForChild("Config"):WaitForChild("Land"))
local Factory = require(Shared.Config:WaitForChild("Factory"))
local state = ReplicatedStorage:WaitForChild("Land")
local buyRemote = state:WaitForChild("Buy")
local placeRemote = state:WaitForChild("Place")
local removeRemote = state:WaitForChild("Remove")
local crewRemote = state:WaitForChild("Crew")
local visitRemote = state:WaitForChild("Visit")
local expandRemote = state:WaitForChild("Expand")
local pickRemote = state:WaitForChild("Pick")
local moveRemote = state:WaitForChild("Move")
local copyRemote = state:WaitForChild("Copy")
local pasteRemote = state:WaitForChild("Paste")
local undoRemote = state:WaitForChild("Undo")

local player = Players.LocalPlayer
local T = Factory.TileSize
local DIRS = { "N", "E", "S", "W" }
local DIR_VECTORS = { N = Vector3.new(0, 0, -1), E = Vector3.new(1, 0, 0), S = Vector3.new(0, 0, 1), W = Vector3.new(-1, 0, 0) }

local Kit = require(Shared:WaitForChild("UI"):WaitForChild("Kit"))
local Theme = Kit.Theme
local F = Theme.Fonts
local INK = Theme.Colors.Ink
local PANEL = Theme.Colors.Paper
local CARD = Theme.Colors.Card
local RED = Theme.Colors.Red
local GREEN = Theme.Colors.Green
local MUTED = Theme.Colors.Muted
local PICKED = Theme.Colors.Picked

local gui = Kit.screen("LandGui", 10, true)

local corner = Kit.corner

local panelBody -- the land office panel's body, set below

local function text(parent, value, size, y, height, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	local inset = parent == panelBody and 0 or 14
	label.Position = UDim2.fromOffset(inset, y)
	label.Size = UDim2.new(1, -inset * 2, 0, height)
	label.Font = font or F.Bold
	label.TextSize = size
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color or INK
	label.Text = value
	label.Parent = parent
	return label
end

local function button(parent, label, color)
	local b = Instance.new("TextButton")
	b.Font = F.Bold
	b.TextSize = 14
	b.Text = label
	b.TextColor3 = Theme.Colors.Cream
	b.BackgroundColor3 = color or GREEN
	b.Parent = parent
	corner(b, 6)
	return b
end

local function plotInfos()
	local list = {}
	for _, info in state:GetChildren() do
		if info:IsA("Configuration") then
			list[info:GetAttribute("Index")] = info
		end
	end
	return list
end

-- Land office panel ---------------------------------------------------------------------------------------------------

local panel
panel, panelBody = Kit.panel(gui, {
	title = "MEADOW LAND OFFICE",
	width = 340,
	height = 490,
	anchor = Vector2.new(1, 0.5),
	position = UDim2.new(1, -16, 0.5, 0),
})
panel.Visible = false

local ownedLabel = text(panelBody, "", 14, 0, 20, GREEN)
local panelMessage = text(panelBody, "", 14, 400, 30, RED, F.Body)

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(0, 26)
list.Size = UDim2.new(1, 0, 0, 368)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local layout = Instance.new("UIListLayout", list)
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local plotButtons = {} -- index -> button
local busy = false

local function refreshPanel()
	local mine = player:GetAttribute("LandPlot") or 0
	local cash = player:GetAttribute("Cash") or 0
	local infos = plotInfos()
	ownedLabel.Text = mine > 0 and infos[mine] and ("You own %s. Press BUILD to set it up."):format(infos[mine]:GetAttribute("Name"))
		or "Buy one plot per save."
	for index, b in plotButtons do
		local info = infos[index]
		local ownerId = info and info:GetAttribute("OwnerId") or 0
		local price = info and info:GetAttribute("Price") or 0
		if ownerId == player.UserId then
			b.Text = "YOURS"
			b.BackgroundColor3 = GREEN
		elseif ownerId ~= 0 then
			b.Text = ("VISIT %s  ♥%d"):format(string.upper(info:GetAttribute("OwnerName") or "?"), info:GetAttribute("Likes") or 0)
			b.BackgroundColor3 = PICKED
		elseif mine > 0 then
			b.Text = ("$%d"):format(price)
			b.BackgroundColor3 = MUTED
		elseif cash >= price then
			b.Text = ("BUY  $%d"):format(price)
			b.BackgroundColor3 = GREEN
		else
			b.Text = ("NEED $%d MORE"):format(price - cash)
			b.BackgroundColor3 = MUTED
		end
	end
end

for index, def in LandConfig.Plots do
	local card = Instance.new("Frame")
	card.LayoutOrder = index
	card.Size = UDim2.new(1, -8, 0, 76)
	card.BackgroundColor3 = CARD
	card.Parent = list
	corner(card)
	text(card, def.name, 17, 6, 22)
	text(card, ("%d x %d tiles (%d x %d studs)"):format(def.tiles.X, def.tiles.Y, def.tiles.X * T, def.tiles.Y * T), 13, 28, 18, INK, F.Body)
	local b = button(card, "", GREEN)
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -8, 1, -8)
	b.Size = UDim2.fromOffset(170, 26)
	plotButtons[index] = b
	b.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		panelMessage.Text = "..."
		local info = plotInfos()[index]
		local ownerId = info and info:GetAttribute("OwnerId") or 0
		local remote = (ownerId ~= 0 and ownerId ~= player.UserId) and visitRemote or buyRemote
		local ok, bought, message = pcall(function()
			return remote:InvokeServer(index)
		end)
		busy = false
		panelMessage.TextColor3 = ok and bought and GREEN or RED
		panelMessage.Text = ok and (message or "") or "Couldn't reach the counter. Try again."
		refreshPanel()
	end)
end

for _, info in state:GetChildren() do
	if info:IsA("Configuration") then
		info.AttributeChanged:Connect(refreshPanel)
	end
end
state.ChildAdded:Connect(function(info)
	if info:IsA("Configuration") then
		info.AttributeChanged:Connect(refreshPanel)
	end
end)
player:GetAttributeChangedSignal("Cash"):Connect(refreshPanel)

task.spawn(function()
	while true do
		task.wait(0.2)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local near = false
		if root then
			for _, rug in CollectionService:GetTagged("LandCounter") do
				local offset = rug.CFrame:PointToObjectSpace(root.Position)
				if math.abs(offset.X) < rug.Size.X / 2 + 2 and math.abs(offset.Z) < rug.Size.Z / 2 + 2 and offset.Y < 8 then
					near = true
				end
			end
		end
		if near and not panel.Visible then
			panelMessage.Text = ""
			refreshPanel()
		end
		panel.Visible = near
	end
end)

-- Build mode ----------------------------------------------------------------------------------------------------------

local buildButton = button(gui, "BUILD", GREEN)
buildButton.AnchorPoint = Vector2.new(0.5, 1)
buildButton.Position = UDim2.new(0.5, 0, 1, -16)
buildButton.Size = UDim2.fromOffset(140, 40)
buildButton.TextSize = 18
buildButton.Visible = false

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -12)
bar.Size = UDim2.new(1, -24, 0, 150)
bar.BackgroundColor3 = PANEL
bar.Visible = false
bar.Parent = gui
corner(bar, 12)
local barConstraint = Instance.new("UISizeConstraint", bar)
barConstraint.MaxSize = Vector2.new(900, 150)
local barStroke = Instance.new("UIStroke", bar)
barStroke.Color = INK
barStroke.Thickness = 2

local infoLabel = text(bar, "", 13, 6, 34, INK, F.Body)
infoLabel.Size = UDim2.new(1, -28, 0, 34)

local pieceRow = Instance.new("ScrollingFrame")
pieceRow.Position = UDim2.fromOffset(10, 42)
pieceRow.Size = UDim2.new(1, -20, 0, 58)
pieceRow.BackgroundTransparency = 1
pieceRow.BorderSizePixel = 0
pieceRow.ScrollBarThickness = 4
pieceRow.ScrollingDirection = Enum.ScrollingDirection.X
pieceRow.AutomaticCanvasSize = Enum.AutomaticSize.X
pieceRow.CanvasSize = UDim2.new()
pieceRow.Parent = bar
local rowLayout = Instance.new("UIListLayout", pieceRow)
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.Padding = UDim.new(0, 6)
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder

local actions = Instance.new("ScrollingFrame")
actions.Position = UDim2.new(0, 10, 1, -44)
actions.Size = UDim2.new(1, -20, 0, 40)
actions.BackgroundTransparency = 1
actions.BorderSizePixel = 0
actions.ScrollBarThickness = 3
actions.ScrollingDirection = Enum.ScrollingDirection.X
actions.AutomaticCanvasSize = Enum.AutomaticSize.X
actions.CanvasSize = UDim2.new()
actions.Parent = bar
local actionLayout = Instance.new("UIListLayout", actions)
actionLayout.FillDirection = Enum.FillDirection.Horizontal
actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
actionLayout.Padding = UDim.new(0, 8)

local placeButton = button(actions, "PLACE", GREEN)
placeButton.Size = UDim2.fromOffset(96, 34)
local rotateButton = button(actions, "TURN (R)", INK)
rotateButton.Size = UDim2.fromOffset(96, 34)
local removeButton = button(actions, "REMOVE (X)", RED)
removeButton.Size = UDim2.fromOffset(110, 34)
local undoButton = button(actions, "UNDO (Z)", INK)
undoButton.Size = UDim2.fromOffset(92, 34)
local moveButton = button(actions, "MOVE (M)", MUTED)
moveButton.Size = UDim2.fromOffset(92, 34)
local copyButton = button(actions, "COPY (C)", MUTED)
copyButton.Size = UDim2.fromOffset(92, 34)
local pasteButton = button(actions, "PASTE (V)", MUTED)
pasteButton.Size = UDim2.fromOffset(98, 34)
local expandButton = button(actions, "EXPAND", GREEN)
expandButton.Size = UDim2.fromOffset(130, 34)
expandButton.Visible = false
local crewButton = button(actions, "CREW", PICKED)
crewButton.Size = UDim2.fromOffset(80, 34)
local doneButton = button(actions, "DONE", MUTED)
doneButton.Size = UDim2.fromOffset(80, 34)

-- Crew panel: everyone else on the server, each with ADD or REMOVE.
local crewPanel = Instance.new("Frame")
crewPanel.AnchorPoint = Vector2.new(0.5, 1)
crewPanel.Position = UDim2.new(0.5, 0, 1, -172)
crewPanel.Size = UDim2.fromOffset(320, 260)
crewPanel.BackgroundColor3 = PANEL
crewPanel.Visible = false
crewPanel.Parent = gui
corner(crewPanel, 12)
local crewStroke = Instance.new("UIStroke", crewPanel)
crewStroke.Color = INK
crewStroke.Thickness = 2
text(crewPanel, "FARM CREW", 16, 8, 20)
local crewMessage = text(crewPanel, "Crew can drive your truck. Hay they run through your line pays you.", 12, 28, 30, INK, Enum.Font.Gotham)
local crewList = Instance.new("ScrollingFrame")
crewList.Position = UDim2.fromOffset(10, 62)
crewList.Size = UDim2.new(1, -20, 1, -72)
crewList.BackgroundTransparency = 1
crewList.BorderSizePixel = 0
crewList.ScrollBarThickness = 4
crewList.AutomaticCanvasSize = Enum.AutomaticSize.Y
crewList.CanvasSize = UDim2.new()
crewList.Parent = crewPanel
local crewLayout = Instance.new("UIListLayout", crewList)
crewLayout.Padding = UDim.new(0, 4)

local function myCrew()
	local index = player:GetAttribute("LandPlot") or 0
	local info = state:FindFirstChild("Plot" .. index)
	local set = {}
	for id in string.gmatch(info and info:GetAttribute("Crew") or "", "%d+") do
		set[tonumber(id)] = true
	end
	return set
end

local crewBusy = false
local function refreshCrew()
	for _, child in crewList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local crew = myCrew()
	local others = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			others += 1
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -6, 0, 36)
			row.BackgroundColor3 = CARD
			row.Parent = crewList
			corner(row, 6)
			local name = text(row, other.DisplayName, 14, 8, 20)
			name.Size = UDim2.new(1, -110, 0, 20)
			local on = crew[other.UserId] == true
			local b = button(row, on and "REMOVE" or "ADD", on and RED or GREEN)
			b.AnchorPoint = Vector2.new(1, 0.5)
			b.Position = UDim2.new(1, -6, 0.5, 0)
			b.Size = UDim2.fromOffset(84, 28)
			b.Activated:Connect(function()
				if crewBusy then
					return
				end
				crewBusy = true
				local ok, _, message = pcall(function()
					return crewRemote:InvokeServer(other.UserId, not on)
				end)
				crewBusy = false
				crewMessage.Text = ok and (message or "") or "Couldn't reach the server."
				task.defer(refreshCrew)
			end)
		end
	end
	if others == 0 then
		crewMessage.Text = "Nobody else is on this server yet."
	end
end

local function refreshExpand()
	local index = player:GetAttribute("LandPlot") or 0
	local info = state:FindFirstChild("Plot" .. index)
	local locked = info and info:GetAttribute("LockedRows") or 0
	expandButton.Visible = locked > 0
	expandButton.Text = ("EXPAND  $%d"):format(LandConfig.ExpansionPrice)
end
for _, info in state:GetChildren() do
	if info:IsA("Configuration") then
		info:GetAttributeChangedSignal("LockedRows"):Connect(refreshExpand)
	end
end
player:GetAttributeChangedSignal("LandPlot"):Connect(refreshExpand)
refreshExpand()
local expandBusy = false
expandButton.Activated:Connect(function()
	if expandBusy then
		return
	end
	expandBusy = true
	local ok, _, message = pcall(function()
		return expandRemote:InvokeServer()
	end)
	expandBusy = false
	infoLabel.Text = ok and (message or "") or "Couldn't reach the server."
	refreshExpand()
end)

crewButton.Activated:Connect(function()
	crewPanel.Visible = not crewPanel.Visible
	if crewPanel.Visible then
		refreshCrew()
	end
end)
Players.PlayerAdded:Connect(function()
	if crewPanel.Visible then
		refreshCrew()
	end
end)
Players.PlayerRemoving:Connect(function()
	if crewPanel.Visible then
		task.defer(refreshCrew)
	end
end)

local building = false
local selected = nil -- piece def, or nil while removing
local removing = false
local dirIndex = 2 -- E
local pieceButtons = {}
local tool = nil -- nil (place or remove), "move", "copy" or "paste"
local moving = nil -- { id, gx, gz, dir } of the piece picked up to move
local copyStart = nil -- first corner { gx, gz } of a copy
local clipboard = nil -- { list = { { id, dx, dz, dir } }, total } from the last copy
local aim = nil -- screen point { x, y, viewport = bool } the ghost follows
local target = nil -- { gx, gz, valid } under the aim

local ghost = Instance.new("Model")
ghost.Name = "BuildGhost"
local ghostParts = {}

local function setInfo(value, color)
	infoLabel.TextColor3 = color or INK
	infoLabel.Text = value
end

local function describeSelection()
	if tool == "move" then
		setInfo(moving and "Move: click where it goes. R turns it." or "Move: click a piece to pick it up.")
	elseif tool == "copy" then
		setInfo(copyStart and "Copy: click the opposite corner." or "Copy: click one corner of the area to copy.")
	elseif tool == "paste" then
		setInfo(clipboard and ("Paste: click where the copy's top-left corner goes. $%d for %d pieces."):format(clipboard.total, #clipboard.list)
			or "Copy an area first.")
	elseif removing then
		setInfo("Remove: click a piece on your land to take it back for half its price.")
	elseif selected then
		setInfo(("%s  ($%d): %s"):format(selected.name, selected.price, selected.blurb))
	else
		setInfo("Pick a piece, then click your land to place it. Belts carry bales the way the arrow points.")
	end
end

local function refreshPieceButtons()
	for id, b in pieceButtons do
		b.BackgroundColor3 = (selected and selected.id == id and not removing and not tool) and PICKED or CARD
	end
	removeButton.BackgroundColor3 = removing and not tool and PICKED or RED
	moveButton.BackgroundColor3 = tool == "move" and PICKED or MUTED
	copyButton.BackgroundColor3 = tool == "copy" and PICKED or MUTED
	pasteButton.BackgroundColor3 = tool == "paste" and PICKED or MUTED
end

local pieceDefs = {}
for _, def in LandConfig.Pieces do
	pieceDefs[def.id] = def
end

for i, def in LandConfig.Pieces do
	local b = Instance.new("TextButton")
	b.LayoutOrder = i
	b.Size = UDim2.fromOffset(118, 52)
	b.BackgroundColor3 = CARD
	b.Font = F.Bold
	b.TextSize = 13
	b.TextWrapped = true
	b.TextColor3 = INK
	b.Text = ("%s\n$%d"):format(def.name, def.price)
	b.Parent = pieceRow
	corner(b, 6)
	pieceButtons[def.id] = b
	b.Activated:Connect(function()
		selected = def
		removing = false
		tool, moving, copyStart = nil, nil, nil
		refreshPieceButtons()
		describeSelection()
	end)
end

local function myPlot()
	local index = player:GetAttribute("LandPlot") or 0
	return index > 0 and plotInfos()[index] or nil
end

local function cellsFor(def, gx, gz, dir)
	local d = DIR_VECTORS[dir]
	local fx, fz = math.round(d.X), math.round(d.Z)
	local rx, rz = -fz, fx
	local cells = {}
	for across = 0, def.size[1] - 1 do
		for along = 0, def.size[2] - 1 do
			table.insert(cells, { gx + fx * along + rx * across, gz + fz * along + rz * across })
		end
	end
	return cells
end

local function takenSet(info)
	local set = {}
	for k in string.gmatch(info:GetAttribute("Taken") or "", "[^;]+") do
		set[k] = true
	end
	return set
end

local function ghostPart(i)
	local p = ghostParts[i]
	if not p then
		p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Transparency = 0.55
		p.Parent = ghost
		ghostParts[i] = p
	end
	return p
end

local function hideGhost()
	ghost.Parent = nil
	target = nil
end

-- Where the aim meets the ground (y = 0), ignoring everything built on it.
local function groundPoint()
	local camera = Workspace.CurrentCamera
	local ray
	if aim and not aim.viewport then
		ray = camera:ScreenPointToRay(aim.x, aim.y)
	else
		local m = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(m.X, m.Y)
	end
	if math.abs(ray.Direction.Y) < 1e-3 then
		return nil
	end
	local t = -ray.Origin.Y / ray.Direction.Y
	if t <= 0 or t > 600 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

local function updateGhost()
	local info = myPlot()
	if not building or not info or (not selected and not removing and not tool) then
		hideGhost()
		return
	end
	local point = groundPoint()
	if not point then
		hideGhost()
		return
	end
	local origin = info:GetAttribute("Corner")
	local tilesX, tilesZ = info:GetAttribute("TilesX"), info:GetAttribute("TilesZ")
	local gx = math.floor((point.X - origin.X) / T)
	local gz = math.floor((point.Z - origin.Z) / T)
	local taken = takenSet(info)
	local dir = DIRS[dirIndex]
	local locked = info:GetAttribute("LockedRows") or 0
	local open = info:GetAttribute("Open")
	local function onPlot(x, z)
		local fromBack = open == "S" and z or tilesZ - 1 - z
		return x >= 0 and z >= 0 and x < tilesX and z < tilesZ and fromBack >= locked
	end
	-- What the ghost covers, and whether the click would work. picking = the cells must hold something.
	local cells, valid, picking, cost, showArrow = {}, true, false, 0, true
	local own = {}
	if tool == "move" and moving then
		local def = pieceDefs[moving.id]
		for _, cell in cellsFor(def, moving.gx, moving.gz, moving.dir) do
			own[cell[1] .. "," .. cell[2]] = true
		end
		cells = cellsFor(def, gx, gz, dir)
	elseif tool == "copy" then
		local sx, sz = copyStart and copyStart.gx or gx, copyStart and copyStart.gz or gz
		for x = math.min(sx, gx), math.max(sx, gx) do
			for z = math.min(sz, gz), math.max(sz, gz) do
				table.insert(cells, { x, z })
			end
		end
		showArrow = false
	elseif tool == "paste" then
		if clipboard then
			for _, entry in clipboard.list do
				for _, cell in cellsFor(pieceDefs[entry.id], gx + entry.dx, gz + entry.dz, entry.dir) do
					table.insert(cells, cell)
				end
			end
			cost = clipboard.total
		else
			cells = { { gx, gz } }
			valid = false
		end
		showArrow = false
	elseif tool == "move" or removing then
		cells = { { gx, gz } }
		picking = true
		showArrow = false
	else
		cells = cellsFor(selected, gx, gz, dir)
		cost = selected.price
	end
	for _, cell in cells do
		local x, z = cell[1], cell[2]
		local k = x .. "," .. z
		local free = not taken[k] or own[k]
		if not onPlot(x, z) or (picking and free) or (not picking and tool ~= "copy" and not free) then
			valid = false
		end
	end
	if cost > 0 and (player:GetAttribute("Cash") or 0) < cost then
		valid = false
	end
	local color = valid and Color3.fromRGB(120, 200, 120) or Color3.fromRGB(220, 90, 80)
	if picking and valid then
		color = removing and not tool and Color3.fromRGB(230, 150, 60) or Color3.fromRGB(110, 160, 230)
	elseif tool == "copy" then
		color = Color3.fromRGB(110, 160, 230)
	end
	for i, cell in cells do
		local p = ghostPart(i)
		p.Size = Vector3.new(T - 0.4, picking and 4.2 or 0.5, T - 0.4)
		p.CFrame = CFrame.new(origin + Vector3.new((cell[1] + 0.5) * T, picking and 2.1 or 0.35, (cell[2] + 0.5) * T))
		p.Color = color
		p.Transparency = 0.55
	end
	-- An arrow on the first cell shows which way the piece faces.
	local arrow = ghostPart(#cells + 1)
	local d = DIR_VECTORS[dir]
	local first = origin + Vector3.new((cells[1][1] + 0.5) * T, Factory.BeltTop + 0.4, (cells[1][2] + 0.5) * T)
	arrow.Size = Vector3.new(1, 0.3, 3.5)
	arrow.CFrame = CFrame.lookAt(first, first + d)
	arrow.Color = color
	arrow.Transparency = showArrow and 0.2 or 1
	for i = #cells + 2, #ghostParts do
		ghostParts[i].Transparency = 1
	end
	ghost.Parent = Workspace
	target = { gx = gx, gz = gz, valid = valid }
end

local function call(remote, ...)
	busy = true
	local out = table.pack(pcall(remote.InvokeServer, remote, ...))
	busy = false
	if not out[1] then
		setInfo("Couldn't reach the server. Try again.", RED)
		return false
	end
	return table.unpack(out, 2, out.n)
end

local function report(done, message)
	if message then
		setInfo(message, done and GREEN or RED)
	end
end

local function act()
	if not building or not target or busy then
		return
	end
	local t = target
	if tool == "move" then
		if not moving then
			local ok, info = call(pickRemote, t.gx, t.gz)
			if ok and typeof(info) == "table" and pieceDefs[info.id] then
				moving = info
				selected = pieceDefs[info.id]
				dirIndex = table.find(DIRS, info.dir) or dirIndex
				describeSelection()
			end
			return
		end
		local done, message = call(moveRemote, moving.gx, moving.gz, t.gx, t.gz, DIRS[dirIndex])
		report(done, message)
		if done then
			moving = nil
		end
	elseif tool == "copy" then
		if not copyStart then
			copyStart = { gx = t.gx, gz = t.gz }
			describeSelection()
			return
		end
		local ok, list, total = call(copyRemote, copyStart.gx, copyStart.gz, t.gx, t.gz)
		copyStart = nil
		if ok and typeof(list) == "table" then
			clipboard = { list = list, total = total or 0 }
			tool = "paste"
			refreshPieceButtons()
			describeSelection()
		else
			report(false, list)
		end
	elseif tool == "paste" then
		if clipboard then
			report(call(pasteRemote, clipboard.list, t.gx, t.gz))
		end
	elseif removing then
		report(call(removeRemote, t.gx, t.gz))
	else
		report(call(placeRemote, selected.id, t.gx, t.gz, DIRS[dirIndex]))
	end
end

local function setTool(name)
	tool = tool ~= name and name or nil
	moving, copyStart = nil, nil
	removing = false
	refreshPieceButtons()
	describeSelection()
end

local function undo()
	if busy then
		return
	end
	report(call(undoRemote))
end

local function rotate()
	dirIndex = dirIndex % 4 + 1
end

local function toggleRemove()
	tool, moving, copyStart = nil, nil, nil
	removing = not removing
	refreshPieceButtons()
	describeSelection()
end

local function setBuilding(on)
	building = on
	bar.Visible = on
	if not on then
		crewPanel.Visible = false
	end
	buildButton.Visible = not on and (player:GetAttribute("LandPlot") or 0) > 0
	if on then
		aim = nil
		describeSelection()
		refreshPieceButtons()
	else
		hideGhost()
	end
end

buildButton.Activated:Connect(function()
	setBuilding(true)
end)
doneButton.Activated:Connect(function()
	setBuilding(false)
end)
placeButton.Activated:Connect(act)
rotateButton.Activated:Connect(rotate)
removeButton.Activated:Connect(toggleRemove)
undoButton.Activated:Connect(undo)
moveButton.Activated:Connect(function()
	setTool("move")
end)
copyButton.Activated:Connect(function()
	setTool("copy")
end)
pasteButton.Activated:Connect(function()
	setTool("paste")
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not building or gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		aim = nil
		act()
	elseif input.UserInputType == Enum.UserInputType.Touch then
		-- On a touch screen a tap moves the ghost; PLACE builds it.
		aim = { x = input.Position.X, y = input.Position.Y, viewport = false }
	elseif input.KeyCode == Enum.KeyCode.R then
		rotate()
	elseif input.KeyCode == Enum.KeyCode.X then
		toggleRemove()
	elseif input.KeyCode == Enum.KeyCode.Z then
		undo()
	elseif input.KeyCode == Enum.KeyCode.M then
		setTool("move")
	elseif input.KeyCode == Enum.KeyCode.C then
		setTool("copy")
	elseif input.KeyCode == Enum.KeyCode.V then
		setTool("paste")
	end
end)

RunService.RenderStepped:Connect(updateGhost)

local function onPlotChanged()
	if (player:GetAttribute("LandPlot") or 0) == 0 then
		setBuilding(false)
		buildButton.Visible = false
	else
		buildButton.Visible = not building
	end
	refreshPanel()
end
player:GetAttributeChangedSignal("LandPlot"):Connect(onPlotChanged)
onPlotChanged()
