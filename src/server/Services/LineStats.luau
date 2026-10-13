--!nonstrict
-- What a farm's lines are doing, for the stats board on each plot: bales sorted, needles found and dollars earned per
-- minute over the last few minutes, so a player sees an upgrade pay off. Machines.luau records into it; anything can.
--
--   LineStats.record(ownerId, "bales" | "needles" | "cash", amount)
--   LineStats.perMinute(ownerId, kind)      -- average over the last WINDOW seconds
--   LineStats.board(parent, cframe, getOwnerId)  -- a standing board; cframe is its ground point, facing its readers
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldLabel = require(Shared.WorldLabel)

local LineStats = {}

local WINDOW = 300 -- seconds
local BOARD = Vector3.new(6, 4.2, 0.4)

local log = {} -- ownerId -> { kind -> { { t, amount } } }

local function trim(list, now)
	while list[1] and now - list[1][1] > WINDOW do
		table.remove(list, 1)
	end
end

function LineStats.record(ownerId, kind, amount)
	if not ownerId or not amount or amount <= 0 then
		return
	end
	local byKind = log[ownerId] or {}
	log[ownerId] = byKind
	local list = byKind[kind] or {}
	byKind[kind] = list
	local now = os.clock()
	table.insert(list, { now, amount })
	trim(list, now)
end

function LineStats.perMinute(ownerId, kind)
	local list = log[ownerId] and log[ownerId][kind]
	if not list or #list == 0 then
		return 0
	end
	local now = os.clock()
	trim(list, now)
	local total = 0
	for _, e in list do
		total += e[2]
	end
	-- Average over the time since the first entry (at least a minute), so a fresh line does not read as huge.
	local span = math.clamp(now - (list[1] and list[1][1] or now), 60, WINDOW)
	return total / span * 60
end

Players.PlayerRemoving:Connect(function(player)
	log[player.UserId] = nil
end)

local function fmt(n)
	if n >= 1e6 then
		return ("%.1fM"):format(n / 1e6)
	elseif n >= 1e4 then
		return ("%.0fk"):format(n / 1e3)
	elseif n >= 10 then
		return ("%d"):format(math.round(n))
	end
	return ("%.1f"):format(n)
end

function LineStats.board(parent, cframe, getOwnerId)
	local model = Instance.new("Model")
	model.Name = "LineStatsBoard"
	model.Parent = parent
	local function part(name, size, cf, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.Parent = model
		return p
	end
	for _, x in { -1, 1 } do
		part("Post", Vector3.new(0.4, 6.4, 0.4), cframe * CFrame.new(x * (BOARD.X / 2 - 0.2), 3.2, 0.3), Color3.fromRGB(133, 110, 82), Enum.Material.WoodPlanks)
	end
	local board = part("Board", BOARD, cframe * CFrame.new(0, 4, 0), Color3.fromRGB(70, 60, 48), Enum.Material.WoodPlanks)
	local label = WorldLabel.billboard(board, "LINE STATS", { offset = Vector3.new(0, 0, 0), kind = "status" })
	label.Parent.Size = UDim2.fromOffset(220, 120)
	label.Parent.MaxDistance = 60

	task.spawn(function()
		while model.Parent do
			local ownerId = getOwnerId()
			if ownerId then
				label.Text = ("LINE STATS (5 min)\n%s bales/min\n%s needles/min\n$%s/min"):format(
					fmt(LineStats.perMinute(ownerId, "bales")),
					fmt(LineStats.perMinute(ownerId, "needles")),
					fmt(LineStats.perMinute(ownerId, "cash"))
				)
			else
				label.Text = "LINE STATS\nno owner"
			end
			task.wait(2)
		end
	end)
	return model
end

return LineStats
