--!nonstrict
-- First-time guide progress and earnings pops. The guide itself runs on the client (Tutorial.client.luau); the
-- server only remembers what you have done that the client can't see for itself, and whether you finished or
-- skipped the guide, in the save slot (Data `tutorial`).
--
--   Tutorial.mark(player, "broke")   -- flags: "sold", "broke", "sorter"
--   Tutorial.earned(player, 63)      -- the client pops "+$63"
--
-- Player attributes: TutorialFlags ("sold,broke"), TutorialDone (bool).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LandConfig = require(ReplicatedStorage.Shared.Config.Land)
local Data = require(script.Parent.Data)

local Tutorial = {}

local earnedRemote = nil

local separators = {}
for _, def in LandConfig.Pieces do
	if def.kind == "separator" then
		separators[def.id] = true
	end
end

local function stateOf(player)
	local s = Data.get(player)
	if not s then
		return nil
	end
	if typeof(s.tutorial) ~= "table" then
		s.tutorial = {}
	end
	if typeof(s.tutorial.flags) ~= "table" then
		s.tutorial.flags = {}
	end
	return s.tutorial
end

local function publish(player)
	local t = stateOf(player)
	if not t then
		return
	end
	local list = {}
	for flag, on in t.flags do
		if on then
			table.insert(list, flag)
		end
	end
	table.sort(list)
	player:SetAttribute("TutorialFlags", table.concat(list, ","))
	player:SetAttribute("TutorialDone", t.done == true)
end

function Tutorial.mark(player, flag)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local t = stateOf(player)
	if not t or t.flags[flag] then
		return
	end
	t.flags[flag] = true
	publish(player)
end

function Tutorial.earned(player, amount)
	if earnedRemote and typeof(player) == "Instance" and player:IsA("Player") and amount and amount > 0 then
		earnedRemote:FireClient(player, math.floor(amount))
	end
end

-- Clears a flag (the self-test puts back what it changed).
function Tutorial.unmark(player, flag)
	local t = stateOf(player)
	if t and t.flags[flag] then
		t.flags[flag] = nil
		publish(player)
	end
end

-- For piece placement (Land.onPlace): marks "sorter" and "built_<id>" when the piece is a needle separator.
function Tutorial.placed(player, pieceId)
	if separators[pieceId] then
		Tutorial.mark(player, "sorter")
		-- Which sorters you have ever built, for the goal bar ("built_shaker_table").
		Tutorial.mark(player, "built_" .. pieceId)
	end
end

local function onLoaded(player)
	local t = stateOf(player)
	local s = Data.get(player)
	if not t or not s then
		return
	end
	if s.land and typeof(s.land.items) == "table" then
		for _, item in s.land.items do
			if typeof(item) == "table" and separators[item.id] then
				t.flags.sorter = true
				t.flags["built_" .. item.id] = true
			end
		end
	end
	publish(player)
end

function Tutorial.start()
	local remotes = Instance.new("Folder")
	remotes.Name = "Tutorial"
	local action = Instance.new("RemoteEvent")
	action.Name = "Action"
	action.Parent = remotes
	earnedRemote = Instance.new("RemoteEvent")
	earnedRemote.Name = "Earned"
	earnedRemote.Parent = remotes
	remotes.Parent = ReplicatedStorage

	-- "done" when the guide is finished or skipped, "replay" to run it again.
	action.OnServerEvent:Connect(function(player, what)
		local t = stateOf(player)
		if not t then
			return
		end
		if what == "done" then
			t.done = true
		elseif what == "replay" then
			t.done = false
		end
		publish(player)
	end)
	Data.loaded.Event:Connect(onLoaded)
end

return Tutorial
