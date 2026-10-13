-- A small fake of the Roblox API, enough to run the world map's build code in the luau CLI and count what it makes.
MODULES = {}
local cache = {}

-- Vector2 ---------------------------------------------------------------------------------------------------------
local V2 = {}
local function v2(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2) end
V2.__add = function(a, b) return v2(a.X + b.X, a.Y + b.Y) end
V2.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
V2.__unm = function(a) return v2(-a.X, -a.Y) end
V2.__mul = function(a, b)
	if type(a) == "number" then return v2(a * b.X, a * b.Y) elseif type(b) == "number" then return v2(a.X * b, a.Y * b) end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b) return v2(a.X / b, a.Y / b) end
V2.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
local V2m = {}
function V2m.Lerp(a, b, t) return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t) end
function V2m.Dot(a, b) return a.X * b.X + a.Y * b.Y end
V2.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y) return v2(t.X / m, t.Y / m) end
	return V2m[k]
end
Vector2 = { new = v2, zero = v2(0, 0), one = v2(1, 1) }

-- Vector3 ---------------------------------------------------------------------------------------------------------
local V3 = {}
local function v3(x, y, z)
	assert(type(x or 0) == "number" and type(y or 0) == "number" and type(z or 0) == "number", "Vector3.new needs numbers")
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
V3.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.X, a * b.Y, a * b.Z) elseif type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__tostring = function(a) return ("%g, %g, %g"):format(a.X, a.Y, a.Z) end
local V3m = {}
function V3m.Lerp(a, b, t) return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
function V3m.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3m.Cross(a, b) return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
V3.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X ^ 2 + t.Y ^ 2 + t.Z ^ 2) end
	if k == "Unit" then
		local m = math.sqrt(t.X ^ 2 + t.Y ^ 2 + t.Z ^ 2)
		assert(m > 0, "Unit of a zero vector")
		return v3(t.X / m, t.Y / m, t.Z / m)
	end
	return V3m[k]
end
Vector3 = { new = v3, zero = v3(), one = v3(1, 1, 1), xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1) }

-- CFrame: position p, columns r (right), u (up), b (back) ---------------------------------------------------------
local CF = {}
local function cf(p, r, u, b) return setmetatable({ p = p, r = r, u = u, b = b }, CF) end
local function rotate(c, v) return c.r * v.X + c.u * v.Y + c.b * v.Z end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then
		return cf(a.p + rotate(a, b.p), rotate(a, b.r), rotate(a, b.u), rotate(a, b.b))
	end
	assert(getmetatable(b) == V3, "CFrame * needs a CFrame or Vector3")
	return a.p + rotate(a, b)
end
CF.__add = function(a, v) return cf(a.p + v, a.r, a.u, a.b) end
CF.__sub = function(a, v) return cf(a.p - v, a.r, a.u, a.b) end
local CFm = {}
function CFm.Inverse(c)
	local r, u, b = c.r, c.u, c.b
	local nr, nu, nb = v3(r.X, u.X, b.X), v3(r.Y, u.Y, b.Y), v3(r.Z, u.Z, b.Z)
	local inv = cf(v3(), nr, nu, nb)
	return cf(-rotate(inv, c.p), nr, nu, nb)
end
function CFm.PointToObjectSpace(c, v) return CFm.Inverse(c) * v end
function CFm.PointToWorldSpace(c, v) return c * v end
function CFm.VectorToWorldSpace(c, v) return rotate(c, v) end
function CFm.ToObjectSpace(a, b) return CFm.Inverse(a) * b end
function CFm.Lerp(a, b, t) return cf(a.p:Lerp(b.p, t), a.r, a.u, a.b) end
function CFm.GetComponents(c) return c.p.X, c.p.Y, c.p.Z, c.r.X, c.u.X, c.b.X, c.r.Y, c.u.Y, c.b.Y, c.r.Z, c.u.Z, c.b.Z end
CF.__index = function(c, k)
	if k == "Position" then return c.p end
	if k == "X" then return c.p.X end
	if k == "Y" then return c.p.Y end
	if k == "Z" then return c.p.Z end
	if k == "LookVector" then return -c.b end
	if k == "RightVector" then return c.r end
	if k == "UpVector" then return c.u end
	if k == "Rotation" then return cf(v3(), c.r, c.u, c.b) end
	return CFm[k]
end
local I = cf(v3(), v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1))
local function rx(a) return cf(v3(), v3(1, 0, 0), v3(0, math.cos(a), math.sin(a)), v3(0, -math.sin(a), math.cos(a))) end
local function ry(a) return cf(v3(), v3(math.cos(a), 0, -math.sin(a)), v3(0, 1, 0), v3(math.sin(a), 0, math.cos(a))) end
local function rz(a) return cf(v3(), v3(math.cos(a), math.sin(a), 0), v3(-math.sin(a), math.cos(a), 0), v3(0, 0, 1)) end
local function lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - at)
	assert(look.Magnitude > 0, "CFrame.lookAt with at == target")
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then right = v3(1, 0, 0) end
	right = right.Unit
	local u = right:Cross(look).Unit
	return cf(at, right, u, -look)
end
CFrame = {
	identity = I,
	new = function(x, y, z, ...)
		if x == nil then return I end
		if getmetatable(x) == V3 then
			if y then return lookAt(x, y) end
			return cf(x, I.r, I.u, I.b)
		end
		assert(type(x) == "number" and type(y) == "number" and type(z) == "number", "CFrame.new needs numbers")
		return cf(v3(x, y, z), I.r, I.u, I.b)
	end,
	Angles = function(a, b, c) return rx(a) * ry(b) * rz(c) end,
	fromEulerAnglesXYZ = function(a, b, c) return rx(a) * ry(b) * rz(c) end,
	fromEulerAnglesYXZ = function(a, b, c) return ry(b) * rx(a) * rz(c) end,
	lookAt = lookAt,
	fromMatrix = function(p, r, u, b) return cf(p, r, u, b or r:Cross(u)) end,
	fromAxisAngle = function(axis, a) return rx(0) end,
}

-- Odds and ends ---------------------------------------------------------------------------------------------------
local C3 = {}
C3.__index = C3
local function c3(r, g, b) return setmetatable({ R = r, G = g, B = b }, C3) end
function C3.Lerp(a, b, t) return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end
Color3 = {
	new = function(r, g, b) return c3(r or 0, g or 0, b or 0) end,
	fromRGB = function(r, g, b) return c3(r / 255, g / 255, b / 255) end,
	fromHSV = function(h, s, v) return c3(v, v, v) end,
}
UDim2 = {
	new = function(...) return { ... } end,
	fromOffset = function(...) return { ... } end,
	fromScale = function(...) return { ... } end,
}
UDim = { new = function(...) return { ... } end }
PhysicalProperties = { new = function(...) return { ... } end }
NumberRange = { new = function(...) return { ... } end }
NumberSequence = { new = function(...) return { ... } end }
ColorSequence = { new = function(...) return { ... } end }
Enum = setmetatable({}, { __index = function(_, cat) return setmetatable({}, { __index = function(_, name) return cat .. "." .. name end }) end })
typeof = function(v)
	local m = getmetatable(v)
	if m == V3 then return "Vector3" elseif m == V2 then return "Vector2" elseif m == CF then return "CFrame" end
	if type(v) == "table" and v.ClassName then return "Instance" end
	return type(v)
end

-- Random: a plain LCG, deterministic per seed.
Random = {
	new = function(seed)
		local state = (seed or 1) % 2147483647
		if state <= 0 then state += 2147483646 end
		local r = {}
		local function nxt()
			state = (state * 16807) % 2147483647
			return state / 2147483647
		end
		function r:NextNumber(a, b)
			if a == nil then return nxt() end
			return a + (b - a) * nxt()
		end
		function r:NextInteger(a, b)
			return a + math.floor(nxt() * (b - a + 1))
		end
		return r
	end,
}

local signal = function()
	return { Connect = function() return { Disconnect = function() end } end, Wait = function() return 1 / 60 end }
end

-- Instances -------------------------------------------------------------------------------------------------------
STATS = { created = 0, byClass = {} }
local PART_CLASSES = { Part = true, WedgePart = true, MeshPart = true, CornerWedgePart = true, TrussPart = true, Seat = true, VehicleSeat = true, SpawnLocation = true }
local INHERITS = {
	BasePart = PART_CLASSES,
	Constraint = { AlignPosition = true, AlignOrientation = true, HingeConstraint = true, RopeConstraint = true, LinearVelocity = true },
	GuiObject = { TextLabel = true, Frame = true, ImageLabel = true, TextButton = true },
	Light = { PointLight = true, SpotLight = true, SurfaceLight = true },
	LayerCollector = { BillboardGui = true, SurfaceGui = true, ScreenGui = true },
	PVInstance = { Model = true, Part = true, WedgePart = true, MeshPart = true },
}
local Inst = {}
local InstMethods = {}
local function newInstance(class)
	STATS.created += 1
	STATS.byClass[class] = (STATS.byClass[class] or 0) + 1
	local o = { _props = { ClassName = class, Name = class, Anchored = false, CanCollide = true, Transparency = 0, Size = v3(4, 1, 2), CFrame = I }, _children = {}, _attrs = {} }
	if class == "Folder" or class == "Model" then o._props.Size = nil end
	return setmetatable(o, Inst)
end
Inst.__index = function(o, k)
	local m = InstMethods[k]
	if m then return m end
	if k == "Position" and o._props.CFrame then return o._props.CFrame.p end
	if k == "ExtentsCFrame" then return o._props.CFrame end
	if k == "ExtentsSize" then return o._props.Size end
	if k == "Triggered" or k == "Changed" or k == "Touched" or k == "ChildAdded" or k == "AncestryChanged" or k == "Event" or k == "OnServerEvent" then return signal() end
	local v = o._props[k]
	if v ~= nil then return v end
	for _, child in o._children do
		if child._props.Name == k then return child end
	end
	return nil
end
Inst.__newindex = function(o, k, v)
	if k == "Parent" then
		local old = o._props.Parent
		if old then
			local list = old._children
			for i = #list, 1, -1 do
				if list[i] == o then table.remove(list, i) end
			end
		end
		o._props.Parent = v
		if v then table.insert(v._children, o) end
		return
	end
	if k == "Position" then
		local c = o._props.CFrame or I
		o._props.CFrame = cf(v, c.r, c.u, c.b)
		return
	end
	if k == "Shape" and v == "PartType.Ball" then
		-- fine
	end
	o._props[k] = v
end
Inst.__tostring = function(o) return o._props.Name end
function InstMethods.IsA(o, class)
	local c = o._props.ClassName
	if c == class then return true end
	local set = INHERITS[class]
	if set and set[c] then return true end
	if class == "Instance" then return true end
	return false
end
function InstMethods.GetChildren(o) return table.clone(o._children) end
function InstMethods.GetDescendants(o)
	local out = {}
	local function walk(x)
		for _, c in x._children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(o)
	return out
end
function InstMethods.FindFirstChild(o, name, recursive)
	for _, c in o._children do
		if c._props.Name == name then return c end
	end
	if recursive then
		for _, c in o._children do
			local f = c:FindFirstChild(name, true)
			if f then return f end
		end
	end
	return nil
end
InstMethods.WaitForChild = function(o, name)
	local c = o:FindFirstChild(name)
	assert(c, "WaitForChild would hang: " .. name)
	return c
end
function InstMethods.FindFirstChildOfClass(o, class)
	for _, c in o._children do
		if c._props.ClassName == class then return c end
	end
end
function InstMethods.FindFirstChildWhichIsA(o, class)
	for _, c in o._children do
		if c:IsA(class) then return c end
	end
end
function InstMethods.FindFirstAncestorOfClass(o, class)
	local p = o._props.Parent
	while p do
		if p._props.ClassName == class then return p end
		p = p._props.Parent
	end
end
function InstMethods.SetAttribute(o, k, v) o._attrs[k] = v end
function InstMethods.GetAttribute(o, k) return o._attrs[k] end
function InstMethods.Destroy(o) o.Parent = nil end
function InstMethods.ClearAllChildren(o) o._children = {} end
function InstMethods.SetNetworkOwner() end
function InstMethods.GetFullName(o)
	local names = {}
	local x = o
	while x do
		table.insert(names, 1, x._props.Name)
		x = x._props.Parent
	end
	return table.concat(names, ".")
end
function InstMethods.GetPivot(o)
	if o._props.ClassName == "Model" then
		local pp = o._props.PrimaryPart
		if pp then return pp._props.CFrame end
		for _, d in o:GetDescendants() do
			if d:IsA("BasePart") then return d._props.CFrame end
		end
		return I
	end
	return o._props.CFrame
end
function InstMethods.PivotTo(o, c)
	if o._props.ClassName == "Model" then
		local from = o:GetPivot()
		local delta = c * from:Inverse()
		for _, d in o:GetDescendants() do
			if d:IsA("BasePart") then d._props.CFrame = delta * d._props.CFrame end
		end
	else
		o._props.CFrame = c
	end
end
function InstMethods.GetBoundingBox(o) return o:GetPivot(), v3(10, 10, 10) end
function InstMethods.GetExtentsSize(o) return v3(10, 10, 10) end
function InstMethods.ScaleTo() end
function InstMethods.Clone(o)
	local c = newInstance(o._props.ClassName)
	for k, v in o._props do
		if k ~= "Parent" then c._props[k] = v end
	end
	for _, ch in o._children do
		ch:Clone().Parent = c
	end
	return c
end

Instance = { new = function(class, parent)
	local o = newInstance(class)
	if parent then o.Parent = parent end
	return o
end }

-- Services --------------------------------------------------------------------------------------------------------
local function pathObj(path)
	return setmetatable({ __path = path }, { __index = function(_, k)
		if k == "WaitForChild" or k == "FindFirstChild" then return function(_, n) return pathObj(path .. "." .. n) end end
		return pathObj(path .. "." .. k)
	end })
end
local replicated = newInstance("ReplicatedStorage")
local repMeta = getmetatable(replicated)
local Replicated = setmetatable({ _real = replicated }, { __index = function(t, k)
	if k == "WaitForChild" or k == "FindFirstChild" then return function(_, n) return pathObj(n) end end
	if k == "SetAttribute" then return function(_, a, v) replicated._attrs[a] = v end end
	if k == "GetAttribute" then return function(_, a) return replicated._attrs[a] end end
	return pathObj(k)
end })
TAGS = {}
local services = {
	ReplicatedStorage = Replicated,
	Workspace = newInstance("Workspace"),
	CollectionService = {
		AddTag = function(_, o, tag) TAGS[tag] = (TAGS[tag] or 0) + 1 end,
		HasTag = function() return false end,
		RemoveTag = function() end,
		GetTagged = function() return {} end,
		GetInstanceAddedSignal = function() return signal() end,
	},
	Players = { GetPlayers = function() return {} end, GetPlayerByUserId = function() return nil end, PlayerAdded = signal(), PlayerRemoving = signal() },
	RunService = { IsStudio = function() return true end, IsServer = function() return true end, Heartbeat = signal(), Stepped = signal() },
	TweenService = { Create = function() return { Play = function() end } end },
	Debris = { AddItem = function() end },
	Lighting = newInstance("Lighting"),
}
services.Lighting.ClockTime = 10
game = { GetService = function(_, name)
	return services[name] or setmetatable({}, { __index = function() return function() return nil end end })
end }
workspace = services.Workspace
SPAWNED = 0
task = {
	wait = function() return 0 end,
	spawn = function(fn, ...) SPAWNED += 1 end, -- background loops (ferry timetables, terrain) don't run here
	defer = function() end,
	delay = function() end,
}
wait = task.wait
tick = os.clock
warnings = {}
warn = function(...)
	local parts = {}
	for _, v in { ... } do table.insert(parts, tostring(v)) end
	table.insert(warnings, table.concat(parts, " "))
	print("WARN", ...)
end

function require(obj)
	local key = obj.__path
	if cache[key] then return cache[key] end
	local fn = MODULES[key]
	if not fn then
		print("STUB", key)
		local stub = setmetatable({}, { __index = function() return function() end end })
		cache[key] = stub
		return stub
	end
	local parent = string.match(key, "^(.*)%.[^%.]+$") or key
	local script = { Parent = pathObj(parent), Name = key }
	local result = fn(script)
	cache[key] = result
	return result
end
