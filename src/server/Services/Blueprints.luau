--!nonstrict
-- Line blueprints: named presets of a copied plot area (Land's COPY tool), kept in the save slot so a line you liked
-- can be built again on any plot in any session. Loading one fills the build bar's clipboard; PASTE then builds it
-- for its total price through Land's own Paste, which does every check and the charge.
--
-- Remotes in ReplicatedStorage.LineBlueprints (RemoteFunctions):
--   Save(name, list)  -> ok, message      list: { { id, dx, dz, dir } } as Land's Copy returns it
--   List()            -> { { name, list, total } }
--   Delete(name)      -> ok, message
-- Data state.lineBlueprints = { { name = string, list = { ... } } }, newest last.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LandConfig = require(ReplicatedStorage.Shared.Config.Land)
local Data = require(script.Parent.Data)

local Blueprints = {}

local MAX_PRESETS = 8
local MAX_PIECES = 60 -- Land's MAX_PASTE
local MAX_NAME = 24
local DIRS = { N = true, S = true, E = true, W = true }

local pieces = {}
for _, def in LandConfig.Pieces do
	pieces[def.id] = def
end

local function isCell(n)
	return typeof(n) == "number" and n == math.floor(n) and n >= 0 and n < 64
end

-- A clean copy of a list from the client or an old save, or nil when anything in it is wrong.
local function clean(list)
	if typeof(list) ~= "table" or #list == 0 or #list > MAX_PIECES then
		return nil
	end
	local out = {}
	for _, e in list do
		if typeof(e) ~= "table" or typeof(e.id) ~= "string" or not pieces[e.id] or not isCell(e.dx) or not isCell(e.dz) or not DIRS[e.dir] then
			return nil
		end
		table.insert(out, { id = e.id, dx = e.dx, dz = e.dz, dir = e.dir })
	end
	return out
end

local function totalOf(list)
	local total = 0
	for _, e in list do
		total += pieces[e.id].price
	end
	return total
end

local function presets(player)
	local state = Data.get(player)
	if not state then
		return nil
	end
	if typeof(state.lineBlueprints) ~= "table" then
		state.lineBlueprints = {}
	end
	return state.lineBlueprints
end

local function onSave(player, name, list)
	local mine = presets(player)
	if not mine then
		return false, "Pick a save slot first."
	end
	if typeof(name) ~= "string" then
		return false, "Give the preset a name."
	end
	name = string.sub(string.gsub(name, "[%c]", ""), 1, MAX_NAME)
	name = string.match(name, "^%s*(.-)%s*$")
	if name == "" then
		return false, "Give the preset a name."
	end
	local good = clean(list)
	if not good then
		return false, "Copy an area of your line first."
	end
	for i, p in mine do
		if p.name == name then
			table.remove(mine, i)
			break
		end
	end
	if #mine >= MAX_PRESETS then
		return false, ("You can keep %d presets. Delete one first."):format(MAX_PRESETS)
	end
	table.insert(mine, { name = name, list = good })
	return true, ("Saved \"%s\": %d pieces, $%d to build."):format(name, #good, totalOf(good))
end

local function onList(player)
	local out = {}
	for _, p in presets(player) or {} do
		local good = typeof(p) == "table" and typeof(p.name) == "string" and clean(p.list)
		if good then
			table.insert(out, { name = p.name, list = good, total = totalOf(good) })
		end
	end
	return out
end

local function onDelete(player, name)
	local mine = presets(player)
	for i, p in mine or {} do
		if p.name == name then
			table.remove(mine, i)
			return true, ("Deleted \"%s\"."):format(name)
		end
	end
	return false, "No preset by that name."
end

function Blueprints.init()
	local folder = Instance.new("Folder")
	folder.Name = "LineBlueprints"
	for name, fn in { Save = onSave, List = onList, Delete = onDelete } do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.OnServerInvoke = function(player, ...)
			local ok, a, b = pcall(fn, player, ...)
			if not ok then
				warn("[Needlewood] blueprint error: " .. tostring(a))
				return false, "Something went wrong."
			end
			return a, b
		end
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

Blueprints._clean = clean -- for SelfTests

return Blueprints
