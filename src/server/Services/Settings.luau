--!nonstrict
-- Player settings (effects volume, UI size, shadows, floating labels), saved with the save slot as state.settings and
-- published as "Setting<Key>" player attributes. The client applies them (Settings.client.luau); the server only
-- checks and stores them. Change one: ReplicatedStorage.Settings.Set:FireServer(key, value).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.Data)

local Settings = {}

-- key -> { attribute, default, check(value) -> ok, cleaned value }
local function volume(v)
	if typeof(v) ~= "number" or v ~= v then
		return false
	end
	return true, math.clamp(math.floor(v * 20 + 0.5) / 20, 0, 1)
end
local function bool(v)
	return typeof(v) == "boolean", v
end
Settings.Keys = {
	effects = { "SettingEffects", 1, volume },
	uiSize = {
		"SettingUiSize",
		"normal",
		function(v)
			return v == "small" or v == "normal" or v == "large", v
		end,
	},
	shadows = { "SettingShadows", true, bool },
	labels = { "SettingLabels", true, bool },
}

local function publish(player)
	local state = Data.get(player)
	local saved = state and state.settings or {}
	for key, def in Settings.Keys do
		local value = saved[key]
		if value == nil then
			value = def[2]
		end
		player:SetAttribute(def[1], value)
	end
end

local function set(player, key, value)
	local def = typeof(key) == "string" and Settings.Keys[key]
	local state = Data.get(player)
	if not def or not state then
		return
	end
	local ok, clean = def[3](value)
	if not ok then
		return
	end
	state.settings = state.settings or {}
	state.settings[key] = clean
	player:SetAttribute(def[1], clean)
end

function Settings.start()
	local folder = Instance.new("Folder")
	folder.Name = "Settings"
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Set"
	remote.Parent = folder
	folder.Parent = ReplicatedStorage
	remote.OnServerEvent:Connect(set)
	Data.loaded.Event:Connect(publish)
end

return Settings
