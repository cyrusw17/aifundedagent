--!nonstrict
-- Earned tool skins (Config/ToolSkins): finish a page of the collection book and a shovel or rake skin unlocks, is
-- put on at once, and is kept in the save slot as state.skins = { owned = { id }, worn = { Shovel = id, Rake = id } }.
-- Cosmetic only: a skin recolors the tool and nothing else. Published as the player attributes "ToolSkins" (owned,
-- "a,b") and "ToolSkinShovel" / "ToolSkinRake" (worn). The WearToolSkin remote (toolName, skinId or "") swaps.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinConfig = require(ReplicatedStorage.Shared.Config.ToolSkins)
local GloveConfig = require(ReplicatedStorage.Shared.Config.Gloves)
local NeedleTypes = require(ReplicatedStorage.Shared.Config.Needles)
local FindsConfig = require(ReplicatedStorage.Shared.Config.Finds)
local Data = require(script.Parent.Data)

local ToolSkins = {}

local byId = {}
for _, def in SkinConfig.Skins do
	byId[def.id] = def
end

-- True when the page a skin needs is complete for this save slot.
function ToolSkins.pageDone(state, page)
	local codex = typeof(state.codex) == "table" and state.codex or {}
	local function all(list, have)
		if typeof(have) ~= "table" then
			return false
		end
		for _, id in list do
			if not have[id] then
				return false
			end
		end
		return #list > 0
	end
	if page == "hay" then
		local ids = {}
		for id in GloveConfig.HayTypes do
			table.insert(ids, id)
		end
		return all(ids, codex.hay)
	elseif page == "needles" then
		local ids = {}
		for _, n in NeedleTypes do
			table.insert(ids, n.id)
		end
		return all(ids, codex.needles)
	elseif page == "finds" then
		local ids = {}
		for _, item in FindsConfig.Items do
			table.insert(ids, item.id)
		end
		return all(ids, state.finds)
	elseif page == "finds_common" then
		return all(SkinConfig.CommonFinds, state.finds)
	end
	return false
end

local function skinsOf(state)
	if typeof(state.skins) ~= "table" then
		state.skins = { owned = {}, worn = {} }
	end
	state.skins.owned = typeof(state.skins.owned) == "table" and state.skins.owned or {}
	state.skins.worn = typeof(state.skins.worn) == "table" and state.skins.worn or {}
	return state.skins
end

local function publish(player, skins)
	player:SetAttribute("ToolSkins", table.concat(skins.owned, ","))
	player:SetAttribute("ToolSkinShovel", skins.worn.Shovel or "")
	player:SetAttribute("ToolSkinRake", skins.worn.Rake or "")
end

-- Recolors one tool for the skin (or puts its own look back when skinId is nil). Parts that are hidden (a mesh's
-- part fallback, transparency 1) are left alone.
function ToolSkins.dress(tool, skinId)
	local def = skinId and byId[skinId]
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local own = part:GetAttribute("OwnColor")
			if def then
				if not own then
					part:SetAttribute("OwnColor", part.Color)
					part:SetAttribute("OwnMaterial", part.Material.Name)
				end
				part.Color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
				part.Material = Enum.Material[def.material] or part.Material
			elseif own then
				part.Color = own
				part.Material = Enum.Material[part:GetAttribute("OwnMaterial")] or part.Material
				part:SetAttribute("OwnColor", nil)
				part:SetAttribute("OwnMaterial", nil)
			end
		end
	end
	local glint = tool:FindFirstChild("SkinGlint", true)
	if glint then
		glint:Destroy()
	end
	local head = tool:FindFirstChild("Blade") or tool:FindFirstChild("Head") or tool:FindFirstChild("Handle")
	if def and def.sparkles and head then
		local sparkles = Instance.new("Sparkles")
		sparkles.Name = "SkinGlint"
		sparkles.SparkleColor = Color3.fromRGB(def.color[1], def.color[2], def.color[3]):Lerp(Color3.new(1, 1, 1), 0.5)
		sparkles.Parent = head
	end
	tool:SetAttribute("Skin", def and def.id or nil)
end

local function dressTools(player)
	local state = Data.get(player)
	if not state then
		return
	end
	local skins = skinsOf(state)
	for _, holder in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		for _, tool in holder and holder:GetChildren() or {} do
			if tool:IsA("Tool") and (tool.Name == "Shovel" or tool.Name == "Rake") then
				local want = skins.worn[tool.Name]
				if tool:GetAttribute("Skin") ~= want then
					ToolSkins.dress(tool, want)
				end
			end
		end
	end
end

-- Puts on (or, with skinId nil, takes off) a skin the player owns.
function ToolSkins.wear(player, toolName, skinId)
	local state = Data.get(player)
	if not state or (toolName ~= "Shovel" and toolName ~= "Rake") then
		return false
	end
	local skins = skinsOf(state)
	if skinId ~= nil then
		local def = byId[skinId]
		if not def or def.tool ~= toolName or not table.find(skins.owned, skinId) then
			return false
		end
	end
	skins.worn[toolName] = skinId
	publish(player, skins)
	dressTools(player)
	return true
end

-- Unlocks every skin whose page is now complete, wearing each new one. Returns the ids unlocked just now.
function ToolSkins.check(player)
	local state = Data.get(player)
	if not state then
		return {}
	end
	local skins = skinsOf(state)
	local fresh = {}
	for _, def in SkinConfig.Skins do
		if not table.find(skins.owned, def.id) and ToolSkins.pageDone(state, def.page) then
			table.insert(skins.owned, def.id)
			skins.worn[def.tool] = def.id
			table.insert(fresh, def.id)
			Data.toast(player, ("Collection page complete! Unlocked the %s skin."):format(def.name))
		end
	end
	publish(player, skins)
	dressTools(player)
	return fresh
end

function ToolSkins.init()
	local remote = Instance.new("RemoteEvent")
	remote.Name = "WearToolSkin"
	remote.Parent = ReplicatedStorage
	remote.OnServerEvent:Connect(function(player, toolName, skinId)
		if typeof(toolName) ~= "string" then
			return
		end
		ToolSkins.wear(player, toolName, typeof(skinId) == "string" and skinId ~= "" and skinId or nil)
	end)

	local function watch(player)
		-- The book pages and the finds shelf change through these attributes (Codex.luau, Finds.luau).
		for _, name in { "CodexHay", "CodexNeedles", "Finds" } do
			player:GetAttributeChangedSignal(name):Connect(function()
				ToolSkins.check(player)
			end)
		end
		-- New tools come with every respawn (Avatar hands them out): dress them.
		local function onTool(child)
			if child:IsA("Tool") and (child.Name == "Shovel" or child.Name == "Rake") then
				task.defer(dressTools, player)
			end
		end
		player.ChildAdded:Connect(function(child)
			if child:IsA("Backpack") then
				child.ChildAdded:Connect(onTool)
			end
		end)
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			backpack.ChildAdded:Connect(onTool)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Data.loaded.Event:Connect(function(player)
		ToolSkins.check(player)
	end)
end

return ToolSkins
