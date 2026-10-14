-- Headless Roblox, part 3: Instance.new, the DataModel and its services, spatial queries, DataStores, tweens,
-- module loading (require) and the fake player. See mock.luau for the rules.
local class, CLASSES, rawNew = H.class, H.CLASSES, H.rawNew
local isInstance, fullName, fireEvent, getSignal = H.isInstance, H.fullName, H.fireEvent, H.getSignal
local setRaw, fire, newSignal = H.setRaw, H.fire, H.newSignal
local v3, cf = H.v3, H.cf
local note = H.note

local function self(o, method)
	if not isInstance(o) then
		error(("Expected ':' not '.' calling member function %s"):format(method), 3)
	end
end

-- Instance.new --------------------------------------------------------------------------------------------------------
local REAL_BUT_UNMOCKED = {} -- filled on demand for the message
Instance = {
	new = function(className, parent)
		if type(className) ~= "string" then
			error("invalid argument #1 to 'new' (string expected, got " .. typeof(className) .. ")", 2)
		end
		local c = CLASSES[className]
		if not c then
			error(("Unable to create an Instance of type \"%s\" [MOCK MISSING: Instance.new(\"%s\"), if that is a real class add it to tools/headless/mock_instances.luau]"):format(className, className), 2)
		end
		if c.abstract or c.service or c.notCreatable then
			error(("Unable to create an Instance of type \"%s\""):format(className), 2)
		end
		local o = rawNew(className)
		if parent ~= nil then
			o.Parent = parent
		end
		return o
	end,
	fromExisting = function(o)
		return rawNew(rawget(o, "_c").name)
	end,
}

-- Services ------------------------------------------------------------------------------------------------------------
local services = {}
H.services = services
local function service(name, super, spec)
	spec = spec or {}
	spec.service = true
	class(name, super or "Instance", spec)
	return spec
end

-- A real Roblox service this mock doesn't model: any member access fails loudly.
local function stubService(name)
	service(name, "Instance", {})
	CLASSES[name].stub = true
end

-- DataModel
local bindToClose = {}
H.bindToClose = bindToClose
class("ServiceProvider", "Instance", { abstract = true })
local SERVICE_NAMES = {}
class("DataModel", "ServiceProvider", {
	notCreatable = true,
	props = {
		PlaceId = { "int", 0, "ro" },
		GameId = { "int", 0, "ro" },
		JobId = { "string", "", "ro" },
		PlaceVersion = { "int", 0, "ro" },
		CreatorId = { "int", 0, "ro" },
		CreatorType = { "Enum:CreatorType", Enum.CreatorType.User, "ro" },
		PrivateServerId = { "string", "", "ro" },
		PrivateServerOwnerId = { "int", 0, "ro" },
		Workspace = { "Instance", nil, "ro", get = function()
			return services.Workspace
		end },
		Lighting = { "Instance", nil, "ro", get = function()
			return services.Lighting
		end },
		Genre = { "any", nil, "ro" },
	},
	methods = {
		GetService = function(o, name)
			self(o, "GetService")
			if type(name) ~= "string" then
				error("invalid argument #1 to 'GetService' (string expected, got " .. typeof(name) .. ")", 2)
			end
			local s = services[name]
			if s then
				return s
			end
			if SERVICE_NAMES[name] then
				return H.makeService(name)
			end
			error(("'%s' is not a valid Service name"):format(name), 2)
		end,
		FindService = function(o, name)
			return services[name]
		end,
		BindToClose = function(o, fn)
			self(o, "BindToClose")
			if type(fn) ~= "function" then
				error("invalid argument #1 to 'BindToClose' (function expected, got " .. typeof(fn) .. ")", 2)
			end
			table.insert(bindToClose, fn)
		end,
		IsLoaded = function()
			return true
		end,
		GetJobsInfo = function()
			return {}
		end,
		Shutdown = function() end,
	},
	events = { "Loaded", "Close", "GraphicsQualityChangeRequest" },
})
CLASSES.DataModel.notCreatable = true

local function makeService(name)
	if services[name] then
		return services[name]
	end
	local s = rawNew(name)
	rawset(s, "_name", name)
	services[name] = s
	if H.game then
		rawset(s, "_parent", H.game)
		table.insert(rawget(H.game, "_kids"), s)
	end
	return s
end
H.makeService = makeService

-- Generic container services
for _, name in { "ReplicatedStorage", "ReplicatedFirst", "ServerStorage", "ServerScriptService", "StarterGui", "StarterPack", "Teams", "Chat" } do
	service(name)
	SERVICE_NAMES[name] = true
end
service("StarterPlayer", "Instance", { props = {
	CharacterWalkSpeed = { "number", 16 }, CharacterJumpPower = { "number", 50 }, CharacterJumpHeight = { "number", 7.2 }, CharacterUseJumpPower = { "bool", false },
	CameraMaxZoomDistance = { "number", 128 }, CameraMinZoomDistance = { "number", 0.5 }, AutoJumpEnabled = { "bool", true }, LoadCharacterAppearance = { "bool", true },
	HealthDisplayDistance = { "number", 100 }, NameDisplayDistance = { "number", 100 }, EnableMouseLockOption = { "bool", true }, CharacterMaxSlopeAngle = { "number", 89 },
} })
SERVICE_NAMES.StarterPlayer = true
class("StarterPlayerScripts", "Instance")
class("StarterCharacterScripts", "StarterPlayerScripts")

-- Lighting
service("Lighting", "Instance", {
	props = {
		ClockTime = { "number", 14, set = function(o, v)
			setRaw(o, "ClockTime", v % 24)
			H.propChanged(o, "TimeOfDay")
		end },
		TimeOfDay = { "string", "14:00:00", get = function(o)
			local t = o.ClockTime
			local h = math.floor(t)
			local m = math.floor((t - h) * 60)
			local s = math.floor(((t - h) * 60 - m) * 60)
			return ("%02d:%02d:%02d"):format(h, m, s)
		end, set = function(o, v)
			local h, m, s = string.match(v, "^(%d+):?(%d*):?(%d*)$")
			if h then
				o.ClockTime = tonumber(h) + (tonumber(m) or 0) / 60 + (tonumber(s) or 0) / 3600
			end
		end },
		Brightness = { "number", 3 },
		Ambient = { "Color3", Color3.fromRGB(70, 70, 70) },
		OutdoorAmbient = { "Color3", Color3.fromRGB(70, 70, 70) },
		ColorShift_Top = { "Color3", Color3.new() },
		ColorShift_Bottom = { "Color3", Color3.new() },
		FogColor = { "Color3", Color3.fromRGB(192, 192, 192) },
		FogEnd = { "number", 100000 },
		FogStart = { "number", 0 },
		GlobalShadows = { "bool", true },
		ShadowSoftness = { "number", 0.2 },
		EnvironmentDiffuseScale = { "number", 1 },
		EnvironmentSpecularScale = { "number", 1 },
		ExposureCompensation = { "number", 0 },
		GeographicLatitude = { "number", 0 },
		Technology = { "Enum:Technology", nil },
		LightingStyle = { "Enum:LightingStyle", nil },
		PrioritizeLightingQuality = { "bool", false },
	},
	methods = {
		GetMinutesAfterMidnight = function(o)
			return o.ClockTime * 60
		end,
		SetMinutesAfterMidnight = function(o, m)
			o.ClockTime = m / 60
		end,
		GetSunDirection = function(o)
			local a = (o.ClockTime / 24) * 2 * math.pi - math.pi / 2
			return v3(math.cos(a), math.sin(a), 0).Unit
		end,
		GetMoonDirection = function(o)
			local a = (o.ClockTime / 24) * 2 * math.pi + math.pi / 2
			return v3(math.cos(a), math.sin(a), 0).Unit
		end,
	},
	events = { "LightingChanged" },
})
SERVICE_NAMES.Lighting = true

-- RunService
service("RunService", "Instance", {
	methods = {
		IsStudio = function()
			return true
		end,
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsRunning = function()
			return true
		end,
		IsRunMode = function()
			return false
		end,
		IsEdit = function()
			return false
		end,
		BindToRenderStep = function()
			error("BindToRenderStep can only be called from the client", 2)
		end,
		UnbindFromRenderStep = function()
			error("UnbindFromRenderStep can only be called from the client", 2)
		end,
	},
	events = { "Heartbeat", "Stepped", "PostSimulation", "PreSimulation", "PreAnimation", "PreRender", "RenderStepped" },
})
SERVICE_NAMES.RunService = true

-- Debris
service("Debris", "Instance", { props = { MaxItems = { "int", 1000 } }, methods = {
	AddItem = function(o, item, lifetime)
		self(o, "AddItem")
		if not isInstance(item) then
			error("invalid argument #1 to 'AddItem' (Instance expected, got " .. typeof(item) .. ")", 2)
		end
		lifetime = lifetime or 10
		H.at(H.now + lifetime, function()
			if not rawget(item, "_locked") then
				item:Destroy()
			end
		end)
	end,
} })
SERVICE_NAMES.Debris = true

-- PhysicsService
local groups = { Default = { Default = true } }
H.collisionGroups = groups
local function needGroup(name)
	if type(name) ~= "string" then
		error("collision group name must be a string", 3)
	end
	if not groups[name] then
		error(("Collision group \"%s\" does not exist."):format(name), 3)
	end
end
service("PhysicsService", "Instance", { methods = {
	RegisterCollisionGroup = function(o, name)
		self(o, "RegisterCollisionGroup")
		if type(name) ~= "string" then
			error("invalid argument #1 to 'RegisterCollisionGroup' (string expected)", 2)
		end
		if not groups[name] then
			local count = 0
			for _ in groups do
				count += 1
			end
			if count >= 32 then
				error("Cannot register more than 32 collision groups", 2)
			end
			groups[name] = {}
			for g in groups do
				groups[name][g] = true
				groups[g][name] = true
			end
		end
	end,
	UnregisterCollisionGroup = function(o, name)
		groups[name] = nil
	end,
	IsCollisionGroupRegistered = function(o, name)
		return groups[name] ~= nil
	end,
	CollisionGroupSetCollidable = function(o, a, b, collide)
		self(o, "CollisionGroupSetCollidable")
		needGroup(a)
		needGroup(b)
		groups[a][b] = collide == true
		groups[b][a] = collide == true
	end,
	CollisionGroupsAreCollidable = function(o, a, b)
		needGroup(a)
		needGroup(b)
		return groups[a][b] ~= false
	end,
	GetRegisteredCollisionGroups = function()
		local out = {}
		for name in groups do
			table.insert(out, { name = name, id = 0, mask = 0 })
		end
		return out
	end,
	GetMaxCollisionGroups = function()
		return 32
	end,
} })
SERVICE_NAMES.PhysicsService = true

-- CollectionService
local tagged = {} -- tag -> { [instance] = true }
local tagAdded, tagRemoved = {}, {}
local function tagSignal(list, tag)
	list[tag] = list[tag] or newSignal("tag " .. tag)
	return list[tag]
end
local CS = {}
function CS.AddTag(o, inst, tag)
	if not isInstance(inst) then
		error("invalid argument #1 to 'AddTag' (Instance expected, got " .. typeof(inst) .. ")", 2)
	end
	if type(tag) ~= "string" then
		error("invalid argument #2 to 'AddTag' (string expected, got " .. typeof(tag) .. ")", 2)
	end
	local tags = rawget(inst, "_tags")
	if not tags then
		tags = {}
		rawset(inst, "_tags", tags)
	end
	if tags[tag] then
		return
	end
	tags[tag] = true
	tagged[tag] = tagged[tag] or {}
	tagged[tag][inst] = true
	if H.inGame(inst) and tagAdded[tag] then
		fire(tagAdded[tag], inst)
	end
end
function CS.RemoveTag(o, inst, tag)
	local tags = rawget(inst, "_tags")
	if not tags or not tags[tag] then
		return
	end
	tags[tag] = nil
	if tagged[tag] then
		tagged[tag][inst] = nil
	end
	if H.inGame(inst) and tagRemoved[tag] then
		fire(tagRemoved[tag], inst)
	end
end
function CS.HasTag(o, inst, tag)
	if not isInstance(inst) then
		error("invalid argument #1 to 'HasTag' (Instance expected, got " .. typeof(inst) .. ")", 2)
	end
	local tags = rawget(inst, "_tags")
	return tags ~= nil and tags[tag] == true
end
function CS.GetTags(o, inst)
	local out = {}
	for t in rawget(inst, "_tags") or {} do
		table.insert(out, t)
	end
	return out
end
function CS.GetTagged(o, tag)
	if type(tag) ~= "string" then
		error("invalid argument #1 to 'GetTagged' (string expected, got " .. typeof(tag) .. ")", 2)
	end
	-- Only instances in the DataModel are returned, like Roblox.
	local out = {}
	for inst in tagged[tag] or {} do
		if H.inGame(inst) then
			table.insert(out, inst)
		end
	end
	return out
end
function CS.GetAllTags()
	local out = {}
	for t in tagged do
		table.insert(out, t)
	end
	return out
end
function CS.GetInstanceAddedSignal(o, tag)
	if type(tag) ~= "string" then
		error("invalid argument #1 to 'GetInstanceAddedSignal' (string expected)", 2)
	end
	return tagSignal(tagAdded, tag)
end
function CS.GetInstanceRemovedSignal(o, tag)
	return tagSignal(tagRemoved, tag)
end
CS.GetCollection = CS.GetTagged
service("CollectionService", "Instance", { methods = CS, events = { "TagAdded", "TagRemoved" } })
SERVICE_NAMES.CollectionService = true
function H.onTaggedMembership(inst, tags, entering)
	for tag in tags do
		local s = entering and tagAdded[tag] or (not entering and tagRemoved[tag])
		if s then
			fire(s, inst)
		end
	end
end
function H.removeAllTags(inst)
	for tag in table.clone(rawget(inst, "_tags") or {}) do
		if tagged[tag] then
			tagged[tag][inst] = nil
		end
	end
end

-- TweenService ----------------------------------------------------------------------------------------------------------
local TWEENABLE = { number = true, int = true, bool = true, CFrame = true, Rect = true, Color3 = true, UDim = true, UDim2 = true, Vector2 = true, Vector3 = true }
local function ease(style, dir, t)
	local function easeIn(x)
		local s = style
		if s == "Linear" then
			return x
		elseif s == "Sine" then
			return 1 - math.cos(x * math.pi / 2)
		elseif s == "Quad" then
			return x * x
		elseif s == "Cubic" then
			return x ^ 3
		elseif s == "Quart" then
			return x ^ 4
		elseif s == "Quint" then
			return x ^ 5
		elseif s == "Exponential" then
			return x == 0 and 0 or 2 ^ (10 * x - 10)
		elseif s == "Circular" then
			return 1 - math.sqrt(1 - x * x)
		elseif s == "Back" then
			return 2.70158 * x ^ 3 - 1.70158 * x * x
		end
		return x
	end
	if dir == "In" then
		return easeIn(t)
	elseif dir == "Out" then
		return 1 - easeIn(1 - t)
	end
	if t < 0.5 then
		return easeIn(t * 2) / 2
	end
	return 1 - easeIn((1 - t) * 2) / 2
end
local function lerpValue(a, b, t)
	local ty = typeof(a)
	if ty == "number" then
		return a + (b - a) * t
	elseif ty == "boolean" then
		return t >= 1 and b or a
	elseif ty == "UDim" then
		return UDim.new(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t)
	elseif ty == "Rect" then
		return Rect.new(a.Min:Lerp(b.Min, t), a.Max:Lerp(b.Max, t))
	end
	return a:Lerp(b, t)
end
local activeTweens = {}
table.insert(H.frameHooks, function()
	for tw in table.clone(activeTweens) do
		local info = tw._info
		local elapsed = H.now - tw._start - info.DelayTime
		if elapsed >= 0 then
			if rawget(tw._inst, "_locked") then
				activeTweens[tw] = nil
				setRaw(tw._obj, "PlaybackState", Enum.PlaybackState.Cancelled)
			else
				local alpha = info.Time > 0 and math.clamp(elapsed / info.Time, 0, 1) or 1
				local e = ease(info.EasingStyle.Name, info.EasingDirection.Name, alpha)
				for k, goal in tw._goals do
					local ok, err = pcall(function()
						tw._inst[k] = lerpValue(tw._from[k], goal, e)
					end)
					if not ok then
						H.reportError(err, nil, "tween " .. fullName(tw._inst) .. "." .. k)
					end
				end
				if alpha >= 1 then
					activeTweens[tw] = nil
					setRaw(tw._obj, "PlaybackState", Enum.PlaybackState.Completed)
					fireEvent(tw._obj, "Completed", Enum.PlaybackState.Completed)
				end
			end
		end
	end
end)
class("TweenBase", "Instance", { abstract = true, props = { PlaybackState = { "Enum:PlaybackState", Enum.PlaybackState.Begin, "ro" } }, events = { "Completed" } })
class("Tween", "TweenBase", {
	notCreatable = true,
	props = {
		Instance = { "Instance", nil, "ro", get = function(o)
			return rawget(o, "_tw")._inst
		end },
		TweenInfo = { "TweenInfo", nil, "ro", get = function(o)
			return rawget(o, "_tw")._info
		end },
	},
	methods = {
		Play = function(o)
			self(o, "Play")
			local tw = rawget(o, "_tw")
			tw._start = H.now
			tw._from = {}
			for k in tw._goals do
				tw._from[k] = tw._inst[k]
			end
			activeTweens[tw] = true
			setRaw(o, "PlaybackState", Enum.PlaybackState.Playing)
		end,
		Cancel = function(o)
			self(o, "Cancel")
			local tw = rawget(o, "_tw")
			if activeTweens[tw] then
				activeTweens[tw] = nil
				setRaw(o, "PlaybackState", Enum.PlaybackState.Cancelled)
				fireEvent(o, "Completed", Enum.PlaybackState.Cancelled)
			end
		end,
		Pause = function(o)
			local tw = rawget(o, "_tw")
			activeTweens[tw] = nil
			setRaw(o, "PlaybackState", Enum.PlaybackState.Paused)
		end,
	},
})
service("TweenService", "Instance", { methods = {
	Create = function(o, inst, info, goals)
		self(o, "Create")
		if not isInstance(inst) then
			error("invalid argument #1 to 'Create' (Instance expected, got " .. typeof(inst) .. ")", 2)
		end
		if typeof(info) ~= "TweenInfo" then
			error("invalid argument #2 to 'Create' (TweenInfo expected, got " .. typeof(info) .. ")", 2)
		end
		if type(goals) ~= "table" then
			error("invalid argument #3 to 'Create' (table expected, got " .. typeof(goals) .. ")", 2)
		end
		local members = rawget(inst, "_c").members
		for k, v in goals do
			local m = members[k]
			if not m or m.kind ~= 1 then
				error(("TweenService:Create no property named '%s' for object '%s'"):format(tostring(k), rawget(inst, "_name")), 2)
			end
			local pt = m.type
			local base = string.gsub(pt, "%?$", "")
			if base == "int" then
				base = "number"
			elseif base == "bool" then
				base = "boolean"
			end
			if not TWEENABLE[m.type] and not TWEENABLE[base] then
				error(("TweenService:Create property named '%s' on object '%s' is not a data type that can be tweened"):format(k, rawget(inst, "_name")), 2)
			end
			if typeof(v) ~= base then
				error(("TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')"):format(k, base, typeof(v)), 2)
			end
			if m.flag == "ro" then
				error(("TweenService:Create property named '%s' is read only"):format(k), 2)
			end
		end
		local t = rawNew("Tween")
		rawset(t, "_tw", { _inst = inst, _info = info, _goals = table.clone(goals), _obj = t })
		return t
	end,
	GetValue = function(o, alpha, style, dir)
		return ease(style.Name, dir.Name, alpha)
	end,
} })
SERVICE_NAMES.TweenService = true

-- HttpService (JSON) ----------------------------------------------------------------------------------------------------
local function jsonEncode(v, seen)
	local t = typeof(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		if v == math.floor(v) and math.abs(v) < 1e15 then
			return ("%d"):format(v)
		end
		return ("%.14g"):format(v)
	elseif t == "string" then
		return '"' .. string.gsub(v, '[%c"\\]', function(c)
			local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
			return map[c] or ("\\u%04x"):format(string.byte(c))
		end) .. '"'
	elseif t == "table" then
		seen = seen or {}
		if seen[v] then
			error("Can't convert to JSON: tables cannot be cyclic", 0)
		end
		seen[v] = true
		local n = #v
		local count = 0
		for _ in v do
			count += 1
		end
		local out = {}
		if count == n then
			for i = 1, n do
				out[i] = jsonEncode(v[i], seen)
			end
			seen[v] = nil
			return "[" .. table.concat(out, ",") .. "]"
		end
		for k, x in v do
			if type(k) ~= "string" then
				error("Can't convert to JSON: keys must be strings (mixed or non-array table)", 0)
			end
			table.insert(out, jsonEncode(k) .. ":" .. jsonEncode(x, seen))
		end
		seen[v] = nil
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null" -- Roblox writes null for unsupported userdata
end
local function jsonDecode(s)
	local i = 1
	local function ws()
		i = string.find(s, "%S", i) or #s + 1
	end
	local value
	local function str()
		local out = {}
		i += 1
		while true do
			local c = string.sub(s, i, i)
			if c == "" then
				error("Can't parse JSON", 0)
			elseif c == '"' then
				i += 1
				break
			elseif c == "\\" then
				local e = string.sub(s, i + 1, i + 1)
				local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				if e == "u" then
					table.insert(out, utf8.char(tonumber(string.sub(s, i + 2, i + 5), 16)))
					i += 6
				else
					table.insert(out, map[e] or e)
					i += 2
				end
			else
				table.insert(out, c)
				i += 1
			end
		end
		return table.concat(out)
	end
	function value()
		ws()
		local c = string.sub(s, i, i)
		if c == "{" then
			i += 1
			local obj = {}
			ws()
			if string.sub(s, i, i) == "}" then
				i += 1
				return obj
			end
			while true do
				ws()
				local k = str()
				ws()
				i += 1 -- :
				obj[k] = value()
				ws()
				local d = string.sub(s, i, i)
				i += 1
				if d == "}" then
					return obj
				elseif d ~= "," then
					error("Can't parse JSON", 0)
				end
			end
		elseif c == "[" then
			i += 1
			local arr = {}
			ws()
			if string.sub(s, i, i) == "]" then
				i += 1
				return arr
			end
			while true do
				table.insert(arr, value())
				ws()
				local d = string.sub(s, i, i)
				i += 1
				if d == "]" then
					return arr
				elseif d ~= "," then
					error("Can't parse JSON", 0)
				end
			end
		elseif c == '"' then
			return str()
		elseif string.sub(s, i, i + 3) == "true" then
			i += 4
			return true
		elseif string.sub(s, i, i + 4) == "false" then
			i += 5
			return false
		elseif string.sub(s, i, i + 3) == "null" then
			i += 4
			return nil
		end
		local num = string.match(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", i)
		if not num or num == "" then
			error("Can't parse JSON", 0)
		end
		i += #num
		return tonumber(num)
	end
	local ok, result = pcall(value)
	if not ok then
		error("Can't parse JSON", 2)
	end
	return result
end
H.jsonEncode = jsonEncode
local guidCounter = 0
service("HttpService", "Instance", {
	props = { HttpEnabled = { "bool", false } },
	methods = {
		JSONEncode = function(o, v)
			self(o, "JSONEncode")
			local ok, r = pcall(jsonEncode, v)
			if not ok then
				error(r, 2)
			end
			return r
		end,
		JSONDecode = function(o, s)
			self(o, "JSONDecode")
			if type(s) ~= "string" then
				error("invalid argument #1 to 'JSONDecode' (string expected)", 2)
			end
			return jsonDecode(s)
		end,
		GenerateGUID = function(o, wrap)
			guidCounter += 1
			local g = ("%08X-0000-4000-8000-%012X"):format(guidCounter, guidCounter * 7919)
			if wrap == false then
				return g
			end
			return "{" .. g .. "}"
		end,
		UrlEncode = function(o, s)
			return (string.gsub(s, "[^%w%-_%.~]", function(c)
				return ("%%%02X"):format(string.byte(c))
			end))
		end,
		GetAsync = function()
			error("Http requests are not enabled. Enable via game settings", 2)
		end,
		PostAsync = function()
			error("Http requests are not enabled. Enable via game settings", 2)
		end,
		RequestAsync = function()
			error("Http requests are not enabled. Enable via game settings", 2)
		end,
	},
})
SERVICE_NAMES.HttpService = true

-- DataStoreService ------------------------------------------------------------------------------------------------------
-- In memory, with Roblox's rules: string keys of 1..50 chars, values that serialise to JSON (no Instances, Vector3s,
-- functions, mixed or non-string-keyed tables), 4 MB per value, and every read/write returns a copy.
H.dataStores = {} -- name -> { data = { key -> json string }, ordered = bool }
H.dataStoreCalls = 0
H.dataStoreFail = nil -- function(method, store, key) -> error message or nil, to simulate outages
local function checkStorable(v, path, seen)
	local t = typeof(v)
	if t == "nil" or t == "boolean" or t == "string" then
		return
	elseif t == "number" then
		if v ~= v then
			error(("104: Cannot store NaN in data store (at %s)"):format(path), 0)
		end
		return
	elseif t == "table" then
		seen = seen or {}
		if seen[v] then
			error("104: Cannot store cyclic table in data store", 0)
		end
		seen[v] = true
		local n = #v
		local count, nonString = 0, nil
		for k, x in v do
			count += 1
			if type(k) ~= "string" and type(k) ~= "number" then
				error(("104: Cannot store %s keys in data store (at %s)"):format(typeof(k), path), 0)
			end
			if type(k) == "number" then
				nonString = k
			end
			checkStorable(x, path .. "." .. tostring(k), seen)
		end
		if nonString ~= nil and count ~= n then
			error(("104: Cannot store mixed or non-sequential array in data store (at %s, key %s)"):format(path, tostring(nonString)), 0)
		end
		seen[v] = nil
		return
	end
	error(("104: Cannot store %s in data store. Data stores can only accept valid UTF-8 characters (at %s)"):format(t, path), 0)
end
H.checkStorable = checkStorable
local function checkKey(key, fname)
	if type(key) ~= "string" then
		if type(key) == "number" then
			key = tostring(key)
		else
			error(("invalid argument #1 to '%s' (string expected, got %s)"):format(fname, typeof(key)), 3)
		end
	end
	if #key == 0 then
		error("101: Key name can't be empty.", 3)
	end
	if #key > 50 then
		error("102: Key name exceeds the 50 character limit.", 3)
	end
	return key
end
local function storeYield()
	H.dataStoreCalls += 1
	-- a DataStore call yields; simulate a short round trip when we're in a yieldable thread
	if coroutine.isyieldable() then
		task.wait(0.05)
	end
end
local function encodeValue(v, key)
	checkStorable(v, key)
	local s = jsonEncode(v)
	if #s > 4194304 then
		error("105: Serialized value exceeds 4MB limit.", 0)
	end
	return s
end
local function failCheck(method, store, key)
	if H.dataStoreFail then
		local msg = H.dataStoreFail(method, store, key)
		if msg then
			error(msg, 0)
		end
	end
end
local function keyInfo(entry)
	return setmetatable({ Version = tostring(entry and entry.version or 0), CreatedTime = 0, UpdatedTime = 0, GetUserIds = function()
		return entry and entry.userIds or {}
	end, GetMetadata = function()
		return {}
	end }, { __type = "DataStoreKeyInfo" })
end
class("GlobalDataStore", "Instance", { notCreatable = true, methods = {
	GetAsync = function(o, key, options)
		self(o, "GetAsync")
		key = checkKey(key, "GetAsync")
		storeYield()
		local s = rawget(o, "_store")
		failCheck("GetAsync", s, key)
		local entry = s.data[key]
		if not entry then
			return nil, nil
		end
		return jsonDecode(entry.json), keyInfo(entry)
	end,
	SetAsync = function(o, key, value, userIds, options)
		self(o, "SetAsync")
		key = checkKey(key, "SetAsync")
		local s = rawget(o, "_store")
		local json = encodeValue(value, key)
		if s.ordered and (type(value) ~= "number" or value ~= math.floor(value)) then
			error("Double value " .. tostring(value) .. " is not an integer (OrderedDataStore only stores integers)", 2)
		end
		storeYield()
		failCheck("SetAsync", s, key)
		local entry = s.data[key] or { version = 0 }
		entry.json = json
		entry.version += 1
		entry.userIds = userIds
		s.data[key] = entry
		return tostring(entry.version)
	end,
	UpdateAsync = function(o, key, transform)
		self(o, "UpdateAsync")
		key = checkKey(key, "UpdateAsync")
		if type(transform) ~= "function" then
			error("invalid argument #2 to 'UpdateAsync' (function expected, got " .. typeof(transform) .. ")", 2)
		end
		storeYield()
		local s = rawget(o, "_store")
		failCheck("UpdateAsync", s, key)
		local entry = s.data[key]
		local old = entry and jsonDecode(entry.json) or nil
		-- The transform must not yield (Roblox: "Callbacks cannot yield").
		local co = coroutine.create(transform)
		local ok, new, userIds = coroutine.resume(co, old, keyInfo(entry))
		if not ok then
			error(new, 0)
		end
		if coroutine.status(co) ~= "dead" then
			error("UpdateAsync: transform function yielded (callbacks cannot yield)", 2)
		end
		if new == nil then
			return nil, nil -- cancelled, nothing written
		end
		local json = encodeValue(new, key)
		if s.ordered and (type(new) ~= "number" or new ~= math.floor(new)) then
			error("Double value " .. tostring(new) .. " is not an integer (OrderedDataStore only stores integers)", 2)
		end
		entry = entry or { version = 0 }
		entry.json = json
		entry.version += 1
		entry.userIds = userIds
		s.data[key] = entry
		return jsonDecode(json), keyInfo(entry)
	end,
	IncrementAsync = function(o, key, delta)
		self(o, "IncrementAsync")
		key = checkKey(key, "IncrementAsync")
		delta = delta or 1
		if type(delta) ~= "number" or delta ~= math.floor(delta) then
			error("IncrementAsync: delta must be an integer", 2)
		end
		storeYield()
		local s = rawget(o, "_store")
		failCheck("IncrementAsync", s, key)
		local entry = s.data[key]
		local old = entry and jsonDecode(entry.json) or 0
		if type(old) ~= "number" then
			error("IncrementAsync: the stored value is not a number", 2)
		end
		entry = entry or { version = 0 }
		entry.json = jsonEncode(old + delta)
		entry.version += 1
		s.data[key] = entry
		return old + delta
	end,
	RemoveAsync = function(o, key)
		self(o, "RemoveAsync")
		key = checkKey(key, "RemoveAsync")
		storeYield()
		local s = rawget(o, "_store")
		failCheck("RemoveAsync", s, key)
		local entry = s.data[key]
		s.data[key] = nil
		return entry and jsonDecode(entry.json) or nil
	end,
	OnUpdate = function()
		return getSignal(rawNew("Folder"), "Changed"):Connect(function() end)
	end,
} })
class("DataStore", "GlobalDataStore", { notCreatable = true, methods = {
	ListKeysAsync = function(o)
		local keys = {}
		for k in rawget(o, "_store").data do
			table.insert(keys, { KeyName = k })
		end
		return H.pages({ keys })
	end,
} })
class("OrderedDataStore", "GlobalDataStore", { notCreatable = true, methods = {
	GetSortedAsync = function(o, ascending, pageSize, minValue, maxValue)
		self(o, "GetSortedAsync")
		if type(ascending) ~= "boolean" then
			error("invalid argument #1 to 'GetSortedAsync' (bool expected, got " .. typeof(ascending) .. ")", 2)
		end
		if type(pageSize) ~= "number" or pageSize < 1 or pageSize > 100 or pageSize ~= math.floor(pageSize) then
			error("GetSortedAsync: pageSize must be an integer from 1 to 100", 2)
		end
		storeYield()
		local rows = {}
		for k, e in rawget(o, "_store").data do
			local v = jsonDecode(e.json)
			if (minValue == nil or v >= minValue) and (maxValue == nil or v <= maxValue) then
				table.insert(rows, { key = k, value = v })
			end
		end
		table.sort(rows, function(a, b)
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
		local pagesList = {}
		for i = 1, math.max(#rows, 1), pageSize do
			table.insert(pagesList, table.move(rows, i, math.min(i + pageSize - 1, #rows), 1, {}))
		end
		return H.pages(pagesList)
	end,
} })
class("Pages", "Instance", { notCreatable = true, props = { IsFinished = { "bool", true, "ro", get = function(o)
	return rawget(o, "_i") >= #rawget(o, "_pages")
end } }, methods = {
	GetCurrentPage = function(o)
		self(o, "GetCurrentPage")
		return table.clone(rawget(o, "_pages")[rawget(o, "_i")] or {})
	end,
	AdvanceToNextPageAsync = function(o)
		self(o, "AdvanceToNextPageAsync")
		if rawget(o, "_i") >= #rawget(o, "_pages") then
			error("AdvanceToNextPageAsync: no more pages", 2)
		end
		storeYield()
		rawset(o, "_i", rawget(o, "_i") + 1)
	end,
} })
class("DataStorePages", "Pages", { notCreatable = true })
function H.pages(list)
	local p = rawNew("DataStorePages")
	rawset(p, "_pages", list)
	rawset(p, "_i", 1)
	return p
end
local storeObjects = {}
local function getStore(name, scope, ordered)
	if type(name) ~= "string" or #name == 0 or #name > 50 then
		error("DataStore name must be a string of 1 to 50 characters", 3)
	end
	local id = (ordered and "O:" or "G:") .. name .. "/" .. (scope or "global")
	local obj = storeObjects[id]
	if obj then
		return obj
	end
	H.dataStores[id] = H.dataStores[id] or { data = {}, ordered = ordered, name = name }
	obj = rawNew(ordered and "OrderedDataStore" or "DataStore")
	rawset(obj, "_name", name)
	rawset(obj, "_store", H.dataStores[id])
	storeObjects[id] = obj
	return obj
end
service("DataStoreService", "Instance", { methods = {
	GetDataStore = function(o, name, scope, options)
		self(o, "GetDataStore")
		return getStore(name, scope, false)
	end,
	GetGlobalDataStore = function(o)
		return getStore("GlobalDataStore", nil, false)
	end,
	GetOrderedDataStore = function(o, name, scope)
		self(o, "GetOrderedDataStore")
		return getStore(name, scope, true)
	end,
	GetRequestBudgetForRequestType = function()
		return 60
	end,
	ListDataStoresAsync = function()
		return H.pages({ {} })
	end,
} })
SERVICE_NAMES.DataStoreService = true

-- MessagingService, MarketplaceService, BadgeService, GroupService, TextService, misc ------------------------------
service("MessagingService", "Instance", { methods = {
	PublishAsync = function(o, topic, message)
		self(o, "PublishAsync")
		if type(topic) ~= "string" then
			error("invalid argument #1 to 'PublishAsync' (string expected)", 2)
		end
		H.serialize(message, "MessagingService:PublishAsync")
		task.wait(0.05)
	end,
	SubscribeAsync = function(o, topic, fn)
		self(o, "SubscribeAsync")
		if type(fn) ~= "function" then
			error("invalid argument #2 to 'SubscribeAsync' (function expected)", 2)
		end
		return getSignal(rawNew("Folder"), "Changed"):Connect(function() end)
	end,
} })
SERVICE_NAMES.MessagingService = true
service("MarketplaceService", "Instance", {
	methods = {
		PromptProductPurchase = function(o, player)
			if not H.isPlayer(player) then
				error("PromptProductPurchase: player must be a Player", 2)
			end
		end,
		PromptGamePassPurchase = function(o, player)
			if not H.isPlayer(player) then
				error("PromptGamePassPurchase: player must be a Player", 2)
			end
		end,
		PromptPurchase = function() end,
		UserOwnsGamePassAsync = function(o, userId, passId)
			if type(userId) ~= "number" or type(passId) ~= "number" then
				error("UserOwnsGamePassAsync expects (userId, gamePassId) numbers", 2)
			end
			task.wait(0.05)
			return false
		end,
		PlayerOwnsAsset = function()
			return false
		end,
		GetProductInfo = function(o, id)
			task.wait(0.05)
			return { Name = "Product " .. tostring(id), PriceInRobux = 0, IsForSale = false, Description = "" }
		end,
	},
	callbacks = { "ProcessReceipt" },
	events = { "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished", "PromptPurchaseFinished" },
})
SERVICE_NAMES.MarketplaceService = true
service("BadgeService", "Instance", { methods = {
	AwardBadge = function(o, userId, badgeId)
		task.wait(0.05)
		return true
	end,
	UserHasBadgeAsync = function()
		task.wait(0.05)
		return false
	end,
	GetBadgeInfoAsync = function(o, id)
		return { Name = "Badge", Description = "", IconImageId = 0, IsEnabled = true }
	end,
} })
SERVICE_NAMES.BadgeService = true
service("GroupService", "Instance", { methods = {
	GetGroupInfoAsync = function(o, id)
		task.wait(0.05)
		return { Name = "Group " .. tostring(id), Id = id, Owner = { Name = "Owner", Id = 1 }, Roles = {} }
	end,
	GetGroupsAsync = function()
		task.wait(0.05)
		return {}
	end,
} })
SERVICE_NAMES.GroupService = true
service("TextService", "Instance", { methods = {
	GetTextSize = function(o, text, size, font, frame)
		return Vector2.new(math.min(#text * size * 0.5, frame.X), size)
	end,
	FilterStringAsync = function(o, text, userId)
		task.wait(0.05)
		local r = rawNew("TextFilterResult")
		rawset(r, "_text", text)
		return r
	end,
} })
SERVICE_NAMES.TextService = true
class("TextFilterResult", "Instance", { notCreatable = true, methods = {
	GetNonChatStringForBroadcastAsync = function(o)
		return rawget(o, "_text")
	end,
	GetNonChatStringForUserAsync = function(o)
		return rawget(o, "_text")
	end,
	GetChatForUserAsync = function(o)
		return rawget(o, "_text")
	end,
} })
service("TextChatService", "Instance", { props = { ChatVersion = { "Enum:ChatVersion", nil } }, methods = {
	DisplayBubble = function() end,
} })
SERVICE_NAMES.TextChatService = true
class("TextChannel", "Instance", { methods = { SendAsync = function() end, DisplaySystemMessage = function() end } })
service("InsertService", "Instance", { methods = {
	LoadAsset = function(o, id)
		error("InsertService:LoadAsset is not available headless (asset " .. tostring(id) .. ")", 2)
	end,
} })
SERVICE_NAMES.InsertService = true
service("SoundService", "Instance", { props = { AmbientReverb = { "Enum:ReverbType", nil }, DistanceFactor = { "number", 3.33 }, DopplerScale = { "number", 1 }, RolloffScale = { "number", 1 }, RespectFilteringEnabled = { "bool", true } }, methods = {
	PlayLocalSound = function()
		error("PlayLocalSound can only be called from the client", 2)
	end,
} })
SERVICE_NAMES.SoundService = true
service("UserInputService", "Instance", { props = { TouchEnabled = { "bool", false, "ro" }, KeyboardEnabled = { "bool", false, "ro" }, MouseEnabled = { "bool", false, "ro" }, GamepadEnabled = { "bool", false, "ro" } }, events = { "InputBegan", "InputEnded", "InputChanged", "JumpRequest", "LastInputTypeChanged" } })
SERVICE_NAMES.UserInputService = true
service("ContentProvider", "Instance", { methods = { PreloadAsync = function() end }, props = { RequestQueueSize = { "int", 0, "ro" } } })
SERVICE_NAMES.ContentProvider = true
service("LocalizationService", "Instance", { props = { RobloxLocaleId = { "string", "en-us", "ro" } }, methods = { GetCountryRegionForPlayerAsync = function()
	return "US"
end } })
SERVICE_NAMES.LocalizationService = true
service("PolicyService", "Instance", { methods = { GetPolicyInfoForPlayerAsync = function()
	return { AreAdsAllowed = true, ArePaidRandomItemsRestricted = false, AllowedExternalLinkReferences = {}, IsPaidItemTradingAllowed = true, IsSubjectToChinaPolicies = false }
end } })
SERVICE_NAMES.PolicyService = true
service("ProximityPromptService", "Instance", { props = { Enabled = { "bool", true }, MaxPromptsVisible = { "int", 16 } }, events = { "PromptTriggered", "PromptTriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" } })
SERVICE_NAMES.ProximityPromptService = true
service("TeleportService", "Instance", { methods = { TeleportAsync = function()
	error("TeleportService is not available headless", 2)
end } })
SERVICE_NAMES.TeleportService = true
for _, name in { "AnalyticsService", "SocialService", "AvatarEditorService", "VoiceChatService", "AssetService", "GuiService", "StarterGui", "VRService", "HapticService", "ContextActionService", "Selection", "ChangeHistoryService", "MemoryStoreService" } do
	if not CLASSES[name] then
		stubService(name)
		SERVICE_NAMES[name] = true
	end
end

-- Players ---------------------------------------------------------------------------------------------------------------
local P = {}
function P.GetPlayers(o)
	self(o, "GetPlayers")
	local out = {}
	for _, k in rawget(o, "_kids") do
		if rawget(k, "_c").name == "Player" then
			table.insert(out, k)
		end
	end
	return out
end
function P.GetPlayerByUserId(o, id)
	self(o, "GetPlayerByUserId")
	if type(id) ~= "number" then
		error("invalid argument #1 to 'GetPlayerByUserId' (number expected, got " .. typeof(id) .. ")", 2)
	end
	for _, p in P.GetPlayers(o) do
		if p.UserId == id then
			return p
		end
	end
	return nil
end
function P.GetPlayerFromCharacter(o, character)
	self(o, "GetPlayerFromCharacter")
	if character == nil then
		return nil
	end
	for _, p in P.GetPlayers(o) do
		if rawget(p, "_p").Character == character then
			return p
		end
	end
	return nil
end
function H.playerFromCharacter(character)
	return P.GetPlayerFromCharacter(services.Players, character)
end
function P.GetNameFromUserIdAsync(o, id)
	self(o, "GetNameFromUserIdAsync")
	if type(id) ~= "number" then
		error("invalid argument #1 to 'GetNameFromUserIdAsync' (number expected, got " .. typeof(id) .. ")", 2)
	end
	task.wait(0.05)
	local p = P.GetPlayerByUserId(o, id)
	return p and p.Name or ("Player" .. tostring(id))
end
function P.GetUserIdFromNameAsync(o, name)
	task.wait(0.05)
	return 1
end
function P.GetUserThumbnailAsync(o, id)
	return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(id) .. "&w=150&h=150", true
end
function P.GetHumanoidDescriptionFromUserId(o, id)
	task.wait(0.05)
	return rawNew("HumanoidDescription")
end
function P.CreateHumanoidModelFromDescription()
	error("Players:CreateHumanoidModelFromDescription is not mocked [MOCK MISSING]", 2)
end
function P.GetFriendsAsync()
	return H.pages({ {} })
end
service("Players", "Instance", {
	props = {
		MaxPlayers = { "int", 20, "ro" },
		RespawnTime = { "number", 5 },
		CharacterAutoLoads = { "bool", true },
		LocalPlayer = { "Instance", nil, "ro" },
		BubbleChat = { "bool", false, "ro" },
		ClassicChat = { "bool", false, "ro" },
	},
	methods = P,
	events = { "PlayerAdded", "PlayerRemoving", "PlayerMembershipChanged" },
})
SERVICE_NAMES.Players = true

class("Player", "Instance", {
	notCreatable = true,
	props = {
		UserId = { "int", 0, "ro" },
		DisplayName = { "string", "" },
		Character = { "Instance:Model", nil, set = function(o, v)
			setRaw(o, "Character", v)
		end },
		CharacterAppearanceId = { "int", 0 },
		AccountAge = { "int", 365, "ro" },
		MembershipType = { "Enum:MembershipType", Enum.MembershipType.None, "ro" },
		Team = { "Instance:Team", nil },
		TeamColor = { "BrickColor", nil },
		Neutral = { "bool", true },
		RespawnLocation = { "Instance:SpawnLocation", nil },
		CameraMaxZoomDistance = { "number", 128 },
		CameraMinZoomDistance = { "number", 0.5 },
		CameraMode = { "Enum:CameraMode", nil },
		DevEnableMouseLock = { "bool", true },
		AutoJumpEnabled = { "bool", true },
		CanLoadCharacterAppearance = { "bool", true },
		HealthDisplayDistance = { "number", 100 },
		NameDisplayDistance = { "number", 100 },
		LocaleId = { "string", "en-us", "ro" },
		FollowUserId = { "int", 0, "ro" },
		GameplayPaused = { "bool", false },
		ReplicationFocus = { "Instance", nil },
	},
	methods = {
		Kick = function(o, message)
			self(o, "Kick")
			warn(("[headless] %s was kicked: %s"):format(rawget(o, "_name"), tostring(message)))
			H.kicked = H.kicked or {}
			table.insert(H.kicked, { player = rawget(o, "_name"), message = message })
		end,
		LoadCharacter = function(o)
			self(o, "LoadCharacter")
			H.spawnCharacter(o)
		end,
		LoadCharacterAsync = function(o)
			H.spawnCharacter(o)
		end,
		-- StreamingEnabled is on: the server asks the client to stream an area in before moving a player there.
		-- Nothing streams here, so it only checks the argument and yields like the real call.
		RequestStreamAroundAsync = function(o, position, timeout)
			self(o, "RequestStreamAroundAsync")
			assert(typeof(position) == "Vector3", "RequestStreamAroundAsync: position must be a Vector3")
			task.wait()
		end,
		GetRankInGroup = function(o, groupId)
			task.wait(0.05)
			return 0
		end,
		GetRoleInGroup = function(o, groupId)
			task.wait(0.05)
			return "Guest"
		end,
		IsInGroup = function(o, groupId)
			task.wait(0.05)
			return false
		end,
		IsFriendsWith = function()
			task.wait(0.05)
			return false
		end,
		GetFriendsOnline = function()
			task.wait(0.05)
			return {}
		end,
		GetJoinData = function()
			return { SourceGameId = nil, SourcePlaceId = nil, LaunchData = nil }
		end,
		GetNetworkPing = function()
			return 0.05
		end,
		DistanceFromCharacter = function(o, pos)
			local c = rawget(o, "_p").Character
			local head = c and c:FindFirstChild("Head")
			if not head then
				return 0
			end
			return (head.Position - pos).Magnitude
		end,
		ClearCharacterAppearance = function() end,
		HasAppearanceLoaded = function()
			return true
		end,
		GetMouse = function()
			error("GetMouse can only be called from the client", 2)
		end,
		SetSuperSafeChat = function() end,
	},
	events = { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted", "Idled", "OnTeleport" },
})

-- Workspace, Terrain and spatial queries ---------------------------------------------------------------------------------
local function partBox(p)
	local pp = rawget(p, "_p")
	return pp.CFrame or CFrame.identity, pp.Size or rawget(p, "_c").members.Size.default
end
-- Spatial index: a 64-stud grid over X/Z of every Workspace part's bounding box, updated lazily from a dirty set.
local CELL = 64
local cells = {} -- key -> { [part] = true }
local big = {} -- parts spanning too many cells, always checked
local partCells = setmetatable({}, { __mode = "k" }) -- part -> { keys } | "big"
local dirty = {}
local function cellKey(ix, iz)
	return (ix + 50000) * 100000 + (iz + 50000)
end
function H.onPartMoved(p)
	dirty[p] = true
end
local function aabbFast(p)
	local c, s = partBox(p)
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local ex = math.abs(c[4]) * hx + math.abs(c[5]) * hy + math.abs(c[6]) * hz
	local ey = math.abs(c[7]) * hx + math.abs(c[8]) * hy + math.abs(c[9]) * hz
	local ez = math.abs(c[10]) * hx + math.abs(c[11]) * hy + math.abs(c[12]) * hz
	return c[1] - ex, c[2] - ey, c[3] - ez, c[1] + ex, c[2] + ey, c[3] + ez
end
H.aabbFast = aabbFast
local function unindex(p)
	local old = partCells[p]
	if old == "big" then
		big[p] = nil
	elseif old then
		for _, k in old do
			local set = cells[k]
			if set then
				set[p] = nil
			end
		end
	end
	partCells[p] = nil
end
local function reindex()
	if next(dirty) == nil then
		return
	end
	for p in dirty do
		unindex(p)
		if H.worldParts[p] and rawget(p, "_c").name ~= "Terrain" then
			local x0, _, z0, x1, _, z1 = aabbFast(p)
			local ix0, ix1, iz0, iz1 = math.floor(x0 / CELL), math.floor(x1 / CELL), math.floor(z0 / CELL), math.floor(z1 / CELL)
			if (ix1 - ix0 + 1) * (iz1 - iz0 + 1) > 64 then
				big[p] = true
				partCells[p] = "big"
			else
				local keys = {}
				for ix = ix0, ix1 do
					for iz = iz0, iz1 do
						local k = cellKey(ix, iz)
						local set = cells[k]
						if not set then
							set = {}
							cells[k] = set
						end
						set[p] = true
						table.insert(keys, k)
					end
				end
				partCells[p] = keys
			end
		end
	end
	table.clear(dirty)
end
-- Candidate parts whose X/Z cells touch the box [x0,x1] x [z0,z1].
local function candidates(x0, z0, x1, z1)
	reindex()
	local out = {}
	local ix0, ix1, iz0, iz1 = math.floor(x0 / CELL), math.floor(x1 / CELL), math.floor(z0 / CELL), math.floor(z1 / CELL)
	if (ix1 - ix0 + 1) * (iz1 - iz0 + 1) > 2500 then
		for p in H.worldParts do
			if rawget(p, "_c").name ~= "Terrain" then
				out[p] = true
			end
		end
		return out
	end
	for ix = ix0, ix1 do
		for iz = iz0, iz1 do
			local set = cells[cellKey(ix, iz)]
			if set then
				for p in set do
					out[p] = true
				end
			end
		end
	end
	for p in big do
		out[p] = true
	end
	return out
end
local function filterFn(params)
	if params == nil then
		return function()
			return true
		end
	end
	local f = rawget(params, "_f")
	local list = f.FilterDescendantsInstances
	local include = f.FilterType == Enum.RaycastFilterType.Include
	local group = f.CollisionGroup or "Default"
	local respect = f.RespectCanCollide
	return function(p)
		local inList = false
		for _, inst in list do
			if p == inst or H.isDescendantOf(p, inst) then
				inList = true
				break
			end
		end
		if include ~= inList then
			return false
		end
		local pp = rawget(p, "_p")
		if respect and pp.CanCollide == false then
			return false
		end
		local g = H.collisionGroups[group]
		if g and g[pp.CollisionGroup or "Default"] == false then
			return false
		end
		return true
	end
end
-- Ray vs oriented box (slab test in the box's space). Returns distance and normal.
local function rayBox(origin, dir, c, size)
	local inv = H.cfInverse(c)
	local o = inv * origin
	local d = inv.Rotation * dir
	local h = { size.X / 2, size.Y / 2, size.Z / 2 }
	local oo = { o.X, o.Y, o.Z }
	local dd = { d.X, d.Y, d.Z }
	local tmin, tmax, axis, sign = 0, 1, nil, 0
	for i = 1, 3 do
		if math.abs(dd[i]) < 1e-12 then
			if oo[i] < -h[i] or oo[i] > h[i] then
				return nil
			end
		else
			local t1 = (-h[i] - oo[i]) / dd[i]
			local t2 = (h[i] - oo[i]) / dd[i]
			local s = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				s = 1
			end
			if t1 > tmin then
				tmin, axis, sign = t1, i, s
			end
			if t2 < tmax then
				tmax = t2
			end
			if tmin > tmax then
				return nil
			end
		end
	end
	if not axis then
		return nil -- origin inside the box: Roblox doesn't report a hit from inside
	end
	local n = { 0, 0, 0 }
	n[axis] = sign
	return tmin, c.Rotation * v3(n[1], n[2], n[3])
end
local function aabbOf(c, s)
	local minV, maxV
	for _, p in H.cornersOf(c, s) do
		minV = minV and minV:Min(p) or p
		maxV = maxV and maxV:Max(p) or p
	end
	return minV, maxV
end
-- Separating axis test between two oriented boxes.
local function obbOverlap(c1, s1, c2, s2)
	local axes = { c1.RightVector, c1.UpVector, c1.LookVector, c2.RightVector, c2.UpVector, c2.LookVector }
	for i = 1, 3 do
		for j = 4, 6 do
			local a = axes[i]:Cross(axes[j])
			if a.Magnitude > 1e-6 then
				table.insert(axes, a.Unit)
			end
		end
	end
	local d = c2.Position - c1.Position
	local h1 = { c1.RightVector * s1.X / 2, c1.UpVector * s1.Y / 2, c1.LookVector * s1.Z / 2 }
	local h2 = { c2.RightVector * s2.X / 2, c2.UpVector * s2.Y / 2, c2.LookVector * s2.Z / 2 }
	for _, a in axes do
		local r1 = math.abs(h1[1]:Dot(a)) + math.abs(h1[2]:Dot(a)) + math.abs(h1[3]:Dot(a))
		local r2 = math.abs(h2[1]:Dot(a)) + math.abs(h2[2]:Dot(a)) + math.abs(h2[3]:Dot(a))
		if math.abs(d:Dot(a)) > r1 + r2 then
			return false
		end
	end
	return true
end

local WS = {}
function WS.Raycast(o, origin, direction, params)
	self(o, "Raycast")
	if typeof(origin) ~= "Vector3" then
		error("invalid argument #1 to 'Raycast' (Vector3 expected, got " .. typeof(origin) .. ")", 2)
	end
	if typeof(direction) ~= "Vector3" then
		error("invalid argument #2 to 'Raycast' (Vector3 expected, got " .. typeof(direction) .. ")", 2)
	end
	if params ~= nil and typeof(params) ~= "RaycastParams" then
		error("invalid argument #3 to 'Raycast' (RaycastParams expected, got " .. typeof(params) .. ")", 2)
	end
	if direction.Magnitude > 15000 then
		direction = direction.Unit * 15000
	end
	local ok = filterFn(params)
	local best, bestT, bestN = nil, math.huge, nil
	-- coarse reject with the ray's bounding box
	local rmin, rmax = origin:Min(origin + direction), origin:Max(origin + direction)
	for p in candidates(rmin.X, rmin.Z, rmax.X, rmax.Z) do
		local pp = rawget(p, "_p")
		if pp.CanQuery ~= false then
			local x0, y0, z0, x1, y1, z1 = aabbFast(p)
			if x1 >= rmin.X and x0 <= rmax.X and y1 >= rmin.Y and y0 <= rmax.Y and z1 >= rmin.Z and z0 <= rmax.Z then
				local c, s = partBox(p)
				local t, n = rayBox(origin, direction, c, s)
				if t and t < bestT and ok(p) then
					best, bestT, bestN = p, t, n
				end
			end
		end
	end
	if not best then
		if not H.terrainNoted then
			H.terrainNoted = true
			note("Raycasts never hit Terrain headless (voxels aren't simulated); code must handle a nil result")
		end
		return nil
	end
	local pos = origin + direction * bestT
	return H.RaycastResult(best, pos, bestN, rawget(best, "_p").Material or Enum.Material.Plastic, (direction * bestT).Magnitude)
end
function WS.Spherecast(o, origin, radius, direction, params)
	self(o, "Spherecast")
	note("Workspace:Spherecast/Blockcast/Shapecast always return nil headless")
	return nil
end
WS.Blockcast = function(o)
	self(o, "Blockcast")
	note("Workspace:Spherecast/Blockcast/Shapecast always return nil headless")
	return nil
end
WS.Shapecast = WS.Blockcast
local function overlapList(params, test, qmin, qmax)
	if params ~= nil and typeof(params) ~= "OverlapParams" then
		error("invalid argument (OverlapParams expected, got " .. typeof(params) .. ")", 3)
	end
	local ok = filterFn(params)
	local max = params and rawget(params, "_f").MaxParts or 0
	local out = {}
	for p in candidates(qmin.X, qmin.Z, qmax.X, qmax.Z) do
		local pp = rawget(p, "_p")
		if pp.CanQuery ~= false and test(p) and ok(p) then
			table.insert(out, p)
			if max > 0 and #out >= max then
				break
			end
		end
	end
	return out
end
function WS.GetPartBoundsInBox(o, c, size, params)
	self(o, "GetPartBoundsInBox")
	if typeof(c) ~= "CFrame" then
		error("invalid argument #1 to 'GetPartBoundsInBox' (CFrame expected, got " .. typeof(c) .. ")", 2)
	end
	if typeof(size) ~= "Vector3" then
		error("invalid argument #2 to 'GetPartBoundsInBox' (Vector3 expected, got " .. typeof(size) .. ")", 2)
	end
	local qmin, qmax = aabbOf(c, size)
	local axisAligned = math.abs(c[4]) > 0.9999 and math.abs(c[8]) > 0.9999 and math.abs(c[12]) > 0.9999
	return overlapList(params, function(p)
		local x0, y0, z0, x1, y1, z1 = aabbFast(p)
		if x1 < qmin.X or x0 > qmax.X or y1 < qmin.Y or y0 > qmax.Y or z1 < qmin.Z or z0 > qmax.Z then
			return false
		end
		if axisAligned then
			return true
		end
		-- the part's bounding box against the query's oriented box
		return obbOverlap(CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), v3(x1 - x0, y1 - y0, z1 - z0), c, size)
	end, qmin, qmax)
end
function WS.GetPartBoundsInRadius(o, pos, radius, params)
	self(o, "GetPartBoundsInRadius")
	if typeof(pos) ~= "Vector3" then
		error("invalid argument #1 to 'GetPartBoundsInRadius' (Vector3 expected, got " .. typeof(pos) .. ")", 2)
	end
	if type(radius) ~= "number" then
		error("invalid argument #2 to 'GetPartBoundsInRadius' (number expected, got " .. typeof(radius) .. ")", 2)
	end
	return overlapList(params, function(p)
		local x0, y0, z0, x1, y1, z1 = aabbFast(p)
		local dx = math.max(x0 - pos.X, 0, pos.X - x1)
		local dy = math.max(y0 - pos.Y, 0, pos.Y - y1)
		local dz = math.max(z0 - pos.Z, 0, pos.Z - z1)
		return dx * dx + dy * dy + dz * dz <= radius * radius
	end, pos - v3(radius, radius, radius), pos + v3(radius, radius, radius))
end
function WS.GetPartsInPart(o, part, params)
	self(o, "GetPartsInPart")
	if not isInstance(part) or not rawget(part, "_c").isa.BasePart then
		error("invalid argument #1 to 'GetPartsInPart' (BasePart expected, got " .. typeof(part) .. ")", 2)
	end
	local c, s = partBox(part)
	local qmin, qmax = aabbOf(c, s)
	return overlapList(params, function(p)
		if p == part then
			return false
		end
		local pc, ps = partBox(p)
		return obbOverlap(c, s, pc, ps)
	end, qmin, qmax)
end
function WS.ArePartsTouchingOthers(o, parts)
	return false
end
function WS.GetServerTimeNow()
	return os.time() + (H.now % 1)
end
function WS.GetRealPhysicsFPS()
	return 60
end
function WS.BulkMoveTo(o, parts, cframes)
	for i, p in parts do
		p.CFrame = cframes[i]
	end
end
function WS.FindPartOnRay()
	error("Workspace:FindPartOnRay is deprecated; not mocked [MOCK MISSING: Workspace.FindPartOnRay]", 2)
end
function WS.FindPartsInRegion3()
	error("Workspace:FindPartsInRegion3 is deprecated; not mocked [MOCK MISSING]", 2)
end
function WS.JoinToOutsiders() end
function WS.UnjoinFromOutsiders() end
service("Workspace", "WorldRoot", {
	props = {
		Gravity = { "number", 196.2 },
		FallenPartsDestroyHeight = { "number", -500 },
		StreamingEnabled = { "bool", false },
		StreamingMinRadius = { "number", 64 },
		StreamingTargetRadius = { "number", 1024 },
		CurrentCamera = { "Instance:Camera", nil },
		DistributedGameTime = { "number", 0, "ro", get = function()
			return H.now
		end },
		AirDensity = { "number", 0.0012 },
		GlobalWind = { "Vector3", Vector3.zero },
		SignalBehavior = { "Enum:SignalBehavior", nil },
		TouchesUseCollisionGroups = { "bool", false },
		AllowThirdPartySales = { "bool", false },
	},
	methods = WS,
	events = { "PersistentLoaded" },
})
SERVICE_NAMES.Workspace = true

-- Terrain: voxel writes are checked (grid alignment, array shapes, size limit) and remembered only as a count.
H.terrain = { writes = 0, fills = 0, colors = {} }
local TERRAIN_MAX_VOXELS = 4194304
local function checkRegion(region, res, fname)
	if typeof(region) ~= "Region3" then
		error(("invalid argument #1 to '%s' (Region3 expected, got %s)"):format(fname, typeof(region)), 3)
	end
	if res ~= 4 then
		error(("%s: resolution must be 4"):format(fname), 3)
	end
	local mn, mx = rawget(region, "_min"), rawget(region, "_max")
	for _, v in { mn.X, mn.Y, mn.Z, mx.X, mx.Y, mx.Z } do
		if v % 4 ~= 0 then
			error(("%s: Region has to be aligned to the grid (use Region3:ExpandToGrid(4))"):format(fname), 3)
		end
	end
	local nx, ny, nz = (mx.X - mn.X) / 4, (mx.Y - mn.Y) / 4, (mx.Z - mn.Z) / 4
	if nx <= 0 or ny <= 0 or nz <= 0 then
		error(("%s: region is empty"):format(fname), 3)
	end
	if nx * ny * nz > TERRAIN_MAX_VOXELS then
		error(("%s: region has %d voxels, more than the %d allowed"):format(fname, nx * ny * nz, TERRAIN_MAX_VOXELS), 3)
	end
	return nx, ny, nz
end
local function checkMaterial(m, fname)
	if getmetatable(m) ~= H.EnumItemMT or m.EnumType ~= H.enumCat("Material") then
		error(("invalid argument to '%s' (Enum.Material expected, got %s)"):format(fname, typeof(m)), 3)
	end
	local terrainOk = { Air = true, Water = true, Grass = true, LeafyGrass = true, Sand = true, Rock = true, Slate = true, Concrete = true, Brick = true, Cobblestone = true, Ground = true, Mud = true, Snow = true, Glacier = true, Ice = true, Sandstone = true, Basalt = true, CrackedLava = true, Asphalt = true, Salt = true, Limestone = true, Pavement = true, WoodPlanks = true }
	if not terrainOk[m.Name] then
		error(("%s: %s is not a terrain material"):format(fname, tostring(m)), 3)
	end
end
local TERR = CLASSES.Terrain.methods
function TERR.WriteVoxels(o, region, res, materials, occupancy)
	self(o, "WriteVoxels")
	local nx, ny, nz = checkRegion(region, res, "WriteVoxels")
	for _, pair in { { materials, "materials" }, { occupancy, "occupancy" } } do
		local arr, label = pair[1], pair[2]
		if type(arr) ~= "table" or #arr ~= nx then
			error(("WriteVoxels: %s must be a %dx%dx%d array (x size is %s)"):format(label, nx, ny, nz, type(arr) == "table" and #arr or typeof(arr)), 2)
		end
		for i = 1, nx do
			local col = arr[i]
			if type(col) ~= "table" or #col ~= ny then
				error(("WriteVoxels: %s[%d] must have %d entries (y), has %s"):format(label, i, ny, type(col) == "table" and #col or typeof(col)), 2)
			end
			for j = 1, ny do
				local row = col[j]
				if type(row) ~= "table" or #row ~= nz then
					error(("WriteVoxels: %s[%d][%d] must have %d entries (z), has %s"):format(label, i, j, nz, type(row) == "table" and #row or typeof(row)), 2)
				end
			end
		end
	end
	-- spot-check the values (checking every voxel would be slow)
	for i = 1, nx, math.max(1, nx // 4) do
		for j = 1, ny, math.max(1, ny // 4) do
			for k = 1, nz, math.max(1, nz // 4) do
				checkMaterial(materials[i][j][k], "WriteVoxels")
				local occ = occupancy[i][j][k]
				if type(occ) ~= "number" then
					error(("WriteVoxels: occupancy[%d][%d][%d] is %s, number expected"):format(i, j, k, typeof(occ)), 2)
				end
			end
		end
	end
	H.terrain.writes += 1
	rawset(o, "_written", true)
	H.terrainCells = H.terrainCells or {}
	-- remember which 4-stud cells were written as solid, so ReadVoxels can answer the probe in WorldTerrain.isBuilt
	local mn = rawget(region, "_min")
	if nx * ny * nz <= 20000 then
		for i = 1, nx do
			for j = 1, ny do
				for k = 1, nz do
					local m = materials[i][j][k]
					if m.Name ~= "Air" and occupancy[i][j][k] > 0 then
						H.terrainCells[(mn.X // 4 + i - 1) .. "," .. (mn.Y // 4 + j - 1) .. "," .. (mn.Z // 4 + k - 1)] = m
					end
				end
			end
		end
	end
end
function TERR.ReadVoxels(o, region, res)
	self(o, "ReadVoxels")
	local nx, ny, nz = checkRegion(region, res, "ReadVoxels")
	local mn = rawget(region, "_min")
	local mats, occs = {}, {}
	for i = 1, nx do
		mats[i], occs[i] = {}, {}
		for j = 1, ny do
			mats[i][j], occs[i][j] = {}, {}
			for k = 1, nz do
				local m = H.terrainCells and H.terrainCells[(mn.X // 4 + i - 1) .. "," .. (mn.Y // 4 + j - 1) .. "," .. (mn.Z // 4 + k - 1)]
				mats[i][j][k] = m or Enum.Material.Air
				occs[i][j][k] = m and 1 or 0
			end
		end
	end
	mats.Size = v3(nx, ny, nz)
	occs.Size = v3(nx, ny, nz)
	return mats, occs
end
local function fillCheck(fname, mat)
	checkMaterial(mat, fname)
	H.terrain.fills += 1
end
function TERR.FillBlock(o, c, size, mat)
	self(o, "FillBlock")
	if typeof(c) ~= "CFrame" then
		error("invalid argument #1 to 'FillBlock' (CFrame expected, got " .. typeof(c) .. ")", 2)
	end
	if typeof(size) ~= "Vector3" then
		error("invalid argument #2 to 'FillBlock' (Vector3 expected, got " .. typeof(size) .. ")", 2)
	end
	fillCheck("FillBlock", mat)
end
function TERR.FillBall(o, center, radius, mat)
	self(o, "FillBall")
	if typeof(center) ~= "Vector3" then
		error("invalid argument #1 to 'FillBall' (Vector3 expected, got " .. typeof(center) .. ")", 2)
	end
	if type(radius) ~= "number" then
		error("invalid argument #2 to 'FillBall' (number expected, got " .. typeof(radius) .. ")", 2)
	end
	fillCheck("FillBall", mat)
end
function TERR.FillCylinder(o, c, height, radius, mat)
	self(o, "FillCylinder")
	if typeof(c) ~= "CFrame" then
		error("invalid argument #1 to 'FillCylinder' (CFrame expected, got " .. typeof(c) .. ")", 2)
	end
	fillCheck("FillCylinder", mat)
end
function TERR.FillWedge(o, c, size, mat)
	self(o, "FillWedge")
	fillCheck("FillWedge", mat)
end
function TERR.FillRegion(o, region, res, mat)
	self(o, "FillRegion")
	checkRegion(region, res, "FillRegion")
	fillCheck("FillRegion", mat)
end
function TERR.Clear(o)
	self(o, "Clear")
	H.terrainCells = {}
	H.terrain.cleared = (H.terrain.cleared or 0) + 1
end
function TERR.SetMaterialColor(o, mat, color)
	self(o, "SetMaterialColor")
	checkMaterial(mat, "SetMaterialColor")
	if typeof(color) ~= "Color3" then
		error("invalid argument #2 to 'SetMaterialColor' (Color3 expected, got " .. typeof(color) .. ")", 2)
	end
	H.terrain.colors[mat.Name] = color
end
function TERR.GetMaterialColor(o, mat)
	checkMaterial(mat, "GetMaterialColor")
	return H.terrain.colors[mat.Name] or Color3.fromRGB(100, 120, 80)
end
function TERR.ReplaceMaterial(o, region, res, from, to)
	checkRegion(region, res, "ReplaceMaterial")
	checkMaterial(from, "ReplaceMaterial")
	checkMaterial(to, "ReplaceMaterial")
end
function TERR.CellCenterToWorld(o, x, y, z)
	return v3(x * 4 + 2, y * 4 + 2, z * 4 + 2)
end
function TERR.WorldToCell(o, p)
	return v3(math.floor(p.X / 4), math.floor(p.Y / 4), math.floor(p.Z / 4))
end
function TERR.CopyRegion()
	error("Terrain:CopyRegion is not mocked [MOCK MISSING: Terrain.CopyRegion]", 2)
end
function TERR.PasteRegion()
	error("Terrain:PasteRegion is not mocked [MOCK MISSING: Terrain.PasteRegion]", 2)
end

-- Build the DataModel ---------------------------------------------------------------------------------------------------
local game_ = rawNew("DataModel")
rawset(game_, "_name", "Game")
H.game = game_
game = game_
Game = game_
for name in SERVICE_NAMES do
	makeService(name)
end
workspace = services.Workspace
Workspace = services.Workspace
H.workspace = services.Workspace
H.CollectionService = services.CollectionService
do
	local camera = rawNew("Camera")
	camera.Parent = workspace
	setRaw(workspace, "CurrentCamera", camera)
	local terrain = rawNew("Terrain")
	rawset(terrain, "_name", "Terrain")
	rawget(terrain, "_p").Anchored = true
	terrain.Parent = workspace
	local sps = rawNew("StarterPlayerScripts")
	rawset(sps, "_name", "StarterPlayerScripts")
	sps.Parent = services.StarterPlayer
	local scs = rawNew("StarterCharacterScripts")
	rawset(scs, "_name", "StarterCharacterScripts")
	scs.Parent = services.StarterPlayer
end
function H.makeService(name)
	return makeService(name)
end
-- Unmocked services: every member access is a MOCK MISSING error.
local baseIndex = getmetatable(game_).__index
getmetatable(game_).__index = function(o, k)
	local c = rawget(o, "_c")
	if c.stub then
		local m = c.members[k]
		if not m or (m.kind ~= 1 or (k ~= "Name" and k ~= "Parent" and k ~= "ClassName")) then
			error(("MOCK MISSING: %s.%s (this service is not mocked headless)"):format(c.name, tostring(k)), 2)
		end
	end
	return baseIndex(o, k)
end

-- RunService frame signals are fired by H.step
do
	local rs = services.RunService
	H.frameSignalsReady = true
	H.fireFrame = function(name, ...)
		fireEvent(rs, name, ...)
	end
end

-- settings() / UserSettings() exist in Roblox; nothing here uses them
function settings()
	error("MOCK MISSING: settings()", 2)
end
function UserSettings()
	error("MOCK MISSING: UserSettings()", 2)
end
version = function()
	return "0.0.0.0"
end
shared = {}
_G = _G or {}

-- Modules and scripts ---------------------------------------------------------------------------------------------------
-- SOURCES[fullName] = { path = "src/...", source = "..." } is filled in by run.py. require() runs a ModuleScript's
-- source once (chunk name = its src path, so errors point at the real file and line).
SOURCES = SOURCES or {}
local moduleState = {} -- module -> { state = "loading"|"done"|"failed", value, waiting = {} }
H.moduleState = moduleState
H.modulesLoaded = 0
local baseRequire = require
function require(target)
	if type(target) == "number" then
		error("require(assetId) is not available headless [MOCK MISSING: require by asset id " .. tostring(target) .. "]", 2)
	end
	if not isInstance(target) or rawget(target, "_c").name ~= "ModuleScript" then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local st = moduleState[target]
	if st then
		if st.state == "done" then
			return st.value
		elseif st.state == "failed" then
			error("Requested module experienced an error while loading", 2)
		end
		-- loading: same thread => recursion; another thread => wait for it
		local co = coroutine.running()
		if st.thread == co or st.chain[co] then
			error("Requested module was required recursively", 2)
		end
		table.insert(st.waiting, co)
		H.parked[co] = "require " .. fullName(target)
		coroutine.yield()
		if st.state == "failed" then
			error("Requested module experienced an error while loading", 2)
		end
		return st.value
	end
	local key = fullName(target)
	local src = SOURCES[key]
	if not src then
		error(("require: no source for %s [headless: run.py did not bundle it]"):format(key), 2)
	end
	local co = coroutine.running()
	st = { state = "loading", waiting = {}, thread = co, chain = { [co] = true } }
	moduleState[target] = st
	local fn, compileErr = loadstring(src.source, "@" .. src.path)
	local ok, result
	if not fn then
		ok, result = false, compileErr
	else
		local n
		local results = table.pack(xpcall(fn, function(e)
			return { msg = e, trace = debug.traceback(nil, 2) }
		end, target))
		ok = results[1]
		if ok then
			n = results.n - 1
			if n ~= 1 then
				ok, result = false, { msg = ("Module code did not return exactly one value (%s)"):format(src.path), trace = "" }
			else
				result = results[2]
			end
		else
			result = results[2]
		end
	end
	local waiting = st.waiting
	if ok then
		st.state = "done"
		st.value = result
		H.modulesLoaded += 1
	else
		st.state = "failed"
		local msg = type(result) == "table" and result.msg or result
		local trace = type(result) == "table" and result.trace or ""
		H.reportError(msg, trace, "loading " .. src.path)
	end
	for _, w in waiting do
		H.parked[w] = nil
		H.resume(w)
	end
	if not ok then
		error("Requested module experienced an error while loading", 2)
	end
	return result
end

-- Runs a Script/LocalScript instance's source as a new thread (script = that instance).
function H.runScript(scriptInst)
	local key = fullName(scriptInst)
	local src = SOURCES[key]
	local fn, err = loadstring(src.source, "@" .. src.path)
	if not fn then
		H.reportError(err, "", "compiling " .. src.path)
		return
	end
	return H.run(function()
		fn(scriptInst)
	end, src.path)
end

-- Sets `script` for every chunk: loadstring chunks read the global, so give each module its own env.
-- (Luau keeps globals shared; we pass the instance as `...` and run.py prefixes each chunk with `local script = ...`.)

-- Characters --------------------------------------------------------------------------------------------------------------
local R15 = {
	{ "HumanoidRootPart", v3(2, 2, 1), v3(0, 0, 0) },
	{ "LowerTorso", v3(2, 0.4, 1), v3(0, -0.2, 0) },
	{ "UpperTorso", v3(2, 1.6, 1), v3(0, 0.8, 0) },
	{ "Head", v3(1.2, 1.2, 1.2), v3(0, 2.2, 0) },
	{ "LeftUpperArm", v3(1, 1.2, 1), v3(-1.5, 1, 0) },
	{ "LeftLowerArm", v3(1, 1, 1), v3(-1.5, -0.1, 0) },
	{ "LeftHand", v3(1, 0.3, 1), v3(-1.5, -0.75, 0) },
	{ "RightUpperArm", v3(1, 1.2, 1), v3(1.5, 1, 0) },
	{ "RightLowerArm", v3(1, 1, 1), v3(1.5, -0.1, 0) },
	{ "RightHand", v3(1, 0.3, 1), v3(1.5, -0.75, 0) },
	{ "LeftUpperLeg", v3(1, 1.2, 1), v3(-0.5, -1, 0) },
	{ "LeftLowerLeg", v3(1, 1.1, 1), v3(-0.5, -2.1, 0) },
	{ "LeftFoot", v3(1, 0.3, 1), v3(-0.5, -2.8, 0) },
	{ "RightUpperLeg", v3(1, 1.2, 1), v3(0.5, -1, 0) },
	{ "RightLowerLeg", v3(1, 1.1, 1), v3(0.5, -2.1, 0) },
	{ "RightFoot", v3(1, 0.3, 1), v3(0.5, -2.8, 0) },
}
local MOTORS = {
	{ "Root", "LowerTorso", "HumanoidRootPart" }, { "Waist", "UpperTorso", "LowerTorso" }, { "Neck", "Head", "UpperTorso" },
	{ "LeftShoulder", "LeftUpperArm", "UpperTorso" }, { "LeftElbow", "LeftLowerArm", "LeftUpperArm" }, { "LeftWrist", "LeftHand", "LeftLowerArm" },
	{ "RightShoulder", "RightUpperArm", "UpperTorso" }, { "RightElbow", "RightLowerArm", "RightUpperArm" }, { "RightWrist", "RightHand", "RightLowerArm" },
	{ "LeftHip", "LeftUpperLeg", "LowerTorso" }, { "LeftKnee", "LeftLowerLeg", "LeftUpperLeg" }, { "LeftAnkle", "LeftFoot", "LeftLowerLeg" },
	{ "RightHip", "RightUpperLeg", "LowerTorso" }, { "RightKnee", "RightLowerLeg", "RightUpperLeg" }, { "RightAnkle", "RightFoot", "RightLowerLeg" },
}
function H.spawnCharacter(player)
	local old = rawget(player, "_p").Character
	if old then
		fireEvent(player, "CharacterRemoving", old)
		old:Destroy()
	end
	local spawnCF = CFrame.new(0, 10, 0)
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpawnLocation") and d.Enabled then
			spawnCF = d.CFrame + v3(0, d.Size.Y / 2 + 3, 0)
			break
		end
	end
	local model = Instance.new("Model")
	model.Name = player.Name
	local parts = {}
	for _, def in R15 do
		local p = Instance.new(def[1] == "HumanoidRootPart" and "Part" or "MeshPart")
		p.Name = def[1]
		p.Size = def[2]
		p.CFrame = spawnCF * CFrame.new(def[3])
		p.CanCollide = def[1] == "HumanoidRootPart"
		p.Transparency = def[1] == "HumanoidRootPart" and 1 or 0
		p.Parent = model
		parts[def[1]] = p
	end
	for _, m in MOTORS do
		local motor = Instance.new("Motor6D")
		motor.Name = m[1]
		local part1, part0 = parts[m[2]], parts[m[3]]
		motor.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
		motor.Part0 = part0
		motor.Part1 = part1
		motor.Parent = part1
	end
	for _, name in { "RightGripAttachment", "LeftGripAttachment" } do
		local a = Instance.new("Attachment")
		a.Name = name
		a.Parent = parts[name == "RightGripAttachment" and "RightHand" or "LeftHand"]
	end
	local rootAtt = Instance.new("Attachment")
	rootAtt.Name = "RootAttachment"
	rootAtt.Parent = parts.HumanoidRootPart
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	model.PrimaryPart = parts.HumanoidRootPart
	player.Character = model
	model.Parent = workspace
	fireEvent(player, "CharacterAdded", model)
	fireEvent(player, "CharacterAppearanceLoaded", model)
	return model
end

-- Makes a Player and parents it to Players (fires PlayerAdded), then spawns its character a frame later.
function H.addPlayer(userId, name)
	local player = rawNew("Player")
	rawset(player, "_name", name)
	rawget(player, "_p").UserId = userId
	rawget(player, "_p").DisplayName = name
	for _, cls in { "Backpack", "PlayerGui", "PlayerScripts" } do
		local x = rawNew(cls)
		rawset(x, "_name", cls)
		x.Parent = player
	end
	local starterGear = rawNew("StarterGear")
	rawset(starterGear, "_name", "StarterGear")
	starterGear.Parent = player
	H.setParent(player, services.Players)
	fireEvent(services.Players, "PlayerAdded", player)
	return player
end
function H.removePlayer(player)
	fireEvent(services.Players, "PlayerRemoving", player)
	local character = rawget(player, "_p").Character
	if character then
		fireEvent(player, "CharacterRemoving", character)
		character:Destroy()
	end
	H.setParent(player, nil)
end

-- Hook RunService frame signals into the scheduler
H.frameSignalNames = { "PreSimulation", "Stepped", "PostSimulation", "Heartbeat" }
