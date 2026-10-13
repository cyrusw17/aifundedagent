--!nonstrict
-- What the collection book (Book.client.luau) shows as found: every needle type you have turned up and every hay type
-- you have broken open, kept in the save slot as state.codex = { needles = { [id] = true }, hay = { [id] = true } }.
-- Fed by the event bus (Events.luau: needle_found, bale_broken), so nothing else has to call it. Published as the
-- player attributes "CodexNeedles" and "CodexHay" ("steel,pine").
local Data = require(script.Parent.Data)
local Events = require(script.Parent.Events)

local Codex = {}

local function codexOf(player)
	local state = Data.get(player)
	if not state then
		return nil
	end
	if typeof(state.codex) ~= "table" then
		state.codex = {}
	end
	state.codex.needles = typeof(state.codex.needles) == "table" and state.codex.needles or {}
	state.codex.hay = typeof(state.codex.hay) == "table" and state.codex.hay or {}
	return state.codex
end

local function joined(set)
	local list = {}
	for id, on in set do
		if on then
			table.insert(list, id)
		end
	end
	table.sort(list)
	return table.concat(list, ",")
end

local function publish(player)
	local codex = codexOf(player)
	if codex then
		player:SetAttribute("CodexNeedles", joined(codex.needles))
		player:SetAttribute("CodexHay", joined(codex.hay))
	end
end

-- page is "needles" or "hay".
function Codex.note(player, page, id)
	local codex = codexOf(player)
	if not codex or typeof(id) ~= "string" or id == "" or codex[page] == nil or codex[page][id] then
		return
	end
	codex[page][id] = true
	publish(player)
end

-- Needle ids out of pocket / bin keys ("steel", "pine*3", "ice!").
local function idOfKey(key)
	return string.match(tostring(key), "^([%w_]+)")
end

local function onLoaded(player)
	local state = Data.get(player)
	local codex = codexOf(player)
	if not state or not codex then
		return
	end
	-- Saves from before the book: count what is already in the pocket and the plot's bin.
	for key in state.pocket or {} do
		local id = idOfKey(key)
		if id then
			codex.needles[id] = true
		end
	end
	local bin = state.land and state.land.needles
	for key in typeof(bin) == "table" and bin or {} do
		local id = idOfKey(key)
		if id then
			codex.needles[id] = true
		end
	end
	publish(player)
end

function Codex.start()
	Data.loaded.Event:Connect(onLoaded)
	Events.on(function(player, kind, _, info)
		if kind == "needle_found" then
			Codex.note(player, "needles", info.needleId)
		elseif kind == "bale_broken" then
			Codex.note(player, "hay", info.hayType or "meadow")
		end
	end)
end

return Codex
