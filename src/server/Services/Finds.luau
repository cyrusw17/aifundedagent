--!nonstrict
-- Foreign objects that tumble out of a burst bale now and then (Config/Finds). A find is a real part on the ground;
-- click it to keep it. Kept finds are counted per save slot (state.finds) and published as the player attribute
-- "Finds" ("boot:2,ring:1") for the collection book. The first of each kind pays its finder's reward.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local FindsConfig = require(ReplicatedStorage.Shared.Config.Finds)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Announce = require(script.Parent.Announce)
local Feedback = require(script.Parent.Feedback)
local Groups = require(script.Parent.Groups)
local Props = require(script.Parent.Props)

local Finds = {}

local rng = Random.new()
local byId = {}
for _, def in FindsConfig.Items do
	byId[def.id] = def
end
-- Rarest first, so one roll per bale gives each item its own odds.
local rarestFirst = table.clone(FindsConfig.Items)
table.sort(rarestFirst, function(a, b)
	return a.oneIn > b.oneIn
end)

local function publish(player)
	local state = Data.get(player)
	local list = {}
	for id, count in (state and state.finds or {}) do
		table.insert(list, ("%s:%d"):format(id, count))
	end
	table.sort(list)
	player:SetAttribute("Finds", table.concat(list, ","))
end

local function keep(player, part, def)
	local state = Data.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not state or not root or not part.Parent then
		return
	end
	if (part.Position - root.Position).Magnitude > FindsConfig.PickupReach + 2 then
		return
	end
	part:Destroy()
	state.finds = state.finds or {}
	local first = (state.finds[def.id] or 0) == 0
	state.finds[def.id] = (state.finds[def.id] or 0) + 1
	publish(player)
	Feedback.needle(root, def.reward * 2)
	if first then
		Bank.earn(player, def.reward, "Finder's reward")
		Feedback.sale(player, def.reward)
		Data.toast(player, ("New find: %s! +$%d"):format(def.name, def.reward))
		if def.oneIn >= 1000 then
			Announce.say(("%s found a %s!"):format(player.DisplayName, def.name:lower()), "gold")
		end
	else
		Data.toast(player, ("%s (you have %d)"):format(def.name, state.finds[def.id]))
	end
end

local function spawnFind(def, position, velocity)
	local part = Instance.new("Part")
	part.Name = "Find_" .. def.id
	part.Size = Vector3.new(def.size[1], def.size[2], def.size[3])
	part.Color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	part.Material = Enum.Material[def.material] or Enum.Material.SmoothPlastic
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	part.CollisionGroup = Groups.Loose
	part.AssemblyLinearVelocity = velocity
	part:SetAttribute("FindId", def.id)

	-- Catches the eye like a needle does.
	local glint = Instance.new("Sparkles")
	glint.SparkleColor = Color3.fromRGB(255, 240, 200)
	glint.Parent = part

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = FindsConfig.PickupReach
	click.MouseClick:Connect(function(player)
		keep(player, part, def)
	end)
	click.Parent = part

	local model = def.prop and Props.has(def.prop) and Props.make(def.prop, part.CFrame, math.max(part.Size.X, part.Size.Y, part.Size.Z))
	if model then
		Props.weldTo(model, part, part)
	end
	part.Parent = workspace
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	Debris:AddItem(part, FindsConfig.DespawnSeconds)
	return part
end

-- One roll for a burst bale. Returns the find part, or nil when nothing turned up.
function Finds.roll(position)
	for _, def in rarestFirst do
		if rng:NextInteger(1, def.oneIn) == 1 then
			return spawnFind(def, position, Vector3.new(rng:NextNumber(-3, 3), 7, rng:NextNumber(-3, 3)))
		end
	end
	return nil
end

function Finds.info(id)
	return byId[id]
end

function Finds.init()
	Data.loaded.Event:Connect(publish)
	for _, player in Players:GetPlayers() do
		if Data.get(player) then
			publish(player)
		end
	end
end

return Finds
