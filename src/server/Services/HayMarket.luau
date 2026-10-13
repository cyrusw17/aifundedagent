--!nonstrict
-- The Hay Market (CEO backlog H6): a market stall at base camp that restocks every Prices.HayMarket.RestockSeconds
-- with a few rare bales: Golden Hay (more needles), Storm Hay (more needles, better mutation odds) and Moon Hay (a
-- long shot at a mutation). Each slot holds one kind of one region's hay, a few bales for the whole server, and each
-- player can buy only a couple per restock, so it is worth coming back for and never a way to skip farming.
--
-- Prices follow from what is inside (HayMarket.priceOf): PriceShare of the bale's value on a conveyor sorter. Money
-- moves through Bank.charge. A bought bale appears in front of the stall, owned by the buyer, and carries:
--   NeedleBoost    times the needles (Storm, Moon); Golden uses Bales.makeGolden, which Bales reads as GoldenField
--   MutationBoost  times each found needle's chance to mutate (for the sorter's roll, Conveyor)
--   RareBale       the kind id, for anything that wants to show it
-- ReplicatedStorage attribute HayMarketRestockAt is the server time (workspace:GetServerTimeNow()) of the next
-- restock, for the HUD countdown (UI H2). HayMarketStock is a one-line summary of what is on sale.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Prices = require(Shared.Config.Prices)
local GloveConfig = require(Shared.Config.Gloves)
local NeedleTypes = require(Shared.Config.Needles)
local WorldLabel = require(Shared.WorldLabel)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Bales = require(script.Parent.Bales)

local HayMarket = {}

local Terms = Prices.HayMarket
local rng = Random.new()

local slots = {} -- { kind, kindId, hayType, price, stock, pad, label, preview }
local bought = {} -- [userId] = bales bought this restock
local restockAt = 0
local onRestock = Instance.new("BindableEvent")
HayMarket.Restocked = onRestock.Event

-- Colors for the kinds that don't use the golden look.
local LOOKS = {
	storm = { color = Color3.fromRGB(108, 120, 142), light = Color3.fromRGB(170, 200, 255) },
	moon = { color = Color3.fromRGB(196, 204, 230), light = Color3.fromRGB(210, 220, 255) },
	golden = { color = Color3.fromRGB(222, 182, 72), light = Color3.fromRGB(255, 214, 120) },
}

local function needleFor(hayType)
	local hay = GloveConfig.HayTypes[hayType]
	for _, n in NeedleTypes do
		if hay and n.map == hay.map then
			return n
		end
	end
	return NeedleTypes[1]
end

-- What a bale of this kind and hay is worth sorted on the reference sorter, mutations included.
function HayMarket.valueOf(kindId, hayType)
	local kind = Terms.Kinds[kindId]
	local mutation = Prices.Mutation
	local found = (Prices.NeedlesPerBale[hayType] or Prices.NeedlesPerBale.meadow) * kind.needles * Terms.ReferenceRecovery
	local needle = Prices.Needles[needleFor(hayType).id] or 100
	local averageExtra = (mutation.min + mutation.max) / 2 - 1
	local mutated = found * math.min(1, kind.mutation / mutation.oneIn) * averageExtra * needle
	return Prices.HayPerBale * Prices.HayPrice + found * needle + mutated
end

-- The stall's price: PriceShare of the value, rounded to $10.
function HayMarket.priceOf(kindId, hayType)
	return math.max(10, math.floor(HayMarket.valueOf(kindId, hayType) * Terms.PriceShare / 10 + 0.5) * 10)
end

local function pick(weights)
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:NextNumber() * total
	for id, w in weights do
		roll -= w
		if roll <= 0 then
			return id
		end
	end
	local _, any = next(weights)
	return any
end

local function kindWeights()
	local out = {}
	for id, kind in Terms.Kinds do
		out[id] = kind.weight
	end
	return out
end

local function slotText(slot)
	local hay = GloveConfig.HayTypes[slot.hayType]
	local kind = Terms.Kinds[slot.kindId]
	local perks = {}
	if kind.needles > 1 then
		table.insert(perks, ("%sx needles"):format(tostring(kind.needles)))
	end
	if kind.mutation > 1 then
		table.insert(perks, ("%dx mutation odds"):format(kind.mutation))
	end
	return ("%s\n%s\n%s\n%s · %s"):format(
		kind.name:upper(),
		hay and hay.name or slot.hayType,
		table.concat(perks, ", "),
		Bank.money(slot.price),
		slot.stock > 0 and ("%d left"):format(slot.stock) or "SOLD OUT"
	)
end

local function summary()
	local parts = {}
	for _, slot in slots do
		if slot.stock > 0 then
			table.insert(parts, ("%s %s"):format(Terms.Kinds[slot.kindId].name, (GloveConfig.HayTypes[slot.hayType] or {}).name or slot.hayType))
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or "Sold out"
end

local function refresh()
	for _, slot in slots do
		if slot.label then
			slot.label.Text = slotText(slot)
		end
		if slot.preview then
			slot.preview.Transparency = slot.stock > 0 and 0 or 0.8
		end
	end
	ReplicatedStorage:SetAttribute("HayMarketStock", summary())
end

-- New stock in every slot, and everyone's per-restock allowance back.
function HayMarket.restock()
	table.clear(bought)
	local kinds = kindWeights()
	for _, slot in slots do
		slot.kindId = pick(kinds)
		slot.hayType = pick(Terms.HayTypes)
		slot.price = HayMarket.priceOf(slot.kindId, slot.hayType)
		slot.stock = Terms.StockPerSlot
		if slot.preview then
			local look = LOOKS[slot.kindId] or LOOKS.golden
			slot.preview.Color = look.color
			local light = slot.preview:FindFirstChildOfClass("PointLight")
			if light then
				light.Color = look.light
			end
		end
	end
	restockAt = Workspace:GetServerTimeNow() + Terms.RestockSeconds
	ReplicatedStorage:SetAttribute("HayMarketRestockAt", restockAt)
	refresh()
	onRestock:Fire()
end

-- Dresses a freshly spawned bale as its kind and marks what it carries.
local function dress(b, kindId)
	local kind = Terms.Kinds[kindId]
	local body = b.body
	if kindId == "golden" then
		Bales.makeGolden(b, false) -- GoldenField: Bales gives it Config.GoldenBaleNeedles (3x) the needles
	else
		local look = LOOKS[kindId]
		body.Color = look.color
		for _, d in body:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Twine" then
				d.Color = look.color
			end
		end
		local light = Instance.new("PointLight")
		light.Color = look.light
		light.Brightness = 1
		light.Range = 9
		light.Parent = body
		if kindId == "storm" then
			local sparkles = Instance.new("Sparkles")
			sparkles.SparkleColor = look.light
			sparkles.Parent = body
		end
		if kind.needles ~= 1 then
			body:SetAttribute("NeedleBoost", kind.needles)
		end
		b.prompt.ObjectText = ("%s bale"):format(kind.name)
	end
	if kind.mutation ~= 1 then
		body:SetAttribute("MutationBoost", kind.mutation)
	end
	body:SetAttribute("RareBale", kindId)
end

-- Sells one bale from slot i to player. Returns ok, a message, and the bale.
function HayMarket.buy(player, i)
	local slot = slots[i]
	if not slot or not Data.get(player) then
		return false, "Pick a save first."
	end
	if slot.stock <= 0 then
		return false, "That one is sold out. New stock soon."
	end
	if (bought[player.UserId] or 0) >= Terms.PerPlayer then
		return false, ("You can buy %d rare bales each restock. New stock soon."):format(Terms.PerPlayer)
	end
	local hay = GloveConfig.HayTypes[slot.hayType]
	local name = ("%s (%s)"):format(Terms.Kinds[slot.kindId].name, hay and hay.name or slot.hayType)
	local ok, why = Bank.charge(player, slot.price, "Hay Market: " .. name)
	if not ok then
		return false, why
	end
	slot.stock -= 1
	bought[player.UserId] = (bought[player.UserId] or 0) + 1
	local spot = slot.pad and (slot.pad.CFrame * CFrame.new(0, 2, -4)).Position or Vector3.new(0, 3, 0)
	local b = Bales.spawn(spot, false, true, slot.hayType)
	if b then
		b.ownerId = player.UserId
		dress(b, slot.kindId)
	end
	refresh()
	return true, ("Bought a %s bale. Sort it on your line for the best needles."):format(name), b
end

-- What is on sale right now (read by SelfTests/Economy).
function HayMarket.slots()
	return slots
end

function HayMarket.build(parent, position)
	local model = Instance.new("Model")
	model.Name = "HayMarket"
	model.Parent = parent
	local base = CFrame.new(position) * CFrame.Angles(0, math.rad(-90), 0) -- the stall's front faces +X, toward camp

	local function part(name, size, cframe, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cframe
		p.Anchored = true
		p.Color = color
		p.Material = material or Enum.Material.WoodPlanks
		p.Parent = model
		return p
	end
	local wood = Color3.fromRGB(128, 100, 72)
	part("Counter", Vector3.new(16, 3, 2), base * CFrame.new(0, 1.5, 1), wood)
	for _, x in { -7.5, 7.5 } do
		part("Post", Vector3.new(0.6, 9, 0.6), base * CFrame.new(x, 4.5, 1.6), wood)
		part("Post", Vector3.new(0.6, 9, 0.6), base * CFrame.new(x, 4.5, 4.6), wood)
	end
	local awning = part("Awning", Vector3.new(17, 0.3, 4.4), base * CFrame.new(0, 9.1, 3.1) * CFrame.Angles(math.rad(-8), 0, 0), Color3.fromRGB(150, 70, 58), Enum.Material.Fabric)
	WorldLabel.billboard(awning, "HAY MARKET\nrare bales, new stock every 5 min", { kind = "sign", offset = Vector3.new(0, 2.5, 0) })

	for i = 1, Terms.Slots do
		local x = (i - (Terms.Slots + 1) / 2) * 5
		local pad = part("Slot" .. i, Vector3.new(4, 0.3, 3), base * CFrame.new(x, 3.15, 1), Color3.fromRGB(92, 74, 54))
		local preview = part("Preview" .. i, Vector3.new(2.3, 1.3, 1.6), pad.CFrame * CFrame.new(0, 0.8, 0), LOOKS.golden.color, Enum.Material.Fabric)
		preview.CanCollide = false
		local light = Instance.new("PointLight")
		light.Range = 6
		light.Brightness = 0.8
		light.Parent = preview
		local label = WorldLabel.billboard(preview, "", { kind = "status", offset = Vector3.new(0, 3.2, 0) })
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Buy"
		prompt.ObjectText = "Rare bale"
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = preview
		local slot = { pad = pad, preview = preview, label = label, stock = 0 }
		slots[i] = slot
		prompt.Triggered:Connect(function(player)
			local _, message = HayMarket.buy(player, i)
			if message then
				Data.toast(player, message)
			end
		end)
	end

	HayMarket.restock()
	task.spawn(function()
		while model.Parent do
			task.wait(1)
			if Workspace:GetServerTimeNow() >= restockAt then
				HayMarket.restock()
			end
		end
	end)
	return model
end

return HayMarket
