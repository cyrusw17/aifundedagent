--!nonstrict
-- The needle market (V8 "server market"). Each server keeps its own price for every needle type. Selling a type pushes
-- its price down, and the push fades with a half-life, so a flooded type recovers in a few minutes. A type nobody has
-- sold lately pays up to Swing above its list price, and a flooded one down to Swing below. That nudges players toward
-- other regions without ever making a needle worthless. Numbers are in Config/Prices (Market).
--
-- Needle.priceOf applies Market.multiplier, so every needle sale, display and ding follows the market. Sales are
-- recorded with Market.sold where needles are actually sold (Needle.sellHeld, the needle bin's SELL NEEDLES pad).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Prices = require(Shared.Config.Prices)
local NeedleTypes = require(Shared.Config.Needles)

local Market = {}

local Terms = Prices.Market
local pressure = {} -- needle id -> recent sales, fading with HalfLifeSeconds
local updated = {} -- needle id -> os.clock() of the last fade

local function fade(id)
	local now = os.clock()
	local p = pressure[id] or 0
	if p > 0 then
		p *= 0.5 ^ ((now - (updated[id] or now)) / Terms.HalfLifeSeconds)
	end
	pressure[id] = p
	updated[id] = now
	return p
end

-- How many recent sales put a type at exactly its list price. Rarer needles sell in smaller numbers, so they need fewer.
local function normal(id)
	local base = Prices.Needles[id] or 100
	return math.max(Terms.MinNormalSales, Terms.NormalSales * 100 / base)
end

-- Share of list price this server pays for a needle type right now: 1 - Swing .. 1 + Swing.
function Market.multiplier(id)
	if not id then
		return 1
	end
	local p = fade(id)
	local k = normal(id)
	return 1 + Terms.Swing - 2 * Terms.Swing * p / (p + k)
end

function Market.sold(id, count)
	if id and count and count > 0 then
		pressure[id] = fade(id) + count
	end
end

-- Rebuilds the price board text: every needle type, its price here, and an arrow against list price.
function Market.boardText()
	local lines = { "NEEDLE PRICES TODAY" }
	for _, def in NeedleTypes do
		local m = Market.multiplier(def.id)
		local arrow = m > 1.02 and "▲" or m < 0.98 and "▼" or "•"
		table.insert(lines, ("%s  $%d  %s%d%%"):format(def.name, math.floor(def.sortedValue * m + 0.5), arrow, math.round((m - 1) * 100)))
	end
	return table.concat(lines, "\n")
end

-- A wooden price board beside the hay shop, refreshed every few seconds.
function Market.build(parent, position)
	local post = Instance.new("Part")
	post.Name = "NeedlePriceBoard"
	post.Size = Vector3.new(7, 9, 0.6)
	post.CFrame = CFrame.new(position + Vector3.new(0, 4.5, 0))
	post.Anchored = true
	post.Material = Enum.Material.WoodPlanks
	post.Color = Color3.fromRGB(120, 98, 72)
	post.Parent = parent
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(280, 360)
		gui.Parent = post
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(236, 226, 200)
		label.Parent = gui
	end
	task.spawn(function()
		while post.Parent do
			local text = Market.boardText()
			for _, gui in post:GetChildren() do
				if gui:IsA("SurfaceGui") then
					gui.TextLabel.Text = text
				end
			end
			task.wait(5)
		end
	end)
	return post
end

return Market
