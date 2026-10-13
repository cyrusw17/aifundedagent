--!nonstrict
-- The weekly region festival (Addiction push H11). Each week one region (Config/WorldMap FestivalOrder, in turn,
-- counted from FestivalEpoch so every server agrees) holds its hay festival:
--   * its field bales carry FestivalBoost times the needles (NeedleBoost; never stacked on the rich field's 2x),
--   * bunting and a banner go up beside its first field,
--   * a player who visits it that week earns that week's festival ribbon (cosmetic, saved as state.festivals,
--     published as the player attribute FestivalRibbons = count).
-- ReplicatedStorage attributes for the HUD countdown strip: FestivalRegion (id), FestivalName and FestivalEnds
-- (server time the week ends).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local WorldRegions = require(Shared.WorldRegions)
local WorldShape = require(script.Parent.WorldShape)
local Regions = require(script.Parent.Regions)
local Data = require(script.Parent.Data)
local Announce = require(script.Parent.Announce)

local Festival = {}

local CHECK_EVERY = 15 -- seconds
local FLAG_COLORS = { Color3.fromRGB(196, 72, 60), Color3.fromRGB(232, 190, 84), Color3.fromRGB(80, 128, 168), Color3.fromRGB(236, 228, 206) }

local names = {}
for _, r in Map.Regions do
	names[r.id] = r.name
end

-- The week number for a unix time (0 = the week starting FestivalEpoch).
function Festival.week(t)
	return math.floor((t - Map.FestivalEpoch) / Map.FestivalWeek)
end

-- The festival region for a week number.
function Festival.regionFor(week)
	local order = Map.FestivalOrder
	return order[week % #order + 1]
end

-- This week's festival: { week, region, name, starts, ends } (unix times).
function Festival.at(t)
	local week = Festival.week(t)
	local region = Festival.regionFor(week)
	local starts = Map.FestivalEpoch + week * Map.FestivalWeek
	return { week = week, region = region, name = names[region] or region, starts = starts, ends = starts + Map.FestivalWeek }
end

local current = nil
local folder = nil

function Festival.current()
	return current
end

local function part(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Bunting round the region's first field: four poles with flag strings between them, and a banner.
local function decorate(fest)
	if folder then
		folder:ClearAllChildren()
	end
	local entry = nil
	for _, f in Regions.fields do
		if f.region == fest.name then
			entry = f
			break
		end
	end
	if not entry or not folder then
		return
	end
	local c = entry.center
	local corners = {}
	for i, o in { Vector2.new(-15, -15), Vector2.new(15, -15), Vector2.new(15, 15), Vector2.new(-15, 15) } do
		local x, z = c.X + o.X, c.Z + o.Y
		local y = WorldShape.heightAt(x, z)
		part(folder, "FestivalPole", Vector3.new(0.5, 10, 0.5), CFrame.new(x, y + 5, z), Color3.fromRGB(92, 70, 52), Enum.Material.Wood)
		corners[i] = Vector3.new(x, y + 9.6, z)
	end
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		local n = 7
		for k = 1, n do
			local p = a:Lerp(b, k / (n + 1)) - Vector3.new(0, math.sin(k / (n + 1) * math.pi) * 1.5, 0)
			local flag = part(folder, "FestivalFlag", Vector3.new(0.1, 1.2, 1), CFrame.lookAt(p, p + (b - a)) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, -0.6, 0), FLAG_COLORS[(i + k) % #FLAG_COLORS + 1])
			flag.CanCollide = false
			flag.CastShadow = false
		end
	end
	local top = corners[1]:Lerp(corners[2], 0.5) + Vector3.new(0, 1.5, 0)
	local banner = part(folder, "FestivalBanner", Vector3.new(14, 3, 0.3), CFrame.new(top), Color3.fromRGB(196, 72, 60))
	banner.CanCollide = false
	pcall(Regions.billboard, banner, ("%s HAY FESTIVAL\n+50%% needles all week"):format(string.upper(fest.name)), Vector3.new(0, 3, 0), 300)
end

-- Gives the festival's fields their boost (and takes it back from last week's), every few seconds so regrown bales
-- get it too. The rich field's own 2x is left alone.
local function boostFields(fest)
	for _, entry in Regions.fields do
		local on = entry.region == fest.name
		for b in entry.bales do
			local body = b.body
			if body and body.Parent then
				local marked = body:GetAttribute("FestivalBoost") == true
				if on and (body:GetAttribute("NeedleBoost") or 1) < Map.FestivalBoost then
					body:SetAttribute("NeedleBoost", Map.FestivalBoost)
					body:SetAttribute("FestivalBoost", true)
				elseif not on and marked then
					body:SetAttribute("FestivalBoost", nil)
					if not entry.rich then
						body:SetAttribute("NeedleBoost", nil)
					end
				end
			end
		end
	end
end

local function publish(player)
	local state = Data.get(player)
	local n = 0
	for _ in (state and state.festivals or {}) do
		n += 1
	end
	player:SetAttribute("FestivalRibbons", n)
end

-- A player standing in the festival region earns this week's ribbon (once). Returns true when it was new.
function Festival.visit(player, position)
	local state = Data.get(player)
	local region = current and WorldRegions.at(position)
	if not state or not region or region.id ~= current.region then
		return false
	end
	state.festivals = state.festivals or {}
	local key = current.week .. ":" .. current.region
	if state.festivals[key] then
		return false
	end
	state.festivals[key] = 1
	publish(player)
	Data.toast(player, ("Festival ribbon: %s Hay Festival! Bales here hold 50%% more needles all week."):format(current.name))
	return true
end

-- Moves the festival on when the week turns (and on start). `t` is a unix time (tests pass their own).
function Festival.refresh(t)
	local fest = Festival.at(t or os.time())
	local changed = not current or current.week ~= fest.week
	current = fest
	ReplicatedStorage:SetAttribute("FestivalRegion", fest.region)
	ReplicatedStorage:SetAttribute("FestivalName", fest.name)
	ReplicatedStorage:SetAttribute("FestivalEnds", fest.ends)
	if changed then
		pcall(decorate, fest)
		if t == nil then
			pcall(Announce.say, ("This week's festival: %s! Its hay holds 50%% more needles until the week turns."):format(fest.name), "event")
		end
	end
	boostFields(fest)
	return fest
end

local started = false
function Festival.start(parent)
	if started then
		return
	end
	started = true
	folder = Instance.new("Model")
	folder.Name = "Festival"
	folder.Parent = parent
	Data.loaded.Event:Connect(publish)
	Festival.refresh()
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			local ok, err = pcall(Festival.refresh)
			if not ok then
				warn("[Needlewood] festival: " .. tostring(err))
			end
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					pcall(Festival.visit, player, root.Position)
				end
			end
		end
	end)
end

return Festival
