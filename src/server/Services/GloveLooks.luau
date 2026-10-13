--!nonstrict
-- What a shovel tier looks like (gloves are gone; Config/Gloves now lists shovels). Every tier shares the one
-- Blender shovel mesh, so a tier shows as a band at the neck of the blade in its color and material, and its name
-- leads the shovel's hotbar tooltip ("Steel Shovel: ..."). Gloves.luau decides who owns and uses what (the player
-- attribute "GloveId"); this only dresses the Shovel tool, in the backpack or in the hand.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GloveConfig = require(ReplicatedStorage.Shared.Config.Gloves)
local ToolGuide = require(ReplicatedStorage.Shared.ToolGuide)

local GloveLooks = {}

local byId = {}
for _, def in GloveConfig.Tiers do
	byId[def.id] = def
end
for _, def in GloveConfig.QuestTiers do
	byId[def.id] = def
end

local BAND = "TierBand"
local NECK = CFrame.new(0, 1.42, 0) -- from the shovel's handle: where the shaft meets the blade (Avatar.buildShovel)

-- The band in a tier's color and material.
local function paint(band, def)
	band.Color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	local ok, material = pcall(function()
		return Enum.Material[def.material]
	end)
	band.Material = ok and material or Enum.Material.Metal
	local glow = band:FindFirstChild("Glow")
	if def.tier >= 5 and not glow then
		glow = Instance.new("PointLight")
		glow.Name = "Glow"
		glow.Color = band.Color:Lerp(Color3.new(1, 1, 1), 0.4)
		glow.Brightness = 0.8
		glow.Range = 5
		glow.Parent = band
	elseif def.tier < 5 and glow then
		glow:Destroy()
	end
end

-- Dresses one Shovel tool for a tier id (the starter Old Shovel when unknown).
function GloveLooks.dressTool(tool, gloveId)
	local def = byId[gloveId or "bare"] or GloveConfig.Tiers[1]
	local handle = tool and tool:FindFirstChild("Handle")
	if not handle then
		return
	end
	local band = tool:FindFirstChild(BAND)
	if not band then
		band = Instance.new("Part")
		band.Name = BAND
		band.Size = Vector3.new(0.42, 0.18, 0.42)
		band.CanCollide = false
		band.CanQuery = false
		band.CanTouch = false
		band.Massless = true
		band.CFrame = handle.CFrame * NECK
		local weld = Instance.new("Weld")
		weld.Part0 = handle
		weld.Part1 = band
		weld.C0 = NECK
		weld.Parent = band
		band.Parent = tool
	end
	paint(band, def)
	tool:SetAttribute("GloveId", def.id)
	tool.ToolTip = ("%s: %s"):format(def.name, ToolGuide.tool("Shovel"))
end

-- Dresses the player's shovel wherever it is (hand or backpack) for gloveId. character is the player's character.
function GloveLooks.dress(character, gloveId)
	local player = Players:GetPlayerFromCharacter(character)
	local backpack = player and player:FindFirstChild("Backpack")
	local tool = character:FindFirstChild("Shovel") or (backpack and backpack:FindFirstChild("Shovel"))
	if tool and tool:IsA("Tool") then
		GloveLooks.dressTool(tool, gloveId)
	end
end

local function dressShovel(player)
	local character = player.Character
	if character then
		GloveLooks.dress(character, player:GetAttribute("GloveId"))
	end
end

-- The shovels on the rack are already built in their tier's colors (Gloves.buildStand); kept so callers need no change.
function GloveLooks.dressStand(_stand) end

function GloveLooks.start()
	local function watch(player)
		player:GetAttributeChangedSignal("GloveId"):Connect(function()
			dressShovel(player)
		end)
		-- Avatar hands out a fresh shovel with each character; dress it as it lands in the backpack.
		player.ChildAdded:Connect(function(child)
			if child:IsA("Backpack") then
				child.ChildAdded:Connect(function(tool)
					if tool.Name == "Shovel" and tool:IsA("Tool") then
						GloveLooks.dressTool(tool, player:GetAttribute("GloveId"))
					end
				end)
			end
		end)
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			backpack.ChildAdded:Connect(function(tool)
				if tool.Name == "Shovel" and tool:IsA("Tool") then
					GloveLooks.dressTool(tool, player:GetAttribute("GloveId"))
				end
			end)
		end
		if player.Character then
			task.spawn(dressShovel, player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return GloveLooks
