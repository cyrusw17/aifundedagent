--!nonstrict
-- Global leaderboards at base camp (CEO "Addiction push" H4): two wooden boards east of the spawn, facing it.
--   TOP SELLERS    most money ever made selling (Bank account `sold`), the best of a player's save slots
--   RAREST NEEDLE  the most valuable needle type a player has ever found (Codex), the best of their save slots
-- Each board is an OrderedDataStore keyed by UserId. Scores only ever go up (UpdateAsync keeps the higher one), so a
-- weaker save slot never lowers a player's place. Online players' live scores are merged in on every redraw, so the
-- board moves while people play even between store reads.
-- Without DataStore access (Studio with API access off, or the store erroring) the boards show the players on this
-- server. Studio never writes, so test money (InfiniteMoney) can't reach the live boards.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Needles = require(Shared.Config.Needles)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)

local Leaderboards = {}

-- East of the spawn pad (0, 14), between the sell pad (z -10 to -2) and the main road (z 19 and up), inside the
-- Meadow BaseCamp flat and KeepClear zone, clear of the glove stand (12.5, -6) and the needle price board (34, -8). The boards face west, toward the spawn.
Leaderboards.SITE = Vector3.new(26, 0, 8.5)
local ROWS = 10
local READ_EVERY = 120 -- seconds between store reads (GetSortedAsync), per board
local WRITE_EVERY = 120 -- seconds between score writes for one player

-- Needle types from least to most valuable; a player's rarest needle is stored as its place in this list (0 = none).
local byValue = table.clone(Needles)
table.sort(byValue, function(a, b)
	return a.sortedValue < b.sortedValue
end)
local rankOf = {}
for i, n in byValue do
	rankOf[n.id] = i
end

local function rarestRank(state)
	local best = 0
	local codex = typeof(state.codex) == "table" and state.codex.needles
	if typeof(codex) == "table" then
		for id, found in codex do
			if found and rankOf[id] and rankOf[id] > best then
				best = rankOf[id]
			end
		end
	end
	return best
end

local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local BOARDS = {
	{
		id = "sold",
		title = "TOP SELLERS",
		store = "NeedlewoodTopSold_v1",
		score = function(state)
			return math.floor(Bank.account(state).sold)
		end,
		show = function(value)
			return "$" .. commas(value)
		end,
	},
	{
		id = "rarest",
		title = "RAREST NEEDLE",
		store = "NeedlewoodRarestNeedle_v1",
		score = rarestRank,
		show = function(value)
			local n = byValue[value]
			return n and n.name or "?"
		end,
	},
}

local function orderedStore(name)
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return ok and store or nil
end

local names = {}
local function nameOf(userId)
	if names[userId] == nil then
		local online = Players:GetPlayerByUserId(userId)
		if online then
			names[userId] = online.DisplayName
		else
			local ok, name = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			names[userId] = ok and name or ("Farmer " .. userId)
		end
	end
	return names[userId]
end

-- The top `n` of stored entries ({ [userId] = score }) and live scores, each player once at their higher score.
local function merge(stored, live, n)
	local best = {}
	for userId, score in stored do
		best[userId] = score
	end
	for userId, score in live do
		if score > (best[userId] or 0) then
			best[userId] = score
		end
	end
	local list = {}
	for userId, score in best do
		if score > 0 then
			table.insert(list, { userId = userId, score = score })
		end
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.userId < b.userId
	end)
	for i = #list, n + 1, -1 do
		table.remove(list, i)
	end
	return list
end

local live = {} -- board id -> { [userId] = score } for players on this server
local written = {} -- board id -> { [userId] = score } last written from this server
local stored = {} -- board id -> { [userId] = score } from the last store read
for _, def in BOARDS do
	live[def.id] = {}
	written[def.id] = {}
	stored[def.id] = {}
end

local function canWrite()
	return not RunService:IsStudio()
end

-- Reads a player's scores from their loaded save into `live`.
local function sample(player)
	local state = Data.get(player)
	if not state then
		return
	end
	for _, def in BOARDS do
		local ok, value = pcall(def.score, state)
		if ok and typeof(value) == "number" and value == value and value > 0 then
			live[def.id][player.UserId] = math.max(live[def.id][player.UserId] or 0, value)
		end
	end
end

-- Writes a player's live scores that went up since the last write. UpdateAsync keeps the higher of the stored and
-- new score, and cancels (returns nil) when nothing would change, so it never lowers a score.
-- `scores` is a snapshot ({ [board id] = score }) taken before the first yield, so a player leaving mid-write can't
-- change what is written.
local function flush(userId, scores)
	if not canWrite() then
		return
	end
	for _, def in BOARDS do
		local value = scores[def.id]
		if value and value > (written[def.id][userId] or 0) then
			local store = orderedStore(def.store)
			local ok = store ~= nil and pcall(function()
				store:UpdateAsync(tostring(userId), function(old)
					if typeof(old) == "number" and old >= value then
						return nil
					end
					return value
				end)
			end)
			if ok then
				written[def.id][userId] = math.max(written[def.id][userId] or 0, value)
			end
		end
	end
end

local function snapshot(userId)
	local scores = {}
	for _, def in BOARDS do
		scores[def.id] = live[def.id][userId]
	end
	return scores
end

local function read(def)
	local store = orderedStore(def.store)
	if not store then
		return
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, ROWS):GetCurrentPage()
	end)
	if ok then
		local fresh = {}
		for _, entry in page do
			local userId = tonumber(entry.key)
			if userId and typeof(entry.value) == "number" then
				fresh[userId] = entry.value
			end
		end
		stored[def.id] = fresh
	end
end

-- A plank board on two posts at `center`, its face toward -X (the spawn). Returns the TextLabels for each row.
local function buildBoard(parent, def, center)
	local model = Instance.new("Model")
	model.Name = "Leaderboard_" .. def.id
	model.Parent = parent
	local facing = CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0) -- Front (-Z) turned to face -X
	local W, H, BOTTOM = 7, 8.5, 1.6
	local function part(name, size, cf, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Anchored = true
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	for _, sx in { -1, 1 } do
		part("Post", Vector3.new(0.6, BOTTOM + H + 0.8, 0.6), facing * CFrame.new(sx * (W / 2 + 0.3), (BOTTOM + H + 0.8) / 2, 0.1), Rustic.WoodDark, Enum.Material.Wood)
	end
	local panel = part("Board", Vector3.new(W, H, 0.4), facing * CFrame.new(0, BOTTOM + H / 2, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	part("Cap", Vector3.new(W + 1.6, 0.4, 1.2), facing * CFrame.new(0, BOTTOM + H + 0.95, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	gui.Parent = panel
	local sheet = Instance.new("Frame")
	sheet.Size = UDim2.fromScale(0.9, 0.9)
	sheet.Position = UDim2.fromScale(0.05, 0.05)
	sheet.BackgroundColor3 = Rustic.Cloth
	sheet.BorderSizePixel = 0
	sheet.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = sheet
	local function line(order, height, text, bold)
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.new(1, -16, height, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(40, 34, 28)
		label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
		label.TextScaled = true
		label.TextXAlignment = bold and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
		label.Text = text
		label.Parent = sheet
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 16)
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 4)
		pad.Parent = label
		return label
	end
	line(0, 0.13, def.title, true)
	local rows = {}
	for i = 1, ROWS do
		rows[i] = line(i, 0.085, "", false)
	end
	WorldLabel.billboard(panel, def.title, { offset = Vector3.new(0, H / 2 + 2.2, 0), kind = "sign" })
	return rows
end

local function redraw(def, rows)
	local list = merge(stored[def.id], live[def.id], ROWS)
	for i = 1, ROWS do
		local entry = list[i]
		if entry then
			rows[i].Text = ("%d. %s  %s"):format(i, nameOf(entry.userId), def.show(entry.score))
		elseif i == 1 then
			rows[i].Text = "Nobody yet. Sell some hay!"
		else
			rows[i].Text = ""
		end
	end
end

function Leaderboards.build(worldFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = worldFolder
	local boards = {}
	for i, def in BOARDS do
		-- Side by side along Z, 8.5 studs apart: posts and all, the pair spans z 0.4 to 16.6 at x 25.5 to 26.5.
		local center = Leaderboards.SITE + Vector3.new(0, 0, (i - 1.5) * 8.5)
		boards[def.id] = buildBoard(folder, def, center)
		redraw(def, boards[def.id])
	end

	local lastWrite = {}
	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		sample(player)
		task.spawn(flush, userId, snapshot(userId))
		lastWrite[player] = nil
		for _, def in BOARDS do
			live[def.id][userId] = nil -- their stored score stays on the board from the next read
		end
	end)

	task.spawn(function()
		local lastRead = -math.huge
		while folder.Parent do
			for _, player in Players:GetPlayers() do
				sample(player)
				if os.clock() - (lastWrite[player] or 0) >= WRITE_EVERY then
					lastWrite[player] = os.clock()
					task.spawn(flush, player.UserId, snapshot(player.UserId))
				end
			end
			if os.clock() - lastRead >= READ_EVERY then
				lastRead = os.clock()
				for _, def in BOARDS do
					read(def)
				end
			end
			for _, def in BOARDS do
				redraw(def, boards[def.id])
			end
			task.wait(15)
		end
	end)
end

-- For SelfTests only.
Leaderboards.test = {
	rarestRank = rarestRank,
	merge = merge,
	commas = commas,
	byValue = byValue,
	boards = BOARDS,
}

return Leaderboards
