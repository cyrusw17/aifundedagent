-- Headless Roblox, part 2: signals and the Instance tree (class hierarchy, properties with type checks, events,
-- attributes, tags, parenting, Clone/Destroy, models, parts, joints, humanoids). See mock.luau for the rules.
local v3, cf, c3 = H.v3, H.cf, H.c3
local cfMul, cfInverse = H.cfMul, H.cfInverse
local TYPE = H.TYPE
local EnumItemMT = H.EnumItemMT
local coerceEnum = H.coerceEnum
local IDENTITY = CFrame.identity
local note = H.note

-- Signals -----------------------------------------------------------------------------------------------------------
local SignalMT = H.datatype("RBXScriptSignal")
local ConnectionMT = H.datatype("RBXScriptConnection")
local SignalMethods = {}
local ConnMethods = {}
H.listenerCount = 0

local function newSignal(name)
	return setmetatable({ _name = name, _conns = {}, _waiting = {} }, SignalMT)
end
H.newSignal = newSignal
SignalMT.__index = function(s, k)
	local m = SignalMethods[k]
	if m then
		return m
	end
	error(("%s is not a valid member of RBXScriptSignal"):format(tostring(k)), 2)
end
SignalMT.__tostring = function(s)
	return "Signal " .. tostring(s._name)
end
ConnectionMT.__index = function(c, k)
	if k == "Connected" then
		return rawget(c, "_on")
	end
	local m = ConnMethods[k]
	if m then
		return m
	end
	error(("%s is not a valid member of RBXScriptConnection"):format(tostring(k)), 2)
end
function ConnMethods.Disconnect(c)
	if rawget(c, "_on") then
		rawset(c, "_on", false)
		local list = c._sig._conns
		local i = table.find(list, c)
		if i then
			table.remove(list, i)
		end
	end
end
function SignalMethods.Connect(s, fn)
	if getmetatable(s) ~= SignalMT then
		error("Expected ':' not '.' calling member function Connect", 2)
	end
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 2)
	end
	local c = setmetatable({ _sig = s, _fn = fn, _on = true }, ConnectionMT)
	table.insert(s._conns, c)
	return c
end
SignalMethods.ConnectParallel = SignalMethods.Connect
function SignalMethods.Once(s, fn)
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 2)
	end
	local c
	c = SignalMethods.Connect(s, function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
function SignalMethods.Wait(s)
	local co = coroutine.running()
	if not coroutine.isyieldable() then
		error("attempt to yield outside a Roblox thread (Signal:Wait)", 2)
	end
	table.insert(s._waiting, co)
	H.parked[co] = "Wait on " .. tostring(s._name)
	return coroutine.yield()
end
local function fire(s, ...)
	if #s._conns > 0 then
		local snapshot = table.clone(s._conns)
		for _, c in snapshot do
			if rawget(c, "_on") then
				local co = H.newThread(c._fn, "handler for " .. tostring(s._name))
				if H.deferredSignals then
					task.defer(co, ...)
				else
					H.resume(co, ...)
				end
			end
		end
	end
	if #s._waiting > 0 then
		local waiting = s._waiting
		s._waiting = {}
		for _, co in waiting do
			H.parked[co] = nil
			if H.deferredSignals then
				task.defer(co, ...)
			else
				H.resume(co, ...)
			end
		end
	end
end
H.fire = fire
local function disconnectAll(s)
	for _, c in s._conns do
		rawset(c, "_on", false)
	end
	s._conns = {}
end

-- Classes -----------------------------------------------------------------------------------------------------------
local PROP, METHOD, EVENT, CALLBACK = 1, 2, 3, 4
local CLASSES = {}
H.CLASSES = CLASSES

-- class(name, super, { props = { Name = { type, default, flags } }, methods = {}, events = {}, callbacks = {},
--                      abstract = true, service = true, notCreatable = true })
-- type: "number" "int" "bool" "string" "any" "Instance" "Instance:Class" "Enum:Cat" "<Datatype>" "<Datatype>?"
-- flags: "ro" read-only, "noscript" scripts can't write it (MeshId), "hidden" deprecated alias.
local function class(name, super, spec)
	spec = spec or {}
	spec.name = name
	spec.super = super
	spec.props = spec.props or {}
	spec.methods = spec.methods or {}
	spec.events = spec.events or {}
	spec.callbacks = spec.callbacks or {}
	CLASSES[name] = spec
	return spec
end
H.class = class

local function resolve(c)
	if c.members then
		return c
	end
	local members, isa = {}, { [c.name] = true }
	if c.super then
		local sup = CLASSES[c.super]
		assert(sup, "mock: unknown superclass " .. c.super)
		resolve(sup)
		for k, m in sup.members do
			members[k] = m
		end
		for k in sup.isa do
			isa[k] = true
		end
	end
	for k, p in c.props do
		members[k] = { kind = PROP, type = p[1], default = p[2], flag = p[3], get = p.get, set = p.set, name = k }
	end
	for k, fn in c.methods do
		members[k] = { kind = METHOD, fn = fn, name = k }
	end
	for _, k in c.events do
		members[k] = { kind = EVENT, name = k }
	end
	for _, k in c.callbacks do
		members[k] = { kind = CALLBACK, name = k }
	end
	c.members = members
	c.isa = isa
	return c
end
H.resolve = resolve

-- Instance objects --------------------------------------------------------------------------------------------------
-- Raw fields: _c class, _name, _parent, _kids (array), _p (property values), _attr, _sig (event signals),
-- _psig (property signals), _asig (attribute signals), _cb (callbacks), _locked (destroyed), _tags.
local InstMT = {}
H.InstMT = InstMT
TYPE[InstMT] = "Instance"
local function isInstance(v)
	return getmetatable(v) == InstMT
end
H.isInstance = isInstance

local function fullName(o)
	local names = {}
	local x = o
	while x and rawget(x, "_c").name ~= "DataModel" do
		table.insert(names, 1, rawget(x, "_name"))
		x = rawget(x, "_parent")
	end
	return table.concat(names, ".")
end
H.fullName = fullName

local function missing(o, k)
	local c = rawget(o, "_c")
	error(("%s is not a valid member of %s \"%s\" [MOCK MISSING: %s.%s, if that is a real Roblox API add it to tools/headless]"):format(tostring(k), c.name, fullName(o), c.name, tostring(k)), 3)
end

local function getSignal(o, k)
	local sigs = rawget(o, "_sig")
	if not sigs then
		sigs = {}
		rawset(o, "_sig", sigs)
	end
	local s = sigs[k]
	if not s then
		s = newSignal(rawget(o, "_name") .. "." .. k)
		sigs[k] = s
	end
	return s
end
H.getSignal = getSignal
-- Fires an instance event if anyone listens.
local function fireEvent(o, k, ...)
	local sigs = rawget(o, "_sig")
	local s = sigs and sigs[k]
	if s then
		fire(s, ...)
	end
end
H.fireEvent = fireEvent

local function getProp(o, m)
	if m.get then
		return m.get(o)
	end
	local v = rawget(o, "_p")[m.name]
	if v == nil then
		return m.default
	end
	return v
end

InstMT.__index = function(o, k)
	local c = rawget(o, "_c")
	local m = c.members[k]
	if m then
		local kind = m.kind
		if kind == PROP then
			return getProp(o, m)
		elseif kind == METHOD then
			return m.fn
		elseif kind == EVENT then
			return getSignal(o, k)
		else
			error(("%s is a callback member of %s; you can only set the callback value, get is not available"):format(k, c.name), 2)
		end
	end
	if type(k) == "string" then
		for _, child in rawget(o, "_kids") do
			if rawget(child, "_name") == k then
				return child
			end
		end
	end
	if type(k) ~= "string" then
		error(("invalid argument #2 (string expected, got %s)"):format(typeof(k)), 2)
	end
	error(("%s is not a valid member of %s \"%s\"%s"):format(k, c.name, fullName(o), H.memberHint and H.memberHint(c, k) or ""), 2)
end

-- Type checks for property writes ---------------------------------------------------------------------------------
local function coerce(o, m, v)
	local t = m.type
	local nullable = false
	if string.sub(t, -1) == "?" then
		nullable = true
		t = string.sub(t, 1, -2)
		if v == nil then
			return nil, true
		end
	end
	local ok = false
	if t == "number" then
		ok = type(v) == "number"
	elseif t == "int" then
		if type(v) == "number" then
			ok = true
			v = if v >= 0 then math.floor(v) else math.ceil(v)
		end
	elseif t == "bool" then
		ok = type(v) == "boolean"
	elseif t == "string" then
		if type(v) == "number" then
			v = tostring(v)
		end
		ok = type(v) == "string"
	elseif t == "any" then
		ok = true
	elseif t == "Instance" then
		ok = v == nil or isInstance(v)
	elseif string.sub(t, 1, 9) == "Instance:" then
		ok = v == nil or (isInstance(v) and rawget(v, "_c").isa[string.sub(t, 10)])
	elseif string.sub(t, 1, 5) == "Enum:" then
		local e = coerceEnum(string.sub(t, 6), v)
		if e then
			return e, true
		end
		return nil, false, ("Unable to assign property %s. %s expected, got %s"):format(m.name, "Enum." .. string.sub(t, 6), if getmetatable(v) == EnumItemMT then tostring(v) else typeof(v))
	else
		ok = typeof(v) == t
	end
	if not ok then
		return nil, false, ("Unable to assign property %s. %s expected, got %s"):format(m.name, t, typeof(v))
	end
	return v, true
end

local function propChanged(o, name)
	local sigs = rawget(o, "_sig")
	if sigs and sigs.Changed and not rawget(o, "_c").isa.ValueBase then
		fire(sigs.Changed, name)
	end
	local ps = rawget(o, "_psig")
	if ps and ps[name] then
		fire(ps[name])
	end
end
H.propChanged = propChanged

-- Sets a stored property and fires change signals when the value changed (no type check; mock-internal).
local function setRaw(o, name, v)
	local p = rawget(o, "_p")
	local m = rawget(o, "_c").members[name]
	local old = p[name]
	if old == nil and m then
		old = m.default
	end
	p[name] = v
	if old ~= v then
		propChanged(o, name)
	end
end
H.setRaw = setRaw

InstMT.__newindex = function(o, k, v)
	local c = rawget(o, "_c")
	local m = c.members[k]
	if not m then
		if type(k) ~= "string" then
			error(("invalid argument #2 (string expected, got %s)"):format(typeof(k)), 2)
		end
		error(("%s is not a valid member of %s \"%s\"%s"):format(k, c.name, fullName(o), H.memberHint and H.memberHint(c, k) or ""), 2)
	end
	if m.kind == CALLBACK then
		if v ~= nil and type(v) ~= "function" then
			error(("Unable to assign property %s. Function expected, got %s"):format(k, typeof(v)), 2)
		end
		local cbs = rawget(o, "_cb")
		if not cbs then
			cbs = {}
			rawset(o, "_cb", cbs)
		end
		cbs[k] = v
		if H.onCallbackSet then
			H.onCallbackSet(o, k, v)
		end
		return
	elseif m.kind ~= PROP then
		error(("Unable to assign property %s. Property is read only"):format(k), 2)
	end
	if m.flag == "ro" then
		error(("Unable to assign property %s. Property is read only"):format(k), 2)
	elseif m.flag == "noscript" then
		error(("Unable to assign property %s. Script write access is restricted"):format(k), 2)
	end
	local value, ok, err = coerce(o, m, v)
	if not ok then
		error(err, 2)
	end
	if m.set then
		m.set(o, value)
		return
	end
	setRaw(o, k, value)
end
InstMT.__tostring = function(o)
	return rawget(o, "_name")
end
InstMT.__iter = function()
	error("attempt to iterate over an Instance value", 2)
end
InstMT.__len = function()
	error("attempt to get length of an Instance value", 2)
end

-- Creating ------------------------------------------------------------------------------------------------------------
local function rawNew(className)
	local c = CLASSES[className]
	resolve(c)
	local o = setmetatable({ _c = c, _name = className, _kids = {}, _p = {}, _attr = {} }, InstMT)
	H.createdTotal += 1
	H.created[className] = (H.created[className] or 0) + 1
	if c.init then
		c.init(o)
	end
	-- run superclass inits too
	local sup = c.super and CLASSES[c.super]
	while sup do
		if sup.init then
			sup.init(o)
		end
		sup = sup.super and CLASSES[sup.super]
	end
	return o
end
H.rawNew = rawNew

-- Membership in the Workspace (for spatial queries) and the DataModel (for tags) ------------------------------------
H.worldParts = {} -- part -> true while it is a descendant of Workspace
local function isDescendantOf(o, ancestor)
	local p = rawget(o, "_parent")
	while p do
		if p == ancestor then
			return true
		end
		p = rawget(p, "_parent")
	end
	return false
end
H.isDescendantOf = isDescendantOf

local function walk(o, fn)
	fn(o)
	for _, k in rawget(o, "_kids") do
		walk(k, fn)
	end
end
H.walk = walk

local function inWorld(o)
	return H.workspace ~= nil and isDescendantOf(o, H.workspace)
end
H.inWorld = inWorld
local function inGame(o)
	return H.game ~= nil and (o == H.game or isDescendantOf(o, H.game))
end
H.inGame = inGame

-- Parenting ---------------------------------------------------------------------------------------------------------
local descendantListeners = 0 -- not tracked precisely; we just check ancestors for signals
local function setParent(o, parent)
	if rawget(o, "_locked") then
		error(("The Parent property of %s is locked, current parent: NULL, new parent %s"):format(rawget(o, "_name"), parent and rawget(parent, "_name") or "NULL"), 3)
	end
	if parent ~= nil and not isInstance(parent) then
		error(("Unable to assign property Parent. Instance expected, got %s"):format(typeof(parent)), 3)
	end
	local old = rawget(o, "_parent")
	if old == parent then
		return
	end
	if rawget(o, "_c").service then
		error(("The Parent property of %s is locked"):format(rawget(o, "_name")), 3)
	end
	if parent then
		if parent == o or isDescendantOf(parent, o) then
			error(("Attempt to set parent of %s to %s would result in circular reference"):format(fullName(o), fullName(parent)), 3)
		end
	end
	local wasWorld, wasGame = inWorld(o), inGame(o)
	if old then
		-- DescendantRemoving fires on the old ancestors before the move
		local a = old
		while a do
			local sigs = rawget(a, "_sig")
			if sigs and sigs.DescendantRemoving then
				local anc = a
				walk(o, function(d)
					fire(sigs.DescendantRemoving, d)
				end)
			end
			a = rawget(a, "_parent")
		end
		local list = rawget(old, "_kids")
		local i = table.find(list, o)
		if i then
			table.remove(list, i)
		end
	end
	rawset(o, "_parent", parent)
	if parent then
		table.insert(rawget(parent, "_kids"), o)
	end
	local isWorld, isGame = inWorld(o), inGame(o)
	if wasWorld ~= isWorld or wasGame ~= isGame then
		walk(o, function(d)
			local dc = rawget(d, "_c")
			if dc.isa.BasePart then
				if isWorld then
					H.worldParts[d] = true
				else
					H.worldParts[d] = nil
				end
				if H.onPartMoved then
					H.onPartMoved(d)
				end
			end
			local tags = rawget(d, "_tags")
			if tags and H.onTaggedMembership then
				H.onTaggedMembership(d, tags, isGame)
			end
			if dc.onWorldChange then
				dc.onWorldChange(d, isWorld)
			end
		end)
	end
	-- AncestryChanged on the instance and every descendant
	walk(o, function(d)
		local sigs = rawget(d, "_sig")
		if sigs and sigs.AncestryChanged then
			fire(sigs.AncestryChanged, o, parent)
		end
	end)
	if old then
		fireEvent(old, "ChildRemoved", o)
	end
	propChanged(o, "Parent")
	if parent then
		fireEvent(parent, "ChildAdded", o)
		local a = parent
		while a do
			local sigs = rawget(a, "_sig")
			if sigs and sigs.DescendantAdded then
				walk(o, function(d)
					fire(sigs.DescendantAdded, d)
				end)
			end
			a = rawget(a, "_parent")
		end
		local pc = rawget(parent, "_c")
		if pc.onChildAdded then
			pc.onChildAdded(parent, o)
		end
	end
	if old then
		local oc = rawget(old, "_c")
		if oc.onChildRemoved then
			oc.onChildRemoved(old, o)
		end
	end
end
H.setParent = setParent

-- Attributes --------------------------------------------------------------------------------------------------------
local ATTR_TYPES = { string = true, boolean = true, number = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true, Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true, Rect = true, Font = true, EnumItem = true }

-- Methods on every Instance -----------------------------------------------------------------------------------------
local function self(o, method)
	if not isInstance(o) then
		error(("Expected ':' not '.' calling member function %s"):format(method), 3)
	end
end
local function checkStr(fname, n, v)
	if type(v) ~= "string" then
		if type(v) == "number" then
			return tostring(v)
		end
		error(("invalid argument #%d to '%s' (string expected, got %s)"):format(n, fname, typeof(v)), 3)
	end
	return v
end

local I = {}
function I.IsA(o, name)
	self(o, "IsA")
	checkStr("IsA", 1, name)
	return rawget(o, "_c").isa[name] == true
end
function I.GetChildren(o)
	self(o, "GetChildren")
	return table.clone(rawget(o, "_kids"))
end
I.getChildren = I.GetChildren
I.children = I.GetChildren
function I.GetDescendants(o)
	self(o, "GetDescendants")
	local out = {}
	local function rec(x)
		for _, k in rawget(x, "_kids") do
			table.insert(out, k)
			rec(k)
		end
	end
	rec(o)
	return out
end
function I.FindFirstChild(o, name, recursive)
	self(o, "FindFirstChild")
	name = checkStr("FindFirstChild", 1, name)
	for _, k in rawget(o, "_kids") do
		if rawget(k, "_name") == name then
			return k
		end
	end
	if recursive then
		for _, k in rawget(o, "_kids") do
			local f = I.FindFirstChild(k, name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
I.findFirstChild = I.FindFirstChild
function I.FindFirstChildOfClass(o, cls)
	self(o, "FindFirstChildOfClass")
	checkStr("FindFirstChildOfClass", 1, cls)
	for _, k in rawget(o, "_kids") do
		if rawget(k, "_c").name == cls then
			return k
		end
	end
	return nil
end
function I.FindFirstChildWhichIsA(o, cls, recursive)
	self(o, "FindFirstChildWhichIsA")
	checkStr("FindFirstChildWhichIsA", 1, cls)
	for _, k in rawget(o, "_kids") do
		if rawget(k, "_c").isa[cls] then
			return k
		end
	end
	if recursive then
		for _, k in rawget(o, "_kids") do
			local f = I.FindFirstChildWhichIsA(k, cls, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function I.FindFirstDescendant(o, name)
	return I.FindFirstChild(o, name, true)
end
function I.FindFirstAncestor(o, name)
	self(o, "FindFirstAncestor")
	local p = rawget(o, "_parent")
	while p do
		if rawget(p, "_name") == name then
			return p
		end
		p = rawget(p, "_parent")
	end
	return nil
end
function I.FindFirstAncestorOfClass(o, cls)
	self(o, "FindFirstAncestorOfClass")
	local p = rawget(o, "_parent")
	while p do
		if rawget(p, "_c").name == cls then
			return p
		end
		p = rawget(p, "_parent")
	end
	return nil
end
function I.FindFirstAncestorWhichIsA(o, cls)
	self(o, "FindFirstAncestorWhichIsA")
	local p = rawget(o, "_parent")
	while p do
		if rawget(p, "_c").isa[cls] then
			return p
		end
		p = rawget(p, "_parent")
	end
	return nil
end
function I.IsDescendantOf(o, ancestor)
	self(o, "IsDescendantOf")
	if ancestor == nil then
		return false
	end
	if not isInstance(ancestor) then
		error("invalid argument #1 to 'IsDescendantOf' (Instance expected, got " .. typeof(ancestor) .. ")", 2)
	end
	return isDescendantOf(o, ancestor)
end
function I.IsAncestorOf(o, d)
	self(o, "IsAncestorOf")
	return d ~= nil and isDescendantOf(d, o)
end
function I.GetFullName(o)
	self(o, "GetFullName")
	return fullName(o)
end
function I.GetDebugId(o)
	return tostring(o)
end
function I.WaitForChild(o, name, timeout)
	self(o, "WaitForChild")
	name = checkStr("WaitForChild", 1, name)
	local found = I.FindFirstChild(o, name)
	if found then
		return found
	end
	if timeout ~= nil and type(timeout) ~= "number" then
		error("invalid argument #2 to 'WaitForChild' (number expected, got " .. typeof(timeout) .. ")", 2)
	end
	local co = coroutine.running()
	if not coroutine.isyieldable() then
		error("WaitForChild yielded outside a Roblox thread", 2)
	end
	local done = false
	local conn
	local function finish(value)
		if done then
			return
		end
		done = true
		conn:Disconnect()
		H.parked[co] = nil
		H.resume(co, value)
	end
	conn = getSignal(o, "ChildAdded"):Connect(function(child)
		if rawget(child, "_name") == name then
			finish(child)
		end
	end)
	local label = ("%s:WaitForChild(\"%s\")"):format(fullName(o), name)
	H.parked[co] = label
	if timeout then
		H.at(H.now + timeout, function()
			finish(nil)
		end)
	else
		H.at(H.now + 5, function()
			if not done then
				warn(("Infinite yield possible on '%s'"):format(label))
				H.infiniteYields = H.infiniteYields or {}
				table.insert(H.infiniteYields, { label = label, trace = debug.traceback(co) })
			end
		end)
	end
	return coroutine.yield()
end
function I.ClearAllChildren(o)
	self(o, "ClearAllChildren")
	for _, k in table.clone(rawget(o, "_kids")) do
		if not rawget(k, "_c").service then
			I.Destroy(k)
		end
	end
end
function I.Destroy(o)
	self(o, "Destroy")
	if rawget(o, "_c").service then
		error(("The Parent property of %s is locked"):format(rawget(o, "_name")), 2)
	end
	if rawget(o, "_locked") then
		return
	end
	fireEvent(o, "Destroying")
	setParent(o, nil)
	rawset(o, "_locked", true)
	for _, k in table.clone(rawget(o, "_kids")) do
		I.Destroy(k)
	end
	local sigs = rawget(o, "_sig")
	if sigs then
		for _, s in sigs do
			disconnectAll(s)
		end
	end
	for _, t in { rawget(o, "_psig"), rawget(o, "_asig") } do
		for _, s in t do
			disconnectAll(s)
		end
	end
	local tags = rawget(o, "_tags")
	if tags and H.removeAllTags then
		H.removeAllTags(o)
	end
	local c = rawget(o, "_c")
	if c.onDestroy then
		c.onDestroy(o)
	end
end
function I.Remove(o)
	setParent(o, nil)
end
function I.GetAttribute(o, name)
	self(o, "GetAttribute")
	checkStr("GetAttribute", 1, name)
	return rawget(o, "_attr")[name]
end
function I.GetAttributes(o)
	self(o, "GetAttributes")
	return table.clone(rawget(o, "_attr"))
end
function I.SetAttribute(o, name, value)
	self(o, "SetAttribute")
	if type(name) ~= "string" then
		error("invalid argument #1 to 'SetAttribute' (string expected, got " .. typeof(name) .. ")", 2)
	end
	if #name > 100 or not string.match(name, "^[%w_]+$") then
		error(("Attribute name '%s' is invalid: names may only use letters, digits and underscores, up to 100 characters"):format(name), 2)
	end
	if string.sub(name, 1, 3) == "RBX" then
		error(("Attribute name '%s' is reserved"):format(name), 2)
	end
	if value ~= nil and not ATTR_TYPES[typeof(value)] then
		error(("%s is not a supported attribute type"):format(typeof(value)), 2)
	end
	local attrs = rawget(o, "_attr")
	local old = attrs[name]
	attrs[name] = value
	if old ~= value then
		fireEvent(o, "AttributeChanged", name)
		local as = rawget(o, "_asig")
		if as and as[name] then
			fire(as[name])
		end
	end
end
function I.GetAttributeChangedSignal(o, name)
	self(o, "GetAttributeChangedSignal")
	checkStr("GetAttributeChangedSignal", 1, name)
	local as = rawget(o, "_asig")
	if not as then
		as = {}
		rawset(o, "_asig", as)
	end
	as[name] = as[name] or newSignal(rawget(o, "_name") .. " attribute " .. name)
	return as[name]
end
function I.GetPropertyChangedSignal(o, name)
	self(o, "GetPropertyChangedSignal")
	checkStr("GetPropertyChangedSignal", 1, name)
	local m = rawget(o, "_c").members[name]
	if not m or m.kind ~= PROP then
		error(("%s is not a valid property name."):format(name), 2)
	end
	local ps = rawget(o, "_psig")
	if not ps then
		ps = {}
		rawset(o, "_psig", ps)
	end
	ps[name] = ps[name] or newSignal(rawget(o, "_name") .. " property " .. name)
	return ps[name]
end
function I.AddTag(o, tag)
	return H.CollectionService:AddTag(o, tag)
end
function I.RemoveTag(o, tag)
	return H.CollectionService:RemoveTag(o, tag)
end
function I.HasTag(o, tag)
	return H.CollectionService:HasTag(o, tag)
end
function I.GetTags(o)
	return H.CollectionService:GetTags(o)
end
function I.GetActor()
	return nil
end
function I.IsPropertyModified(o, name)
	return rawget(o, "_p")[name] ~= nil
end
function I.ResetPropertyToDefault(o, name)
	rawget(o, "_p")[name] = nil
end
function I.GetStyled(o, name)
	return o[name]
end

-- Clone: deep copy (Archivable only), with references inside the copied tree pointing at the copies.
function I.Clone(o)
	self(o, "Clone")
	if rawget(o, "_p").Archivable == false then
		return nil
	end
	local map = {}
	local function copy(src)
		local c = rawget(src, "_c")
		local dst = setmetatable({ _c = c, _name = rawget(src, "_name"), _kids = {}, _p = table.clone(rawget(src, "_p")), _attr = table.clone(rawget(src, "_attr")) }, InstMT)
		H.createdTotal += 1
		H.created[c.name] = (H.created[c.name] or 0) + 1
		map[src] = dst
		if c.onClone then
			c.onClone(src, dst)
		end
		local tags = rawget(src, "_tags")
		if tags then
			for tag in tags do
				H.CollectionService:AddTag(dst, tag)
			end
		end
		for _, k in rawget(src, "_kids") do
			if rawget(k, "_p").Archivable ~= false then
				local kc = copy(k)
				rawset(kc, "_parent", dst)
				table.insert(rawget(dst, "_kids"), kc)
			end
		end
		return dst
	end
	local root = copy(o)
	for _, dst in map do
		local p = rawget(dst, "_p")
		for k, v in p do
			if isInstance(v) and map[v] then
				p[k] = map[v]
			end
		end
		local c = rawget(dst, "_c")
		if c.afterClone then
			c.afterClone(dst, map)
		end
	end
	return root
end

-- Base classes ------------------------------------------------------------------------------------------------------
class("Instance", nil, {
	abstract = true,
	props = {
		Name = { "string", "", get = function(o)
			return rawget(o, "_name")
		end, set = function(o, v)
			if rawget(o, "_name") ~= v then
				rawset(o, "_name", v)
				propChanged(o, "Name")
			end
		end },
		ClassName = { "string", "", "ro", get = function(o)
			return rawget(o, "_c").name
		end },
		Parent = { "Instance", nil, get = function(o)
			return rawget(o, "_parent")
		end, set = function(o, v)
			setParent(o, v)
		end },
		Archivable = { "bool", true },
		Capabilities = { "any", nil },
		Sandboxed = { "bool", false },
		UniqueId = { "string", "", "ro" },
	},
	methods = I,
	events = { "Changed", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "AttributeChanged", "Destroying" },
})

-- Helpers for derived property values on parts ---------------------------------------------------------------------
local function deg(x)
	return math.deg(x)
end
local function orientationOf(c)
	local x, y, z = c:ToEulerAnglesYXZ()
	return v3(deg(x), deg(y), deg(z))
end
local function rotationOf(c)
	local x, y, z = c:ToEulerAnglesXYZ()
	return v3(deg(x), deg(y), deg(z))
end
H.orientationOf = orientationOf

-- Joints and assemblies ---------------------------------------------------------------------------------------------
local RIGID = { Weld = true, Motor6D = true, WeldConstraint = true, ManualWeld = true, Snap = true, Glue = true, ManualGlue = true, Motor = true, Rotate = true, RotateP = true, RotateV = true }
local jointsOf = setmetatable({}, { __mode = "k" }) -- part -> { joint = true }
H.jointsOf = jointsOf
local function jointActive(j)
	local p = rawget(j, "_p")
	if p.Enabled == false then
		return false
	end
	local a, b = p.Part0, p.Part1
	return a ~= nil and b ~= nil and a ~= b and not rawget(j, "_locked") and inWorld(j) and inWorld(a) and inWorld(b)
end
-- Parts rigidly joined to part (its assembly), optionally not crossing `skip`.
local function assemblyOf(part, skip)
	local seen, list = { [part] = true }, { part }
	local i = 1
	while i <= #list do
		local p = list[i]
		i += 1
		local js = jointsOf[p]
		if js then
			for j in js do
				if j ~= skip and RIGID[rawget(j, "_c").name] and jointActive(j) then
					local jp = rawget(j, "_p")
					local other = jp.Part0 == p and jp.Part1 or jp.Part0
					if other and not seen[other] then
						seen[other] = true
						table.insert(list, other)
					end
				end
			end
		end
	end
	return list
end
H.assemblyOf = assemblyOf
local function anyAnchored(list)
	for _, p in list do
		if rawget(p, "_p").Anchored then
			return true
		end
	end
	return false
end
local function rootOf(list)
	-- anchored part, else the heaviest part (Roblox picks by RootPriority, then size)
	local best, bestScore = list[1], -math.huge
	for _, p in list do
		local pp = rawget(p, "_p")
		local s = pp.Size or v3(4, 1, 2)
		local score = (pp.Anchored and 1e12 or 0) + (pp.RootPriority or 0) * 1e9 + (pp.Massless and 0 or 1) * 1e8 + s.X * s.Y * s.Z
		if score > bestScore then
			best, bestScore = p, score
		end
	end
	return best
end
local function registerJoint(j, old0, old1)
	for _, p in { old0, old1 } do
		if p and jointsOf[p] then
			jointsOf[p][j] = nil
		end
	end
	local jp = rawget(j, "_p")
	for _, p in { jp.Part0, jp.Part1 } do
		if p then
			jointsOf[p] = jointsOf[p] or {}
			jointsOf[p][j] = true
		end
	end
end

local function partCF(p)
	return rawget(p, "_p").CFrame or IDENTITY
end
-- Moves a part (and, in the Workspace, everything rigidly joined to it) to cframe.
local function movePart(part, cframe, follow)
	local old = partCF(part)
	if follow ~= false and jointsOf[part] and inWorld(part) then
		local list = assemblyOf(part)
		if #list > 1 then
			local delta = cfMul(cframe, cfInverse(old))
			for _, p in list do
				if p ~= part then
					setRaw(p, "CFrame", cfMul(delta, partCF(p)))
					if H.onPartMoved then
						H.onPartMoved(p)
					end
				end
			end
		end
	end
	setRaw(part, "CFrame", cframe)
	if H.onPartMoved then
		H.onPartMoved(part)
	end
end
H.movePart = movePart

-- A Weld/Motor6D puts Part1 where Part0 * C0 = Part1 * C1 (moving the unanchored side).
local function snapWeld(j)
	local jp = rawget(j, "_p")
	local a, b = jp.Part0, jp.Part1
	if not a or not b or jp.Enabled == false then
		return
	end
	local c0, c1 = jp.C0 or IDENTITY, jp.C1 or IDENTITY
	if not rawget(b, "_p").Anchored then
		local target = cfMul(cfMul(partCF(a), c0), cfInverse(c1))
		local side = inWorld(b) and assemblyOf(b, j) or { b }
		local delta = cfMul(target, cfInverse(partCF(b)))
		for _, p in side do
			if p ~= a then
				setRaw(p, "CFrame", cfMul(delta, partCF(p)))
				if H.onPartMoved then
					H.onPartMoved(p)
				end
			end
		end
	elseif not rawget(a, "_p").Anchored then
		local target = cfMul(cfMul(partCF(b), c1), cfInverse(c0))
		movePart(a, target, false)
	end
end

local function partMass(p)
	local pp = rawget(p, "_p")
	local s = pp.Size or v3(4, 1, 2)
	local density
	if pp.CustomPhysicalProperties then
		density = pp.CustomPhysicalProperties.Density
	else
		local mat = pp.Material
		density = H.DENSITY[mat and mat.Name or "Plastic"] or 0.7
	end
	local shape = pp.Shape and pp.Shape.Name
	local vol = s.X * s.Y * s.Z
	if shape == "Ball" then
		local r = math.min(s.X, s.Y, s.Z) / 2
		vol = 4 / 3 * math.pi * r ^ 3
	elseif shape == "Cylinder" then
		local r = math.min(s.Y, s.Z) / 2
		vol = math.pi * r * r * s.X
	elseif shape == "Wedge" or rawget(p, "_c").name == "WedgePart" then
		vol /= 2
	end
	return vol * density
end

local function checkOwnership(part, fname)
	if not inWorld(part) then
		error("Can only call Network Ownership API on a part that is descendent of Workspace", 3)
	end
	if anyAnchored(assemblyOf(part)) then
		error("Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts", 3)
	end
end

local function cornersOf(c, s)
	local out = {}
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(out, c * v3(sx * hx, sy * hy, sz * hz))
			end
		end
	end
	return out
end
H.cornersOf = cornersOf

-- PVInstance / BasePart -----------------------------------------------------------------------------------------------
class("PVInstance", "Instance", {
	abstract = true,
	props = {
		Origin = { "CFrame", IDENTITY, get = function(o)
			return o:GetPivot()
		end, set = function(o, v)
			o:PivotTo(v)
		end },
		PivotOffset = { "CFrame", IDENTITY },
	},
	methods = {},
})

local BP = {}
function BP.GetMass(o)
	self(o, "GetMass")
	return partMass(o)
end
function BP.GetConnectedParts(o, recursive)
	self(o, "GetConnectedParts")
	return assemblyOf(o)
end
function BP.GetJoints(o)
	local out = {}
	for j in jointsOf[o] or {} do
		table.insert(out, j)
	end
	return out
end
function BP.GetRootPart(o)
	return rootOf(assemblyOf(o))
end
function BP.GetTouchingParts(o)
	return {}
end
function BP.IsGrounded(o)
	return anyAnchored(assemblyOf(o))
end
function BP.SetNetworkOwner(o, player)
	self(o, "SetNetworkOwner")
	if player ~= nil and not (isInstance(player) and rawget(player, "_c").name == "Player") then
		error("invalid argument #1 to 'SetNetworkOwner' (Player expected, got " .. typeof(player) .. ")", 2)
	end
	checkOwnership(o, "SetNetworkOwner")
	for _, p in assemblyOf(o) do
		rawset(p, "_owner", player or false)
	end
end
function BP.GetNetworkOwner(o)
	self(o, "GetNetworkOwner")
	checkOwnership(o, "GetNetworkOwner")
	local owner = rawget(o, "_owner")
	return owner or nil
end
function BP.SetNetworkOwnershipAuto(o)
	self(o, "SetNetworkOwnershipAuto")
	checkOwnership(o, "SetNetworkOwnershipAuto")
	for _, p in assemblyOf(o) do
		rawset(p, "_owner", nil)
	end
end
function BP.GetNetworkOwnershipAuto(o)
	checkOwnership(o, "GetNetworkOwnershipAuto")
	return rawget(o, "_owner") == nil
end
function BP.CanSetNetworkOwner(o)
	self(o, "CanSetNetworkOwner")
	if not inWorld(o) then
		return false, "Can only call Network Ownership API on a part that is descendent of Workspace"
	end
	if anyAnchored(assemblyOf(o)) then
		return false, "Cannot change network ownership of anchored part"
	end
	return true, nil
end
local function assemblyMass(o)
	local total = 0
	for _, p in assemblyOf(o) do
		if not rawget(p, "_p").Massless then
			total += partMass(p)
		end
	end
	return total > 0 and total or partMass(o)
end
function BP.ApplyImpulse(o, impulse)
	self(o, "ApplyImpulse")
	if typeof(impulse) ~= "Vector3" then
		error("invalid argument #1 to 'ApplyImpulse' (Vector3 expected, got " .. typeof(impulse) .. ")", 2)
	end
	if anyAnchored(assemblyOf(o)) then
		return
	end
	local v = o.AssemblyLinearVelocity + impulse / assemblyMass(o)
	for _, p in assemblyOf(o) do
		setRaw(p, "AssemblyLinearVelocity", v)
	end
end
function BP.ApplyImpulseAtPosition(o, impulse, pos)
	BP.ApplyImpulse(o, impulse)
end
function BP.ApplyAngularImpulse(o, impulse)
	self(o, "ApplyAngularImpulse")
	if typeof(impulse) ~= "Vector3" then
		error("invalid argument #1 to 'ApplyAngularImpulse' (Vector3 expected, got " .. typeof(impulse) .. ")", 2)
	end
end
function BP.GetVelocityAtPosition(o, pos)
	return o.AssemblyLinearVelocity
end
function BP.BreakJoints(o)
	for j in table.clone(jointsOf[o] or {}) do
		if RIGID[rawget(j, "_c").name] then
			j:Destroy()
		end
	end
end
function BP.Resize(o, normalId, delta)
	return true
end
function BP.GetClosestPointOnSurface(o, pos)
	local local_ = partCF(o):PointToObjectSpace(pos)
	local s = o.Size / 2
	local c = v3(math.clamp(local_.X, -s.X, s.X), math.clamp(local_.Y, -s.Y, s.Y), math.clamp(local_.Z, -s.Z, s.Z))
	return partCF(o) * c
end

local function partSize(o)
	return rawget(o, "_p").Size or rawget(o, "_c").members.Size.default
end
class("BasePart", "PVInstance", {
	abstract = true,
	props = {
		Anchored = { "bool", false, set = function(o, v)
			setRaw(o, "Anchored", v)
		end },
		CanCollide = { "bool", true },
		CanTouch = { "bool", true },
		CanQuery = { "bool", true },
		CastShadow = { "bool", true },
		Massless = { "bool", false },
		Locked = { "bool", false },
		Transparency = { "number", 0 },
		Reflectance = { "number", 0 },
		LocalTransparencyModifier = { "number", 0 },
		Color = { "Color3", Color3.fromRGB(163, 162, 165) },
		BrickColor = { "BrickColor", nil, get = function(o)
			return H.nearestBrick(o.Color)
		end, set = function(o, v)
			setRaw(o, "Color", v.Color)
			propChanged(o, "BrickColor")
		end },
		Material = { "Enum:Material", Enum.Material.Plastic },
		MaterialVariant = { "string", "" },
		Size = { "Vector3", v3(4, 1, 2), set = function(o, v)
			-- Roblox clamps every axis to at least 0.001 and at most 2048
			v = v3(math.clamp(v.X, 0.001, 2048), math.clamp(v.Y, 0.001, 2048), math.clamp(v.Z, 0.001, 2048))
			setRaw(o, "Size", v)
			if H.onPartMoved then
				H.onPartMoved(o)
			end
		end },
		CFrame = { "CFrame", IDENTITY, set = function(o, v)
			movePart(o, v)
		end },
		Position = { "Vector3", nil, get = function(o)
			local c = partCF(o)
			return v3(c[1], c[2], c[3])
		end, set = function(o, v)
			local c = partCF(o)
			movePart(o, cf(v.X, v.Y, v.Z, c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]))
			propChanged(o, "Position")
		end },
		Orientation = { "Vector3", nil, get = function(o)
			return orientationOf(partCF(o))
		end, set = function(o, v)
			local p = partCF(o).Position
			movePart(o, CFrame.new(p) * CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z)))
			propChanged(o, "Orientation")
		end },
		Rotation = { "Vector3", nil, get = function(o)
			return rotationOf(partCF(o))
		end, set = function(o, v)
			local p = partCF(o).Position
			movePart(o, CFrame.new(p) * CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z)))
		end },
		ExtentsCFrame = { "CFrame", nil, "ro", get = function(o)
			return partCF(o)
		end },
		ExtentsSize = { "Vector3", nil, "ro", get = function(o)
			return partSize(o)
		end },
		AssemblyLinearVelocity = { "Vector3", Vector3.zero },
		AssemblyAngularVelocity = { "Vector3", Vector3.zero },
		Velocity = { "Vector3", nil, get = function(o)
			return o.AssemblyLinearVelocity
		end, set = function(o, v)
			setRaw(o, "AssemblyLinearVelocity", v)
		end },
		RotVelocity = { "Vector3", nil, get = function(o)
			return o.AssemblyAngularVelocity
		end, set = function(o, v)
			setRaw(o, "AssemblyAngularVelocity", v)
		end },
		AssemblyMass = { "number", nil, "ro", get = assemblyMass },
		Mass = { "number", nil, "ro", get = partMass },
		AssemblyRootPart = { "Instance", nil, "ro", get = function(o)
			return rootOf(assemblyOf(o))
		end },
		AssemblyCenterOfMass = { "Vector3", nil, "ro", get = function(o)
			return partCF(rootOf(assemblyOf(o))).Position
		end },
		CenterOfMass = { "Vector3", nil, "ro", get = function(o)
			return Vector3.zero
		end },
		CustomPhysicalProperties = { "PhysicalProperties?", nil },
		CurrentPhysicalProperties = { "PhysicalProperties", nil, "ro", get = function(o)
			return o.CustomPhysicalProperties or PhysicalProperties.new(o.Material)
		end },
		CollisionGroup = { "string", "Default" },
		CollisionGroupId = { "int", 0 },
		RootPriority = { "int", 0 },
		TopSurface = { "Enum:SurfaceType", Enum.SurfaceType.Smooth },
		BottomSurface = { "Enum:SurfaceType", Enum.SurfaceType.Smooth },
		FrontSurface = { "Enum:SurfaceType", Enum.SurfaceType.Smooth },
		BackSurface = { "Enum:SurfaceType", Enum.SurfaceType.Smooth },
		LeftSurface = { "Enum:SurfaceType", Enum.SurfaceType.Smooth },
		RightSurface = { "Enum:SurfaceType", Enum.SurfaceType.Smooth },
		EnableFluidForces = { "bool", true },
		AudioCanCollide = { "bool", true },
		ResizeIncrement = { "int", 1, "ro" },
		ResizeableFaces = { "any", nil, "ro" },
	},
	methods = BP,
	events = { "Touched", "TouchEnded" },
	onClone = function(src, dst)
		-- joints are re-registered by the joint's own clone
	end,
})
class("Part", "BasePart", { props = { Shape = { "Enum:PartType", Enum.PartType.Block } } })
class("SpawnLocation", "Part", { props = { Neutral = { "bool", true }, Duration = { "number", 10 }, Enabled = { "bool", true }, AllowTeamChangeOnTouch = { "bool", false }, TeamColor = { "BrickColor", nil } } })
class("WedgePart", "BasePart")
class("CornerWedgePart", "BasePart")
class("TrussPart", "BasePart", { props = { Style = { "Enum:Style", nil } } })
class("FormFactorPart", "BasePart", { abstract = true })
class("TriangleMeshPart", "BasePart", { abstract = true, props = { CollisionFidelity = { "Enum:CollisionFidelity", Enum.CollisionFidelity.Default } } })
class("MeshPart", "TriangleMeshPart", {
	props = {
		MeshId = { "string", "", "noscript" },
		TextureID = { "string", "" },
		DoubleSided = { "bool", false },
		RenderFidelity = { "Enum:RenderFidelity", Enum.RenderFidelity.Automatic },
		MeshSize = { "Vector3", v3(1, 1, 1), "ro" },
		HasJointOffset = { "bool", false, "ro" },
		HasSkinnedMesh = { "bool", false, "ro" },
		JointOffset = { "Vector3", Vector3.zero, "ro" },
	},
})
class("PartOperation", "TriangleMeshPart", { props = { UsePartColor = { "bool", false }, RenderFidelity = { "Enum:RenderFidelity", Enum.RenderFidelity.Automatic }, SmoothingAngle = { "number", 0 } } })
class("UnionOperation", "PartOperation")
class("NegateOperation", "PartOperation")
class("IntersectOperation", "PartOperation")
local function seatSit(o, humanoid)
	self(o, "Sit")
	if not isInstance(humanoid) or not rawget(humanoid, "_c").isa.Humanoid then
		error("invalid argument #1 to 'Sit' (Humanoid expected, got " .. typeof(humanoid) .. ")", 2)
	end
	if o.Disabled or o.Occupant then
		return
	end
	local root = humanoid.RootPart
	setRaw(o, "Occupant", humanoid)
	setRaw(humanoid, "SeatPart", o)
	setRaw(humanoid, "Sit", true)
	if root then
		local weld = H.rawNew("Weld")
		rawset(weld, "_name", "SeatWeld")
		weld.Part0 = o
		weld.Part1 = root
		weld.C0 = CFrame.new(0, o.Size.Y / 2 + 1.5, 0)
		weld.Parent = o
	end
	fireEvent(humanoid, "Seated", true, o)
end
class("Seat", "Part", {
	props = { Disabled = { "bool", false }, Occupant = { "Instance:Humanoid", nil, "ro" } },
	methods = { Sit = seatSit },
})
class("VehicleSeat", "BasePart", {
	props = {
		Disabled = { "bool", false },
		Occupant = { "Instance:Humanoid", nil, "ro" },
		Throttle = { "int", 0 },
		Steer = { "int", 0 },
		ThrottleFloat = { "number", 0 },
		SteerFloat = { "number", 0 },
		MaxSpeed = { "number", 25 },
		Torque = { "number", 10 },
		TurnSpeed = { "number", 1 },
		HeadsUpDisplay = { "bool", true },
		AreHingesDetected = { "int", 0, "ro" },
	},
	methods = { Sit = seatSit },
})
class("Terrain", "BasePart", {
	notCreatable = true,
	props = {
		WaterColor = { "Color3", Color3.fromRGB(12, 84, 92) },
		WaterReflectance = { "number", 1 },
		WaterTransparency = { "number", 0.3 },
		WaterWaveSize = { "number", 0.15 },
		WaterWaveSpeed = { "number", 10 },
		Decoration = { "bool", false },
		GrassLength = { "number", 0.7 },
		MaxExtents = { "any", nil, "ro" },
	},
	methods = {}, -- filled in by mock_services.luau
})

-- Model -------------------------------------------------------------------------------------------------------------
local function modelParts(o)
	local out = {}
	local function rec(x)
		for _, k in rawget(x, "_kids") do
			if rawget(k, "_c").isa.BasePart then
				table.insert(out, k)
			end
			rec(k)
		end
	end
	rec(o)
	return out
end
H.modelParts = modelParts
local function modelPivot(o)
	local pp = rawget(o, "_p").PrimaryPart
	if pp and isDescendantOf(pp, o) then
		return cfMul(partCF(pp), pp.PivotOffset)
	end
	local wp = rawget(o, "_p").WorldPivot
	if wp then
		return wp
	end
	-- uninitialised pivot: centre of the bounding box (Roblox sets it when the first part is added)
	local parts = modelParts(o)
	if #parts == 0 then
		return IDENTITY
	end
	local minV, maxV
	for _, p in parts do
		for _, c in cornersOf(partCF(p), partSize(p)) do
			minV = minV and minV:Min(c) or c
			maxV = maxV and maxV:Max(c) or c
		end
	end
	return CFrame.new((minV + maxV) / 2)
end
local M = {}
function M.GetPivot(o)
	self(o, "GetPivot")
	if rawget(o, "_c").isa.BasePart then
		return cfMul(partCF(o), o.PivotOffset)
	end
	return modelPivot(o)
end
function M.PivotTo(o, target)
	self(o, "PivotTo")
	if typeof(target) ~= "CFrame" then
		error("invalid argument #1 to 'PivotTo' (CFrame expected, got " .. typeof(target) .. ")", 2)
	end
	if rawget(o, "_c").isa.BasePart then
		movePart(o, cfMul(target, cfInverse(o.PivotOffset)))
		return
	end
	local from = modelPivot(o)
	local delta = cfMul(target, cfInverse(from))
	for _, p in modelParts(o) do
		setRaw(p, "CFrame", cfMul(delta, partCF(p)))
		if H.onPartMoved then
			H.onPartMoved(p)
		end
	end
	local pp = rawget(o, "_p").PrimaryPart
	if not (pp and isDescendantOf(pp, o)) then
		rawget(o, "_p").WorldPivot = target
	end
end
class("PVInstance", "Instance") -- re-declared below with methods
CLASSES.PVInstance.methods = { GetPivot = M.GetPivot, PivotTo = M.PivotTo }
CLASSES.PVInstance.props = {
	Origin = { "CFrame", IDENTITY, get = function(o)
		return o:GetPivot()
	end, set = function(o, v)
		o:PivotTo(v)
	end },
	PivotOffset = { "CFrame", IDENTITY },
}
CLASSES.PVInstance.abstract = true
local function bounds(o, orientation)
	local parts = modelParts(o)
	if #parts == 0 then
		return orientation, Vector3.zero
	end
	local inv = cfInverse(orientation)
	local minV, maxV
	for _, p in parts do
		for _, c in cornersOf(partCF(p), partSize(p)) do
			local l = inv * c
			minV = minV and minV:Min(l) or l
			maxV = maxV and maxV:Max(l) or l
		end
	end
	return orientation * CFrame.new((minV + maxV) / 2), maxV - minV
end
function M.GetBoundingBox(o)
	self(o, "GetBoundingBox")
	return bounds(o, modelPivot(o).Rotation)
end
function M.GetExtentsSize(o)
	self(o, "GetExtentsSize")
	local pp = rawget(o, "_p").PrimaryPart
	local _, size = bounds(o, pp and partCF(pp).Rotation or IDENTITY)
	return size
end
function M.GetScale(o)
	return rawget(o, "_scale") or 1
end
function M.ScaleTo(o, scale)
	self(o, "ScaleTo")
	if type(scale) ~= "number" or scale <= 0 then
		error("ScaleTo: scale must be a positive number", 2)
	end
	local factor = scale / (rawget(o, "_scale") or 1)
	local pivot = modelPivot(o)
	for _, p in modelParts(o) do
		local rel = cfInverse(pivot) * partCF(p)
		local pos = rel.Position * factor
		setRaw(p, "Size", partSize(p) * factor)
		setRaw(p, "CFrame", pivot * (CFrame.new(pos) * rel.Rotation))
		if H.onPartMoved then
			H.onPartMoved(p)
		end
	end
	rawset(o, "_scale", scale)
end
function M.MoveTo(o, pos)
	self(o, "MoveTo")
	local pivot = modelPivot(o)
	M.PivotTo(o, CFrame.new(pos) * pivot.Rotation)
end
function M.TranslateBy(o, delta)
	M.PivotTo(o, modelPivot(o) + delta)
end
function M.SetPrimaryPartCFrame(o, c)
	local pp = rawget(o, "_p").PrimaryPart
	if not pp then
		error("Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set, or the PrimaryPart no longer exists. Please set Model.PrimaryPart before using this.", 2)
	end
	M.PivotTo(o, cfMul(c, pp.PivotOffset))
end
function M.GetPrimaryPartCFrame(o)
	local pp = rawget(o, "_p").PrimaryPart
	if not pp then
		error("Model:GetPrimaryPartCFrame() failed because no PrimaryPart has been set", 2)
	end
	return partCF(pp)
end
function M.GetModelCFrame(o)
	return (bounds(o, IDENTITY))
end
function M.AddPersistentPlayer() end
function M.RemovePersistentPlayer() end
class("Model", "PVInstance", {
	props = {
		PrimaryPart = { "Instance:BasePart", nil },
		WorldPivot = { "CFrame", nil, get = modelPivot, set = function(o, v)
			rawget(o, "_p").WorldPivot = v
		end },
		ModelStreamingMode = { "Enum:ModelStreamingMode", Enum.ModelStreamingMode.Default },
		LevelOfDetail = { "Enum:ModelLevelOfDetail", nil },
		Scale = { "number", 1, get = function(o)
			return rawget(o, "_scale") or 1
		end, set = function(o, v)
			M.ScaleTo(o, v)
		end },
	},
	methods = { GetBoundingBox = M.GetBoundingBox, GetExtentsSize = M.GetExtentsSize, GetScale = M.GetScale, ScaleTo = M.ScaleTo, MoveTo = M.MoveTo, TranslateBy = M.TranslateBy, SetPrimaryPartCFrame = M.SetPrimaryPartCFrame, GetPrimaryPartCFrame = M.GetPrimaryPartCFrame, GetModelCFrame = M.GetModelCFrame, AddPersistentPlayer = M.AddPersistentPlayer, RemovePersistentPlayer = M.RemovePersistentPlayer },
})
class("WorldRoot", "Model", { abstract = true })
class("Actor", "Model")

-- Tools -------------------------------------------------------------------------------------------------------------
class("BackpackItem", "Model", { abstract = true, props = { TextureId = { "string", "" } } })
class("Tool", "BackpackItem", {
	props = {
		CanBeDropped = { "bool", true },
		Enabled = { "bool", true },
		ManualActivationOnly = { "bool", false },
		RequiresHandle = { "bool", true },
		ToolTip = { "string", "" },
		Grip = { "CFrame", IDENTITY },
		GripPos = { "Vector3", Vector3.zero },
		GripForward = { "Vector3", v3(0, 0, -1) },
		GripRight = { "Vector3", v3(1, 0, 0) },
		GripUp = { "Vector3", v3(0, 1, 0) },
	},
	methods = { Activate = function() end, Deactivate = function() end },
	events = { "Activated", "Deactivated", "Equipped", "Unequipped" },
})
class("HopperBin", "BackpackItem")
class("Backpack", "Instance")
class("StarterGear", "Instance")
class("PlayerGui", "Instance", { props = { ScreenOrientation = { "any", nil }, SelectionImageObject = { "Instance", nil } } })
class("PlayerScripts", "Instance")

-- Joints and constraints ---------------------------------------------------------------------------------------------
local function jointPart(name)
	return { "Instance:BasePart", nil, set = function(o, v)
		local jp = rawget(o, "_p")
		local old0, old1 = jp.Part0, jp.Part1
		setRaw(o, name, v)
		registerJoint(o, old0, old1)
		local c = rawget(o, "_c")
		if c.isa.JointInstance then
			snapWeld(o)
		end
	end }
end
class("JointInstance", "Instance", {
	abstract = true,
	props = {
		Part0 = jointPart("Part0"),
		Part1 = jointPart("Part1"),
		C0 = { "CFrame", IDENTITY, set = function(o, v)
			setRaw(o, "C0", v)
			snapWeld(o)
		end },
		C1 = { "CFrame", IDENTITY, set = function(o, v)
			setRaw(o, "C1", v)
			snapWeld(o)
		end },
		Enabled = { "bool", true },
		Active = { "bool", false, "ro", get = function(o)
			return jointActive(o)
		end },
	},
	afterClone = function(dst)
		registerJoint(dst)
	end,
	onDestroy = function(o)
		registerJoint(o, rawget(o, "_p").Part0, rawget(o, "_p").Part1)
		local jp = rawget(o, "_p")
		for _, p in { jp.Part0, jp.Part1 } do
			if p and jointsOf[p] then
				jointsOf[p][o] = nil
			end
		end
	end,
})
class("Weld", "JointInstance")
class("ManualWeld", "JointInstance")
class("Snap", "JointInstance")
class("Glue", "JointInstance")
class("Motor", "JointInstance", { props = { CurrentAngle = { "number", 0 }, DesiredAngle = { "number", 0 }, MaxVelocity = { "number", 0 } } })
class("Motor6D", "Motor", { props = { Transform = { "CFrame", IDENTITY } } })
class("WeldConstraint", "Instance", {
	props = {
		Part0 = jointPart("Part0"),
		Part1 = jointPart("Part1"),
		Enabled = { "bool", true },
		Active = { "bool", false, "ro", get = function(o)
			return jointActive(o)
		end },
	},
	afterClone = function(dst)
		registerJoint(dst)
	end,
	onDestroy = CLASSES.JointInstance.onDestroy,
})
class("NoCollisionConstraint", "Instance", { props = { Part0 = { "Instance:BasePart", nil }, Part1 = { "Instance:BasePart", nil }, Enabled = { "bool", true } } })

class("Constraint", "Instance", {
	abstract = true,
	props = {
		Attachment0 = { "Instance:Attachment", nil },
		Attachment1 = { "Instance:Attachment", nil },
		Enabled = { "bool", true },
		Visible = { "bool", false },
		Color = { "BrickColor", nil, get = function()
			return BrickColor.new("Bright blue")
		end, set = function() end },
		Active = { "bool", false, "ro", get = function(o)
			return o.Enabled and o.Attachment0 ~= nil
		end },
	},
})
local INF = math.huge
class("AlignPosition", "Constraint", { props = {
	Mode = { "Enum:PositionAlignmentMode", Enum.PositionAlignmentMode.TwoAttachment },
	Position = { "Vector3", Vector3.zero },
	MaxForce = { "number", 10000 },
	MaxAxesForce = { "Vector3", v3(10000, 10000, 10000) },
	MaxVelocity = { "number", INF },
	Responsiveness = { "number", 10 },
	RigidityEnabled = { "bool", false },
	ReactionForceEnabled = { "bool", false },
	ApplyAtCenterOfMass = { "bool", false },
	ForceLimitMode = { "Enum:ForceLimitMode", Enum.ForceLimitMode.Magnitude },
	ForceRelativeTo = { "Enum:ActuatorRelativeTo", Enum.ActuatorRelativeTo.World },
} })
class("AlignOrientation", "Constraint", { props = {
	Mode = { "Enum:OrientationAlignmentMode", Enum.OrientationAlignmentMode.TwoAttachment },
	CFrame = { "CFrame", IDENTITY },
	PrimaryAxis = { "Vector3", v3(1, 0, 0) },
	SecondaryAxis = { "Vector3", v3(0, 1, 0) },
	LookAtPosition = { "Vector3", Vector3.zero },
	MaxTorque = { "number", 10000 },
	MaxAngularVelocity = { "number", INF },
	Responsiveness = { "number", 10 },
	RigidityEnabled = { "bool", false },
	ReactionTorqueEnabled = { "bool", false },
	PrimaryAxisOnly = { "bool", false },
	AlignType = { "Enum:AlignType", Enum.AlignType.Parallel },
} })
class("LinearVelocity", "Constraint", { props = {
	VelocityConstraintMode = { "Enum:VelocityConstraintMode", Enum.VelocityConstraintMode.Vector },
	VectorVelocity = { "Vector3", Vector3.zero },
	PlaneVelocity = { "Vector2", Vector2.zero },
	LineVelocity = { "number", 0 },
	LineDirection = { "Vector3", v3(1, 0, 0) },
	PrimaryTangentAxis = { "Vector3", v3(1, 0, 0) },
	SecondaryTangentAxis = { "Vector3", v3(0, 1, 0) },
	MaxForce = { "number", 1000 },
	MaxAxesForce = { "Vector3", v3(1000, 1000, 1000) },
	MaxPlanarAxesForce = { "Vector2", v2 and v2(1000, 1000) or Vector2.new(1000, 1000) },
	ForceLimitMode = { "Enum:ForceLimitMode", Enum.ForceLimitMode.Magnitude },
	ForceLimitsEnabled = { "bool", true },
	RelativeTo = { "Enum:ActuatorRelativeTo", Enum.ActuatorRelativeTo.World },
} })
class("AngularVelocity", "Constraint", { props = {
	AngularVelocity = { "Vector3", Vector3.zero },
	MaxTorque = { "number", 0 },
	ReactionTorqueEnabled = { "bool", false },
	RelativeTo = { "Enum:ActuatorRelativeTo", Enum.ActuatorRelativeTo.World },
} })
class("VectorForce", "Constraint", { props = { Force = { "Vector3", Vector3.zero }, ApplyAtCenterOfMass = { "bool", false }, RelativeTo = { "Enum:ActuatorRelativeTo", Enum.ActuatorRelativeTo.Attachment0 } } })
class("Torque", "Constraint", { props = { Torque = { "Vector3", Vector3.zero }, RelativeTo = { "Enum:ActuatorRelativeTo", Enum.ActuatorRelativeTo.Attachment0 } } })
class("LineForce", "Constraint", { props = { Magnitude = { "number", 1 }, ApplyAtCenterOfMass = { "bool", false }, InverseSquareLaw = { "bool", false }, MaxForce = { "number", INF }, ReactionForceEnabled = { "bool", false } } })
class("HingeConstraint", "Constraint", { props = {
	ActuatorType = { "Enum:ActuatorType", Enum.ActuatorType.None },
	AngularSpeed = { "number", 0 },
	AngularVelocity = { "number", 0 },
	AngularResponsiveness = { "number", 45 },
	MotorMaxTorque = { "number", 0 },
	MotorMaxAcceleration = { "number", INF },
	ServoMaxTorque = { "number", 0 },
	TargetAngle = { "number", 0 },
	LimitsEnabled = { "bool", false },
	LowerAngle = { "number", -45 },
	UpperAngle = { "number", 45 },
	Restitution = { "number", 0 },
	CurrentAngle = { "number", 0, "ro" },
	Radius = { "number", 0.15 },
} })
class("BallSocketConstraint", "Constraint", { props = {
	LimitsEnabled = { "bool", false },
	UpperAngle = { "number", 45 },
	TwistLimitsEnabled = { "bool", false },
	TwistLowerAngle = { "number", -45 },
	TwistUpperAngle = { "number", 45 },
	Restitution = { "number", 0 },
	MaxFrictionTorque = { "number", 0 },
	Radius = { "number", 0.15 },
} })
class("RopeConstraint", "Constraint", { props = { Length = { "number", 5 }, Restitution = { "number", 0 }, Thickness = { "number", 0.1 }, WinchEnabled = { "bool", false }, WinchTarget = { "number", 5 }, WinchSpeed = { "number", 2 }, WinchForce = { "number", 10000 }, WinchResponsiveness = { "number", 45 }, CurrentDistance = { "number", 0, "ro" } } })
class("RodConstraint", "Constraint", { props = { Length = { "number", 5 }, Thickness = { "number", 0.1 }, LimitsEnabled = { "bool", false } } })
class("SpringConstraint", "Constraint", { props = { Stiffness = { "number", 0 }, Damping = { "number", 0 }, FreeLength = { "number", 1 }, LimitsEnabled = { "bool", false }, MaxLength = { "number", 5 }, MinLength = { "number", 0 }, MaxForce = { "number", INF }, Coils = { "number", 3 }, Radius = { "number", 0.4 }, Thickness = { "number", 0.1 }, CurrentLength = { "number", 0, "ro" } } })
class("PrismaticConstraint", "Constraint", { props = { ActuatorType = { "Enum:ActuatorType", Enum.ActuatorType.None }, Speed = { "number", 0 }, Velocity = { "number", 0 }, TargetPosition = { "number", 0 }, ServoMaxForce = { "number", 0 }, MotorMaxForce = { "number", 0 }, LimitsEnabled = { "bool", false }, LowerLimit = { "number", 0 }, UpperLimit = { "number", 5 }, CurrentPosition = { "number", 0, "ro" } } })
class("CylindricalConstraint", "PrismaticConstraint")
class("PlaneConstraint", "Constraint")
class("RigidConstraint", "Constraint")

-- Attachment --------------------------------------------------------------------------------------------------------
local function attParentCF(o)
	local p = rawget(o, "_parent")
	if p and rawget(p, "_c").isa.BasePart then
		return partCF(p)
	end
	return IDENTITY
end
class("Attachment", "Instance", {
	props = {
		CFrame = { "CFrame", IDENTITY },
		Position = { "Vector3", nil, get = function(o)
			return o.CFrame.Position
		end, set = function(o, v)
			setRaw(o, "CFrame", CFrame.new(v) * o.CFrame.Rotation)
		end },
		Orientation = { "Vector3", nil, get = function(o)
			return orientationOf(o.CFrame)
		end, set = function(o, v)
			setRaw(o, "CFrame", CFrame.new(o.CFrame.Position) * CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z)))
		end },
		Axis = { "Vector3", nil, get = function(o)
			return o.CFrame.RightVector
		end, set = function() end },
		SecondaryAxis = { "Vector3", nil, get = function(o)
			return o.CFrame.UpVector
		end, set = function() end },
		WorldCFrame = { "CFrame", nil, get = function(o)
			return attParentCF(o) * o.CFrame
		end, set = function(o, v)
			setRaw(o, "CFrame", cfInverse(attParentCF(o)) * v)
		end },
		WorldPosition = { "Vector3", nil, get = function(o)
			return (attParentCF(o) * o.CFrame).Position
		end, set = function(o, v)
			local world = CFrame.new(v) * (attParentCF(o) * o.CFrame).Rotation
			setRaw(o, "CFrame", cfInverse(attParentCF(o)) * world)
		end },
		WorldOrientation = { "Vector3", nil, get = function(o)
			return orientationOf(attParentCF(o) * o.CFrame)
		end, set = function() end },
		WorldAxis = { "Vector3", nil, get = function(o)
			return (attParentCF(o) * o.CFrame).RightVector
		end, set = function() end },
		Visible = { "bool", false },
	},
})
class("Bone", "Attachment", { props = { Transform = { "CFrame", IDENTITY } } })

-- Values ------------------------------------------------------------------------------------------------------------
local function valueClass(name, typ, default)
	class(name, "ValueBase", { props = { Value = { typ, default, set = function(o, v)
		local old = rawget(o, "_p").Value
		if old == nil then
			old = default
		end
		rawget(o, "_p").Value = v
		if old ~= v then
			fireEvent(o, "Changed", v)
			local ps = rawget(o, "_psig")
			if ps and ps.Value then
				fire(ps.Value)
			end
		end
	end } } })
end
class("ValueBase", "Instance", { abstract = true })
valueClass("IntValue", "int", 0)
valueClass("NumberValue", "number", 0)
valueClass("StringValue", "string", "")
valueClass("BoolValue", "bool", false)
valueClass("ObjectValue", "Instance", nil)
valueClass("CFrameValue", "CFrame", IDENTITY)
valueClass("Vector3Value", "Vector3", Vector3.zero)
valueClass("Color3Value", "Color3", c3(0, 0, 0))
valueClass("BrickColorValue", "BrickColor", nil)
valueClass("RayValue", "Ray", nil)
class("Folder", "Instance")
class("Configuration", "Instance")

-- Scripts -----------------------------------------------------------------------------------------------------------
class("LuaSourceContainer", "Instance", { abstract = true, props = { Source = { "string", "", "noscript" } } })
class("BaseScript", "LuaSourceContainer", { abstract = true, props = { Disabled = { "bool", false, get = function(o)
	return rawget(o, "_p").Enabled == false
end, set = function(o, v)
	setRaw(o, "Enabled", not v)
end }, Enabled = { "bool", true }, RunContext = { "Enum:RunContext", nil }, LinkedSource = { "string", "" } } })
class("Script", "BaseScript")
class("LocalScript", "Script")
class("ModuleScript", "LuaSourceContainer")

-- Remote and bindable events -----------------------------------------------------------------------------------------
-- What survives a trip through a remote, a bindable or a DataStore: Roblox serialises the arguments.
local function serialize(v, where, seen)
	local t = typeof(v)
	if t == "table" then
		seen = seen or {}
		if seen[v] then
			error(where .. ": tables cannot be cyclic", 0)
		end
		seen[v] = true
		local out = {}
		local n = #v
		local hasNum, hasStr = false, false
		for k, x in v do
			if type(k) == "number" then
				hasNum = true
			elseif type(k) == "string" then
				hasStr = true
			else
				-- Instance or other keys: dropped by remotes
				hasStr = true
			end
			out[k] = serialize(x, where, seen)
		end
		if hasNum and hasStr then
			H.mixedTableWarn(where)
		end
		seen[v] = nil
		return out
	elseif t == "function" then
		return nil
	end
	return v
end
H.serialize = serialize
function H.mixedTableWarn(where)
	warn(("[headless] %s got a table mixing number and string keys; Roblox drops or rejects such tables (\"Cannot convert mixed or non-array tables\")"):format(where))
end
local function isPlayer(v)
	return isInstance(v) and rawget(v, "_c").name == "Player"
end
H.isPlayer = isPlayer
local function packArgs(where, ...)
	local n = select("#", ...)
	local out = table.create(n)
	for i = 1, n do
		out[i] = serialize((select(i, ...)), where)
	end
	return out, n
end
H.clientLog = {} -- { { remote, player, args } } of FireClient/FireAllClients for the summary
class("RemoteEvent", "Instance", {
	methods = {
		FireClient = function(o, player, ...)
			self(o, "FireClient")
			if not isPlayer(player) then
				error("FireClient: player argument must be a Player object", 2)
			end
			packArgs(fullName(o) .. ":FireClient", ...)
			H.remoteCalls = (H.remoteCalls or 0) + 1
		end,
		FireAllClients = function(o, ...)
			self(o, "FireAllClients")
			packArgs(fullName(o) .. ":FireAllClients", ...)
			H.remoteCalls = (H.remoteCalls or 0) + 1
		end,
		FireServer = function(o)
			error("FireServer can only be called from the client", 2)
		end,
	},
	events = { "OnServerEvent", "OnClientEvent" },
})
class("UnreliableRemoteEvent", "RemoteEvent")
class("RemoteFunction", "Instance", {
	methods = {
		InvokeClient = function(o, player, ...)
			if not isPlayer(player) then
				error("InvokeClient: player argument must be a Player object", 2)
			end
			note("RemoteFunction:InvokeClient is answered with nil (no client)")
			return nil
		end,
		InvokeServer = function()
			error("InvokeServer can only be called from the client", 2)
		end,
	},
	callbacks = { "OnServerInvoke", "OnClientInvoke" },
})
class("BindableEvent", "Instance", {
	methods = {
		Fire = function(o, ...)
			self(o, "Fire")
			local args, n = packArgs(fullName(o) .. ":Fire", ...)
			fireEvent(o, "Event", table.unpack(args, 1, n))
		end,
	},
	events = { "Event" },
})
class("BindableFunction", "Instance", {
	methods = {
		Invoke = function(o, ...)
			self(o, "Invoke")
			local cb = rawget(o, "_cb") and rawget(o, "_cb").OnInvoke
			if not cb then
				error("BindableFunction:Invoke has no OnInvoke callback", 2)
			end
			local args, n = packArgs(fullName(o) .. ":Invoke", ...)
			return cb(table.unpack(args, 1, n))
		end,
	},
	callbacks = { "OnInvoke" },
})
-- Calls a RemoteFunction's server callback as a client would (used by the scenario).
function H.invokeServer(remote, player, ...)
	local cb = rawget(remote, "_cb") and rawget(remote, "_cb").OnServerInvoke
	if not cb then
		error("no OnServerInvoke set on " .. fullName(remote))
	end
	local args, n = packArgs(fullName(remote) .. ":InvokeServer", ...)
	return cb(player, table.unpack(args, 1, n))
end
function H.fireServer(remote, player, ...)
	local args, n = packArgs(fullName(remote) .. ":FireServer", ...)
	fireEvent(remote, "OnServerEvent", player, table.unpack(args, 1, n))
end

-- Interaction -------------------------------------------------------------------------------------------------------
class("ProximityPrompt", "Instance", {
	props = {
		ActionText = { "string", "Interact" },
		ObjectText = { "string", "" },
		HoldDuration = { "number", 0 },
		MaxActivationDistance = { "number", 10 },
		MaxIndicatorDistance = { "number", 0 },
		RequiresLineOfSight = { "bool", true },
		KeyboardKeyCode = { "Enum:KeyCode", Enum.KeyCode.E },
		GamepadKeyCode = { "Enum:KeyCode", Enum.KeyCode.ButtonX },
		ClickablePrompt = { "bool", true },
		Enabled = { "bool", true },
		Exclusivity = { "Enum:ProximityPromptExclusivity", Enum.ProximityPromptExclusivity.OnePerButton },
		Style = { "Enum:ProximityPromptStyle", Enum.ProximityPromptStyle.Default },
		UIOffset = { "Vector2", Vector2.zero },
		AutoLocalize = { "bool", true },
		RootLocalizationTable = { "Instance", nil },
	},
	methods = { InputHoldBegin = function() end, InputHoldEnd = function() end },
	events = { "Triggered", "TriggerEnded", "PromptButtonHoldBegan", "PromptButtonHoldEnded", "PromptShown", "PromptHidden" },
})
class("ClickDetector", "Instance", {
	props = { MaxActivationDistance = { "number", 32 }, CursorIcon = { "string", "" } },
	events = { "MouseClick", "RightMouseClick", "MouseHoverEnter", "MouseHoverLeave", "MouseActionStarted" },
})
class("DragDetector", "ClickDetector")

-- Effects -----------------------------------------------------------------------------------------------------------
class("Light", "Instance", { abstract = true, props = { Brightness = { "number", 1 }, Color = { "Color3", c3(1, 1, 1) }, Enabled = { "bool", true }, Shadows = { "bool", false } } })
class("PointLight", "Light", { props = { Range = { "number", 8 } } })
class("SpotLight", "Light", { props = { Range = { "number", 16 }, Angle = { "number", 90 }, Face = { "Enum:NormalId", Enum.NormalId.Front } } })
class("SurfaceLight", "Light", { props = { Range = { "number", 16 }, Angle = { "number", 90 }, Face = { "Enum:NormalId", Enum.NormalId.Front } } })
class("ParticleEmitter", "Instance", {
	props = {
		Rate = { "number", 5 },
		Lifetime = { "NumberRange", NumberRange.new(5, 10) },
		Speed = { "NumberRange", NumberRange.new(5) },
		SpreadAngle = { "Vector2", Vector2.zero },
		Color = { "ColorSequence", ColorSequence.new(c3(1, 1, 1)) },
		Size = { "NumberSequence", NumberSequence.new(1) },
		Transparency = { "NumberSequence", NumberSequence.new(0) },
		Squash = { "NumberSequence", NumberSequence.new(0) },
		Texture = { "string", "rbxasset://textures/particles/sparkles_main.dds" },
		Enabled = { "bool", true },
		LightEmission = { "number", 0 },
		LightInfluence = { "number", 0 },
		Brightness = { "number", 1 },
		Acceleration = { "Vector3", Vector3.zero },
		Drag = { "number", 0 },
		EmissionDirection = { "Enum:NormalId", Enum.NormalId.Top },
		Rotation = { "NumberRange", NumberRange.new(0) },
		RotSpeed = { "NumberRange", NumberRange.new(0) },
		ZOffset = { "number", 0 },
		LockedToPart = { "bool", false },
		VelocityInheritance = { "number", 0 },
		TimeScale = { "number", 1 },
		Orientation = { "Enum:ParticleOrientation", Enum.ParticleOrientation.FacingCamera },
		Shape = { "Enum:ParticleEmitterShape", Enum.ParticleEmitterShape.Box },
		ShapeInOut = { "Enum:ParticleEmitterShapeInOut", nil },
		ShapeStyle = { "Enum:ParticleEmitterShapeStyle", nil },
		ShapePartial = { "number", 1 },
		FlipbookLayout = { "Enum:ParticleFlipbookLayout", nil },
		FlipbookMode = { "Enum:ParticleFlipbookMode", nil },
		WindAffectsDrag = { "bool", false },
	},
	methods = {
		Emit = function(o, n)
			self(o, "Emit")
			if n ~= nil and type(n) ~= "number" then
				error("invalid argument #1 to 'Emit' (number expected, got " .. typeof(n) .. ")", 2)
			end
		end,
		Clear = function() end,
	},
})
class("Sparkles", "Instance", { props = { SparkleColor = { "Color3", Color3.fromRGB(144, 25, 255) }, Enabled = { "bool", true }, TimeScale = { "number", 1 } } })
class("Fire", "Instance", { props = { Color = { "Color3", Color3.fromRGB(236, 139, 70) }, SecondaryColor = { "Color3", Color3.fromRGB(139, 80, 55) }, Enabled = { "bool", true }, Heat = { "number", 9 }, Size = { "number", 5 }, TimeScale = { "number", 1 } } })
class("Smoke", "Instance", { props = { Color = { "Color3", c3(1, 1, 1) }, Enabled = { "bool", true }, Opacity = { "number", 0.5 }, RiseVelocity = { "number", 1 }, Size = { "number", 1 }, TimeScale = { "number", 1 } } })
class("Trail", "Instance", { props = { Attachment0 = { "Instance:Attachment", nil }, Attachment1 = { "Instance:Attachment", nil }, Color = { "ColorSequence", ColorSequence.new(c3(1, 1, 1)) }, Transparency = { "NumberSequence", NumberSequence.new(0.5) }, Lifetime = { "number", 2 }, Enabled = { "bool", true }, FaceCamera = { "bool", false }, LightEmission = { "number", 0 }, WidthScale = { "NumberSequence", NumberSequence.new(1) }, Texture = { "string", "" }, MinLength = { "number", 0.1 }, MaxLength = { "number", 0 } }, methods = { Clear = function() end } })
class("Beam", "Instance", { props = { Attachment0 = { "Instance:Attachment", nil }, Attachment1 = { "Instance:Attachment", nil }, Color = { "ColorSequence", ColorSequence.new(c3(1, 1, 1)) }, Transparency = { "NumberSequence", NumberSequence.new(0.5) }, Enabled = { "bool", true }, FaceCamera = { "bool", false }, LightEmission = { "number", 0 }, LightInfluence = { "number", 0 }, Width0 = { "number", 1 }, Width1 = { "number", 1 }, CurveSize0 = { "number", 0 }, CurveSize1 = { "number", 0 }, Segments = { "int", 10 }, Texture = { "string", "" }, TextureLength = { "number", 1 }, TextureSpeed = { "number", 1 }, ZOffset = { "number", 0 } } })
class("Highlight", "Instance", { props = {
	Adornee = { "Instance", nil },
	DepthMode = { "Enum:HighlightDepthMode", Enum.HighlightDepthMode.AlwaysOnTop },
	Enabled = { "bool", true },
	FillColor = { "Color3", c3(1, 0, 0) },
	FillTransparency = { "number", 0.5 },
	OutlineColor = { "Color3", c3(1, 1, 1) },
	OutlineTransparency = { "number", 0 },
} })
class("SelectionBox", "Instance", { props = { Adornee = { "Instance", nil }, Color3 = { "Color3", c3(0, 0, 1) }, LineThickness = { "number", 0.15 }, Transparency = { "number", 0 }, SurfaceColor3 = { "Color3", c3(0, 0, 1) }, SurfaceTransparency = { "number", 1 }, Visible = { "bool", true } } })
class("Decal", "Instance", { props = { Texture = { "string", "" }, Color3 = { "Color3", c3(1, 1, 1) }, Transparency = { "number", 0 }, Face = { "Enum:NormalId", Enum.NormalId.Front }, ZIndex = { "int", 1 } } })
class("Texture", "Decal", { props = { StudsPerTileU = { "number", 2 }, StudsPerTileV = { "number", 2 }, OffsetStudsU = { "number", 0 }, OffsetStudsV = { "number", 0 } } })
class("DataModelMesh", "Instance", { abstract = true, props = { Scale = { "Vector3", v3(1, 1, 1) }, Offset = { "Vector3", Vector3.zero }, VertexColor = { "Vector3", v3(1, 1, 1) } } })
class("SpecialMesh", "DataModelMesh", { props = { MeshType = { "Enum:MeshType", Enum.MeshType.Head }, MeshId = { "string", "" }, TextureId = { "string", "" } } })
class("BlockMesh", "DataModelMesh")
class("CylinderMesh", "DataModelMesh")
class("SurfaceAppearance", "Instance", { props = { ColorMap = { "string", "", "noscript" }, Color = { "Color3", c3(1, 1, 1) } } })
class("Sound", "Instance", {
	props = {
		SoundId = { "string", "" },
		Volume = { "number", 0.5 },
		PlaybackSpeed = { "number", 1 },
		Pitch = { "number", 1 },
		Looped = { "bool", false },
		Playing = { "bool", false },
		PlayOnRemove = { "bool", false },
		TimePosition = { "number", 0 },
		TimeLength = { "number", 0, "ro" },
		IsPlaying = { "bool", false, "ro", get = function(o)
			return rawget(o, "_p").Playing == true
		end },
		IsLoaded = { "bool", true, "ro" },
		IsPaused = { "bool", true, "ro", get = function(o)
			return rawget(o, "_p").Playing ~= true
		end },
		RollOffMaxDistance = { "number", 10000 },
		RollOffMinDistance = { "number", 10 },
		RollOffMode = { "Enum:RollOffMode", Enum.RollOffMode.Inverse },
		SoundGroup = { "Instance:SoundGroup", nil },
		PlaybackRegionsEnabled = { "bool", false },
	},
	methods = {
		Play = function(o)
			self(o, "Play")
			setRaw(o, "Playing", true)
			fireEvent(o, "Played", o.SoundId)
		end,
		Stop = function(o)
			self(o, "Stop")
			setRaw(o, "Playing", false)
			rawget(o, "_p").TimePosition = 0
			fireEvent(o, "Stopped", o.SoundId)
		end,
		Pause = function(o)
			setRaw(o, "Playing", false)
		end,
		Resume = function(o)
			setRaw(o, "Playing", true)
		end,
	},
	events = { "Played", "Paused", "Resumed", "Stopped", "Ended", "Loaded", "DidLoop" },
})
class("SoundGroup", "Instance", { props = { Volume = { "number", 0.5 } } })
class("SoundEffect", "Instance", { abstract = true, props = { Enabled = { "bool", true }, Priority = { "int", 0 } } })
class("ReverbSoundEffect", "SoundEffect")
class("EqualizerSoundEffect", "SoundEffect")

-- Post-effects and sky (Lighting children)
class("PostEffect", "Instance", { abstract = true, props = { Enabled = { "bool", true } } })
class("BloomEffect", "PostEffect", { props = { Intensity = { "number", 1 }, Size = { "number", 24 }, Threshold = { "number", 2 } } })
class("BlurEffect", "PostEffect", { props = { Size = { "number", 24 } } })
class("ColorCorrectionEffect", "PostEffect", { props = { Brightness = { "number", 0 }, Contrast = { "number", 0 }, Saturation = { "number", 0 }, TintColor = { "Color3", c3(1, 1, 1) } } })
class("SunRaysEffect", "PostEffect", { props = { Intensity = { "number", 0.25 }, Spread = { "number", 1 } } })
class("DepthOfFieldEffect", "PostEffect", { props = { FarIntensity = { "number", 0.75 }, FocusDistance = { "number", 0.05 }, InFocusRadius = { "number", 10 }, NearIntensity = { "number", 0.75 } } })
class("Atmosphere", "Instance", { props = { Density = { "number", 0.395 }, Offset = { "number", 0 }, Color = { "Color3", Color3.fromRGB(199, 170, 107) }, Decay = { "Color3", Color3.fromRGB(92, 60, 13) }, Glare = { "number", 0 }, Haze = { "number", 0 } } })
class("Sky", "Instance", { props = { SkyboxBk = { "string", "" }, SkyboxDn = { "string", "" }, SkyboxFt = { "string", "" }, SkyboxLf = { "string", "" }, SkyboxRt = { "string", "" }, SkyboxUp = { "string", "" }, SunTextureId = { "string", "" }, MoonTextureId = { "string", "" }, CelestialBodiesShown = { "bool", true }, StarCount = { "int", 3000 }, SunAngularSize = { "number", 21 }, MoonAngularSize = { "number", 11 } } })
class("Clouds", "Instance", { props = { Cover = { "number", 0.5 }, Density = { "number", 0.7 }, Color = { "Color3", c3(1, 1, 1) }, Enabled = { "bool", true } } })

-- GUI ---------------------------------------------------------------------------------------------------------------
class("GuiBase", "Instance", { abstract = true })
class("GuiBase2d", "GuiBase", { abstract = true, props = {
	AbsolutePosition = { "Vector2", Vector2.zero, "ro" },
	AbsoluteSize = { "Vector2", Vector2.zero, "ro" },
	AbsoluteRotation = { "number", 0, "ro" },
	AutoLocalize = { "bool", true },
	ClipsDescendants = { "bool", false },
} })
class("LayerCollector", "GuiBase2d", { abstract = true, props = { Enabled = { "bool", true }, ResetOnSpawn = { "bool", true }, ZIndexBehavior = { "Enum:ZIndexBehavior", Enum.ZIndexBehavior.Sibling } } })
class("ScreenGui", "LayerCollector", { props = { DisplayOrder = { "int", 0 }, IgnoreGuiInset = { "bool", false }, ScreenInsets = { "Enum:ScreenInsets", nil } } })
class("BillboardGui", "LayerCollector", { props = {
	Adornee = { "Instance", nil },
	AlwaysOnTop = { "bool", false },
	Size = { "UDim2", UDim2.new() },
	SizeOffset = { "Vector2", Vector2.zero },
	StudsOffset = { "Vector3", Vector3.zero },
	StudsOffsetWorldSpace = { "Vector3", Vector3.zero },
	ExtentsOffset = { "Vector3", Vector3.zero },
	ExtentsOffsetWorldSpace = { "Vector3", Vector3.zero },
	MaxDistance = { "number", math.huge },
	DistanceLowerLimit = { "number", 0 },
	DistanceUpperLimit = { "number", -1 },
	DistanceStep = { "number", 0 },
	LightInfluence = { "number", 1 },
	Brightness = { "number", 1 },
	PlayerToHideFrom = { "Instance", nil },
	Active = { "bool", false },
} })
class("SurfaceGuiBase", "LayerCollector", { abstract = true, props = { Adornee = { "Instance", nil }, Face = { "Enum:NormalId", Enum.NormalId.Front }, Active = { "bool", true } } })
class("SurfaceGui", "SurfaceGuiBase", { props = {
	SizingMode = { "Enum:SurfaceGuiSizingMode", Enum.SurfaceGuiSizingMode.FixedSize },
	PixelsPerStud = { "number", 50 },
	CanvasSize = { "Vector2", Vector2.new(800, 600) },
	LightInfluence = { "number", 1 },
	Brightness = { "number", 1 },
	AlwaysOnTop = { "bool", false },
	ZOffset = { "number", 0 },
	MaxDistance = { "number", 1000 },
	ToolPunchThroughDistance = { "number", 0 },
} })
class("GuiObject", "GuiBase2d", { abstract = true, props = {
	Size = { "UDim2", UDim2.new() },
	Position = { "UDim2", UDim2.new() },
	AnchorPoint = { "Vector2", Vector2.zero },
	BackgroundColor3 = { "Color3", Color3.fromRGB(163, 162, 165) },
	BackgroundTransparency = { "number", 0 },
	BorderColor3 = { "Color3", Color3.fromRGB(27, 42, 53) },
	BorderSizePixel = { "int", 1 },
	BorderMode = { "Enum:BorderMode", nil },
	Visible = { "bool", true },
	ZIndex = { "int", 1 },
	LayoutOrder = { "int", 0 },
	Rotation = { "number", 0 },
	AutomaticSize = { "Enum:AutomaticSize", Enum.AutomaticSize.None },
	SizeConstraint = { "Enum:SizeConstraint", Enum.SizeConstraint.RelativeXY },
	Active = { "bool", false },
	Selectable = { "bool", false },
	Interactable = { "bool", true },
} }, nil)
local textProps = {
	Text = { "string", "Label" },
	TextColor3 = { "Color3", Color3.fromRGB(27, 42, 53) },
	TextSize = { "number", 14 },
	Font = { "Enum:Font", Enum.Font.Legacy },
	FontFace = { "Font", nil },
	TextScaled = { "bool", false },
	TextWrapped = { "bool", false },
	TextXAlignment = { "Enum:TextXAlignment", Enum.TextXAlignment.Center },
	TextYAlignment = { "Enum:TextYAlignment", Enum.TextYAlignment.Center },
	TextStrokeColor3 = { "Color3", c3(0, 0, 0) },
	TextStrokeTransparency = { "number", 1 },
	TextTransparency = { "number", 0 },
	TextTruncate = { "Enum:TextTruncate", Enum.TextTruncate.None },
	RichText = { "bool", false },
	LineHeight = { "number", 1 },
	MaxVisibleGraphemes = { "int", -1 },
	TextBounds = { "Vector2", Vector2.zero, "ro" },
	TextFits = { "bool", true, "ro" },
	ContentText = { "string", "", "ro", get = function(o)
		return o.Text
	end },
	TextDirection = { "Enum:TextDirection", nil },
	OpenTypeFeatures = { "string", "" },
}
class("TextLabel", "GuiObject", { props = textProps })
class("TextButton", "GuiObject", { props = textProps, events = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseEnter", "MouseLeave" } })
class("TextBox", "GuiObject", { props = textProps, events = { "FocusLost", "Focused" } })
local imageProps = {
	Image = { "string", "" },
	ImageColor3 = { "Color3", c3(1, 1, 1) },
	ImageTransparency = { "number", 0 },
	ScaleType = { "Enum:ScaleType", Enum.ScaleType.Stretch },
	ImageRectOffset = { "Vector2", Vector2.zero },
	ImageRectSize = { "Vector2", Vector2.zero },
	SliceCenter = { "Rect", Rect.new(0, 0, 0, 0) },
	SliceScale = { "number", 1 },
	TileSize = { "UDim2", UDim2.fromScale(1, 1) },
	ResampleMode = { "Enum:ResamplerMode", nil },
}
class("ImageLabel", "GuiObject", { props = imageProps })
class("ImageButton", "GuiObject", { props = imageProps, events = { "Activated", "MouseButton1Click" } })
class("Frame", "GuiObject", { props = { Style = { "Enum:FrameStyle", nil } } })
class("ScrollingFrame", "GuiObject", { props = { CanvasSize = { "UDim2", UDim2.new(0, 0, 2, 0) }, CanvasPosition = { "Vector2", Vector2.zero }, ScrollBarThickness = { "int", 12 }, ScrollingDirection = { "Enum:ScrollingDirection", nil }, AutomaticCanvasSize = { "Enum:AutomaticSize", Enum.AutomaticSize.None }, ScrollingEnabled = { "bool", true } } })
class("ViewportFrame", "GuiObject", { props = { CurrentCamera = { "Instance", nil } } })
class("UIComponent", "Instance", { abstract = true })
class("UIConstraint", "UIComponent", { abstract = true })
class("UITextSizeConstraint", "UIConstraint", { props = { MaxTextSize = { "int", 100 }, MinTextSize = { "int", 1 } } })
class("UISizeConstraint", "UIConstraint", { props = { MaxSize = { "Vector2", Vector2.new(math.huge, math.huge) }, MinSize = { "Vector2", Vector2.zero } } })
class("UIAspectRatioConstraint", "UIConstraint", { props = { AspectRatio = { "number", 1 } } })
class("UIPadding", "UIComponent", { props = { PaddingBottom = { "UDim", UDim.new() }, PaddingLeft = { "UDim", UDim.new() }, PaddingRight = { "UDim", UDim.new() }, PaddingTop = { "UDim", UDim.new() } } })
class("UICorner", "UIComponent", { props = { CornerRadius = { "UDim", UDim.new(0, 8) } } })
class("UIStroke", "UIComponent", { props = { Color = { "Color3", c3(0, 0, 0) }, Thickness = { "number", 1 }, Transparency = { "number", 0 }, Enabled = { "bool", true }, ApplyStrokeMode = { "Enum:ApplyStrokeMode", Enum.ApplyStrokeMode.Contextual }, LineJoinMode = { "Enum:LineJoinMode", Enum.LineJoinMode.Round } } })
class("UIScale", "UIComponent", { props = { Scale = { "number", 1 } } })
class("UIGradient", "UIComponent", { props = { Color = { "ColorSequence", ColorSequence.new(c3(1, 1, 1)) }, Transparency = { "NumberSequence", NumberSequence.new(0) }, Rotation = { "number", 0 }, Offset = { "Vector2", Vector2.zero }, Enabled = { "bool", true } } })
class("UIGridStyleLayout", "UIComponent", { abstract = true, props = { FillDirection = { "Enum:FillDirection", Enum.FillDirection.Vertical }, SortOrder = { "Enum:SortOrder", Enum.SortOrder.LayoutOrder }, HorizontalAlignment = { "Enum:HorizontalAlignment", Enum.HorizontalAlignment.Left }, VerticalAlignment = { "Enum:VerticalAlignment", Enum.VerticalAlignment.Top }, AbsoluteContentSize = { "Vector2", Vector2.zero, "ro" } } })
class("UIListLayout", "UIGridStyleLayout", { props = { Padding = { "UDim", UDim.new() }, Wraps = { "bool", false } } })
class("UIGridLayout", "UIGridStyleLayout", { props = { CellPadding = { "UDim2", UDim2.fromOffset(5, 5) }, CellSize = { "UDim2", UDim2.fromOffset(100, 100) }, FillDirectionMaxCells = { "int", 0 } } })

-- Humanoids and characters ------------------------------------------------------------------------------------------
local HUM = {}
function HUM.TakeDamage(o, amount)
	self(o, "TakeDamage")
	if type(amount) ~= "number" then
		error("invalid argument #1 to 'TakeDamage' (number expected, got " .. typeof(amount) .. ")", 2)
	end
	o.Health = o.Health - amount
end
function HUM.MoveTo(o, pos, part)
	self(o, "MoveTo")
	rawget(o, "_p").WalkToPoint = pos
	H.at(H.now + 0.5, function()
		fireEvent(o, "MoveToFinished", true)
	end)
end
function HUM.Move(o, dir) end
function HUM.EquipTool(o, tool)
	self(o, "EquipTool")
	if not isInstance(tool) or not rawget(tool, "_c").isa.Tool then
		error("invalid argument #1 to 'EquipTool' (Tool expected, got " .. typeof(tool) .. ")", 2)
	end
	local character = rawget(o, "_parent")
	if not character then
		return
	end
	HUM.UnequipTools(o)
	tool.Parent = character
	local hand = I.FindFirstChild(character, "RightHand") or I.FindFirstChild(character, "Right Arm")
	local handle = I.FindFirstChild(tool, "Handle")
	if hand and handle and rawget(handle, "_c").isa.BasePart then
		local grip = H.rawNew("Weld")
		rawset(grip, "_name", "RightGrip")
		grip.C0 = CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
		grip.C1 = tool.Grip
		grip.Part0 = hand
		grip.Part1 = handle
		grip.Parent = hand
		rawset(tool, "_grip", grip)
	end
	fireEvent(tool, "Equipped")
end
function HUM.UnequipTools(o)
	self(o, "UnequipTools")
	local character = rawget(o, "_parent")
	if not character then
		return
	end
	local player = H.playerFromCharacter and H.playerFromCharacter(character)
	local backpack = player and I.FindFirstChild(player, "Backpack")
	for _, k in table.clone(rawget(character, "_kids")) do
		if rawget(k, "_c").isa.Tool then
			local grip = rawget(k, "_grip")
			if grip then
				grip:Destroy()
				rawset(k, "_grip", nil)
			end
			k.Parent = backpack
			fireEvent(k, "Unequipped")
		end
	end
end
function HUM.GetState(o)
	return rawget(o, "_state") or Enum.HumanoidStateType.Running
end
function HUM.ChangeState(o, s)
	rawset(o, "_state", s)
	fireEvent(o, "StateChanged", HUM.GetState(o), s)
end
function HUM.SetStateEnabled() end
function HUM.GetStateEnabled()
	return true
end
function HUM.ApplyDescription(o, desc)
	self(o, "ApplyDescription")
	if not isInstance(desc) or rawget(desc, "_c").name ~= "HumanoidDescription" then
		error("ApplyDescription: argument must be a HumanoidDescription", 2)
	end
	rawset(o, "_desc", desc)
end
HUM.ApplyDescriptionReset = HUM.ApplyDescription
function HUM.GetAppliedDescription(o)
	return rawget(o, "_desc") or H.rawNew("HumanoidDescription")
end
function HUM.LoadAnimation(o, anim)
	return H.animTrack(anim)
end
function HUM.GetPlayingAnimationTracks()
	return {}
end
function HUM.RemoveAccessories(o)
	local character = rawget(o, "_parent")
	for _, k in table.clone(character and rawget(character, "_kids") or {}) do
		if rawget(k, "_c").isa.Accessory then
			k:Destroy()
		end
	end
end
function HUM.AddAccessory(o, acc)
	acc.Parent = rawget(o, "_parent")
end
function HUM.GetAccessories(o)
	local out = {}
	local character = rawget(o, "_parent")
	for _, k in character and rawget(character, "_kids") or {} do
		if rawget(k, "_c").isa.Accessory then
			table.insert(out, k)
		end
	end
	return out
end
function HUM.BuildRigFromAttachments() end
function HUM.GetLimb()
	return Enum.Limb.Unknown
end
function HUM.GetMoveVelocity()
	return Vector3.zero
end
class("Humanoid", "Instance", {
	props = {
		Health = { "number", 100, set = function(o, v)
			local old = o.Health
			v = math.clamp(v, 0, o.MaxHealth)
			setRaw(o, "Health", v)
			if v ~= old then
				fireEvent(o, "HealthChanged", v)
			end
			if v <= 0 and old > 0 then
				rawset(o, "_state", Enum.HumanoidStateType.Dead)
				fireEvent(o, "Died")
			end
		end },
		MaxHealth = { "number", 100 },
		WalkSpeed = { "number", 16 },
		JumpPower = { "number", 50 },
		JumpHeight = { "number", 7.2 },
		UseJumpPower = { "bool", false },
		HipHeight = { "number", 2 },
		Jump = { "bool", false },
		Sit = { "bool", false, set = function(o, v)
			setRaw(o, "Sit", v)
			if not v then
				local seat = rawget(o, "_p").SeatPart
				if seat then
					for _, k in table.clone(rawget(seat, "_kids")) do
						if rawget(k, "_name") == "SeatWeld" then
							k:Destroy()
						end
					end
					setRaw(seat, "Occupant", nil)
					setRaw(o, "SeatPart", nil)
					fireEvent(o, "Seated", false, seat)
				end
			end
		end },
		SeatPart = { "Instance:BasePart", nil, "ro" },
		PlatformStand = { "bool", false },
		AutoRotate = { "bool", true },
		AutoJumpEnabled = { "bool", true },
		DisplayName = { "string", "" },
		DisplayDistanceType = { "Enum:DisplayDistanceType", Enum.DisplayDistanceType.Viewer },
		HealthDisplayType = { "Enum:HumanoidHealthDisplayType", Enum.HumanoidHealthDisplayType.DisplayWhenDamaged },
		HealthDisplayDistance = { "number", 100 },
		NameDisplayDistance = { "number", 100 },
		NameOcclusion = { "Enum:NameOcclusion", nil },
		RigType = { "Enum:HumanoidRigType", Enum.HumanoidRigType.R15 },
		RootPart = { "Instance:BasePart", nil, "ro", get = function(o)
			local character = rawget(o, "_parent")
			return character and I.FindFirstChild(character, "HumanoidRootPart") or nil
		end },
		MoveDirection = { "Vector3", Vector3.zero, "ro" },
		WalkToPoint = { "Vector3", Vector3.zero },
		WalkToPart = { "Instance:BasePart", nil },
		TargetPoint = { "Vector3", Vector3.zero },
		FloorMaterial = { "Enum:Material", Enum.Material.Air, "ro" },
		BreakJointsOnDeath = { "bool", true },
		RequiresNeck = { "bool", true },
		EvaluateStateMachine = { "bool", true },
		AutomaticScalingEnabled = { "bool", true },
		MaxSlopeAngle = { "number", 89 },
		CameraOffset = { "Vector3", Vector3.zero },
	},
	methods = HUM,
	events = { "Died", "Running", "Jumping", "Climbing", "FreeFalling", "Seated", "StateChanged", "HealthChanged", "MoveToFinished", "Touched", "AnimationPlayed", "GettingUp", "FallingDown", "Swimming", "PlatformStanding", "Ragdoll", "StateEnabledChanged" },
})
class("HumanoidDescription", "Instance", { props = {
	HeadColor = { "Color3", c3(1, 1, 1) }, TorsoColor = { "Color3", c3(1, 1, 1) }, LeftArmColor = { "Color3", c3(1, 1, 1) }, RightArmColor = { "Color3", c3(1, 1, 1) }, LeftLegColor = { "Color3", c3(1, 1, 1) }, RightLegColor = { "Color3", c3(1, 1, 1) },
	Shirt = { "int", 0 }, Pants = { "int", 0 }, GraphicTShirt = { "int", 0 }, Face = { "int", 0 }, Head = { "int", 0 }, Torso = { "int", 0 }, LeftArm = { "int", 0 }, RightArm = { "int", 0 }, LeftLeg = { "int", 0 }, RightLeg = { "int", 0 },
	HatAccessory = { "string", "" }, HairAccessory = { "string", "" }, FaceAccessory = { "string", "" }, NeckAccessory = { "string", "" }, ShouldersAccessory = { "string", "" }, FrontAccessory = { "string", "" }, BackAccessory = { "string", "" }, WaistAccessory = { "string", "" },
	BodyTypeScale = { "number", 0.3 }, DepthScale = { "number", 1 }, HeadScale = { "number", 1 }, HeightScale = { "number", 1 }, ProportionScale = { "number", 1 }, WidthScale = { "number", 1 },
} })
class("Animator", "Instance", { methods = { LoadAnimation = function(o, a)
	return H.animTrack(a)
end, GetPlayingAnimationTracks = function()
	return {}
end } })
class("Animation", "Instance", { props = { AnimationId = { "string", "" } } })
class("AnimationTrack", "Instance", {
	props = { IsPlaying = { "bool", false, "ro" }, Length = { "number", 1, "ro" }, Looped = { "bool", false }, Priority = { "Enum:AnimationPriority", nil }, Speed = { "number", 1, "ro" }, TimePosition = { "number", 0 }, WeightCurrent = { "number", 1, "ro" }, WeightTarget = { "number", 1, "ro" }, Animation = { "Instance", nil, "ro" } },
	methods = {
		Play = function(o)
			setRaw(o, "IsPlaying", true)
		end,
		Stop = function(o)
			setRaw(o, "IsPlaying", false)
			fireEvent(o, "Stopped")
		end,
		AdjustSpeed = function() end,
		AdjustWeight = function() end,
		GetMarkerReachedSignal = function(o, name)
			return getSignal(o, "Marker_" .. tostring(name))
		end,
	},
	events = { "Stopped", "Ended", "DidLoop", "KeyframeReached" },
})
function H.animTrack(anim)
	local t = H.rawNew("AnimationTrack")
	rawget(t, "_p").Animation = anim
	return t
end
class("Accessory", "Instance", { props = { AttachmentPoint = { "CFrame", IDENTITY }, AccessoryType = { "Enum:AccessoryType", nil } } })
class("Accoutrement", "Accessory")
class("Hat", "Accessory")
class("Clothing", "Instance", { abstract = true, props = { Color3 = { "Color3", c3(1, 1, 1) } } })
class("Shirt", "Clothing", { props = { ShirtTemplate = { "string", "" } } })
class("Pants", "Clothing", { props = { PantsTemplate = { "string", "" } } })
class("ShirtGraphic", "Instance", { props = { Graphic = { "string", "" }, Color3 = { "Color3", c3(1, 1, 1) } } })
class("BodyColors", "Instance", { props = {
	HeadColor3 = { "Color3", c3(1, 1, 1) }, TorsoColor3 = { "Color3", c3(1, 1, 1) }, LeftArmColor3 = { "Color3", c3(1, 1, 1) }, RightArmColor3 = { "Color3", c3(1, 1, 1) }, LeftLegColor3 = { "Color3", c3(1, 1, 1) }, RightLegColor3 = { "Color3", c3(1, 1, 1) },
} })
class("ForceField", "Instance", { props = { Visible = { "bool", true } } })
class("Camera", "Instance", { props = { CFrame = { "CFrame", IDENTITY }, Focus = { "CFrame", IDENTITY }, FieldOfView = { "number", 70 }, CameraType = { "Enum:CameraType", Enum.CameraType.Custom }, CameraSubject = { "Instance", nil }, ViewportSize = { "Vector2", Vector2.new(1920, 1080), "ro" } } })
class("Team", "Instance", { props = { TeamColor = { "BrickColor", nil }, AutoAssignable = { "bool", true } }, methods = { GetPlayers = function()
	return {}
end }, events = { "PlayerAdded", "PlayerRemoved" } })
class("LocalizationTable", "Instance")
class("Dialog", "Instance")
