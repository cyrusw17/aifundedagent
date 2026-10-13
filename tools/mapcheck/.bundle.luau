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

TweenInfo = { new = function(...) return { ... } end }

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
	if k == "Triggered" or k == "Changed" or k == "Touched" or k == "ChildAdded" or k == "DescendantAdded" or k == "DescendantRemoving" or k == "AncestryChanged" or k == "Event" or k == "OnServerEvent" then return signal() end
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
TAGGED = {}
local services = {
	ReplicatedStorage = Replicated,
	Workspace = newInstance("Workspace"),
	CollectionService = {
		AddTag = function(_, o, tag) TAGS[tag] = (TAGS[tag] or 0) + 1; TAGGED[tag] = TAGGED[tag] or {}; table.insert(TAGGED[tag], o) end,
		HasTag = function(_, o, tag) for _, x in TAGGED[tag] or {} do if x == o then return true end end return false end,
		RemoveTag = function() end,
		GetTagged = function(_, tag) return table.clone(TAGGED[tag] or {}) end,
		GetInstanceAddedSignal = function() return signal() end,
	},
	Players = { GetPlayers = function() return {} end, GetPlayerByUserId = function() return nil end, PlayerAdded = signal(), PlayerRemoving = signal() },
	RunService = { IsStudio = function() return true end, IsServer = function() return true end, Heartbeat = signal(), Stepped = signal() },
	TweenService = { Create = function(_, inst, _, goal) return { Play = function() for k, v in goal do inst[k] = v end end, Completed = { Wait = function() end } } end },
	Debris = { AddItem = function() end },
	Lighting = newInstance("Lighting"),
}
services.Lighting.ClockTime = 10
game = { GetService = function(_, name)
	return services[name] or setmetatable({}, { __index = function() return function() return nil end end })
end }
workspace = services.Workspace
workspace.GetServerTimeNow = function() return os.clock() end
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

MODULES["Services.Props"] = function() return { has = function() return false end, make = function() return nil end, weldTo = function() end, restOn = function() end } end
BALES = 0
MODULES["Services.Bales"] = function()
	return { consume = function(b) b.gone = true; BALES -= 1; b.body:Destroy() end, spawn = function(pos, home, fade, hayType)
		BALES += 1
		local body = Instance.new("Part")
		body.Size = Vector3.new(4.6, 2.6, 3.2)
		body.CFrame = CFrame.new(pos)
		body.Parent = workspace
		return { body = body, hayType = hayType, spawnPosition = pos, gone = false }
	end }
end
MODULES["Services.Data"] = function() return { get = function() return nil end, toast = function() end, loaded = { Event = { Connect = function() end } } } end
MODULES["Services.Vehicles"] = function() return { all = function() return {} end } end
MODULES["Services.WorldTerrain"] = function() return { ensure = function() end, isReady = function() return false end } end
MODULES["Shared.WorldLabel"] = function()
	local W = {}
	function W.billboard(adornee, text, opts)
		local gui = Instance.new("BillboardGui")
		local label = Instance.new("TextLabel")
		label.Text = text
		label.Parent = gui
		gui.Parent = adornee
		return label
	end
	function W.surface(board, text, faces)
		for _, face in faces or { 1, 2 } do
			local gui = Instance.new("SurfaceGui")
			local label = Instance.new("TextLabel")
			label.Text = text
			label.Parent = gui
			gui.Parent = board
		end
	end
	return W
end
MODULES["Services.Bank"] = function() return { charge = function() return true end } end

MODULES["Shared.Config.WorldMap"] = function(script)
-- The Stitched Isles: every region outside Meadow Farm, the roads that join them, the sea, the ports and the ferries.
-- World studs, north = -Z, east = +X, Meadow Farm's flat ground is Y = 0. Meadow itself (the 1024 x 1024 square around
-- base camp) is Config/Meadow.luau and is never written from here; the land around it blends into its edge hills.
--
-- Layout, from docs/GAME_PLAN_V8.md and the world map board: Meadow sits on the south coast of the main island.
-- North of it are Mirror Lake and the Spindle, then Homestead Valley (the hub). Pine Forest and Haunted Grove are
-- west, Snow Peak north-west, the Volcano north-east, Desert Dunes east and the Swamp south-east. Thimble Keys lies
-- east across the sea (the Longstitch Highway or the ferry), Bobbin Rock north-east (ferry only), and Sky Island
-- floats above the hub (zeppelin).
--
-- Every number is a placeholder to tune in playtests.

export type Discovery = { id: string, name: string, at: Vector2?, flat: string?, radius: number }
type FlatZone = { name: string, min: Vector2, max: Vector2, height: number, blend: number, material: string? }
return {
	-- Bump when the shape changes: a place baked in Studio with an older version is rewritten on Play.
	Version = 2, -- 2: Cave Lane and Bobbin Track
	Seed = 23,

	SeaLevel = -4, -- the open sea's surface
	SeaFloor = -30, -- depth of open water
	Bounds = { min = Vector2.new(-2048, -2560), max = Vector2.new(3584, 1280) }, -- terrain is written inside this
	Top = 470, -- highest ground (the snow peak), for raycasts

	-- How the land meets Meadow's edge hills: the outside blends into them over this many studs.
	MeadowBlend = 200,
	MeadowShore = 260, -- land reaches at least this far past Meadow's square before the coast

	-- Each region is an oval of land (center, radius) with its own ground. Neighbors blend into each other; where no
	-- region reaches, there is sea. hayType is the Config/Gloves hay its bales carry.
	--   base: ground height; hills: { amplitude, scale } noise; peak: a mountain in the middle;
	--   materials: top, alt (patches), cliff (steep), beach; shore = "mud" for a swampy edge
	Regions = {
		{
			id = "shore",
			name = "Meadow Shore",
			center = Vector2.new(60, 760),
			radius = Vector2.new(980, 250),
			base = 4,
			hills = { { 5, 90 } },
			materials = { top = "LeafyGrass", alt = "Ground", cliff = "Rock", beach = "Sand" },
			hayType = "meadow",
			-- STYLE.md Regions: the accent for signs and trim, and the sky / fog tint.
			style = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) },
		},
		{
			id = "valley",
			name = "Mirror Lake Valley",
			center = Vector2.new(150, -840),
			radius = Vector2.new(660, 390),
			base = 10,
			hills = { { 16, 160 }, { 4, 50 } },
			materials = { top = "LeafyGrass", alt = "Ground", cliff = "Rock", beach = "Sand" },
			hayType = "meadow",
			style = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) },
		},
		{
			id = "homestead",
			name = "Homestead Valley",
			center = Vector2.new(0, -1470),
			radius = Vector2.new(560, 380),
			base = 8,
			hills = { { 12, 200 }, { 3, 60 } },
			materials = { top = "LeafyGrass", alt = "Ground", cliff = "Rock", beach = "Sand" },
			hayType = "meadow",
			style = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) },
		},
		{
			id = "spindle",
			name = "The Spindle",
			center = Vector2.new(-90, -1010),
			radius = Vector2.new(300, 260),
			base = 20,
			hills = { { 8, 80 } },
			peak = { center = Vector2.new(-90, -1010), radius = 250, height = 360, power = 1.35 },
			materials = { top = "Limestone", alt = "Slate", cliff = "Slate", beach = "Sand" },
			hayType = "meadow",
			style = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) },
		},
		{
			id = "pine",
			name = "Pine Forest",
			center = Vector2.new(-1150, 120),
			radius = Vector2.new(600, 560),
			base = 16,
			hills = { { 26, 190 }, { 6, 60 } },
			materials = { top = "LeafyGrass", alt = "Ground", cliff = "Rock", beach = "Sand" },
			hayType = "pine",
			style = { accent = Color3.fromRGB(61, 102, 94), fog = Color3.fromRGB(158, 176, 173) },
		},
		{
			id = "haunted",
			name = "Haunted Grove",
			center = Vector2.new(-1240, -880),
			radius = Vector2.new(570, 430),
			base = 6,
			hills = { { 9, 110 }, { 3, 30 } },
			materials = { top = "Mud", alt = "Slate", cliff = "Basalt", beach = "Mud" },
			hayType = "haunted",
			style = { accent = Color3.fromRGB(110, 96, 130), fog = Color3.fromRGB(140, 140, 150), density = 0.14 },
		},
		{
			id = "snow",
			name = "Snow Peak",
			center = Vector2.new(-930, -1720),
			radius = Vector2.new(660, 560),
			base = 36,
			hills = { { 22, 150 }, { 6, 45 } },
			peak = { center = Vector2.new(-1000, -1820), radius = 470, height = 400, power = 1.25 },
			snowLine = 70, -- everything above this is snow
			materials = { top = "Snow", alt = "Glacier", cliff = "Slate", beach = "Snow" },
			hayType = "snow",
			style = { accent = Color3.fromRGB(112, 150, 178), fog = Color3.fromRGB(209, 219, 230), density = 0.04 },
		},
		{
			id = "volcano",
			name = "Volcano",
			center = Vector2.new(1030, -1460),
			radius = Vector2.new(590, 510),
			base = 18,
			hills = { { 10, 120 } },
			peak = { center = Vector2.new(1080, -1520), radius = 430, height = 340, power = 1.15, crater = 95, craterDepth = 70 },
			lavaRivers = true,
			materials = { top = "Basalt", alt = "Rock", cliff = "Basalt", beach = "Basalt" },
			hayType = "volcano",
			style = { accent = Color3.fromRGB(150, 70, 40), fog = Color3.fromRGB(150, 130, 120) },
		},
		{
			id = "desert",
			name = "Desert Dunes",
			center = Vector2.new(1290, -440),
			radius = Vector2.new(640, 480),
			base = 8,
			hills = { { 6, 160 } },
			dunes = { amplitude = 16, scale = 70 },
			materials = { top = "Sand", alt = "Sandstone", cliff = "Sandstone", beach = "Sand" },
			hayType = "desert",
			style = { accent = Color3.fromRGB(168, 97, 64), fog = Color3.fromRGB(224, 209, 184) },
		},
		{
			id = "swamp",
			name = "Swamp",
			center = Vector2.new(1120, 470),
			radius = Vector2.new(620, 380),
			base = 1.5,
			hills = { { 3.5, 60 } },
			pools = { level = -0.5, threshold = -0.18, scale = 55 }, -- low spots fill with bog water
			materials = { top = "Mud", alt = "LeafyGrass", cliff = "Ground", beach = "Mud" },
			hayType = "swamp",
			style = { accent = Color3.fromRGB(153, 173, 71), fog = Color3.fromRGB(153, 163, 143), density = 0.08 },
		},
		{
			id = "keys",
			name = "Thimble Keys",
			center = Vector2.new(3100, -200),
			radius = Vector2.new(430, 360),
			base = 4,
			hills = { { 9, 120 } },
			islets = true, -- broken up into keys by a channel noise
			materials = { top = "LeafyGrass", alt = "Sand", cliff = "Sandstone", beach = "Salt" },
			hayType = "keys",
			style = { accent = Color3.fromRGB(64, 132, 140), fog = Color3.fromRGB(196, 214, 216) },
		},
		{
			id = "bobbin",
			name = "Bobbin Rock",
			center = Vector2.new(2760, -1860),
			radius = Vector2.new(280, 260),
			base = 10,
			hills = { { 10, 60 } },
			peak = { center = Vector2.new(2790, -1890), radius = 230, height = 170, power = 0.8 },
			materials = { top = "Rock", alt = "Slate", cliff = "Slate", beach = "Slate" },
			hayType = "bobbin",
			fieldFlat = "BobbinFields", -- too steep for fields to find their own spot: one goes on this terrace
			style = { accent = Color3.fromRGB(120, 110, 150), fog = Color3.fromRGB(180, 180, 196) },
		},
	},

	-- Terrain colors for the materials Meadow doesn't color (Meadow sets Grass, LeafyGrass, Ground, Mud, Sand, Rock).
	Colors = {
		Snow = Color3.fromRGB(226, 228, 226),
		Glacier = Color3.fromRGB(176, 192, 196),
		Slate = Color3.fromRGB(96, 92, 98),
		Basalt = Color3.fromRGB(64, 58, 56),
		CrackedLava = Color3.fromRGB(196, 92, 46),
		Limestone = Color3.fromRGB(162, 154, 170),
		Sandstone = Color3.fromRGB(186, 156, 112),
		Salt = Color3.fromRGB(222, 214, 192),
		Cobblestone = Color3.fromRGB(128, 120, 108),
		Pavement = Color3.fromRGB(112, 108, 102),
	},

	-- Ground pulled to a set height under buildings and ports. Rects are min/max X and Z.
	Flat = ({
		{ name = "HomesteadPlaza", min = Vector2.new(-130, -1560), max = Vector2.new(130, -1380), height = 8, blend = 60, material = "Cobblestone" },
		{ name = "ZeppelinField", min = Vector2.new(260, -1790), max = Vector2.new(380, -1660), height = 8, blend = 40 },
		{ name = "SkiLodge", min = Vector2.new(-700, -1640), max = Vector2.new(-600, -1560), height = 46, blend = 50 },
		{ name = "Lighthouse", min = Vector2.new(390, 830), max = Vector2.new(450, 890), height = 6, blend = 30 },
		{ name = "TailorShack", min = Vector2.new(-270, 640), max = Vector2.new(-230, 680), height = 4, blend = 30 },
		{ name = "PineMill", min = Vector2.new(-1240, 160), max = Vector2.new(-1180, 220), height = 18, blend = 40 },
		{ name = "Pyramid", min = Vector2.new(1440, -640), max = Vector2.new(1560, -520), height = 10, blend = 50 },
		{ name = "Oasis", min = Vector2.new(1160, -330), max = Vector2.new(1240, -250), height = 6, blend = 40 },
		{ name = "Quarry", min = Vector2.new(690, -1350), max = Vector2.new(790, -1250), height = 30, blend = 50 },
		{ name = "Wreck", min = Vector2.new(-1800, -900), max = Vector2.new(-1730, -820), height = -2, blend = 30 },
		{ name = "SwampPort", min = Vector2.new(1640, 470), max = Vector2.new(1730, 570), height = 3, blend = 40 },
		{ name = "AshDock", min = Vector2.new(1540, -1280), max = Vector2.new(1630, -1170), height = 3, blend = 40 },
		{ name = "KeysHarbor", min = Vector2.new(2780, 20), max = Vector2.new(2880, 130), height = 3, blend = 40 },
		{ name = "BobbinPier", min = Vector2.new(2510, -1840), max = Vector2.new(2570, -1760), height = 3, blend = 30 },
		{ name = "Workshop", min = Vector2.new(2760, -1920), max = Vector2.new(2820, -1860), height = 182, blend = 40 },
		-- A terrace above the Bobbin Track for the rock's only hay field (the rest of the rock is too steep).
		{ name = "BobbinFields", min = Vector2.new(2793, -1686), max = Vector2.new(2825, -1658), height = 14, blend = 24 },
		{ name = "HighwayWest", min = Vector2.new(1800, -460), max = Vector2.new(1880, -380), height = 3, blend = 40 },
		{ name = "HighwayEast", min = Vector2.new(2720, -330), max = Vector2.new(2800, -250), height = 3, blend = 40 },
	} :: { FlatZone }),

	-- Sea lanes kept deep so a ferry never scrapes the bottom (min depth along a line).
	Channels = {
		{ from = Vector2.new(1860, 500), to = Vector2.new(2720, 100), width = 90, depth = -22 },
		{ from = Vector2.new(1740, -1300), to = Vector2.new(2420, -1740), width = 90, depth = -22 },
	},

	-- Dirt roads, leveled into the land and joined to Meadow's two exits (Meadow.luau North and South end there).
	-- A road's height follows the land, smoothed and kept gentle enough to drive a loaded truck up.
	RoadWidth = 16,
	MaxGrade = 0.14, -- rise per stud along a road
	Roads = {
		{
			name = "North Road", -- Meadow's north exit, past Mirror Lake and the Spindle, into Homestead
			points = {
				Vector2.new(-30, -512), Vector2.new(-30, -620), Vector2.new(90, -760), Vector2.new(170, -900),
				Vector2.new(190, -1080), Vector2.new(120, -1260), Vector2.new(0, -1330), Vector2.new(0, -1390),
			},
		},
		{
			name = "Shore Road", -- Meadow's south exit along the coast: west to Pine Forest, east to the Swamp
			points = {
				Vector2.new(150, 512), Vector2.new(150, 640), Vector2.new(-60, 700), Vector2.new(-420, 690),
				Vector2.new(-760, 560), Vector2.new(-980, 380), Vector2.new(-1150, 160),
			},
		},
		{
			name = "Swamp Road",
			points = {
				Vector2.new(150, 640), Vector2.new(420, 700), Vector2.new(700, 620), Vector2.new(960, 520),
				Vector2.new(1300, 520), Vector2.new(1560, 520), Vector2.new(1700, 520),
			},
		},
		{
			name = "Pine Road", -- Pine Forest north through Haunted Grove to Homestead
			points = {
				Vector2.new(-1150, 160), Vector2.new(-1200, -120), Vector2.new(-1180, -420), Vector2.new(-1120, -760),
				Vector2.new(-900, -1060), Vector2.new(-620, -1300), Vector2.new(-360, -1420), Vector2.new(-125, -1400),
			},
		},
		{
			name = "Wreck Lane",
			points = { Vector2.new(-1120, -760), Vector2.new(-1500, -840), Vector2.new(-1730, -860) },
		},
		{
			name = "Snow Road",
			points = { Vector2.new(-620, -1300), Vector2.new(-640, -1460), Vector2.new(-650, -1595) },
		},
		{
			name = "Volcano Road", -- Homestead east to the quarry, then round the volcano's foot to Ash Dock
			points = {
				Vector2.new(130, -1445), Vector2.new(230, -1450), Vector2.new(460, -1420), Vector2.new(620, -1300), Vector2.new(690, -1245),
				Vector2.new(760, -1120), Vector2.new(980, -1020), Vector2.new(1260, -1010), Vector2.new(1480, -1150),
				Vector2.new(1585, -1225),
			},
		},
		{
			name = "Desert Road", -- from the North Road east across the desert to the highway
			points = {
				Vector2.new(90, -760), Vector2.new(420, -640), Vector2.new(760, -560), Vector2.new(1060, -500),
				Vector2.new(1300, -380), Vector2.new(1600, -420), Vector2.new(1840, -420),
			},
		},
		{
			name = "Dune Cut", -- desert south to the swamp
			points = { Vector2.new(1300, -380), Vector2.new(1240, -60), Vector2.new(1180, 250), Vector2.new(1300, 520) },
		},
		{
			name = "Pyramid Track",
			points = { Vector2.new(1600, -420), Vector2.new(1500, -520) },
		},
		{
			name = "Zeppelin Lane",
			points = { Vector2.new(120, -1545), Vector2.new(200, -1580), Vector2.new(320, -1640), Vector2.new(320, -1680) },
		},
		{
			name = "Keys Road", -- off the highway, across Thimble Keys to the harbor
			points = {
				Vector2.new(2760, -290), Vector2.new(2960, -300), Vector2.new(3160, -200), Vector2.new(3080, 20),
				Vector2.new(2880, 75),
			},
		},
		{
			name = "Cave Lane", -- off the North Road, west round the Spindle's south foot to the Crystal Cave mouth
			points = {
				Vector2.new(-30, -600), Vector2.new(-200, -760), Vector2.new(-320, -900), Vector2.new(-338, -948),
			},
		},
		{
			name = "Bobbin Track", -- from the Bobbin Rock pier round the rock's low south shore (the top is a climb)
			points = {
				Vector2.new(2544, -1800), Vector2.new(2615, -1715), Vector2.new(2706, -1659), Vector2.new(2811, -1645),
				Vector2.new(2913, -1677), Vector2.new(2984, -1739),
			},
		},
	},

	-- The Longstitch Highway: a bridge from the desert coast, the Midway Rest Stop, then an undersea tunnel up onto
	-- Thimble Keys. Built from parts; the terrain under it stays sea.
	-- Its height along X is the Profile (x, deck top), straight-line between the points.
	Highway = {
		width = 22,
		from = Vector2.new(1840, -420),
		to = Vector2.new(2720, -290),
		Profile = { { 1840, 3 }, { 1900, 10 }, { 2180, 10 }, { 2440, -24 }, { 2520, -24 }, { 2720, 3 } },
		restStop = { x = 2050, size = Vector2.new(70, 60) }, -- a wide stretch of deck with a pump and a stall
		toll = 1905, -- X of the toll gate
		tubeTop = 12, -- the undersea tube's inside height
	},

	-- Ports. A ferry runs between two piers; each pier points out to sea along the route. Deck tops are at
	-- Ferry.DeckTop, level with the pier.
	Ferry = {
		DeckTop = 3,
		Length = 150, -- ferry deck, end to end
		Width = 54, -- three lanes of trucks with trailers
		Speed = 26, -- studs per second at cruise
		Dock = 25, -- seconds boarding at each pier
		Warn = 8, -- seconds of horn before the gates close
		Routes = {
			{
				id = "keys_ferry",
				name = "Thimble Keys Ferry",
				a = { name = "Swamp Port", shore = Vector2.new(1700, 520), pierEnd = Vector2.new(1860, 500) },
				b = { name = "Keys Harbor", shore = Vector2.new(2860, 80), pierEnd = Vector2.new(2720, 100) },
			},
			{
				id = "bobbin_ferry",
				name = "Bobbin Rock Ferry",
				a = { name = "Ash Dock", shore = Vector2.new(1590, -1225), pierEnd = Vector2.new(1740, -1300) },
				b = { name = "Bobbin Rock", shore = Vector2.new(2550, -1800), pierEnd = Vector2.new(2420, -1740) },
			},
		},
	},

	-- The zeppelin from Homestead up to Sky Island. Same rules as a ferry, flying.
	Zeppelin = {
		name = "Sky Island Zeppelin",
		-- Deck-top centers at each stop: it lands on the Homestead field, and docks off the south edge of Sky Island
		-- beside a platform that runs onto the island.
		a = { name = "Zeppelin Field", pos = Vector3.new(320, 9, -1720) },
		b = { name = "Sky Island", pos = Vector3.new(380, 449, -1958) },
		Length = 64,
		Width = 30,
		Speed = 22,
		Dock = 25,
	},
	SkyIsland = { center = Vector2.new(380, -2240), radius = 220, top = 448, thickness = 150 },

	-- The cave under the Spindle: a tunnel from its west foot into a crystal cavern.
	Cave = {
		mouth = Vector3.new(-330, 26, -960),
		path = { Vector3.new(-290, 22, -965), Vector3.new(-240, 14, -980), Vector3.new(-180, 8, -1000) },
		chamber = { center = Vector3.new(-100, 10, -1010), radius = 70 },
		hayType = "cave",
	},

	-- Places worth finding (Services/Discoveries.luau): the first visit pays Prices.Discovery.landmark, stamps the
	-- map and fills a collection page. at = the place (x, z); radius = how close counts. Every region (and Sky Island
	-- and the Crystal Cave) is a discovery too, worth Prices.Discovery.region. Set flat = a Flat zone's name to use
	-- its middle instead of at.
	Discoveries = ({
		{ id = "old_well", name = "The Old Well", at = Vector2.new(0, -1440), radius = 25 },
		{ id = "spindle_door", name = "The Spindle Door", at = Vector2.new(155, -990), radius = 40 },
		{ id = "observatory", name = "The Observatory", at = Vector2.new(30, -1080), radius = 40 },
		{ id = "mirror_lake", name = "Mirror Lake", at = Vector2.new(400, -880), radius = 170 },
		{ id = "lighthouse", name = "The Lighthouse", at = Vector2.new(420, 860), radius = 45 },
		{ id = "tailors_shack", name = "The Tailor's Shack", at = Vector2.new(-250, 660), radius = 40 },
		{ id = "wreck_bobbin", name = "Wreck of the Bobbin", at = Vector2.new(-1770, -860), radius = 60 },
		{ id = "ghost_isle", name = "Ghost Isle", at = Vector2.new(-2075, -780), radius = 50 },
		{ id = "ski_lodge", name = "Snow Peak Lodge", at = Vector2.new(-650, -1625), radius = 50 },
		{ id = "crater_rim", name = "The Crater Rim", at = Vector2.new(1080, -1520), radius = 115 },
		{ id = "old_quarry", name = "The Old Quarry", at = Vector2.new(740, -1300), radius = 50 },
		{ id = "buried_pyramid", name = "The Buried Pyramid", at = Vector2.new(1500, -580), radius = 80 },
		{ id = "graveyard_of_ships", name = "Graveyard of Ships", at = Vector2.new(2150, -1560), radius = 300 },
		{ id = "weavers_workshop", name = "The Weaver's Workshop", flat = "Workshop", radius = 50 },
	} :: { Discovery }),

	-- Mirror Lake, north of Meadow. Low Tide drains it later; for now it is a calm lake with a dock.
	Lake = { center = Vector2.new(400, -880), radius = 130, depth = 18, level = 3 },
	Oasis = { center = Vector2.new(1200, -290), radius = 30, depth = 6, level = 5 },

	-- Hay fields: groups of bales per region (a field is a circle). Bales regrow like Meadow's.
	BalesPerField = { 6, 9 },
	FieldsPerRegion = 3,

	-- The rich field: every RichMinutes, one field on the server glows on the map and its bales carry 2x needles.
	RichMinutes = 20,

	-- Part budget (#21). Health's Workspace budget is 40,000 parts (Main.server.luau); the map's share is 12,000.
	-- Each container under Needlewood.StitchedIsles (and each region under Isles) gets a slice; mapcheck and the Map
	-- self-test fail any container over its slice. "Field bales" is the hay lying in the region fields.
	-- Regions are plain Models (Default streaming): parts stream in and out one by one. Only buildings, windmill
	-- sails and vehicles are Atomic, and only the skyline labels and the rich-field beam are Persistent.
	PartBudget = {
		["Meadow Shore"] = 600,
		["Mirror Lake Valley"] = 800,
		["Homestead Valley"] = 700,
		["The Spindle"] = 400,
		["Pine Forest"] = 1100,
		["Haunted Grove"] = 800,
		["Snow Peak"] = 1100,
		["Volcano"] = 400,
		["Desert Dunes"] = 600,
		["Swamp"] = 800,
		["Thimble Keys"] = 800,
		["Bobbin Rock"] = 300,
		["Crystal Cave"] = 200,
		["Graveyard of Ships"] = 150,
		["Sky Island"] = 200,
		["Signs"] = 150,
		["Longstitch Highway"] = 400,
		["Ferries"] = 400,
		["Wilds"] = 300,
		["RoadPolish"] = 300,
		["HayWagon"] = 100,
		["Field bales"] = 400,
		["Lighting"] = 400, -- landmark lights at night (#26)
		["Festival"] = 60, -- this week's festival bunting (Festival.luau)
	} :: { [string]: number },
	PartShare = 12000, -- the slices above must add up to no more than this

	-- Weekly region festival (Addiction push H11, Services/Festival.luau). Weeks count from FestivalEpoch (a Monday,
	-- 00:00 UTC), so every server agrees on the region and the dates. The festival region's field bales carry
	-- FestivalBoost times the needles (not stacked on the rich field's 2x), it gets bunting and a banner, and a
	-- player who visits it that week earns that week's festival ribbon (cosmetic, kept in the save).
	FestivalEpoch = 1704067200, -- Monday 2024-01-01 00:00 UTC
	FestivalWeek = 7 * 24 * 3600,
	FestivalBoost = 1.5, -- Economy (H13): 2 put a stacked week over the 2x cap (tools/boost_sim.py)
	FestivalOrder = { "pine", "valley", "desert", "snow", "swamp", "shore", "haunted", "volcano", "keys", "homestead", "bobbin" }, -- the Spindle has no hay field
}

end

MODULES["Shared.Config.Meadow"] = function(script)
-- Meadow Farm, the starting biome. Everything the terrain script and the scatter need lives here so the layout can be
-- tuned without touching code. Positions are world studs on the ground (Y is the flat ground level, 0).
-- North is -Z (the way a new player faces), east is +X.
return {
	-- Change Version whenever the layout or noise changes. A place that was baked in Studio with an older version
	-- gets regenerated when you press Play.
	Version = 7,
	Seed = 7, -- shifts the noise; same seed always gives the same hills

	HalfSize = 512, -- the biome is 1024 x 1024 studs, centered on base camp
	EdgeStart = 400, -- hills start rising here so the biome feels closed in
	EdgeHeight = 55,
	Bottom = -24, -- lowest terrain written
	Top = 96, -- highest terrain written

	-- Rolling meadow hills: amplitude in studs and scale (bigger scale = wider hills)
	Hills = {
		{ amplitude = 14, scale = 220 },
		{ amplitude = 4, scale = 70 },
	},
	BaseHeight = 3,

	-- Ground kept flat (height 0) so buildings, pads and the trailer path sit on it. Rects are min/max X and Z;
	-- blend is how far the hills take to rise again.
	Flat = {
		{ name = "BaseCamp", min = Vector2.new(-45, -40), max = Vector2.new(45, 32), blend = 40 },
		{ name = "StarterBase", min = Vector2.new(40, -58), max = Vector2.new(100, 8), blend = 30 },
		{ name = "TrailerTurn", min = Vector2.new(84, -82), max = Vector2.new(132, -26), blend = 30 },
		{ name = "TrailerRoad", min = Vector2.new(108, -82), max = Vector2.new(132, 180), blend = 30 },
		{ name = "Dealer", min = Vector2.new(-190, -70), max = Vector2.new(-55, 50), blend = 40 },
		{ name = "LandOffice", min = Vector2.new(-45, 30), max = Vector2.new(5, 66), blend = 30 },
		{ name = "Plots", min = Vector2.new(-155, 70), max = Vector2.new(103, 240), blend = 30 },
		{ name = "Bank", min = Vector2.new(30, 36), max = Vector2.new(64, 66), blend = 24 }, -- Meadow Savings & Loan (Bank.luau)
		-- Quest places (Config/Quests.luau Spots)
		{ name = "OldBarn", min = Vector2.new(268, -84), max = Vector2.new(312, -36), blend = 30 },
		{ name = "StoneRing", min = Vector2.new(-222, -167), max = Vector2.new(-188, -133), blend = 25 },
		{ name = "OldWell", min = Vector2.new(197, -183), max = Vector2.new(213, -167), blend = 20 },
		{ name = "CropCircle", min = Vector2.new(228, -322), max = Vector2.new(272, -278), blend = 30 },
		{ name = "CornMaze", min = Vector2.new(220, 104), max = Vector2.new(304, 196), blend = 30 },
		{ name = "StrawLabyrinth", min = Vector2.new(-322, -372), max = Vector2.new(-238, -284), blend = 30 },
	},

	-- Dirt roads, painted into the terrain and leveled. Each is a list of points.
	RoadWidth = 14,
	Roads = {
		{ name = "Main", points = { Vector2.new(-120, 26), Vector2.new(120, 26) } },
		{ name = "PlotRoad", points = { Vector2.new(18, 26), Vector2.new(18, 236) } },
		{ name = "PlotLane", points = { Vector2.new(-150, 156), Vector2.new(98, 156) } },
		{ name = "North", points = { Vector2.new(0, -36), Vector2.new(0, -200), Vector2.new(-30, -330), Vector2.new(-30, -512) } },
		{ name = "South", points = { Vector2.new(120, 26), Vector2.new(120, 260), Vector2.new(150, 380), Vector2.new(150, 512) } },
	},
	-- Where a road leaves the biome: a closed gate until the next map exists.
	Gates = {
		{ at = Vector2.new(-30, -490), facing = Vector2.new(0, 1), text = "HOMESTEAD VALLEY\nCOMING SOON" },
		{ at = Vector2.new(150, 490), facing = Vector2.new(0, -1), text = "PINE FOREST\nCOMING SOON" },
	},

	Pond = { center = Vector2.new(-250, 200), radius = 46, depth = 10, waterLevel = -1.5 },

	-- Places hay bales and trees keep away from, with a margin. Rects are min/max X and Z.
	KeepClear = {
		{ min = Vector2.new(-40, -32), max = Vector2.new(40, 22) }, -- base camp: spawn, hay shop, sell pad, drop-off
		{ min = Vector2.new(40, -56), max = Vector2.new(100, 6) }, -- starter base and conveyor line
		{ min = Vector2.new(84, -80), max = Vector2.new(132, -26) }, -- trailer turn
		{ min = Vector2.new(108, -80), max = Vector2.new(132, 180) }, -- trailer road
		{ min = Vector2.new(-185, -66), max = Vector2.new(-58, 44) }, -- truck dealer and its lot
		{ min = Vector2.new(-40, 36), max = Vector2.new(0, 62) }, -- land office
		{ min = Vector2.new(-150, 76), max = Vector2.new(98, 236) }, -- land plots and their lanes
		{ min = Vector2.new(32, 38), max = Vector2.new(62, 64) }, -- the bank
		-- Quest places (Config/Quests.luau Spots): the Old Barn, the stone ring, the old well and the crop circle.
		{ min = Vector2.new(270, -82), max = Vector2.new(310, -38) },
		{ min = Vector2.new(-220, -165), max = Vector2.new(-190, -135) },
		{ min = Vector2.new(197, -183), max = Vector2.new(213, -167) },
		{ min = Vector2.new(230, -320), max = Vector2.new(270, -280) },
		{ min = Vector2.new(222, 106), max = Vector2.new(302, 194) }, -- the corn maze
		{ min = Vector2.new(-320, -370), max = Vector2.new(-240, -286) }, -- the straw labyrinth
	},
	BuildingMargin = 22, -- "not super close to things like the shop"
	RoadMargin = 10, -- from the road's center line
	MaxScatterHeight = 22, -- nothing on the tall edge hills

	-- Hay bales scattered over the meadow. The map is split into cells; each cell may get a small group.
	BaleCell = 36,
	BaleChance = 0.22,
	BalesPerGroup = { 1, 3 },

	-- Decoration
	TreeCount = 90,
	RockCount = 45,

	-- The truck dealer. Its front (shop entrance and garage door) faces east toward base camp.
	DealerCenter = Vector3.new(-150, 0, 6),
	TowSpot = Vector3.new(-95, 0, -4), -- on the dealer lot, facing east: where a towed truck is set down

	-- Land you can buy (built by the land shop thread). The office faces north toward the main road and spawn.
	-- Plots are 72 x 72 and flat; a lane runs between the two rows and a road links them to the main road.
	LandOffice = { min = Vector2.new(-40, 36), max = Vector2.new(0, 62), facing = Vector2.new(0, -1) },
	Plots = {
		{ id = "plot_1", min = Vector2.new(-150, 76), max = Vector2.new(-78, 148) },
		{ id = "plot_2", min = Vector2.new(-62, 76), max = Vector2.new(10, 148) },
		{ id = "plot_3", min = Vector2.new(26, 76), max = Vector2.new(98, 148) },
		{ id = "plot_4", min = Vector2.new(-150, 164), max = Vector2.new(-78, 236) },
		{ id = "plot_5", min = Vector2.new(-62, 164), max = Vector2.new(10, 236) },
		{ id = "plot_6", min = Vector2.new(26, 164), max = Vector2.new(98, 236) },
	},
}

end

MODULES["Shared.Config.Rustic"] = function(script)
-- The Rustic house palette as Roblox colors. Mid tones from blender/lib/style.py RUSTIC (PR #12), so part-built
-- placeholders match the Blender meshes that replace them later. Ground colors are new and kept just as muted.
local function rgb(r: number, g: number, b: number): Color3
	return Color3.new(r, g, b)
end

return {
	Hay = rgb(0.74, 0.66, 0.44),
	HayLight = rgb(0.86, 0.80, 0.60),
	Bark = rgb(0.30, 0.25, 0.20),
	BarkDark = rgb(0.16, 0.13, 0.10),
	Wood = rgb(0.70, 0.60, 0.45),
	WoodDark = rgb(0.52, 0.43, 0.32),
	Handle = rgb(0.50, 0.41, 0.30),
	Metal = rgb(0.48, 0.48, 0.47), -- clean weathered grey iron, no rust (STYLE.md, BUILD_REGISTRY art style)
	Rust = rgb(0.40, 0.26, 0.16),
	Twine = rgb(0.38, 0.33, 0.26),
	PaintRed = rgb(0.52, 0.24, 0.19),
	PaintRedDark = rgb(0.36, 0.18, 0.14),
	PaintGreen = rgb(0.34, 0.42, 0.28),
	PaintBlue = rgb(0.32, 0.39, 0.46),
	PaintCream = rgb(0.78, 0.73, 0.60),
	PaintYellow = rgb(0.72, 0.58, 0.26),
	Stone = rgb(0.56, 0.53, 0.49),
	StoneDark = rgb(0.40, 0.38, 0.35),
	Cloth = rgb(0.74, 0.70, 0.58),
	Tire = rgb(0.13, 0.12, 0.11),
	Glass = rgb(0.20, 0.26, 0.28),

	-- Ground and plants
	Grass = Color3.fromRGB(112, 128, 82),
	LeafyGrass = Color3.fromRGB(96, 112, 70),
	Dirt = Color3.fromRGB(150, 128, 92),
	Mud = Color3.fromRGB(100, 84, 64),
	Sand = Color3.fromRGB(176, 160, 124),
	Rock = Color3.fromRGB(122, 116, 108),
	Water = Color3.fromRGB(74, 92, 84),
	Leaves = Color3.fromRGB(88, 104, 62),
	LeavesDark = Color3.fromRGB(70, 86, 52),
	LeavesDry = Color3.fromRGB(128, 122, 70),
}

end

MODULES["Shared.Config.Gloves"] = function(script)
-- Shovels and hay weight. The tools are the shovel, the rake and the wheelbarrow; the shovel is the upgrade (Cyrus,
-- 2026-10-13: gloves are gone, a better shovel carries more). Carried hay slows you down, rarer hay is heavier, and
-- hay rarer than your shovel is rated for slows you much more and scoops slower. A better shovel takes the edge off.
-- The module, the tier ids and the save's state.gloves keep their old names so saves carry over: a pair of gloves
-- bought before is now the shovel of the same tier. Every number here is a placeholder to tune from playtests.
local Prices = require(script.Parent.Prices)
return {
	-- Walk speed lost per unit of carried weight, before the shovel eases it. One meadow strand weighs 1.
	SlowPerWeight = 0.12,
	MinWalkSpeed = 5,
	-- A carried bale weighs this fraction of the hay inside it (it is packed tight and easier to hold).
	BaleWeightFactor = 0.8,
	-- For each tier your shovel falls short of the hay's tier, the slowdown is multiplied by (1 + this).
	UnderGearedSlow = 1.0,
	-- For each tier short, a scoop picks up this fraction fewer strands (at least 2 always).
	UnderGearedScoop = 0.35,

	-- Hay by map. map matches Config/Needles. tier is the shovel tier needed to handle it comfortably.
	HayTypes = {
		meadow = { name = "Meadow hay", map = "Meadow", weight = 1.0, tier = 0 },
		pine = { name = "Pine straw", map = "Pine Forest", weight = 1.3, tier = 1 },
		desert = { name = "Desert grass", map = "Desert", weight = 1.6, tier = 2 },
		snow = { name = "Frozen hay", map = "Snow Peak", weight = 2.0, tier = 2 },
		keys = { name = "Sea grass", map = "Thimble Keys", weight = 2.2, tier = 3 },
		swamp = { name = "Bog reed", map = "Swamp", weight = 2.4, tier = 3 },
		volcano = { name = "Ashen hay", map = "Volcano", weight = 3.0, tier = 4 },
		bobbin = { name = "Thread grass", map = "Bobbin Rock", weight = 3.2, tier = 4 },
		cave = { name = "Crystal hay", map = "Cave", weight = 3.4, tier = 4 },
		sky = { name = "Cloud hay", map = "Sky Island", weight = 4.0, tier = 5 },
		haunted = { name = "Phantom hay", map = "Haunted Grove", weight = 4.5, tier = 5 },
		star = { name = "Star hay", map = "Star Hay", weight = 6.0, tier = 6 }, -- beyond every shovel: always a struggle
	},
	DefaultHayType = "meadow",

	-- Shovel tiers, worst to best. relief is the fraction of slowdown taken away. scoopBonus adds strands per scoop,
	-- carryBonus adds to how much hay one shovel load holds. carrySpeed is walk speed added while you carry anything (a
	-- bale, a shovel load, a full barrow). color and material are the band at the neck of the blade (GloveLooks.luau)
	-- and the shovel on the rack, so each tier reads at a glance on the one Blender shovel mesh.
	Tiers = {
		{ id = "bare", name = "Old Shovel", tier = 0, price = Prices.Gloves.bare, relief = 0, scoopBonus = 0, carryBonus = 0, carrySpeed = 0, material = "Wood", color = { 128, 105, 77 } },
		{ id = "work", name = "Garden Shovel", tier = 1, price = Prices.Gloves.work, relief = 0.2, scoopBonus = 2, carryBonus = 15, carrySpeed = 0.5, material = "Metal", color = { 150, 140, 128 } },
		{ id = "leather", name = "Steel Shovel", tier = 2, price = Prices.Gloves.leather, relief = 0.35, scoopBonus = 4, carryBonus = 30, carrySpeed = 1, material = "DiamondPlate", color = { 170, 172, 170 } },
		{ id = "reinforced", name = "Reinforced Shovel", tier = 3, price = Prices.Gloves.reinforced, relief = 0.5, scoopBonus = 6, carryBonus = 50, carrySpeed = 1.5, material = "Metal", color = { 92, 74, 54 } },
		{ id = "iron", name = "Iron Spade", tier = 4, price = Prices.Gloves.iron, relief = 0.62, scoopBonus = 9, carryBonus = 80, carrySpeed = 2, material = "CorrodedMetal", color = { 107, 94, 84 } },
		{ id = "starlight", name = "Starlight Shovel", tier = 5, price = Prices.Gloves.starlight, relief = 0.78, scoopBonus = 14, carryBonus = 140, carrySpeed = 3, material = "Glass", color = { 70, 72, 96 } },
	},

	-- Quest shovels: earned from quests and rituals (Config/Quests.luau Rewards), never sold, so they are not on the
	-- shovel rack. Each is a little better than the shop shovel of the same tier, as a thank-you for the quest. The ids
	-- keep their old glove names so quest rewards and saves still match.
	QuestTiers = {
		{ id = "scarecrow_gloves", name = "Scarecrow Shovel", tier = 2, price = 0, quest = true, relief = 0.4, scoopBonus = 5, carryBonus = 35, carrySpeed = 1.2, material = "Fabric", color = { 189, 168, 112 } },
		{ id = "frostbite_mitts", name = "Frostbite Spade", tier = 3, price = 0, quest = true, relief = 0.55, scoopBonus = 7, carryBonus = 55, carrySpeed = 1.8, material = "Fabric", color = { 190, 210, 225 } },
		{ id = "magma_grips", name = "Magma Shovel", tier = 4, price = 0, quest = true, relief = 0.66, scoopBonus = 10, carryBonus = 90, carrySpeed = 2.2, material = "Basalt", color = { 140, 70, 50 } },
		{ id = "kraken_gauntlets", name = "Kraken Spade", tier = 5, price = 0, quest = true, relief = 0.8, scoopBonus = 15, carryBonus = 150, carrySpeed = 3, material = "Metal", color = { 60, 96, 110 } },
		{ id = "starweave_gloves", name = "Starweave Shovel", tier = 6, price = 0, quest = true, relief = 0.9, scoopBonus = 18, carryBonus = 180, carrySpeed = 3.5, material = "Glass", color = { 120, 140, 210 } },
	},
}

end

MODULES["Shared.Config.Prices"] = function(script)
-- Every price in Needlewood, in one place. Shops, sorters, the land office, the dealer, the glove stand and the bank all
-- read their numbers from here, so changing a price means changing one line.
--
-- docs/ECONOMY.md explains why each number is what it is, and tools/economy_model.py re-derives the tables behind it.
-- The short version: a Meadow bale is worth $47 raw, a player hauls about 2.3 bales a minute by hand (about $6,500 an
-- hour), and every price is set from how long it takes to earn at the stage where you would buy it, and how fast it
-- pays you back.
local Prices = {}

-- Selling -----------------------------------------------------------------------------------------------------------

Prices.HayPerBale = 90 -- straw strands in one bale (Config/Game PiecesPerBale x HayPerPiece)
Prices.HayPrice = 0.5 -- dollars per strand, at the public shop and at your own hay buyer
Prices.RawNeedlePrice = 1 -- the public shop finds the needles in your hay but only pays this for each

-- A needle you spot and pick up yourself (one that tumbled out of a broken bale) pays this share of its sorted value.
-- Full value: it is rare and it is the first thing that shows a new player what sorting is worth.
Prices.HandFoundNeedleShare = 1
-- When a bale breaks, this share of its hidden needles tumbles out where you can see it. The rest stay in the hay.
Prices.VisibleNeedleShare = 0.25

-- Hidden needles per bale, by hay type (ids from Config/Gloves HayTypes). Richer hay pays twice: more needles, and
-- pricier needles. Meadow's 2 keeps a sorted bale worth 1.6x to 4.9x a raw one instead of 25x.
Prices.NeedlesPerBale = {
	meadow = 2,
	pine = 3,
	desert = 4,
	snow = 5,
	swamp = 6,
	keys = 6, -- Thimble Keys, by ferry from Swamp Port: Swamp's count with a better needle, paid for by the fare
	volcano = 8,
	bobbin = 9, -- Bobbin Rock, by ferry from Ash Dock: between Volcano and Cave
	cave = 10,
	sky = 12,
	haunted = 14,
	star = 20,
}

-- Sorted needle value by needle id (Config/Needles). What the SELL NEEDLES pad pays for each.
Prices.Needles = {
	steel = 100,
	pine = 110,
	sand = 140,
	ice = 160,
	bog = 170,
	coral = 220, -- Thimble Keys
	obsidian = 300,
	brass = 320, -- Bobbin Rock
	geode = 340,
	cloud = 700,
	phantom = 800,
	cosmic = 5000,
}

-- Finder's rewards for foreign objects in hay (Config/Finds, by id), paid once for the first of each kind. About $1
-- for every bale it takes on average to turn one up (Finds oneIn), with the two rarest doubled because they are the
-- finds players talk about. They are a moment, not an income: all six together are under an hour of pickup earnings.
Prices.FinderRewards = {
	boot = 50, -- 1 in 50 bales
	horseshoe = 150, -- 1 in 150
	key = 300, -- 1 in 300
	radio = 600, -- 1 in 600
	ring = 1500, -- 1 in 1,000, doubled
	fossil = 4000, -- 1 in 2,000, doubled
}

-- NPC buyer orders (Services/Orders.luau). Three local buyers post an order each, new ones every RotateSeconds. Every
-- unit delivered pays at once: its normal price times mult, up to the order's amount per player. Plain bales pay 1.5x
-- the public shop ($71 a bale), sorted bales 2x their hay ($90, double what a hay buyer pays, since the sorting is
-- done), and steel needles 1.25x list ($125). A full order is worth a few hundred to a thousand dollars over selling
-- normally: a 5 to 10 minute bonus at the pickup stage, and a reason to haul somewhere other than your own line.
Prices.Orders = {
	RotateSeconds = 1200,
	Buyers = { "Miller Joe", "Widow Hale", "Old Tobias", "Mabel at the feed store", "The Thatcher twins", "Pastor Reed" },
	Kinds = {
		bales = { amount = { 8, 16 }, mult = 1.5 },
		sorted = { amount = { 10, 20 }, mult = 2 },
		needles = { amount = { 6, 15 }, mult = 1.25 },
	},
}

-- Daily contracts (Services/Orders.luau, CEO H9). Three contracts a day from the same buyers, the same for everyone on
-- a UTC day, reset at midnight UTC. Deliver on the orders pad: goods pay their normal price (or the open order's rate
-- when one wants them too), so a contract never costs you a sale. Finishing one pays reward, all three pay bonus and
-- count a streak day. The cash scales with how far along you are, read once a day from your lifetime sales (Bank
-- sold): each tier starts just after the purchase that opens that stage in tools/economy_model.py's first playthrough
-- (tools/boost_sim.py checks it), perHour is that stage's
-- income (the slowest stage until the next tier), and a full day (3 x reward + bonus) is about 20% of one hour there.
-- tests/contracts.luau fails if any tier goes over 25%. Before a sorter (sold under 10,000) the sorted contract is a
-- second hay one.
Prices.DailyContracts = {
	Kinds = {
		bales = { amount = { 10, 20 } },
		sorted = { amount = { 10, 20 } },
		needles = { amount = { 8, 16 } },
	},
	Tiers = {
		{ fromSold = 0, perHour = 6500, reward = 250, bonus = 500, needle = "steel", kinds = { "bales", "needles", "bales" } },
		{ fromSold = 10000, perHour = 13700, reward = 550, bonus = 1100, needle = "steel" },
		{ fromSold = 16000, perHour = 21600, reward = 850, bonus = 1700, needle = "pine" },
		{ fromSold = 75000, perHour = 40500, reward = 1500, bonus = 3000, needle = "sand" },
		{ fromSold = 110000, perHour = 90000, reward = 3500, bonus = 7000, needle = "ice" },
		{ fromSold = 455000, perHour = 150000, reward = 6000, bonus = 12000, needle = "bog" },
		{ fromSold = 605000, perHour = 436000, reward = 17000, bonus = 34000, needle = "obsidian" },
		{ fromSold = 2400000, perHour = 750000, reward = 30000, bonus = 60000, needle = "geode" },
		{ fromSold = 3100000, perHour = 1396000, reward = 55000, bonus = 110000, needle = "cloud" },
	} :: { any }, -- tiers after the first leave out `kinds` (it is optional)
}

-- The needle market (Services/Market.luau). Each server's needle prices drift up to Swing either side of the list price:
-- selling a type pushes its price down, and the push fades with HalfLifeSeconds. NormalSales recent steel sales (about a
-- solo shaker-table farm's pace) is exactly list price; rarer types need proportionally fewer, but never under
-- MinNormalSales. A quiet type pays up to 20% more, which nudges players toward regions nobody is farming.
Prices.Market = {
	Swing = 0.2,
	HalfLifeSeconds = 600,
	NormalSales = 40,
	MinNormalSales = 5,
}

-- Buying ------------------------------------------------------------------------------------------------------------

-- Trucks, at Homestead Motors. Each costs one to two hours of what you earn at the stage before it, so it is a real
-- goal, and the bank finances any of them with 20% down. The pickup is priced like a real used pickup on purpose: you
-- can't pay cash for it in your first 15 minutes, but you can put $1,200 down.
Prices.Trucks = {
	rusty_pickup = 6000,
	farm_flatbed = 25000,
	box_truck = 90000,
	heavy_hauler = 350000,
	semi_rig = 1500000,
}

-- Trailers cost about a quarter to a third of the truck that pulls them, like a real hitch-on trailer.
Prices.Trailers = {
	wagon_trailer = 1500,
	small_trailer = 8000,
	medium_trailer = 30000,
	large_trailer = 120000,
	bale_rack_trailer = 200000,
}

-- The wheelbarrow carries 3 bales a push: about 4.7 bales a minute to the sell pad, double what you carry by hand.
-- Doubling your income should cost about 10 minutes of hand hauling, so it lands about 12 minutes in, between Work
-- Gloves and the pickup (docs/ECONOMY.md).
Prices.Wheelbarrow = 1000

-- Gloves (Config/Gloves Tiers, by id). Each pair costs about 30 minutes of what you earn just before you need it for
-- the next region's heavier hay. Work Gloves are the first purchase, two or three minutes in.
Prices.Gloves = {
	bare = 0,
	work = 250,
	leather = 8000,
	reinforced = 45000,
	iron = 75000,
	starlight = 400000,
}

-- A land plot (Config/Land). Every plot is the same 12 x 10 tiles, and a save owns one. It is the first land goal, at
-- about 45 minutes in: roughly 15 minutes of pickup earnings once the pickup and wagon are paid for, or $500 down
-- with a land loan. With a hand sieve and a short line ($3,600 in all) it lifts a bale from $47 to $75.
Prices.Plot = 2500
-- Each extra row of 12 tiles at the back of a plot (two rows to buy). A new plot's 96 tiles hold a first line easily;
-- the extra rows matter when you add a second line around the shaker-table stage, so a row costs about 12 minutes of
-- earnings there. That is $417 a tile against the plot's $26, because by then you are buying room for income, not land.
Prices.PlotExpansion = 5000
-- A second farm per save. Hauling, not sorting, limits income at almost every stage, so a second plot buys room more
-- than money. It comes after the first plot is built out (plot + rows + conveyor sorter is about $37,500) and takes one
-- of a server's six plots, so it is a mid-game commitment: about 90 minutes at the conveyor-sorter stage.
Prices.SecondPlot = 60000
Prices.BinDividers = 1500 -- splits a plot's needle bin into one corner per needle type: tidiness, so cheap (ECONOMY.md)

-- Things you build on your land (Config/Land Pieces, by id). Removing one refunds RefundShare of its price.
-- Sorters are priced from the V8 payback targets: the hand sieve pays back in about 9 minutes, the shaker 15, the
-- conveyor sorter 30, the magnet drum about 75, and the optical sorter about 3.5 hours (Meadow hay, kept full).
Prices.Pieces = {
	belt = 25,
	hay_buyer = 400,
	parking = 250,
	silo = 5000,
	hand_sieve = 500,
	shaker_table = 4000,
	conveyor_sorter = 25000,
	magnet_drum = 190000, -- A-grade needles (+10%) lift it to $210 a bale; this holds its V8 payback near 74 minutes
	optical_sorter = 1350000, -- S-grade needles (+25%) lift it to $275 a bale; this holds its payback near 200 minutes
	-- Blueprints are cheap templates; what you fill them with (bales or needles) is the real cost.
	blueprint_post = 10,
	blueprint_wall = 10,
	blueprint_floor = 10,
	-- Conveyor thread pieces: belt-priced fittings, a display that is pure pride, and a press that sells nothing
	-- (thatch is for building), so it is priced like a mid-game toy rather than from a payback.
	raised_belt = 60, -- a belt on the upper level, so one line can cross another
	ramp_up = 150,
	ramp_down = 150,
	splitter = 300,
	sort_splitter = 600,
	display_wall = 1000,
	hay_press = 8000,
	loading_dock = 2000, -- the public shop's dock, on your own land: the haul ends at your farm
	-- Region machines (Services/Treat.luau): each pays back in about 20 to 25 minutes of a solo player's haul (about 3
	-- to 4 bales a minute) at the stage where they reach that region in ECONOMY.md's timeline: Snow with the box
	-- truck and a conveyor sorter, Swamp with a magnet drum, Volcano with the heavy hauler. Snow and Swamp hay can't be
	-- sorted without theirs, so they gate the region; the ash sifter only lifts a penalty, so it pays back slower.
	thawing_shed = 30000,
	drying_rack = 50000,
	ash_sifter = 100000,
	needle_vault = 6000, -- holds any number of needles with no parts; pure storage, so priced like a mid-game comfort
	hay_baler = 3000, -- packs raked or scooped strands back into bales: a convenience, so a cheap early buy
	needle_polisher = 12000,
	alloy_mixer = 20000,
	garage = 2000, -- swaps which owned truck is out; a convenience, so priced like a mid-early piece
	hay_barn = 15000, -- holds 150 bales to the silo's 60, so a long line can run unattended longer
	-- Decor (Land): looks only, no stats. Small cash sinks that make a farm worth visiting.
	decor_flowers = 200,
	decor_bench = 350,
	decor_lantern = 500,
	decor_scarecrow = 900,
	-- Late-game decor: pure show for players with money to spare (Economy: $10k-$50k sinks).
	decor_fountain = 15000,
	decor_windmill = 45000,
}
Prices.RefundShare = 0.5

-- The Starbeam Collector (alien gauntlet reward): beams one Star hay bale onto its belt every this many minutes.
-- A Star bale hides NeedlesPerBale.star Cosmic needles, so this is the richest feed in the game; tune with care.
Prices.Starbeam = {
	minutes = 10,
}

-- A needle polisher on a bin polishes needles that land in it: each sells for this much more. It works through
-- PolishPerMinute needles a minute; the rest stay plain.
Prices.PolishBonus = 0.25

-- Needle grades: the sorter that finds a needle grades it, and a better grade sells for more. It keeps upgrading
-- worth it once a sorter's recovery is "good enough". B adds nothing.
Prices.NeedleGrades = { B = 0, A = 0.10, S = 0.25 }
Prices.SorterGrade = {
	hand_sieve = "B",
	shaker_table = "B",
	conveyor_sorter = "B",
	magnet_drum = "A",
	optical_sorter = "S",
	alien_collector = "S",
}
Prices.PolishPerMinute = 30

-- Sorter oil: click the oil can on any sorter. A flat price, so it is a small treat on a cheap sorter and pocket
-- change on a big one; it only pays when the sorter is what holds the line back.
Prices.SorterOil = {
	price = 250,
	bales = 25, -- the next this many bales sort faster
	speedup = 0.1, -- 10% faster
	maxBales = 75, -- at most three cans stacked
}

-- Sorter speeds, in bales a minute (Config/Sorters turns them into hay per minute). Each tier doubles the last.
Prices.SorterBalesPerMinute = {
	hand_sieve = 2,
	shaker_table = 4,
	conveyor_sorter = 8,
	magnet_drum = 16,
	optical_sorter = 30,
}

-- The trading post (Land) settles every trade through Bank.settleTrade. A side that hands over cash pays a small flat
-- fee plus a share of that cash, so cash-for-needles deals don't dodge the market and moving money between accounts
-- costs something. A side that only gives items pays nothing, so swaps and gifts are always free. Set both to 0 to
-- make cash trades free too.
Prices.Trade = {
	Fee = 25, -- per side that gives cash, per trade
	CashShare = 0.05, -- of the cash a side gives
	-- A save slot can hand over cash only once it has made this much from selling (not from one-time rewards like
	-- secrets, discoveries, mazes, quests and finds). About 2 hours of a new player's farming, so a fresh alt slot
	-- can't collect one-time rewards and pass the cash on. Items can always be traded.
	MinSoldToGiveCash = 25000,
}

-- Travel fares for the rest of the Stitched Isles (for the world map thread; nothing reads them yet). A fare is a small
-- share of what the trip carries, so it is felt but never decides whether a trip is worth it. Roads, including the
-- Longstitch Highway, stay free.
Prices.Travel = {
	ferry = 250, -- public ferry, per truck with its trailer, each way: under 5% of a box-truck load of Snow hay
	barge = 0, -- the Captain's Barge is earned by quest and free to use
	zeppelin = 1000, -- to Sky Island, per trip: under 5% of a pickup load of Sky hay
	snack = 15, -- a snack from the ferry galley: cosmetic, a little treat for the crossing
}

-- Wet hay (Hay thread; Config/Game reads it as WetPriceFactor): a bale soaked by rain sells its hay at this share of
-- the price until it dries. Needles are unharmed, so a wet Meadow bale sorts to $227 against $245: a nudge to park
-- under cover or wait out the rain (it dries 150 s after), never a disaster.
Prices.WetHayShare = 0.6

-- Mutated needles (Needle.rollMutation): 1 found needle in oneIn is mutated and sells for min to max times its value
-- (announced to the server). The average mutation is 14x, so mutations add (14 - 1) / 500 = 2.6% to needle income: a
-- jackpot moment, not a source. A mutated Cosmic needle can be worth $125,000.
Prices.Mutation = {
	oneIn = 500,
	min = 3,
	max = 25,
}

-- Pity (CEO "Addiction push" H3, src/shared/Pity.luau): after `bales` sorted bales in a row that found needles but no
-- mutated one, the next such bale makes its first needle mutated at `mult` (the smallest mutation), so a dry run always
-- ends. A roll under Mutation.oneIn's chance times `nearMiss` that just missed flickers gold ("so close").
-- tests/pity.luau measures what it adds to needle income (not total): hand sieve 3.9%, Meadow conveyor 2.7%, Desert
-- magnet drum 1.3%, Swamp optical 0.7%, Star optical 0.1%. It fails if any case reaches 5%.
Prices.Pity = {
	bales = 40,
	mult = 3,
	nearMiss = 3,
}

-- The Hay Market (Services/HayMarket.luau, CEO H6): a stall at base camp restocks every RestockSeconds with Slots
-- rare bales, each a kind (Golden, Storm or Moon Hay) of one region's hay, StockPerSlot of each for the whole server.
-- A player can buy PerPlayer bales per restock. needles multiplies the bale's hidden needles and mutation multiplies
-- each found needle's chance to mutate (Prices.Mutation).
-- Price is not set by hand: it is PriceShare of what the bale is worth sorted on a conveyor sorter
-- (ReferenceRecovery), mutations included. So a player with a conveyor sorter or better makes a little on every rare
-- bale and gets a lottery ticket on top, while a player selling raw or hand-sieving loses money on them: rare bales
-- are a bonus for a working line, not a replacement for farming (ECONOMY.md "The Hay Market").
Prices.HayMarket = {
	RestockSeconds = 300,
	Slots = 3,
	StockPerSlot = 3,
	PerPlayer = 2,
	PriceShare = 0.85,
	ReferenceRecovery = 0.55,
	Kinds = {
		-- weight: how often a slot rolls this kind
		golden = { name = "Golden Hay", weight = 5, needles = 3, mutation = 1 },
		storm = { name = "Storm Hay", weight = 3, needles = 2, mutation = 5 },
		moon = { name = "Moon Hay", weight = 1, needles = 1, mutation = 25 },
	},
	-- Which region's hay a slot holds, by weight. Hay that needs a region machine (Snow, Swamp) is left out, so
	-- any bale can go straight into a sorter.
	HayTypes = { meadow = 6, pine = 4, desert = 3, keys = 2, volcano = 1, bobbin = 1 },
}

-- Wet needles (H7 weather, Weather.needleOdds): a needle sorted where it is raining is, 1 in oneIn, a "Wet" needle
-- worth mult times (x2: under the smallest real mutation, so x2 always means Wet, in saves too). It doesn't end a
-- pity run. PROPOSED by Conveyor, pending Economy. tests/pity.luau keeps storm + Wet + pity within 2x of the
-- mutation value of today's rules (pity, no weather) even if it always rained: x1.2 to x1.5.
Prices.WetMutation = {
	oneIn = 100,
	mult = 2,
}

-- Stacked boosts (CEO H13, src/shared/Boosts.luau). Extras a bale picks up on top of its own boost (the play-together
-- bonus, thunderstorm odds) stop once the bale's needles are worth Cap times a plain bale's, or the bale's own boost
-- if that is bigger. tools/boost_sim.py plays a week with every boost stacked and fails if income goes over Cap times
-- the plain game or any purchase lands in under half its target time.
Prices.Boosts = {
	Cap = 2,
}

-- Needle index (CEO "Addiction push" H10, Services/NeedleIndex): every needle type found plain, Wet and mutated
-- (12 types x 3 = 36 entries). Each milestone pays once per slot (Bank.earn, note "Discovered ...", a one-time
-- reward) and gives a title; 75% also unlocks the gilded sorter skin. 100% needs a mutated and a Wet Cosmic needle,
-- so it is an end-game goal; the first 25% (9 entries) comes from the first few regions.
Prices.NeedleIndex = {
	{ at = 25, cash = 5000, title = "Needle Spotter" },
	{ at = 50, cash = 40000, title = "Needle Collector" },
	{ at = 75, cash = 250000, title = "Needle Curator", skin = "gilded" },
	{ at = 100, cash = 1000000, title = "Master Indexer" },
}

-- Golden field bales (Hay thread, Bales.makeGolden): 1 field bale in oneIn grows golden and hides `needles` times
-- the needles. On average that adds (needles - 1) / oneIn = 1.3% to needle income, too little to move the pacing, so it
-- is a moment rather than a source: a golden Meadow bale sorts to about $645 against a plain one's $245.
Prices.GoldenBale = {
	oneIn = 150,
	needles = 3,
}

-- Region events (world map thread, Services/RegionEvents.luau): one at a time, every EveryMinutes, each for
-- Minutes. The reward is hay, never cash: the event drops `bales` extra bales of the region's hay, each with `boost`
-- times the needles (the same NeedleBoost the rich field uses, 2x). Kept near the rich field so an event is worth a
-- detour but never beats a steady haul. Each is worth about 5 to 10 minutes of income at the stage where you reach
-- its region (ECONOMY.md "Region events").
Prices.RegionEvents = {
	EveryMinutes = 30,
	Minutes = 5,
	hay_fever = { bales = 10, boost = 1.5 }, -- Meadow Shore: pollen in the air, the grass bursts
	windfall = { bales = 12, boost = 1.5 }, -- Pine Forest: the wind brings bales down off the ridge
	sandstorm = { bales = 10, boost = 2 }, -- Desert Dunes: the storm uncovers buried bales
	avalanche = { bales = 10, boost = 2 }, -- Snow Peak: bales tumble down to the lodge
	low_tide = { bales = 10, boost = 1.5 }, -- Swamp: the water drops and sunken bales come up
	eruption = { bales = 10, boost = 2.5 }, -- Volcano: hot ash over the slopes (hardest to reach, so the richest drop)
	meteor_shower = { bales = 8, boost = 3 }, -- Mirror Lake Valley, nights only (rarer, so the best Meadow-hay event)
}

-- Discoveries (Services/Discoveries.luau): the first visit to each region and landmark, once per save slot. Small on
-- purpose: exploring pays a little everywhere (about $5,700 for the whole map) and the stamps are the real prize.
Prices.Discovery = {
	region = 250,
	landmark = 150,
}

-- Region secrets (Services/Wilds.luau): paid once per save slot to whoever finds them, like a finder's reward. Each is
-- worth a trip on its own: for a player who arrives early (walking, before they haul there) it's about the price of
-- the next mid-game buy, and for one who arrives on schedule it's a few minutes of income. Gated secrets pay more.
Prices.Secrets = {
	ember_cache = 40000, -- in the volcano's crater, past the heat: needs $75,000 Iron Gauntlets, so it pays the most
	captains_lantern = 15000, -- on Ghost Isle, at the end of the night-only Ghost Road: walkable early, so the least
	geode_heart = 20000, -- behind the crystals on the Crystal Cave's far wall
	lost_kite = 25000, -- on a ledge under Sky Island's west rim, a $1,000 zeppelin fare away
	-- Each region's hidden spot (Wilds, hidden_<region>), a short walk off a road from its Old Sign clue. Smaller than
	-- the four big secrets and scaled to the region: about 5 minutes of income at the stage you reach it, so the
	-- Meadow ones can't hand a new player a pickup. `hidden` is the fallback for a region not listed. $58,000 in all.
	hidden = 500,
	hidden_shore = 500,
	hidden_valley = 500,
	hidden_homestead = 500,
	hidden_spindle = 500,
	hidden_pine = 1500,
	hidden_desert = 2500,
	hidden_snow = 4000,
	hidden_keys = 5000,
	hidden_swamp = 6000,
	hidden_volcano = 10000,
	hidden_bobbin = 12000,
	hidden_haunted = 15000,
}

-- Robux store prices in Robux (V8 Part C). Recorded here so every price is in one place; the store itself waits until
-- the cash economy has been playtested. Paid trucks match their cash tier's stats exactly, and nothing is random.
-- Truck keys are the skin mesh names in Config/Props Sizes; a skin is drawn at the meshSize of the truck it repaints.
Prices.Robux = {
	Trucks = {
		homestead_classic = 399, -- skin of the Rusty Pickup tier
		timber_wolf_4x4 = 799, -- Farm Flatbed tier (key = its mesh name in Config/Props)
		midnight_express = 1199, -- Box Truck tier
		prairie_schooner = 1799, -- Heavy Hauler tier
		founders_semi = 2499, -- Semi tier, launch edition
	},
	Passes = {
		vip = 249,
		auto_dock = 299,
		big_silo = 199,
		paint_studio = 149,
		plot_themes = 199,
		truck_radio = 99,
	},
	HarvestPass = 499,
	ServerBoost = 99,
	PrivateServer = 100, -- a month
}

-- The bank -----------------------------------------------------------------------------------------------------------

Prices.Bank = {
	-- Savings interest is paid every InterestSeconds of play, but only if you sold something in that time, so it
	-- rewards saving while you work and never pays an idle player. Tiered like a real savings account, but upside
	-- down: the first $10,000 earns the most, so it helps a new farm and stays small next to a big farm's income.
	InterestSeconds = 600,
	InterestTiers = {
		{ upTo = 10000, rate = 0.01 },
		{ upTo = 100000, rate = 0.005 },
	},

	-- Loans. You pick what you are financing, put DownPayment of its price in the bank yourself, and the bank lends
	-- the rest. Interest is one flat fee added up front, so "borrow $4,800, pay back $5,280" is the whole deal.
	-- Repayment comes out of your sales automatically (repayShare of each one) until it is paid; there are no due
	-- dates and no penalties, and you can pay the rest off early at any time.
	DownPayment = 0.2,
	Loans = {
		truck = { name = "Truck loan", interest = 0.10, repayShare = 0.25, blurb = "Trucks and trailers" },
		land = { name = "Land loan", interest = 0.08, repayShare = 0.20, blurb = "Land plots" },
	},
	-- How much you can owe in total: a base line of credit plus twice everything you have ever earned.
	CreditBase = 5000,
	CreditPerEarned = 2,

	HistoryLength = 40, -- transactions kept per save slot
}

-- Hidden needles per strand of a hay type, for the rolls in Economy.rollNeedles.
function Prices.needleChance(hayType: string?): number
	local perBale = Prices.NeedlesPerBale[hayType or "meadow"] or Prices.NeedlesPerBale.meadow
	return perBale / Prices.HayPerBale
end

-- Pacing scale (CEO H18) --------------------------------------------------------------------------------------------

-- One dial for how long the climb takes after the first hour. Every truck, trailer, glove and build piece priced at
-- PacingFrom or more is multiplied by PacingScale and rounded to two significant figures; first-hour buys (under
-- PacingFrom, and the Rusty Pickup) never change. 1 is the prices written above. tools/boost_sim.py picks the value
-- that lands the Semi at Prices' target hours for a typical player with typical boosts, and tools/line_sim.py,
-- pacing_sim.py and economy_model.py apply the same rule (line_sim.paced). Cyrus's 14 h vs 40 h question is
-- separate: answering it changes the target, then this value.
Prices.PacingScale = 1.2
Prices.PacingFrom = 4000
Prices.PacingKeep = { rusty_pickup = true }

function Prices.paced(id: string, price: number): number
	if Prices.PacingScale == 1 or price < Prices.PacingFrom or Prices.PacingKeep[id] then
		return price
	end
	local x = price * Prices.PacingScale
	local step = 10 ^ (math.floor(math.log10(x)) - 1)
	return math.floor(x / step + 0.5) * step
end

-- The daily contract tiers are lifetime sales at each stage, so they stretch with it.
for _, tier: any in Prices.DailyContracts.Tiers do
	tier.fromSold = math.floor(tier.fromSold * Prices.PacingScale + 0.5)
end

for _, list: { [string]: any } in { Prices.Trucks, Prices.Trailers, Prices.Gloves, Prices.Pieces } :: { any } do
	for id, price in list do
		if typeof(price) == "number" then
			list[id] = Prices.paced(id :: string, price)
		end
	end
end

return Prices

end

MODULES["Services.MeadowTerrain"] = function(script)
-- Meadow Farm terrain, written by script. Rolling grass hills, flat ground under every building, dirt roads, a pond,
-- and tall hills around the edge. The same seed always gives the same land.
--
-- Load time: pressing Play builds it in about a second. To skip even that, bake it once in Studio's edit mode
-- (command bar):  require(game.ServerScriptService.Server.Services.MeadowTerrain).generate()
-- then save the place. Play sees the baked terrain (Terrain's MeadowVersion attribute) and leaves it alone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Meadow = require(Shared.Config.Meadow)
local Rustic = require(Shared.Config.Rustic)

local MeadowTerrain = {}

local RES = 4 -- voxel size in studs
local CHUNK = 64 -- voxels per side written at once
local SEED = Meadow.Seed * 17.31

-- Looked up once: indexing Enum in the voxel loop would cost more than the rest of the work.
local AIR = Enum.Material.Air
local GROUND = Enum.Material.Ground
local WATER = Enum.Material.Water
-- Never Enum.Material.Grass: only Grass grows the tall decoration blades, and Terrain.Decoration cannot be turned
-- off from a script or Rojo (it is not scriptable). The meadow is LeafyGrass instead (Roblox has no Moss terrain material).
local GRASS = Enum.Material.LeafyGrass
local LEAFY = Enum.Material.LeafyGrass
local ROCK = Enum.Material.Rock
local SAND = Enum.Material.Sand
local MUD = Enum.Material.Mud

local function smoothstep(edge0, edge1, x)
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- Distance from a point to a rect on the ground (0 inside).
local function rectDistance(x, z, min, max)
	local dx = math.max(min.X - x, 0, x - max.X)
	local dz = math.max(min.Y - z, 0, z - max.Y)
	return math.sqrt(dx * dx + dz * dz)
end

local function segmentDistance(x, z, a, b)
	local abx, abz = b.X - a.X, b.Y - a.Y
	local t = math.clamp(((x - a.X) * abx + (z - a.Y) * abz) / (abx * abx + abz * abz), 0, 1)
	local dx, dz = x - (a.X + abx * t), z - (a.Y + abz * t)
	return math.sqrt(dx * dx + dz * dz)
end

-- Distance to the nearest road's center line.
function MeadowTerrain.roadDistance(x, z)
	local best = math.huge
	for _, road in Meadow.Roads do
		for i = 1, #road.points - 1 do
			best = math.min(best, segmentDistance(x, z, road.points[i], road.points[i + 1]))
		end
	end
	return best
end

local function noise(x, z, scale, salt)
	return math.noise(x / scale + SEED + salt * 3.7, z / scale - SEED + salt * 1.9, salt * 0.61 + 0.5)
end

-- How strongly the ground here is pulled flat to height 0 (1 = fully flat).
local function flatness(x, z)
	local w = 0
	for _, zone in Meadow.Flat do
		local d = rectDistance(x, z, zone.min, zone.max)
		w = math.max(w, 1 - smoothstep(0, zone.blend, d))
	end
	local road = MeadowTerrain.roadDistance(x, z)
	w = math.max(w, 1 - smoothstep(Meadow.RoadWidth / 2, Meadow.RoadWidth / 2 + 26, road))
	return w
end

-- Ground height at a point. Deterministic, so anything can ask without raycasting.
function MeadowTerrain.heightAt(x, z)
	local h = Meadow.BaseHeight
	for i, hill in Meadow.Hills do
		h += hill.amplitude * noise(x, z, hill.scale, i)
	end
	local edge = smoothstep(Meadow.EdgeStart, Meadow.HalfSize - 12, math.max(math.abs(x), math.abs(z)))
	h += edge * (Meadow.EdgeHeight + 18 * noise(x, z, 60, 9))

	h = lerp(h, 0, flatness(x, z))

	-- The pond: level ground around it, then a bowl that holds water.
	local pond = Meadow.Pond
	local d = math.sqrt((x - pond.center.X) ^ 2 + (z - pond.center.Y) ^ 2)
	h = lerp(h, 1, 1 - smoothstep(pond.radius, pond.radius + 50, d))
	h -= pond.depth * (1 - smoothstep(pond.radius * 0.35, pond.radius + 6, d))
	return math.min(h, Meadow.Top - 2)
end

local function inPond(x, z)
	local pond = Meadow.Pond
	return (x - pond.center.X) ^ 2 + (z - pond.center.Y) ^ 2 < (pond.radius + 8) ^ 2
end

-- Surface material for a column, from its height and the slope around it.
local function surfaceMaterial(x, z, h, slope)
	if MeadowTerrain.roadDistance(x, z) < Meadow.RoadWidth / 2 + noise(x, z, 9, 4) * 1.5 then
		return GROUND
	end
	if inPond(x, z) and h < Meadow.Pond.waterLevel + 1.2 then
		return h < Meadow.Pond.waterLevel - 2 and MUD or SAND
	end
	if slope > 0.9 or (h > 34 and noise(x, z, 30, 6) > 0.1) then
		return ROCK
	end
	if noise(x, z, 45, 5) > 0.22 then
		return LEAFY
	end
	return GRASS
end

local function setColors(terrain)
	-- Roblox's decoration grass grows knee-high on the Grass material and hides bales, pads and paths. Cut it short
	-- and switch it off; each in its own pcall, since a place may refuse script writes to either.
	pcall(function()
		terrain.GrassLength = 0.1
	end)
	pcall(function()
		terrain.Decoration = false
	end)
	terrain:SetMaterialColor(Enum.Material.Grass, Rustic.Grass)
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Rustic.Grass)
	terrain:SetMaterialColor(Enum.Material.Ground, Rustic.Dirt)
	terrain:SetMaterialColor(Enum.Material.Mud, Rustic.Mud)
	terrain:SetMaterialColor(Enum.Material.Sand, Rustic.Sand)
	terrain:SetMaterialColor(Enum.Material.Rock, Rustic.Rock)
	terrain.WaterColor = Rustic.Water
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.05
end

function MeadowTerrain.isBuilt()
	return Workspace.Terrain:GetAttribute("MeadowVersion") == Meadow.Version
end

-- Writes the whole biome. Yields between chunks while the game runs so the server never freezes.
function MeadowTerrain.generate()
	local terrain = Workspace.Terrain
	local started = os.clock()
	local half = Meadow.HalfSize
	local columns = half * 2 // RES
	local bottom = Meadow.Bottom
	local water = Meadow.Pond.waterLevel

	-- Heights at the center of every column first, so slopes can use the neighbors.
	local heights = table.create(columns)
	for i = 1, columns do
		local row = table.create(columns)
		local x = -half + (i - 0.5) * RES
		for k = 1, columns do
			row[k] = MeadowTerrain.heightAt(x, -half + (k - 0.5) * RES)
		end
		heights[i] = row
	end

	-- Chunks nearest base camp go first, so the spawn has ground under it right away.
	local chunks = {}
	for ci = 0, columns // CHUNK - 1 do
		for ck = 0, columns // CHUNK - 1 do
			table.insert(chunks, { ci, ck })
		end
	end
	local mid = columns / CHUNK / 2 - 0.5
	table.sort(chunks, function(a, b)
		return (a[1] - mid) ^ 2 + (a[2] - mid) ^ 2 < (b[1] - mid) ^ 2 + (b[2] - mid) ^ 2
	end)

	-- Start clean, so an older layout never leaves hills floating above the new one.
	terrain:Clear()

	for _, chunk in chunks do
		local i0, k0 = chunk[1] * CHUNK, chunk[2] * CHUNK

		-- Only write the layers this chunk needs: a shell 3 voxels thick under its lowest ground, up to its highest
		-- ground or the pond surface. Air above is already empty, which keeps the write small and quick.
		local lowest, highest = math.huge, -math.huge
		for di = 1, CHUNK do
			local row = heights[i0 + di]
			for dk = 1, CHUNK do
				local h = row[k0 + dk]
				lowest = math.min(lowest, h)
				highest = math.max(highest, h)
			end
		end
		highest = math.max(highest, water)
		local first = math.max(1, (lowest - bottom) // RES - 2)
		local last = math.min((Meadow.Top - bottom) // RES, (highest - bottom) // RES + 1)
		local layers = last - first + 1
		local base = bottom + (first - 1) * RES

		local materials = table.create(CHUNK)
		local occupancy = table.create(CHUNK)
		for di = 1, CHUNK do
			local i = i0 + di
			local x = -half + (i - 0.5) * RES
			local matX = table.create(layers)
			local occX = table.create(layers)
			for j = 1, layers do
				matX[j] = table.create(CHUNK)
				occX[j] = table.create(CHUNK)
			end
			for dk = 1, CHUNK do
				local k = k0 + dk
				local z = -half + (k - 0.5) * RES
				local h = heights[i][k]
				local hx = heights[math.clamp(i + 1, 1, columns)][k] - heights[math.clamp(i - 1, 1, columns)][k]
				local hz = heights[i][math.clamp(k + 1, 1, columns)] - heights[i][math.clamp(k - 1, 1, columns)]
				local slope = math.sqrt(hx * hx + hz * hz) / (RES * 2)
				local top = surfaceMaterial(x, z, h, slope)
				local wet = inPond(x, z)
				for j = 1, layers do
					local y0 = base + (j - 1) * RES
					local fill = math.clamp((h - y0) / RES, 0, 1)
					local material, occ = AIR, 0
					if fill > 0 then
						material = (h - y0 > RES * 3) and GROUND or top
						occ = fill
					elseif wet and y0 < water then
						material = WATER
						occ = math.clamp((water - y0) / RES, 0, 1)
					end
					matX[j][dk] = material
					occX[j][dk] = occ
				end
			end
			materials[di] = matX
			occupancy[di] = occX
		end
		local low = Vector3.new(-half + i0 * RES, base, -half + k0 * RES)
		local region = Region3.new(low, low + Vector3.new(CHUNK * RES, layers * RES, CHUNK * RES))
		terrain:WriteVoxels(region, RES, materials, occupancy)
		if RunService:IsRunning() then
			task.wait()
		end
	end

	setColors(terrain)
	terrain:SetAttribute("MeadowVersion", Meadow.Version)
	print(("[Needlewood] Meadow terrain written in %.1fs"):format(os.clock() - started))
end

-- Builds the terrain unless this place already has the current version baked in.
function MeadowTerrain.ensure()
	if MeadowTerrain.isBuilt() then
		setColors(Workspace.Terrain)
		return
	end
	MeadowTerrain.generate()
end

-- The real ground height under a point (terrain surface), falling back to the formula.
function MeadowTerrain.groundAt(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(Vector3.new(x, Meadow.Top + 10, z), Vector3.new(0, -(Meadow.Top - Meadow.Bottom + 20), 0), params)
	if hit then
		return hit.Position.Y, hit.Normal, hit.Material
	end
	return MeadowTerrain.heightAt(x, z), Vector3.yAxis, nil
end

-- Turns any Grass voxel left anywhere in the world into LeafyGrass, once the world map's terrain has finished writing.
-- Grass is the one material Roblox grows tall blades on, and a place baked or hand-painted before the switch can still
-- hold some. Runs in the background in 512-stud blocks; ReplaceMaterial is quick over air.
function MeadowTerrain.sweepGrass(bounds)
	task.spawn(function()
		local terrain = Workspace.Terrain
		local waited = 0
		while terrain:GetAttribute("WorldMapVersion") == nil and waited < 180 do
			waited += task.wait(2)
		end
		local started = os.clock()
		local STEP, LOW, HIGH = 512, -128, 1024
		for x = bounds.min.X, bounds.max.X - 1, STEP do
			for z = bounds.min.Y, bounds.max.Y - 1, STEP do
				for y = LOW, HIGH - 1, 576 do
					local region = Region3.new(Vector3.new(x, y, z), Vector3.new(x + STEP, y + 576, z + STEP)):ExpandToGrid(RES)
					pcall(terrain.ReplaceMaterial, terrain, region, RES, Enum.Material.Grass, Enum.Material.LeafyGrass)
				end
				task.wait()
			end
		end
		print(("[Needlewood] grass sweep done in %.1fs"):format(os.clock() - started))
	end)
end

return MeadowTerrain

end

MODULES["Services.WorldShape"] = function(script)
-- The shape of the Stitched Isles outside Meadow Farm, as plain math: ground height, water and surface material for
-- any point. WorldTerrain writes it into voxels and Regions places trees and buildings on it, so both always agree.
-- Pure functions of Config/WorldMap.luau and the Meadow edge, so the same seed always gives the same islands.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)
local MeadowTerrain = require(script.Parent.MeadowTerrain)

local WorldShape = {}

local HALF = Meadow.HalfSize
local SEED = Map.Seed * 13.7
local SEA = Map.SeaLevel
local ROAD_HALF = Map.RoadWidth / 2
local ROAD_BLEND = 22 -- how far past the road's edge the land takes to rise or fall back
local CELL = 64 -- road lookup grid

local function smoothstep(edge0, edge1, x)
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end
WorldShape.smoothstep = smoothstep

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function noise(x, z, scale, salt)
	return math.noise(x / scale + SEED + salt * 3.1, z / scale - SEED + salt * 2.3, salt * 0.37 + 0.5)
end
WorldShape.noise = noise

local function rectDistance(x, z, min, max)
	local dx = math.max(min.X - x, 0, x - max.X)
	local dz = math.max(min.Y - z, 0, z - max.Y)
	return math.sqrt(dx * dx + dz * dz)
end
WorldShape.rectDistance = rectDistance

-- Distance from a point to segment ab, and how far along it (0..1) the nearest point is.
local function segment(x, z, ax, az, bx, bz)
	local abx, abz = bx - ax, bz - az
	local len2 = abx * abx + abz * abz
	local t = len2 > 0 and math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1) or 0
	local dx, dz = x - (ax + abx * t), z - (az + abz * t)
	return math.sqrt(dx * dx + dz * dz), t
end
WorldShape.segment = segment

-- Distance outside Meadow's square (0 on or inside it).
local function meadowDistance(x, z)
	local dx = math.max(math.abs(x) - HALF, 0)
	local dz = math.max(math.abs(z) - HALF, 0)
	return math.sqrt(dx * dx + dz * dz)
end
WorldShape.meadowDistance = meadowDistance

function WorldShape.inMeadow(x, z)
	return math.abs(x) < HALF and math.abs(z) < HALF
end

-- Regions ---------------------------------------------------------------------------------------------------------

local regions = {}
for i, def in Map.Regions do
	local r = table.clone(def)
	r.index = i
	r.salt = i * 1.7
	r.cx, r.cz = def.center.X, def.center.Y
	r.rx, r.rz = def.radius.X, def.radius.Y
	-- Past 1.45 radii a region has no say at all, so most points only ask two or three regions.
	r.reach = 1.45
	regions[i] = r
end
WorldShape.regions = regions

function WorldShape.region(id)
	for _, r in regions do
		if r.id == id then
			return r
		end
	end
	return nil
end

-- How far inside a region's oval a point is: 1 at its center, 0 on its coast, negative outside. The coast wobbles.
local function inside(r, x, z)
	local dx, dz = (x - r.cx) / r.rx, (z - r.cz) / r.rz
	local d2 = dx * dx + dz * dz
	if d2 > r.reach * r.reach then
		return -1
	end
	local d = math.sqrt(d2) * (1 + 0.10 * noise(x, z, 260, r.salt) + 0.05 * noise(x, z, 70, r.salt + 1))
	local value = 1 - d
	if r.islets then
		-- Channels of sea break the keys into a chain of islets.
		local channel = math.abs(noise(x, z, 150, r.salt + 4))
		value -= math.max(0, 0.12 - channel) * 2.6
	end
	return value
end

local function peakHeight(peak, x, z)
	local dx, dz = x - peak.center.X, z - peak.center.Y
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist >= peak.radius then
		return 0
	end
	local shape = (1 - dist / peak.radius) ^ peak.power
	local h = peak.height * shape
	if peak.crater and dist < peak.crater then
		local rim = peak.height * (1 - peak.crater / peak.radius) ^ peak.power
		local k = dist / peak.crater
		h = rim + 6 - peak.craterDepth * (1 - k * k)
	end
	return h
end

local function regionHeight(r, x, z)
	local h = r.base
	for i, hill in r.hills do
		h += hill[1] * noise(x, z, hill[2], r.salt + i)
	end
	if r.peak then
		h += peakHeight(r.peak, x, z)
		-- A rough, ridged face on big mountains.
		h += 10 * math.abs(noise(x, z, 40, r.salt + 7)) * smoothstep(0, r.peak.radius, r.peak.radius - math.sqrt((x - r.peak.center.X) ^ 2 + (z - r.peak.center.Y) ^ 2))
	end
	if r.dunes then
		-- Long dune ridges that run north-south.
		local ridge = 1 - math.abs(noise(x / 2.2, z, r.dunes.scale, r.salt + 5))
		h += r.dunes.amplitude * ridge * ridge
	end
	return h
end

-- Roads -----------------------------------------------------------------------------------------------------------
-- Each road is cut into short pieces with a height at each end. The heights follow the land, smoothed, never steeper
-- than MaxGrade, and never under the sea (over water a road becomes a causeway).

local roadPieces = {} -- { ax, az, bx, bz, ha, hb, road }
local roadGrid = {} -- cell key -> list of pieces

local function gridKey(cx, cz)
	return cx * 65536 + cz
end

-- Land height before roads are cut in (used to lay the roads themselves).
local baseHeight -- forward declared, set below

local function addPiece(piece)
	table.insert(roadPieces, piece)
	local reach = ROAD_HALF + ROAD_BLEND + 4
	local x0 = math.floor((math.min(piece[1], piece[3]) - reach) / CELL)
	local x1 = math.floor((math.max(piece[1], piece[3]) + reach) / CELL)
	local z0 = math.floor((math.min(piece[2], piece[4]) - reach) / CELL)
	local z1 = math.floor((math.max(piece[2], piece[4]) + reach) / CELL)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local key = gridKey(cx, cz)
			local list = roadGrid[key]
			if not list then
				list = {}
				roadGrid[key] = list
			end
			table.insert(list, piece)
		end
	end
end

-- Nearest road piece to a point: distance, road height there, the road's name, and the nearest point on its center
-- line (x, z). nil when none is close.
local function nearestRoad(x, z)
	local list = roadGrid[gridKey(math.floor(x / CELL), math.floor(z / CELL))]
	if not list then
		return nil
	end
	local best, bestH, bestRoad, bestX, bestZ = math.huge, 0, nil, x, z
	for _, p in list do
		local d, t = segment(x, z, p[1], p[2], p[3], p[4])
		if d < best then
			best, bestH, bestRoad = d, lerp(p[5], p[6], t), p[7]
			bestX, bestZ = lerp(p[1], p[3], t), lerp(p[2], p[4], t)
		end
	end
	return best, bestH, bestRoad, bestX, bestZ
end
WorldShape.nearestRoad = nearestRoad

local function layRoads()
	local STEP = 8
	local laid = {} -- earlier roads' samples, for joining junctions
	for _, road in Map.Roads do
		-- Sample points along the road.
		local samples = {}
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			local n = math.max(1, math.ceil((b - a).Magnitude / STEP))
			for k = (i == 1 and 0 or 1), n do
				local p = a:Lerp(b, k / n)
				table.insert(samples, { x = p.X, z = p.Y, h = 0, pin = nil :: number? })
			end
		end
		for _, s in samples do
			-- Ports, plazas and the highway ends are flat zones: the road arrives at their height, so a truck rolls
			-- straight onto a pier or the highway deck with no step.
			s.h = math.max(WorldShape.applyFlats(s.x, s.z, baseHeight(s.x, s.z)), SEA + 2.5)
			for _, zone in Map.Flat do
				if rectDistance(s.x, s.z, zone.min, zone.max) <= 0 then
					s.pin = zone.height
				end
			end
			-- Meadow's own roads arrive flat at height 0 at its edge.
			if meadowDistance(s.x, s.z) < 1 then
				s.pin = 0
			end
			-- A road that starts or ends on an earlier road joins it at that road's height.
			for _, other in laid do
				if (other.x - s.x) ^ 2 + (other.z - s.z) ^ 2 < 36 then
					s.pin = other.h
					break
				end
			end
		end
		-- Smooth the heights, then keep the grade gentle in both directions.
		local n = #samples
		for _ = 1, 4 do
			local smoothed = table.create(n)
			for i = 1, n do
				local sum, count = 0, 0
				for k = math.max(1, i - 8), math.min(n, i + 8) do
					sum += samples[k].h
					count += 1
				end
				smoothed[i] = sum / count
			end
			for i = 1, n do
				samples[i].h = samples[i].pin or math.max(smoothed[i], SEA + 2.5)
			end
		end
		local rise = Map.MaxGrade * STEP
		for i = 2, n do
			local s, prev = samples[i], samples[i - 1]
			if not s.pin then
				s.h = math.clamp(s.h, prev.h - rise, prev.h + rise)
			end
		end
		for i = n - 1, 1, -1 do
			local s, nxt = samples[i], samples[i + 1]
			if not s.pin then
				s.h = math.clamp(s.h, nxt.h - rise, nxt.h + rise)
			end
		end
		for i = 1, n - 1 do
			local a, b = samples[i], samples[i + 1]
			addPiece({ a.x, a.z, b.x, b.z, a.h, b.h, road.name })
		end
		for _, s in samples do
			table.insert(laid, s)
		end
	end
end

-- The highway deck height at an X along the Longstitch Highway (Config Highway.Profile).
function WorldShape.highwayY(x)
	local profile = Map.Highway.Profile
	if x <= profile[1][1] then
		return profile[1][2]
	end
	for i = 1, #profile - 1 do
		local a, b = profile[i], profile[i + 1]
		if x <= b[1] then
			return lerp(a[2], b[2], (x - a[1]) / (b[1] - a[1]))
		end
	end
	return profile[#profile][2]
end

-- Distance from the highway's center line, and the X along it.
function WorldShape.highwayDistance(x, z)
	local hw = Map.Highway
	local d, t = segment(x, z, hw.from.X, hw.from.Y, hw.to.X, hw.to.Y)
	return d, lerp(hw.from.X, hw.to.X, t)
end

-- Height ------------------------------------------------------------------------------------------------------------

-- How much land there is here (positive = land) and the land height, before roads and special features.
local UNION = 7 -- how readily neighboring regions merge into one coast (higher = sharper, more separate)

local function landShape(x, z)
	local sum, weight = 0, 0
	local union = 0
	local best, bestInside = nil, -math.huge

	-- Meadow counts as a region whose land reaches MeadowShore past its square, at its own edge height.
	local dm = meadowDistance(x, z)
	local meadowInside = 1 - dm / Map.MeadowShore
	if meadowInside > -0.4 then
		local edgeH = MeadowTerrain.heightAt(math.clamp(x, -HALF, HALF), math.clamp(z, -HALF, HALF))
		local w = (meadowInside + 0.4) ^ 2
		-- Away from the edge the meadow's hills settle down to gentle country.
		local h = lerp(edgeH, 10 + 6 * noise(x, z, 120, 0.3), smoothstep(0, Map.MeadowShore, dm))
		sum += h * w
		weight += w
		union += math.exp(UNION * meadowInside)
	end

	for _, r in regions do
		local v = inside(r, x, z)
		if v > -0.4 then
			local w = (v + 0.4) ^ 2
			sum += regionHeight(r, x, z) * w
			weight += w
			union += math.exp(UNION * v)
			if v > bestInside then
				best, bestInside = r, v
			end
		end
	end

	-- A soft union: two regions that nearly touch share one coast instead of leaving a thin strait between them.
	local landness = union > 0 and math.log(union) / UNION or -1
	landness += 0.04 * noise(x, z, 110, 21)

	local land = weight > 0 and sum / weight or 0
	-- The coast: land drops away under the sea as landness goes below zero.
	local coast = smoothstep(-0.07, 0.09, landness)
	local floor = Map.SeaFloor + 6 * noise(x, z, 90, 9)
	local h = lerp(floor, land, coast)

	-- Right at Meadow's square the ground meets its edge exactly.
	if dm < Map.MeadowBlend then
		local edgeH = MeadowTerrain.heightAt(math.clamp(x, -HALF, HALF), math.clamp(z, -HALF, HALF))
		h = lerp(edgeH, h, smoothstep(0, Map.MeadowBlend, dm))
	end
	return h, landness, best, bestInside, dm
end

local function applyFlats(x, z, h)
	local zoneMaterial = nil
	for _, zone in Map.Flat do
		local d = rectDistance(x, z, zone.min, zone.max)
		if d < zone.blend then
			local f = 1 - smoothstep(0, zone.blend, d)
			h = lerp(h, zone.height, f)
			if d <= 0 and zone.material then
				zoneMaterial = zone.material
			end
		end
	end
	return h, zoneMaterial
end
WorldShape.applyFlats = applyFlats

local function bowl(x, z, h, def)
	local d = math.sqrt((x - def.center.X) ^ 2 + (z - def.center.Y) ^ 2)
	if d < def.radius + 50 then
		-- Level shore, then a bowl that holds water.
		h = lerp(h, def.level + 1.5, 1 - smoothstep(def.radius, def.radius + 50, d))
		if d < def.radius + 6 then
			h = math.min(h, def.level + 1 - def.depth * (1 - smoothstep(def.radius * 0.3, def.radius + 6, d)))
		end
	end
	return h, d
end

baseHeight = function(x, z)
	local h = landShape(x, z)
	h = applyFlats(x, z, h)
	return h
end

-- Everything about one column of ground: height, the water surface over it (or nil), the surface material name and
-- the region it belongs to. slope is filled in by the caller when it has neighbors (WorldTerrain).
function WorldShape.column(x, z)
	local h, landness, region, _, dm = landShape(x, z)
	local material = nil
	local water = nil
	local h0

	h, material = applyFlats(x, z, h)

	-- Sea lanes stay deep so the ferries clear the bottom. They only deepen sea that is already there.
	for _, lane in Map.Channels do
		local d = segment(x, z, lane.from.X, lane.from.Y, lane.to.X, lane.to.Y)
		if d < lane.width / 2 + 40 and h < SEA - 2 then
			h = math.min(h, lerp(lane.depth, h, smoothstep(lane.width / 2, lane.width / 2 + 40, d)))
		end
	end

	-- Mirror Lake and the desert oasis.
	local ld
	h, ld = bowl(x, z, h, Map.Lake)
	if ld < Map.Lake.radius + 8 and h < Map.Lake.level then
		water = Map.Lake.level
	end
	local od
	h, od = bowl(x, z, h, Map.Oasis)
	if od < Map.Oasis.radius + 6 and h < Map.Oasis.level then
		water = Map.Oasis.level
	end

	-- Bog pools in the swamp.
	if region and region.pools and landness > 0.05 then
		local p = region.pools
		local n = noise(x, z, p.scale, region.salt + 11)
		if n < p.threshold then
			local deep = smoothstep(p.threshold, p.threshold - 0.15, n)
			h = math.min(h, lerp(h, p.level - 3, deep))
			if h < p.level then
				water = p.level
			end
		end
	end

	-- Roads cut and fill the land to their own height.
	h0 = h
	local roadD, roadH = nearestRoad(x, z)
	local onRoad = false
	if roadD and roadD < ROAD_HALF + ROAD_BLEND then
		h = lerp(h, roadH, 1 - smoothstep(ROAD_HALF, ROAD_HALF + ROAD_BLEND, roadD))
		onRoad = roadD < ROAD_HALF + noise(x, z, 9, 4) * 1.5
		if onRoad and water and h >= water then
			water = nil
		end
	end

	-- The Longstitch Highway is parts: keep the sea under its bridge, and dig a bed for the undersea tube.
	local hwD, hwX = WorldShape.highwayDistance(x, z)
	local tube = nil
	local hw = Map.Highway
	if hwD < hw.width / 2 + 6 and hwX > hw.Profile[2][1] and hwX < hw.Profile[#hw.Profile][1] - 20 then
		local deck = WorldShape.highwayY(hwX)
		if deck < SEA + 2 then
			-- Inside the tube is air; the sea starts above its roof.
			tube = { floor = deck - 1, roof = deck + hw.tubeTop + 1.5 }
			h = math.min(h, deck - 1.5)
		end
	end

	-- Sea over anything below sea level that isn't Meadow.
	if not water and h < SEA and dm > 0 then
		water = SEA
	end

	-- Surface material.
	if not material then
		if onRoad then
			material = "Ground"
		elseif water and h < water - 0.5 then
			material = (h < SEA - 14) and "Slate" or (region and region.materials.beach == "Mud" and "Mud" or "Sand")
		elseif not region or landness < -0.1 then
			material = h < SEA + 3 and "Sand" or "LeafyGrass"
		else
			local m = region.materials
			if h < SEA + 2.5 and landness < 0.2 then
				material = m.beach
			elseif region.snowLine and h > region.snowLine then
				material = noise(x, z, 30, 12) > 0.25 and "Glacier" or "Snow"
			elseif region.peak and region.peak.crater then
				local pd = math.sqrt((x - region.peak.center.X) ^ 2 + (z - region.peak.center.Y) ^ 2)
				if pd < region.peak.crater * 0.8 then
					material = "CrackedLava"
				elseif region.lavaRivers and pd < region.peak.radius * 0.95 and math.abs(noise(x, z, 60, 13)) < 0.025 then
					material = "CrackedLava"
				end
			end
			if not material then
				material = noise(x, z, 45, region.salt + 6) > 0.25 and m.alt or m.top
			end
		end
	end
	-- Grass blades only grow on the Grass material; nothing out here uses it, so the ground stays clear to see.
	if material == "Grass" then
		material = "LeafyGrass"
	end
	return h, water, material, region, tube, h0
end

-- Ground height at a point (roads and flats included).
function WorldShape.heightAt(x, z)
	if WorldShape.inMeadow(x, z) then
		return MeadowTerrain.heightAt(x, z)
	end
	local h = WorldShape.column(x, z)
	return h
end

-- The region a point belongs to (nil out at sea or in Meadow).
function WorldShape.regionAt(x, z)
	local _, landness, region = landShape(x, z)
	if landness < 0 then
		return nil
	end
	return region
end

-- The cliff material for steep ground at a point.
function WorldShape.cliffAt(region)
	return region and region.materials.cliff or "Rock"
end

layRoads()

return WorldShape

end

MODULES["Services.Regions"] = function(script)
-- Everything standing on the Stitched Isles outside Meadow: each region's trees in its own LT2 style, rocks, hay
-- fields with that region's hay, signposts, and the landmarks from the world map (the Homestead hub, the Spindle
-- door and cave, the lighthouse, the pyramid, the wreck, the quarry, the Weaver's workshop and more).
-- Placement uses a fixed seed, so every server looks alike. Ground heights come from WorldShape, the same math the
-- terrain was written from, so nothing waits for the terrain to finish.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local GloveConfig = require(Shared.Config.Gloves)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local WorldShape = require(script.Parent.WorldShape)
local Bales = require(script.Parent.Bales)
local Props = require(script.Parent.Props)
local Data = require(script.Parent.Data)

local Regions = {}

local IRON = Color3.new(0.48, 0.48, 0.47) -- weathered grey iron (BUILD_REGISTRY.md), never rusty orange
local SNOW = Color3.fromRGB(226, 228, 226)
local BARN_RED = Color3.fromRGB(133, 61, 48) -- the Meadow accent, for anything outside a region

-- The region's accent (Config/WorldMap style, from STYLE.md Regions) at a point: one sign or trim per building.
local function accentAt(x, z)
	local region = WorldShape.regionAt(x, z)
	return region and region.style and region.style.accent or BARN_RED
end

-- Tree colors from the STYLE.md region sheet (mid shades). Regions not on the sheet keep the house palette.
local PALETTE = {
	pine = { leaves = Color3.fromRGB(48, 76, 59), bark = Color3.fromRGB(66, 51, 38) },
	snow = { leaves = Color3.fromRGB(54, 76, 71), bark = Color3.fromRGB(71, 64, 56) },
	desert = { leaves = Color3.fromRGB(107, 128, 89), bark = Color3.fromRGB(122, 110, 94) },
	swamp = { leaves = Color3.fromRGB(74, 92, 54), bark = Color3.fromRGB(59, 54, 46) },
}
local palette: { leaves: Color3?, bark: Color3? } = {} -- the region being planted right now (set in Regions.build)
local SEA = Map.SeaLevel

-- Every hay field in the world, for the rich field rotation: { region, center, bales = { bale record } }
Regions.fields = {}

-- Parts ---------------------------------------------------------------------------------------------------------

local function part(parent, name, size, cframe, color, material, shape, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	if collide == false then
		p.CanCollide = false
	end
	p.Parent = parent
	return p
end

local function wedge(parent, name, size, cframe, color, material)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- A cylinder standing upright (Roblox cylinders lie along X).
local function post(parent, name, height, thick, base, color, material, collide)
	return part(parent, name, Vector3.new(height, thick, thick), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder, collide)
end

local function light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1
	l.Shadows = false
	l.Parent = p
	return l
end

local function ground(x, z)
	return WorldShape.heightAt(x, z)
end

local function at(x, z, yOffset)
	return Vector3.new(x, ground(x, z) + (yOffset or 0), z)
end

-- A spot on the ground facing a direction (Vector2).
local function spot(x, z, facing, y)
	local p = Vector3.new(x, y or ground(x, z), z)
	facing = facing or Vector2.new(0, -1)
	return CFrame.lookAt(p, p + Vector3.new(facing.X, 0, facing.Y))
end

-- A label floating over a part, seen from a distance.
local function billboard(parent, text, offset, distance)
	return WorldLabel.billboard(parent, text, {
		offset = offset or Vector3.new(0, 6, 0),
		kind = "sign",
		distance = distance or 140,
		color = Color3.fromRGB(240, 232, 210),
		-- Landmarks read from far away get bigger letters.
		studs = (distance or 140) > 300 and 10 or nil,
	})
end
Regions.billboard = billboard

local function boardText(board, text, faces)
	return WorldLabel.surface(board, text, faces or { Enum.NormalId.Front, Enum.NormalId.Back })
end

-- Moves a point off any road, out to clearance studs past its edge (signs placed by hand must never stand in a lane).
local ROAD_HALF = Map.RoadWidth / 2
local function offRoad(x, z, clearance)
	for _ = 1, 12 do
		local d = WorldShape.nearestRoad(x, z)
		if not d or d >= ROAD_HALF + clearance then
			break
		end
		-- Step away from the center line: the direction in which the distance grows.
		local function far(px, pz)
			return WorldShape.nearestRoad(px, pz) or ROAD_HALF + clearance + 50
		end
		local g = Vector2.new(far(x + 1, z) - far(x - 1, z), far(x, z + 1) - far(x, z - 1))
		if g.Magnitude < 1e-3 then
			g = Vector2.new(1, 0)
		end
		g = g.Unit * (ROAD_HALF + clearance - d + 0.5)
		x += g.X
		z += g.Y
	end
	return x, z
end
Regions.offRoad = offRoad

-- A wooden board on a post, readable from both sides. Never on a road: it steps to the roadside.
local function signpost(parent, x, z, facing, text, width)
	width = width or 11
	-- The board can stand across the road's direction, so keep half its width clear as well.
	x, z = offRoad(x, z, width / 2 + 2)
	local model = Instance.new("Model")
	model.Name = "Signpost"
	local base = spot(x, z, facing)
	part(model, "Post", Vector3.new(0.6, 7, 0.6), base * CFrame.new(0, 3, 0.4), Rustic.WoodDark, Enum.Material.Wood)
	local board = part(model, "Board", Vector3.new(width, 3.6, 0.4), base * CFrame.new(0, 6.2, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	part(model, "Trim", Vector3.new(width + 0.4, 0.4, 0.6), base * CFrame.new(0, 8.2, 0), accentAt(x, z), Enum.Material.WoodPlanks)
	boardText(board, text)
	model.Parent = parent
	return model
end
Regions.signpost = signpost

-- A simple plank building: four walls with a door gap in front, a gable roof. Used as the collision shell and as the
-- look until a Blender building of that name is imported (then the mesh rides on it, PropMeshes.client.luau).
-- Blender batch 2 props (hub, regions, scatter) that face -Z already; every other building prop faces +Z.
local FORWARD_PROPS = {
	trading_post = true,
	homestead_bank = true,
	pine_lodge = true,
	snow_cabin = true,
	haunted_barn = true,
	volcano_forge = true,
	swamp_stilt_house = true,
	bobbin_captain_shack = true,
	land_office = true,
}

local function building(parent, name, cframe, w, d, h, opts)
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = name
	local wall = opts.wall or Rustic.Wood
	local roofColor = opts.roof or Rustic.PaintRedDark
	local material = opts.material or Enum.Material.WoodPlanks
	local t = 0.8
	local door = math.min(opts.door or 8, w - 4)
	local floor = part(model, "Floor", Vector3.new(w, 1, d), cframe * CFrame.new(0, 0.5, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	part(model, "Back", Vector3.new(w, h, t), cframe * CFrame.new(0, h / 2 + 1, d / 2 - t / 2), wall, material)
	for _, side in { -1, 1 } do
		part(model, "Side", Vector3.new(t, h, d), cframe * CFrame.new(side * (w / 2 - t / 2), h / 2 + 1, 0), wall, material)
		local front = (w - door) / 2
		part(model, "Front", Vector3.new(front, h, t), cframe * CFrame.new(side * (w / 2 - front / 2), h / 2 + 1, -d / 2 + t / 2), wall, material)
	end
	-- The lintel over the door is the one trim in the region's accent color.
	part(model, "Lintel", Vector3.new(door, h * 0.3, t), cframe * CFrame.new(0, h * 0.85 + 1, -d / 2 + t / 2), accentAt(cframe.X, cframe.Z), material)
	-- Gable roof: two slabs meeting over the middle.
	local rise = math.min(w, d) * 0.3
	local slant = math.sqrt((w / 2) ^ 2 + rise ^ 2) + 0.6
	local angle = math.atan2(rise, w / 2)
	for _, side in { -1, 1 } do
		part(
			model,
			"Roof",
			Vector3.new(slant, 0.8, d + 1.6),
			cframe * CFrame.new(side * w / 4, h + 1 + rise / 2, 0) * CFrame.Angles(0, 0, -side * angle),
			roofColor,
			Enum.Material.WoodPlanks
		)
	end
	for _, side in { -1, 1 } do
		wedge(model, "Gable", Vector3.new(0.6, rise, w / 2), cframe * CFrame.new(side * w / 4, h + 1 + rise / 2, d / 2 - t / 2) * CFrame.Angles(0, side * math.pi / 2, 0), wall, material)
	end
	if opts.sign then
		local board = part(model, "Sign", Vector3.new(math.min(w - 2, 16), 2.4, 0.3), cframe * CFrame.new(0, h + 0.2, -d / 2 - 0.2), Rustic.PaintCream, Enum.Material.WoodPlanks)
		boardText(board, opts.sign, { Enum.NormalId.Front })
	end
	-- Night lights (#26): a lantern beside the door and a warm glow inside that spills out of the doorway. Their
	-- names hold "Lantern" / "Lamp", so WorldClock switches them on at dusk and off at dawn.
	if opts.lit ~= false then
		local lantern = part(model, "DoorLantern", Vector3.new(0.8, 1.2, 0.8), cframe * CFrame.new(door / 2 + 1.2, math.min(h * 0.6, 7) + 1, -d / 2 - 1), Color3.fromRGB(255, 196, 110), Enum.Material.Neon, nil, false)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 120)
		light.Range = 16
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = lantern
		local inside = part(model, "LampGlow", Vector3.new(1, 1, 1), cframe * CFrame.new(0, h * 0.6 + 1, 0), Color3.fromRGB(255, 196, 110), Enum.Material.Neon, nil, false)
		inside.Transparency = 1
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 180, 110)
		glow.Range = math.min(24, math.max(w, d))
		glow.Brightness = 1.5
		glow.Shadows = false
		glow.Parent = inside
	end
	model.PrimaryPart = floor
	-- With StreamingEnabled: a building streams in whole (never a roof without walls), and from far away it still
	-- shows as a low-detail mesh, so the skyline never pops.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	-- The Blender building of this kind, when imported, takes over the look. Its front faces cframe's LookVector.
	-- The older buildings (mill, warehouse, museum...) were exported front at +Z, hence their half turn, stretched to
	-- the box. The hub and region props (Blender batch 2) already face -Z: no turn, scaled evenly to the footprint
	-- and stood on the floor.
	if opts.prop and Props.has(opts.prop) then
		local mesh
		if FORWARD_PROPS[opts.prop] then
			mesh = Props.make(opts.prop, cframe * CFrame.new(0, h / 2 + 1, 0), math.max(w, d) + 1)
			if mesh then
				local box, size = mesh:GetBoundingBox()
				mesh:PivotTo(mesh:GetPivot() + Vector3.new(0, (cframe.Y + 1) - (box.Y - size.Y / 2), 0))
			end
		else
			mesh = Props.make(opts.prop, cframe * CFrame.new(0, (h + rise) / 2 + 1, 0), Vector3.new(w + 1, h + rise + 1, d + 1), CFrame.Angles(0, math.pi, 0))
		end
		if mesh then
			Props.weldTo(mesh, floor, model)
		end
	end
	model.Parent = parent
	return model
end
Regions.building = building

-- A townsperson: a blocky figure in work clothes with a name over their head and a Talk prompt. Tagged "QuestGiver"
-- with a QuestGiver id, so the quest system can take the prompt over (set QuestHandled on the model and it stops
-- saying its own lines). Until then each one says its lines in turn.
local function townsperson(parent, id, name, cframe, shirt, lines)
	local model = Instance.new("Model")
	model.Name = name
	local skin = Color3.fromRGB(204, 162, 128)
	for _, side in { -1, 1 } do
		part(model, "Leg", Vector3.new(0.9, 2.6, 1), cframe * CFrame.new(side * 0.5, 1.3, 0), Rustic.WoodDark, Enum.Material.Fabric)
		part(model, "Arm", Vector3.new(0.8, 2.4, 0.9), cframe * CFrame.new(side * 1.45, 3.6, 0), shirt, Enum.Material.Fabric)
	end
	local torso = part(model, "Torso", Vector3.new(2, 2.4, 1.1), cframe * CFrame.new(0, 3.8, 0), shirt, Enum.Material.Fabric)
	local head = part(model, "Head", Vector3.new(1.2, 1.2, 1.2), cframe * CFrame.new(0, 5.6, 0), skin, Enum.Material.SmoothPlastic)
	part(model, "HatBrim", Vector3.new(2.2, 0.15, 2.2), cframe * CFrame.new(0, 6.25, 0), Rustic.Cloth, Enum.Material.Fabric)
	part(model, "HatTop", Vector3.new(1.3, 0.6, 1.3), cframe * CFrame.new(0, 6.6, 0), Rustic.Cloth, Enum.Material.Fabric)
	model.PrimaryPart = torso
	for _, p in model:GetChildren() do
		p.CanCollide = false
	end
	billboard(head, name, Vector3.new(0, 2.2, 0), 60)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = name
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = torso
	model:SetAttribute("QuestGiver", id)
	model:SetAttribute("Lines", table.concat(lines, "\n")) -- Quests says them once it takes the prompt over
	CollectionService:AddTag(model, "QuestGiver")
	local turn = setmetatable({}, { __mode = "k" }) -- players who left drop out on their own
	prompt.Triggered:Connect(function(player)
		if model:GetAttribute("QuestHandled") then
			return
		end
		local i = (turn[player] or 0) % #lines + 1
		turn[player] = i
		if Data.get(player) then
			Data.toast(player, ("%s: %s"):format(name, lines[i]))
		end
	end)
	model.Parent = parent
	return model
end
Regions.townsperson = townsperson

-- Trees in each region's style ---------------------------------------------------------------------------------

local TREES = {}

function TREES.oak(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local height = rng:NextNumber(10, 14) * s
	local thick = rng:NextNumber(1.4, 1.9) * s
	post(model, "Trunk", height, thick, base, Rustic.Bark, Enum.Material.Wood)
	local colors = { Rustic.Leaves, Rustic.LeavesDark, Rustic.LeavesDry }
	for i = 1, 3 do
		local size = Vector3.new(rng:NextNumber(6, 9), rng:NextNumber(4, 6), rng:NextNumber(6, 9)) * s
		local offset = Vector3.new(rng:NextNumber(-2.5, 2.5) * s, height + rng:NextNumber(-1.5, 2.5), rng:NextNumber(-2.5, 2.5) * s)
		part(model, "Leaves", size, base * CFrame.new(offset) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), colors[rng:NextInteger(1, 3)], Enum.Material.Grass, nil, false)
	end
	model.Parent = parent
end

local function pineTiers(model, base, height, s, rng, color, snowy)
	local tiers = 3
	for i = 1, tiers do
		local k = 1 - (i - 1) / tiers
		local size = Vector3.new(9 * k + 2, 4.2, 9 * k + 2) * Vector3.new(s, s, s)
		local y = height * (0.42 + (i - 1) * 0.22)
		local cf = base * CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(45 * i) + rng:NextNumber(-0.2, 0.2), 0)
		part(model, "Needles", size, cf, color, Enum.Material.Grass, nil, false)
		if snowy then
			part(model, "Snow", Vector3.new(size.X * 0.85, 0.8, size.Z * 0.85), cf * CFrame.new(0, size.Y / 2 + 0.3, 0), SNOW, Enum.Material.Snow, nil, false)
		end
	end
end

function TREES.pine(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "PineTree"
	local height = rng:NextNumber(18, 26) * s
	post(model, "Trunk", height, rng:NextNumber(1.3, 1.8) * s, base, palette.bark or Rustic.Bark, Enum.Material.Wood)
	local dark = rng:NextNumber() < 0.5
	pineTiers(model, base, height, s, rng, palette.leaves and (dark and palette.leaves:Lerp(Color3.new(), 0.15) or palette.leaves) or (dark and Rustic.LeavesDark or Color3.fromRGB(62, 80, 54)), false)
	model.Parent = parent
end

function TREES.snowpine(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "SnowPine"
	local height = rng:NextNumber(16, 22) * s
	post(model, "Trunk", height, rng:NextNumber(1.2, 1.6) * s, base, palette.bark or Rustic.Bark, Enum.Material.Wood)
	pineTiers(model, base, height, s, rng, palette.leaves or Color3.fromRGB(64, 82, 66), true)
	model.Parent = parent
end

function TREES.dead(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "DeadTree"
	local bark = palette.bark or Color3.fromRGB(58, 50, 52)
	local height = rng:NextNumber(12, 18) * s
	local thick = rng:NextNumber(1.2, 1.7) * s
	local lean = CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12))
	post(model, "Trunk", height, thick, base * lean, bark, Enum.Material.Wood)
	for i = 1, 3 do
		local length = height * rng:NextNumber(0.25, 0.4)
		local cf = base
			* lean
			* CFrame.new(0, height * (0.45 + i * 0.13), 0)
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(35, 65)))
			* CFrame.new(0, length / 2, 0)
		part(model, "Branch", Vector3.new(length, thick * 0.45, thick * 0.45), cf * CFrame.Angles(0, 0, math.pi / 2), bark, Enum.Material.Wood, Enum.PartType.Cylinder, false)
	end
	model.Parent = parent
end

function TREES.charred(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "CharredTree"
	local height = rng:NextNumber(6, 11) * s
	local thick = rng:NextNumber(1.1, 1.6) * s
	post(model, "Trunk", height, thick, base * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), Color3.fromRGB(38, 34, 32), Enum.Material.Slate)
	local length = height * 0.4
	local cf = base * CFrame.new(0, height * 0.7, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(50)) * CFrame.new(0, length / 2, 0)
	part(model, "Branch", Vector3.new(length, thick * 0.4, thick * 0.4), cf * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(38, 34, 32), Enum.Material.Slate, Enum.PartType.Cylinder, false)
	model.Parent = parent
end

function TREES.palm(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "PalmTree"
	local height = rng:NextNumber(14, 20) * s
	local bend = rng:NextNumber(0.1, 0.25)
	local turn = base * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local half = height / 2
	local lower = turn * CFrame.Angles(bend * 0.5, 0, 0)
	post(model, "Trunk", half + 0.4, 1.3 * s, lower, Rustic.Wood, Enum.Material.Wood)
	local upper = lower * CFrame.new(0, half, 0) * CFrame.Angles(bend, 0, 0)
	post(model, "Trunk", half, 1.1 * s, upper, Rustic.Wood, Enum.Material.Wood)
	local crown = upper * CFrame.new(0, half, 0)
	for i = 1, 5 do
		local leaf = crown * CFrame.Angles(0, i * math.pi * 2 / 5, 0) * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(0, 0, -3.5 * s)
		part(model, "Frond", Vector3.new(2.2 * s, 0.3, 7 * s), leaf, Color3.fromRGB(96, 120, 70), Enum.Material.Grass, nil, false)
	end
	model.Parent = parent
end

function TREES.cactus(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "Cactus"
	local green = Color3.fromRGB(92, 116, 74)
	local height = rng:NextNumber(5, 9) * s
	post(model, "Stem", height, 1.6 * s, base, green, Enum.Material.Grass)
	for _, side in { -1, 1 } do
		if rng:NextNumber() < 0.75 then
			local y = height * rng:NextNumber(0.35, 0.6)
			part(model, "Arm", Vector3.new(1.8 * s, 1, 1) * Vector3.new(1, s, s), base * CFrame.new(side * 1.3 * s, y, 0), green, Enum.Material.Grass, nil, false)
			post(model, "ArmUp", height * 0.35, 1.0 * s, base * CFrame.new(side * 2 * s, y, 0), green, Enum.Material.Grass, false)
		end
	end
	model.Parent = parent
end

function TREES.willow(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "Willow"
	local height = rng:NextNumber(10, 14) * s
	post(model, "Trunk", height, 1.8 * s, base * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1)), Color3.fromRGB(70, 62, 50), Enum.Material.Wood)
	local canopy = base * CFrame.new(0, height, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	part(model, "Canopy", Vector3.new(12, 3, 12) * Vector3.new(s, 1, s), canopy, palette.leaves or Rustic.LeavesDark, Enum.Material.Grass, nil, false)
	for _, side in { -1, 1 } do
		part(model, "Drape", Vector3.new(11 * s, height * 0.55, 1.2), canopy * CFrame.new(0, -height * 0.27, side * 5.2 * s), Color3.fromRGB(84, 98, 60), Enum.Material.Grass, nil, false)
	end
	model.Parent = parent
end

function TREES.reeds(parent, base, s, rng)
	local model = Instance.new("Model")
	model.Name = "Reeds"
	for _ = 1, 3 do
		local cf = base * CFrame.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2)) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15))
		post(model, "Reed", rng:NextNumber(4, 6) * s, 0.35, cf, Color3.fromRGB(110, 120, 70), Enum.Material.Grass, false)
	end
	model.Parent = parent
end

function TREES.crystal(parent, base, s, rng)
	local colors = { Color3.fromRGB(176, 150, 220), Color3.fromRGB(140, 196, 214), Color3.fromRGB(214, 160, 190) }
	local color = colors[rng:NextInteger(1, 3)]
	local height = rng:NextNumber(4, 9) * s
	local p = part(parent, "Crystal", Vector3.new(1.6 * s, height, 1.6 * s), base * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)) * CFrame.new(0, height / 2, 0), color, Enum.Material.Neon)
	p.Transparency = 0.15
	if rng:NextNumber() < 0.4 then
		light(p, color, 18, 0.8)
	end
end

-- How many of each kind of tree grow in each region.
local PLANTING = {
	shore = { { "oak", 45 } },
	valley = { { "oak", 75 }, { "pine", 14 } },
	homestead = { { "oak", 40 } },
	spindle = { { "pine", 30 } },
	pine = { { "pine", 190 }, { "oak", 10 } },
	haunted = { { "dead", 110 } },
	snow = { { "snowpine", 110 } },
	volcano = { { "charred", 55 } },
	desert = { { "cactus", 70 } },
	swamp = { { "willow", 60 }, { "reeds", 45 } },
	keys = { { "palm", 70 } },
	bobbin = { { "dead", 14 } },
}

local ROCK_COLORS = {
	default = { Rustic.Stone, Rustic.StoneDark, Rustic.Rock },
	snow = { Color3.fromRGB(150, 150, 156), Color3.fromRGB(120, 120, 128) },
	volcano = { Color3.fromRGB(64, 58, 56), Color3.fromRGB(44, 40, 40) },
	desert = { Color3.fromRGB(186, 156, 112), Color3.fromRGB(160, 132, 96) },
	haunted = { Color3.fromRGB(80, 76, 84), Color3.fromRGB(60, 58, 64) },
}

-- Placement -----------------------------------------------------------------------------------------------------

local taken = {} -- grid cell -> list of Vector2 already used

local function crowded(x, z, gap)
	local cx, cz = math.floor(x / 32), math.floor(z / 32)
	for i = cx - 1, cx + 1 do
		for k = cz - 1, cz + 1 do
			for _, p in taken[i * 65536 + k] or {} do
				if (p.X - x) ^ 2 + (p.Y - z) ^ 2 < gap * gap then
					return true
				end
			end
		end
	end
	return false
end

local function claim(x, z)
	local key = math.floor(x / 32) * 65536 + math.floor(z / 32)
	taken[key] = taken[key] or {}
	table.insert(taken[key], Vector2.new(x, z))
end

-- Marks the ground under everything in a folder as taken, so no tree grows through a landmark.
local function claimParts(folder)
	for _, p in folder:GetDescendants() do
		if p:IsA("BasePart") then
			local cf, size = p.ExtentsCFrame, p.ExtentsSize
			local nx, nz = math.min(12, math.ceil(size.X / 8)), math.min(12, math.ceil(size.Z / 8))
			for i = 0, nx do
				for k = 0, nz do
					local at = cf * Vector3.new((i / nx - 0.5) * size.X, 0, (k / nz - 0.5) * size.Z)
					claim(at.X, at.Z)
				end
			end
		end
	end
end

-- Whether something can stand here: on dry, not too steep land, off roads, the highway and building spots.
local function buildable(x, z, margin)
	if WorldShape.inMeadow(x, z) then
		return false
	end
	local h, water, material = WorldShape.column(x, z)
	if water or h < SEA + 1.5 or material == "CrackedLava" then
		return false
	end
	local d = WorldShape.nearestRoad(x, z)
	if d and d < Map.RoadWidth / 2 + margin then
		return false
	end
	if WorldShape.highwayDistance(x, z) < Map.Highway.width / 2 + margin then
		return false
	end
	for _, zone in Map.Flat do
		if WorldShape.rectDistance(x, z, zone.min, zone.max) < margin then
			return false
		end
	end
	local sx = WorldShape.heightAt(x + 4, z) - WorldShape.heightAt(x - 4, z)
	local sz = WorldShape.heightAt(x, z + 4) - WorldShape.heightAt(x, z - 4)
	if math.sqrt(sx * sx + sz * sz) / 8 > 0.7 then
		return false
	end
	return true, h
end

-- A random spot inside a region's oval (well clear of its coast).
local function randomIn(r, rng)
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = math.sqrt(rng:NextNumber()) * 0.92
	return r.cx + math.cos(angle) * r.rx * radius, r.cz + math.sin(angle) * r.rz * radius
end

local function plant(folder, r, kind, count, rng)
	local placed, tries = 0, 0
	while placed < count and tries < count * 30 do
		tries += 1
		local x, z = randomIn(r, rng)
		if WorldShape.regionAt(x, z) ~= r or crowded(x, z, kind == "reeds" and 5 or 10) then
			continue
		end
		local ok, h = buildable(x, z, 6)
		if not ok then
			continue
		end
		-- Trees thin out high on the snow peak and the volcano.
		if (kind == "snowpine" and h > 190) or (kind == "charred" and h > 120) then
			continue
		end
		TREES[kind](folder, CFrame.new(x, h - 1, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng:NextNumber(0.85, 1.3), rng)
		claim(x, z)
		placed += 1
	end
	return placed
end

local function rocks(folder, r, count, rng)
	local colors = ROCK_COLORS[r.id] or ROCK_COLORS.default
	for _ = 1, count do
		local x, z = randomIn(r, rng)
		if WorldShape.regionAt(x, z) == r and not crowded(x, z, 6) then
			local ok, h = buildable(x, z, 4)
			if ok then
				local size = Vector3.new(rng:NextNumber(2, 8), rng:NextNumber(1.5, 5), rng:NextNumber(2, 7))
				local cf = CFrame.new(x, h + size.Y * 0.2, z) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.3, 0.3))
				part(folder, "Rock", size, cf, colors[rng:NextInteger(1, #colors)], Enum.Material.Slate)
				claim(x, z)
			end
		end
	end
end

-- Hay ---------------------------------------------------------------------------------------------------------------

-- Bale colors by hay, so each region's hay reads at a glance (the mesh, when imported, keeps its own straw look).
local HAY_TINT = {
	pine = Color3.fromRGB(158, 156, 102), -- STYLE.md Regions hay (mid shade)
	desert = Color3.fromRGB(209, 186, 133),
	snow = Color3.fromRGB(191, 184, 148),
	swamp = Color3.fromRGB(133, 128, 79),
	volcano = Color3.fromRGB(120, 96, 80),
	cave = Color3.fromRGB(170, 160, 196),
	sky = Color3.fromRGB(226, 220, 196),
	haunted = Color3.fromRGB(132, 120, 140),
	keys = Color3.fromRGB(214, 196, 150),
	bobbin = Color3.fromRGB(150, 140, 120),
}

local function tint(b, hayType)
	local color = HAY_TINT[hayType]
	if color and b and b.body then
		b.body.Color = color
	end
end

-- A field of bales around a point. y is the ground height there.
local function field(regionName, hayType, center, y, count, rng)
	local entry = { region = regionName, hayType = hayType, center = center, bales = {}, rich = false }
	local function track(b)
		if not b then
			return
		end
		tint(b, hayType)
		entry.bales[b] = true
		-- The bale that grows back is the same hay, and stays in this field.
		b.onRegrow = function(fresh)
			entry.bales[b] = nil
			track(fresh)
			if entry.rich and fresh then
				fresh.body:SetAttribute("NeedleBoost", 2)
				fresh.body:SetAttribute("RichBoost", true)
			end
		end
	end
	local placed = {}
	for _ = 1, count * 4 do
		if #placed >= count then
			break
		end
		local p = center + Vector3.new(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9))
		local ok = true
		for _, other in placed do
			if (other - p).Magnitude < 5.5 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(placed, p)
			local gy = y or WorldShape.heightAt(p.X, p.Z)
			track(Bales.spawn(Vector3.new(p.X, gy - 0.35, p.Z), true, false, hayType))
		end
	end
	table.insert(Regions.fields, entry)
	return entry
end

-- Fields beside the roads of a region, so a truck can pull up to them.
local FIELD_REACH = 60 -- a field's center at most this far from its road, so a trailer backs right up to it
local FIELD_SLOPE = 0.4 -- rise per stud a pickup and trailer can pull up between the road and the field

-- Can a truck with a trailer drive straight from (ax, az) to (bx, bz)? Dry the whole way and never too steep.
local function drivable(ax, az, bx, bz)
	local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local steps = math.max(1, math.floor(length / 4))
	local step = length / steps
	local last = nil
	for s = 0, steps do
		local t = s / steps
		local h, water = WorldShape.column(ax + (bx - ax) * t, az + (bz - az) * t)
		if water and water > h + 1 then
			return false
		end
		if last and math.abs(h - last) / step > FIELD_SLOPE then
			return false
		end
		last = h
	end
	return true
end
Regions.drivable = drivable

local function hayFields(r, rng)
	local made = 0
	for _ = 1, 400 do
		if made >= Map.FieldsPerRegion then
			break
		end
		local x, z = randomIn(r, rng)
		local d, _, _, rx, rz = WorldShape.nearestRoad(x, z)
		if WorldShape.regionAt(x, z) ~= r or not d or d < 24 or d > FIELD_REACH or crowded(x, z, 22) then
			continue
		end
		if not drivable(rx, rz, x, z) then
			continue
		end
		local ok, h = buildable(x, z, 18)
		if not ok then
			continue
		end
		-- The whole field must be fairly level.
		local level = true
		for _, o in { Vector2.new(10, 0), Vector2.new(-10, 0), Vector2.new(0, 10), Vector2.new(0, -10) } do
			if math.abs(WorldShape.heightAt(x + o.X, z + o.Y) - h) > 2.5 then
				level = false
				break
			end
		end
		if not level then
			continue
		end
		field(r.name, r.hayType, Vector3.new(x, h, z), nil, rng:NextInteger(Map.BalesPerField[1], Map.BalesPerField[2]), rng)
		for i = -1, 1 do
			for k = -1, 1 do
				claim(x + i * 10, z + k * 10)
			end
		end
		made += 1
	end
	if made == 0 and r.fieldFlat then
		for _, zone in Map.Flat do
			if zone.name == r.fieldFlat then
				local mid = (zone.min + zone.max) / 2
				field(r.name, r.hayType, Vector3.new(mid.X, zone.height, mid.Y), zone.height, rng:NextInteger(Map.BalesPerField[1], Map.BalesPerField[2]), rng)
			end
		end
	end
end

-- Farm life ------------------------------------------------------------------------------------------------------

-- The nearest open spot to (x, z): dry, gentle, off roads, and clear of anything already placed.
local function findSpot(x, z, margin)
	for radius = 0, 240, 12 do
		local steps = math.max(1, math.floor(radius / 6))
		for i = 0, steps - 1 do
			local a = i / steps * math.pi * 2
			local px, pz = x + math.cos(a) * radius, z + math.sin(a) * radius
			local ok, h = buildable(px, pz, margin)
			if ok and not crowded(px, pz, margin) then
				return px, pz, h
			end
		end
	end
	return nil
end

-- A windmill on a stone base. Its sails are their own model, tagged "WindmillSails"; Ambient.client.luau turns them.
local function windmill(folder, x, z)
	local px, pz, h = findSpot(x, z, 14)
	if not px then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Windmill"
	local base = CFrame.new(px, h - 1, pz) * CFrame.Angles(0, math.rad(30), 0)
	post(model, "Tower", 26, 10, base, Rustic.PaintCream, Enum.Material.WoodPlanks)
	post(model, "Footing", 3, 13, base * CFrame.new(0, -1, 0), Rustic.Stone, Enum.Material.Cobblestone)
	part(model, "Cap", Vector3.new(9, 5, 9), base * CFrame.new(0, 27.5, 0), Rustic.PaintRedDark, Enum.Material.WoodPlanks)
	part(model, "Door", Vector3.new(4, 7, 0.4), base * CFrame.new(0, 4.5, -5.1), Rustic.WoodDark, Enum.Material.WoodPlanks)
	local sails = Instance.new("Model")
	sails.Name = "WindmillSails"
	local hubCF = base * CFrame.new(0, 27, -5.2)
	local hub = part(sails, "Hub", Vector3.new(1.6, 2, 2), hubCF * CFrame.Angles(0, math.pi / 2, 0), IRON, Enum.Material.Metal, Enum.PartType.Cylinder, false)
	for i = 0, 3 do
		local arm = hubCF * CFrame.Angles(0, 0, i * math.pi / 2)
		part(sails, "Spar", Vector3.new(0.5, 18, 0.4), arm * CFrame.new(0, 9, -0.3), Rustic.WoodDark, Enum.Material.Wood, nil, false)
		part(sails, "Sail", Vector3.new(4, 14, 0.15), arm * CFrame.new(2.2, 10, -0.4), Rustic.Cloth, Enum.Material.Fabric, nil, false)
	end
	sails.PrimaryPart = hub
	-- Streams in whole, so the client never sees sails without their hub.
	sails.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	sails.Parent = model
	CollectionService:AddTag(sails, "WindmillSails")
	model.Parent = folder
	claim(px, pz)
	return model
end

-- A cow standing in a field, head down. Purely scenery: nothing collides, so it never blocks a truck.
local COW_COATS = { { Color3.fromRGB(236, 230, 218), Color3.fromRGB(46, 40, 36) }, { Color3.fromRGB(122, 78, 52), Color3.fromRGB(236, 230, 218) }, { Color3.fromRGB(70, 58, 48), Color3.fromRGB(70, 58, 48) } }
local function cow(folder, x, z, h, rng)
	local model = Instance.new("Model")
	model.Name = "Cow"
	local coat = COW_COATS[rng:NextInteger(1, #COW_COATS)]
	local base = CFrame.new(x, h, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local body = part(model, "Body", Vector3.new(3.2, 3, 6), base * CFrame.new(0, 3.6, 0), coat[1], Enum.Material.Fabric, nil, false)
	part(model, "Patch", Vector3.new(3.3, 1.8, 2.2), base * CFrame.new(0, 4, 0.8), coat[2], Enum.Material.Fabric, nil, false)
	part(model, "Head", Vector3.new(2, 2, 2.4), base * CFrame.new(0, 2.6, -3.8) * CFrame.Angles(math.rad(-35), 0, 0), coat[1], Enum.Material.Fabric, nil, false)
	part(model, "Muzzle", Vector3.new(1.6, 1, 0.6), base * CFrame.new(0, 1.7, -4.9) * CFrame.Angles(math.rad(-35), 0, 0), Color3.fromRGB(214, 170, 160), Enum.Material.SmoothPlastic, nil, false)
	for _, lx in { -1, 1 } do
		for _, lz in { -1, 1 } do
			part(model, "Leg", Vector3.new(0.8, 2.4, 0.8), base * CFrame.new(lx * 1.1, 1.2, lz * 2.2), coat[1], Enum.Material.Fabric, nil, false)
		end
	end
	model.PrimaryPart = body
	CollectionService:AddTag(model, "Cow")
	model.Parent = folder
end

local function herd(folder, r, count, rng)
	local made, tries = 0, 0
	while made < count and tries < count * 20 do
		tries += 1
		local cx, cz = randomIn(r, rng)
		local ok = WorldShape.regionAt(cx, cz) == r and buildable(cx, cz, 14) and not crowded(cx, cz, 14)
		if not ok then
			continue
		end
		-- A few cows together.
		for _ = 1, rng:NextInteger(2, 4) do
			local x, z = cx + rng:NextNumber(-12, 12), cz + rng:NextNumber(-12, 12)
			local fine, h = buildable(x, z, 4)
			if fine and not crowded(x, z, 4) then
				cow(folder, x, z, h, rng)
				claim(x, z)
				made += 1
			end
		end
	end
	return made
end

-- Landmarks -----------------------------------------------------------------------------------------------------

local LANDMARKS = {}

function LANDMARKS.homestead(folder)
	local y = 8
	-- The plaza: market stalls, the trading post, the museum, a sawmill row and the bounty board round a well.
	local stalls = Instance.new("Folder")
	stalls.Name = "NeedleMarket"
	stalls.Parent = folder
	local colors = { Rustic.PaintRed, Rustic.PaintGreen, Rustic.PaintBlue, Rustic.PaintYellow }
	for i = 0, 3 do
		local base = CFrame.new(-100, y, -1530 + i * 34) * CFrame.Angles(0, -math.pi / 2, 0)
		part(stalls, "Counter", Vector3.new(12, 3.5, 3), base * CFrame.new(0, 1.75, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
		for _, x in { -5.5, 5.5 } do
			post(stalls, "Pole", 9, 0.5, base * CFrame.new(x, 0, 2), Rustic.Wood, Enum.Material.Wood)
		end
		part(stalls, "Canopy", Vector3.new(13, 0.4, 7), base * CFrame.new(0, 9, 0.5) * CFrame.Angles(math.rad(10), 0, 0), colors[i + 1], Enum.Material.Fabric)
	end
	billboard(part(stalls, "MarketSign", Vector3.new(1, 1, 1), CFrame.new(-100, y + 12, -1480), Rustic.Wood, nil, nil, false), "NEEDLE MARKET", Vector3.zero, 220)

	building(folder, "TradingPost", CFrame.new(0, y, -1590) * CFrame.Angles(0, math.pi, 0), 40, 26, 14, { sign = "TRADING POST", prop = "trading_post" })
	building(folder, "Museum", CFrame.new(90, y, -1580) * CFrame.Angles(0, math.pi, 0), 34, 24, 16, { sign = "MUSEUM", prop = "museum", wall = Rustic.PaintCream, roof = Rustic.PaintBlue })
	for i, z in { -1405, -1490, -1530 } do
		building(folder, "Sawmill", CFrame.new(165, y, z) * CFrame.Angles(0, math.pi / 2, 0), 26, 20, 12, { sign = i == 1 and "SAWMILL ROW" or nil, prop = "mill" })
	end
	building(folder, "Workshop", CFrame.new(-150, y, -1600) * CFrame.Angles(0, math.pi * 0.75, 0), 24, 20, 11, { sign = "WORKSHOP", prop = "workshop" })

	-- The bounty board and the well in the middle.
	local board = part(folder, "BountyBoard", Vector3.new(14, 8, 0.6), CFrame.new(0, y + 6, -1480), Rustic.Wood, Enum.Material.WoodPlanks)
	boardText(board, "BOUNTY BOARD\nNew jobs every day")
	for _, x in { -6.5, 6.5 } do
		post(folder, "BoardPost", 10, 0.7, CFrame.new(x, y, -1480), Rustic.WoodDark, Enum.Material.Wood)
	end
	local well = CFrame.new(0, y, -1440)
	post(folder, "Well", 3, 8, well, Rustic.Stone, Enum.Material.Cobblestone)
	part(folder, "WellWater", Vector3.new(0.2, 6.4, 6.4), well * CFrame.new(0, 2.9, 0) * CFrame.Angles(0, 0, math.pi / 2), Rustic.Water, Enum.Material.Glass, Enum.PartType.Cylinder, false)
	for _, x in { -3.6, 3.6 } do
		post(folder, "WellPost", 8, 0.5, well * CFrame.new(x, 0, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	part(folder, "WellRoof", Vector3.new(9, 0.5, 5), well * CFrame.new(0, 8, 0), Rustic.PaintRedDark, Enum.Material.WoodPlanks)

	-- An arch where the North Road comes in.
	-- On the road's center line, facing along it (the road runs (120, -1260) -> (0, -1330) here).
	local arch = spot(80, -1283.3, Vector2.new(-120, -70).Unit)
	for _, side in { -1, 1 } do
		post(folder, "ArchPost", 16, 1.6, arch * CFrame.new(side * 11, -1, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	local beam = part(folder, "ArchBeam", Vector3.new(26, 3, 1), arch * CFrame.new(0, 14, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	boardText(beam, "HOMESTEAD VALLEY")

	-- The Homestead branch of the bank (the Economy thread's counter can hook the BankCounter tag), facing the well.
	local bank = building(folder, "HomesteadBank", CFrame.new(95, y, -1490) * CFrame.Angles(0, math.pi / 2, 0), 30, 22, 13, { sign = "SAVINGS & LOAN", wall = Rustic.PaintCream, roof = Rustic.PaintGreen, material = Enum.Material.Brick, prop = "homestead_bank" })
	local counter = part(bank, "Counter", Vector3.new(10, 3.5, 2), CFrame.new(95, y, -1490) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, 2.75, 3), Rustic.WoodDark, Enum.Material.WoodPlanks)
	CollectionService:AddTag(counter, "BankCounter")

	CollectionService:AddTag(board, "BountyBoard")

	-- The people of the hub. The quest system takes them over by their QuestGiver id.
	local people = Instance.new("Folder")
	people.Name = "Townsfolk"
	people.Parent = folder
	local function facing(x, z, tx, tz)
		local p = Vector3.new(x, y, z)
		return CFrame.lookAt(p, Vector3.new(tx, y, tz))
	end
	townsperson(people, "bounty", "Marshal Hettie", facing(10, -1474, 0, -1440), Rustic.PaintBlue, {
		"Jobs go up on the board every morning. Bring the hay, get paid.",
		"Folks out past the Spindle pay double for clean bales.",
	})
	townsperson(people, "trader", "Trader Oskar", facing(-12, -1572, 0, -1440), Rustic.PaintGreen, {
		"I'll trade for anything with a shine on it. Needles most of all.",
		"Pine needles from the west woods? Bring me those.",
	})
	townsperson(people, "elder", "Old Wren", facing(-14, -1436, 0, -1440), Rustic.PaintRedDark, {
		"Twelve shards, they say, and the Spindle door opens.",
		"The tailor down on the south shore knows more than she lets on.",
		"When the gold beam goes up, ride for it. Rich hay never lasts.",
	})
	townsperson(people, "ferrymaster", "Ferrymaster Bo", facing(70, -1400, 80, -1300), IRON, {
		"Ferries leave from Swamp Port and Ash Dock. Trailers ride free.",
		"The zeppelin lifts off the field east of here, trucks and all.",
	})
end

function LANDMARKS.spindle(folder)
	-- The sealed door on the Spindle's east face, with a socket for each of the twelve shards of the Master Needle.
	local x, z = 155, -990
	local base = spot(x, z, Vector2.new(1, 0))
	local stone = Color3.fromRGB(150, 142, 160)
	local frame = part(folder, "DoorFrame", Vector3.new(20, 26, 4), base * CFrame.new(0, 12, 2.5), stone, Enum.Material.Slate)
	local door = part(folder, "SpindleDoor", Vector3.new(14, 20, 1), base * CFrame.new(0, 10, 0.2), Color3.fromRGB(96, 86, 120), Enum.Material.Slate)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local socket = part(folder, "ShardSocket", Vector3.new(0.6, 1, 1), door.CFrame * CFrame.new(math.cos(a) * 5, math.sin(a) * 5 + 2, -0.6) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(242, 183, 5), Enum.Material.Neon, Enum.PartType.Cylinder, false)
		socket.Transparency = 0.6
		socket:SetAttribute("Slot", i + 1) -- SpindleDoor.luau lights it once anyone here holds that shard
		CollectionService:AddTag(socket, "ShardSocket")
	end
	CollectionService:AddTag(door, "SpindleDoor")
	-- The Blender Spindle (Config/Props the_spindle), built round this door: its door (center 11 up, front -Z) on
	-- this one and its twelve sockets on these. Only a look. The part door stays the door (SpindleDoor.client fades
	-- it for a player with all twelve shards) and the part sockets stay the lights, so the mesh drops its own door.
	local spindle = Props.make("the_spindle", base * CFrame.new(0, 10 - 11 + 59.9, 0.2 + 19.45 - 2.65))
	if spindle then
		for _, piece in Props.find(spindle, "Door") do
			piece:Destroy()
		end
		Props.weldTo(spindle, frame, frame)
	end
	billboard(door, "THE SPINDLE\nTwelve shards open this door", Vector3.new(0, 14, 0), 160)

	-- The Observatory on the Spindle's shoulder (meteor showers land here).
	local ox, oz = 30, -1080
	local oy = ground(ox, oz)
	local obs = Instance.new("Model")
	obs.Name = "Observatory"
	post(obs, "Tower", 18, 16, CFrame.new(ox, oy - 2, oz), Rustic.PaintCream, Enum.Material.Concrete)
	local dome = part(obs, "Dome", Vector3.new(15, 15, 15), CFrame.new(ox, oy + 16, oz), IRON, Enum.Material.Metal, Enum.PartType.Ball)
	part(obs, "Scope", Vector3.new(9, 1.6, 1.6), CFrame.new(ox, oy + 21, oz) * CFrame.Angles(0, 0.6, math.rad(40)), Rustic.Metal, Enum.Material.Metal, Enum.PartType.Cylinder)
	obs.PrimaryPart = dome
	if Props.has("observatory") then
		local mesh = Props.make("observatory", CFrame.new(ox, oy + 12, oz), nil, CFrame.Angles(0, math.pi, 0))
		if mesh then
			Props.restOn(mesh, oy - 1)
			Props.weldTo(mesh, dome, obs)
		end
	end
	obs.Parent = folder

	-- The cave mouth on the west foot: a stone arch and a lantern.
	local mouth = Map.Cave.mouth
	local arch = CFrame.lookAt(mouth, mouth + Vector3.new(-1, 0, 0.1))
	for _, side in { -1, 1 } do
		part(folder, "CavePillar", Vector3.new(3, 16, 3), arch * CFrame.new(side * 9, 2, 0), Rustic.StoneDark, Enum.Material.Slate)
	end
	part(folder, "CaveLintel", Vector3.new(22, 3, 3.4), arch * CFrame.new(0, 11, 0), Rustic.StoneDark, Enum.Material.Slate)
	local lantern = part(folder, "Lantern", Vector3.new(1, 1.4, 1), arch * CFrame.new(-7, 8, -2), Color3.fromRGB(255, 200, 120), Enum.Material.Neon, nil, false)
	light(lantern, Color3.fromRGB(255, 190, 120), 22, 1.2)
	signpost(folder, mouth.X - 18, mouth.Z + 14, Vector2.new(-1, 0), "CRYSTAL CAVE", 9)
end

function LANDMARKS.cave(folder, rng)
	-- Crystals all round the cavern and a field of crystal hay on its floor.
	local c = Map.Cave.chamber
	local floorY = c.center.Y - c.radius * 0.45 + 4
	for i = 1, 26 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(c.radius * 0.35, c.radius * 0.75)
		TREES.crystal(folder, CFrame.new(c.center.X + math.cos(a) * d, floorY - 0.5, c.center.Z + math.sin(a) * d), rng:NextNumber(0.8, 1.6), rng)
	end
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		local p = Map.Cave.mouth:Lerp(c.center, i / 7)
		local lamp = part(folder, "CaveLamp", Vector3.new(0.8, 0.8, 0.8), CFrame.new(p + Vector3.new(math.cos(a) * 2, 4, 0)), Color3.fromRGB(255, 196, 120), Enum.Material.Neon, nil, false)
		CollectionService:AddTag(lamp, "AlwaysLit") -- it's always night in the cave
		light(lamp, Color3.fromRGB(255, 190, 120), 26, 1)
	end
	field("Crystal Cave", Map.Cave.hayType, Vector3.new(c.center.X, floorY, c.center.Z), floorY, 8, rng)
end

function LANDMARKS.valley(folder)
	-- A jetty into Mirror Lake, and the stone ruins of the Sunken Harbor on its bed (Low Tide uncovers them later).
	local lake = Map.Lake
	local shore = Vector2.new(lake.center.X - lake.radius - 20, lake.center.Y)
	local level = lake.level
	for i = 0, 6 do
		local x = shore.X + i * 8
		part(folder, "JettyDeck", Vector3.new(8, 0.6, 10), CFrame.new(x, level + 1.6, shore.Y), Rustic.Wood, Enum.Material.WoodPlanks)
		for _, side in { -1, 1 } do
			post(folder, "JettyPost", 10, 0.7, CFrame.new(x, level - 8, shore.Y + side * 4.5), Rustic.WoodDark, Enum.Material.Wood)
		end
	end
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local p = Vector3.new(lake.center.X + math.cos(a) * 40, level - lake.depth + 6, lake.center.Y + math.sin(a) * 40)
		part(folder, "HarborRuin", Vector3.new(4, 10 + (i % 3) * 3, 4), CFrame.new(p) * CFrame.Angles(0.1 * (i % 2), a, 0), Rustic.StoneDark, Enum.Material.Cobblestone)
	end
	signpost(folder, shore.X - 6, shore.Y + 10, Vector2.new(-1, 0), "MIRROR LAKE", 9)
end

function LANDMARKS.shore(folder)
	-- The lighthouse on the south coast: it flashes at night (its code is a puzzle for later).
	local x, z = 420, 860
	local y = ground(x, z)
	local tower = Instance.new("Model")
	tower.Name = "Lighthouse"
	for i = 0, 4 do
		local color = i % 2 == 0 and Rustic.PaintCream or Rustic.PaintRed
		post(tower, "Tower", 8, 12 - i * 1.2, CFrame.new(x, y + i * 8, z), color, Enum.Material.Concrete)
	end
	part(tower, "Gallery", Vector3.new(1, 10, 10), CFrame.new(x, y + 40.5, z) * CFrame.Angles(0, 0, math.pi / 2), IRON, Enum.Material.Metal, Enum.PartType.Cylinder)
	local lamp = part(tower, "Lamp", Vector3.new(4, 4, 4), CFrame.new(x, y + 43, z), Color3.fromRGB(255, 236, 190), Enum.Material.Neon, Enum.PartType.Ball, false)
	light(lamp, Color3.fromRGB(255, 230, 180), 60, 2)
	part(tower, "Cap", Vector3.new(6, 2.4, 6), CFrame.new(x, y + 46.5, z), Rustic.PaintRedDark, Enum.Material.Metal)
	tower.PrimaryPart = lamp
	tower.Parent = folder

	-- The Tailor's shack, where the mystery starts.
	building(folder, "TailorShack", spot(-250, 660, Vector2.new(0, 1), 4), 18, 14, 9, { sign = "THE TAILOR", roof = Rustic.PaintGreen })
	signpost(folder, -230, 690, Vector2.new(0, 1), "THE TAILOR'S SHACK", 10)
end

function LANDMARKS.pine(folder)
	-- The old mill by the end of the Shore Road, with log piles.
	building(folder, "PineMill", spot(-1210, 190, Vector2.new(1, 0), 18), 30, 22, 14, { sign = "PINE MILL", prop = "mill", roof = Rustic.PaintGreen })
	-- A log pile beside it: three logs on the ground, two on top.
	for layer = 0, 1 do
		for k = 0, 2 - layer do
			local x = -1180 + k * 2.3 + layer * 1.15
			part(folder, "Log", Vector3.new(14, 2.2, 2.2), CFrame.new(x, 18 + 1.1 + layer * 2, 214) * CFrame.Angles(0, math.pi / 2, 0), Rustic.Bark, Enum.Material.Wood, Enum.PartType.Cylinder)
		end
	end
	signpost(folder, -1120, 120, Vector2.new(1, 0.3), "PINE FOREST", 9)
end

function LANDMARKS.haunted(folder, rng)
	-- The Wreck of the Bobbin, half sunk on the west shore. The captain's cabin hides the Moth-Eaten Map.
	local cf = CFrame.new(-1770, -2, -860) * CFrame.Angles(0, math.rad(20), math.rad(12))
	local hull = Color3.fromRGB(70, 58, 48)
	part(folder, "Hull", Vector3.new(16, 10, 60), cf * CFrame.new(0, 3, 0), hull, Enum.Material.WoodPlanks)
	wedge(folder, "Bow", Vector3.new(16, 10, 14), cf * CFrame.new(0, 3, -37), hull, Enum.Material.WoodPlanks)
	part(folder, "Deck", Vector3.new(15, 1, 58), cf * CFrame.new(0, 8.4, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	building(folder, "CaptainsCabin", cf * CFrame.new(0, 8.4, 18), 12, 12, 7, { roof = hull })
	post(folder, "Mast", 34, 1.4, cf * CFrame.new(0, 8, -6) * CFrame.Angles(0, 0, math.rad(-18)), Rustic.WoodDark, Enum.Material.Wood)
	signpost(folder, -1700, -830, Vector2.new(-1, 0), "WRECK OF THE BOBBIN", 11)

	-- Graves and lanterns along the grove road.
	for i = 1, 14 do
		local x, z = -1180 + rng:NextNumber(-90, 90), -780 + rng:NextNumber(-60, 60)
		if buildable(x, z, 4) and not crowded(x, z, 4) then
			local base = spot(x, z, Vector2.new(0, -1))
			part(folder, "Gravestone", Vector3.new(2.4, 3.4, 0.6), base * CFrame.new(0, 1.2, 0) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), Color3.fromRGB(110, 106, 116), Enum.Material.Slate)
			claim(x, z)
		end
	end
	for i = 0, 8 do
		local p = Vector2.new(-1120, -760):Lerp(Vector2.new(-900, -1060), i / 8) + Vector2.new(11, 0)
		local lx, lz = offRoad(p.X, p.Y, 1.5) -- the road bends near the end; keep every post out of the lane
		local base = CFrame.new(at(lx, lz))
		post(folder, "LanternPost", 7, 0.4, base, Color3.fromRGB(40, 36, 36), Enum.Material.Metal)
		local glow = part(folder, "Lantern", Vector3.new(1, 1.2, 1), base * CFrame.new(0, 7.4, 0), Color3.fromRGB(150, 210, 190), Enum.Material.Neon, nil, false)
		light(glow, Color3.fromRGB(140, 220, 200), 20, 0.8)
	end
	signpost(folder, -1150, -700, Vector2.new(0.3, 1), "HAUNTED GROVE\nStay on the road at night", 11)
end

function LANDMARKS.snow(folder)
	-- The ski lodge at the end of the Snow Road.
	building(folder, "SkiLodge", spot(-650, -1625, Vector2.new(0, 1), 46), 34, 24, 13, { sign = "SNOW PEAK LODGE", roof = SNOW })
	-- The hidden door: a stitched seam in the rock high on the ridge.
	local x, z = -1060, -1700
	local base = spot(x, z, Vector2.new(1, 0.4))
	local seam = part(folder, "HiddenDoor", Vector3.new(8, 12, 1.2), base * CFrame.new(0, 5, 0), Color3.fromRGB(110, 120, 134), Enum.Material.Slate)
	for i = -2, 2 do
		part(folder, "Stitch", Vector3.new(2.4, 0.3, 0.3), seam.CFrame * CFrame.new(0, i * 2, -0.7) * CFrame.Angles(0, 0, math.rad(i % 2 == 0 and 30 or -30)), Color3.fromRGB(170, 220, 240), Enum.Material.Neon, nil, false)
	end
	signpost(folder, -660, -1460, Vector2.new(0, 1), "SNOW PEAK\nLodge ahead", 9)
end

function LANDMARKS.volcano(folder, rng)
	-- The Magma Spindle stands in the crater over the lava.
	local peak = WorldShape.region("volcano").peak
	local c = peak.center
	local floor = ground(c.X, c.Y)
	local spire = part(folder, "MagmaSpindle", Vector3.new(3, 46, 3), CFrame.new(c.X, floor + 22, c.Y) * CFrame.Angles(0, 0.4, 0.05), Color3.fromRGB(90, 40, 30), Enum.Material.Basalt)
	local glow = part(folder, "LavaGlow", Vector3.new(peak.crater * 1.4, 1, peak.crater * 1.4), CFrame.new(c.X, floor + 1.5, c.Y), Color3.fromRGB(230, 110, 40), Enum.Material.Neon, nil, false)
	glow.Transparency = 0.35
	light(glow, Color3.fromRGB(255, 120, 50), 60, 2)
	billboard(spire, "VOLCANO", Vector3.new(0, 30, 0), 900)

	-- The Old Quarry at the foot: cut stone, a cracked mine cart track and a locked chest.
	local q = CFrame.new(740, 30, -1300)
	for i = 1, 9 do
		local size = Vector3.new(rng:NextNumber(4, 7), rng:NextNumber(3, 6), rng:NextNumber(4, 7))
		part(folder, "QuarryStone", size, q * CFrame.new(rng:NextNumber(-30, 30), size.Y / 2, rng:NextNumber(-25, 25)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color3.fromRGB(122, 112, 104), Enum.Material.Slate)
	end
	for i = 0, 7 do
		local cf = q * CFrame.new(-20 + i * 6, 0.2, 18)
		for _, side in { -1, 1 } do
			part(folder, "Rail", Vector3.new(6, 0.3, 0.3), cf * CFrame.new(0, 0, side * 1.2), IRON, Enum.Material.Metal)
		end
		part(folder, "Sleeper", Vector3.new(0.6, 0.3, 3.4), cf, Rustic.WoodDark, Enum.Material.Wood)
	end
	local cart = q * CFrame.new(4, 1.6, 18)
	part(folder, "MineCart", Vector3.new(5, 2.6, 3.6), cart, IRON, Enum.Material.Metal)
	part(folder, "Chest", Vector3.new(3, 2, 2), q * CFrame.new(-26, 1, -18), Rustic.WoodDark, Enum.Material.WoodPlanks)
	signpost(folder, 680, -1275, Vector2.new(-0.6, 0.8), "OLD QUARRY", 8)
end

function LANDMARKS.desert(folder, rng)
	-- The Buried Pyramid: stepped sandstone, half under the dunes.
	local c = Vector3.new(1500, 10, -580)
	local stone = Color3.fromRGB(190, 160, 112)
	for i = 0, 5 do
		local w = 96 - i * 16
		part(folder, "PyramidStep", Vector3.new(w, 8, w), CFrame.new(c + Vector3.new(0, i * 8 - 2, 0)), stone, Enum.Material.Sandstone)
	end
	local door = part(folder, "PyramidDoor", Vector3.new(8, 10, 1), CFrame.new(c + Vector3.new(0, 7, 48.6)), Color3.fromRGB(60, 50, 40), Enum.Material.Slate)
	billboard(door, "BURIED PYRAMID", Vector3.new(0, 10, 0), 200)

	-- The oasis: palms round the pool, and a camp of tents.
	local o = Map.Oasis
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local x, z = o.center.X + math.cos(a) * (o.radius + 12), o.center.Y + math.sin(a) * (o.radius + 12)
		TREES.palm(folder, CFrame.new(x, ground(x, z) - 1, z), rng:NextNumber(0.9, 1.2), rng)
		claim(x, z)
	end
	for i = 0, 2 do
		local base = spot(1170 + i * 16, -222, Vector2.new(0, 1))
		wedge(folder, "Tent", Vector3.new(8, 6, 5), base * CFrame.new(0, 3, -2.5), Rustic.Cloth, Enum.Material.Fabric)
		wedge(folder, "Tent", Vector3.new(8, 6, 5), base * CFrame.new(0, 3, 2.5) * CFrame.Angles(0, math.pi, 0), Rustic.Cloth, Enum.Material.Fabric)
	end
	signpost(folder, 1060, -470, Vector2.new(-1, 0), "DESERT DUNES", 9)
end

function LANDMARKS.swamp(folder, rng)
	-- Boardwalks out over the bog, with lily pads in the pools.
	for _, walk in { { Vector2.new(1000, 545), Vector2.new(1060, 700) }, { Vector2.new(1440, 495), Vector2.new(1500, 360) } } do
		local a, b = walk[1], walk[2]
		local n = math.floor((b - a).Magnitude / 6)
		local along = CFrame.lookAt(Vector3.zero, Vector3.new(b.X - a.X, 0, b.Y - a.Y))
		for i = 0, n do
			local p = a:Lerp(b, i / n)
			local base = along + Vector3.new(p.X, 1.4, p.Y)
			part(folder, "Boardwalk", Vector3.new(6, 0.5, 6.2), base, Rustic.Wood, Enum.Material.WoodPlanks)
			if i % 2 == 0 then
				for _, side in { -1, 1 } do
					post(folder, "BoardwalkPost", 5, 0.5, base * CFrame.new(side * 2.8, -4, 0), Rustic.WoodDark, Enum.Material.Wood)
				end
			end
		end
	end
	for _ = 1, 50 do
		local x, z = 1120 + rng:NextNumber(-500, 500), 470 + rng:NextNumber(-300, 300)
		local h, water = WorldShape.column(x, z)
		if water and water > SEA and water - h < 3 then
			part(folder, "LilyPad", Vector3.new(0.2, 3, 3), CFrame.new(x, water + 0.1, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(96, 128, 70), Enum.Material.Grass, Enum.PartType.Cylinder, false)
		end
	end
	signpost(folder, 980, 540, Vector2.new(-1, 0), "THE SWAMP\nMud slows trucks", 10)
end

function LANDMARKS.keys(folder)
	-- A harbor market by the ferry, and tide-pool rocks.
	for i = 0, 2 do
		local base = spot(2905 + i * 16, 40, Vector2.new(-1, 0), 2)
		part(folder, "Counter", Vector3.new(3, 3.5, 10), base * CFrame.new(0, 1.75, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
		part(folder, "Awning", Vector3.new(7, 0.4, 12), base * CFrame.new(0, 8, 0) * CFrame.Angles(0, 0, math.rad(10)), ({ Rustic.PaintBlue, Rustic.PaintCream, Rustic.PaintGreen })[i + 1], Enum.Material.Fabric)
		for _, z in { -5, 5 } do
			post(folder, "Pole", 8, 0.4, base * CFrame.new(2.5, 0, z), Rustic.Wood, Enum.Material.Wood)
		end
	end
	signpost(folder, 2780, -270, Vector2.new(-1, 0), "THIMBLE KEYS", 9)
end

function LANDMARKS.bobbin(folder)
	-- The Weaver's lost workshop on top of the rock: broken stone walls and the twelfth shard on a pedestal.
	local zone
	for _, f in Map.Flat do
		if f.name == "Workshop" then
			zone = f
		end
	end
	local mid = (zone.min + zone.max) / 2
	local base = CFrame.new(mid.X, zone.height, mid.Y)
	local stone = Color3.fromRGB(110, 106, 112)
	for i, w in { { Vector3.new(30, 12, 2), CFrame.new(0, 6, -14) }, { Vector3.new(2, 9, 26), CFrame.new(-14, 4.5, 0) }, { Vector3.new(14, 6, 2), CFrame.new(8, 3, 14) } } do
		part(folder, "WorkshopWall" .. i, w[1], base * w[2], stone, Enum.Material.Cobblestone)
	end
	part(folder, "Pedestal", Vector3.new(3, 4, 3), base * CFrame.new(0, 2, 0), stone, Enum.Material.Slate)
	local shard = part(folder, "Shard", Vector3.new(0.6, 3, 0.6), base * CFrame.new(0, 5.6, 0) * CFrame.Angles(0, 0, 0.2), Color3.fromRGB(242, 183, 5), Enum.Material.Neon, nil, false)
	light(shard, Color3.fromRGB(255, 200, 80), 24, 1.5)
	billboard(shard, "THE WEAVER'S WORKSHOP", Vector3.new(0, 6, 0), 200)
end

-- The Graveyard of Ships: wrecks on the reef between the main island and Bobbin Rock, clear of the ferry lane.
local function graveyard(folder, rng)
	local lane = Map.Channels[2]
	local made = 0
	for _ = 1, 60 do
		if made >= 6 then
			break
		end
		local x, z = 2150 + rng:NextNumber(-260, 260), -1560 + rng:NextNumber(-200, 200)
		local d = WorldShape.segment(x, z, lane.from.X, lane.from.Y, lane.to.X, lane.to.Y)
		if d > lane.width / 2 + 70 then
			local cf = CFrame.new(x, SEA - 6, z) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, math.pi * 2), rng:NextNumber(0.2, 0.5))
			part(folder, "Wreck", Vector3.new(12, 9, 44), cf, Color3.fromRGB(64, 54, 46), Enum.Material.WoodPlanks)
			post(folder, "WreckMast", 22, 1.1, cf * CFrame.new(0, 3, -6) * CFrame.Angles(0.3, 0, 0), Rustic.WoodDark, Enum.Material.Wood)
			made += 1
		end
	end
end

-- The sky island's trees and its field of cloud hay.
local function skyIsland(folder, rng)
	local sky = Map.SkyIsland
	for i = 1, 16 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(30, sky.radius * 0.7)
		local x, z = sky.center.X + math.cos(a) * d, sky.center.Y + math.sin(a) * d
		TREES.oak(folder, CFrame.new(x, sky.top - 2, z), rng:NextNumber(0.9, 1.3), rng)
	end
	field("Sky Island", "sky", Vector3.new(sky.center.X, sky.top - 1, sky.center.Y + 40), sky.top - 1.5, 9, rng)
	signpost(folder, sky.center.X + 10, sky.center.Y + 150, Vector2.new(0, 1), "SKY ISLAND", 9)
end

-- Signs where the roads branch, so nobody gets lost.
-- Junction signs: where they stand, which way they face, and the places they point to. Each line is an arrow, a
-- name and a target; the driving distance is worked out from the road graph (RoadGraph.luau) when the map builds, so
-- "HOMESTEAD 880" can never drift from the roads. A line with no target is plain text.
local function regionCenter(id)
	local r = WorldShape.region(id)
	return r and Vector2.new(r.cx, r.cz) or Vector2.zero
end
local HOMESTEAD = Vector2.new(0, -1470)
local ASH_DOCK = Vector2.new(1585, -1225)
local JUNCTIONS = {
	{ -30, -600, Vector2.new(0, 1), { { "^", "HOMESTEAD VALLEY", HOMESTEAD }, { ">", "MIRROR LAKE", Vector2.new(400, -880) } } },
	{ 100, -748, Vector2.new(0, 1), { { "<", "HOMESTEAD", HOMESTEAD }, { ">", "DESERT", function() return regionCenter("desert") end } } },
	{ 150, 610, Vector2.new(0, -1), { { "<", "PINE FOREST", function() return regionCenter("pine") end }, { ">", "SWAMP", function() return regionCenter("swamp") end } } },
	{ -1190, -740, Vector2.new(1, 0), { { "^", "HOMESTEAD", HOMESTEAD }, { ">", "WRECK", Vector2.new(-1765, -860) } } },
	{ -620, -1320, Vector2.new(1, 0), { { "<", "SNOW PEAK", Vector2.new(-650, -1600) }, { ">", "HOMESTEAD", HOMESTEAD } } },
	{ 220, -1475, Vector2.new(-1, 0), { { ">", "VOLCANO", function() return regionCenter("volcano") end }, { ">", "ASH DOCK", ASH_DOCK } } },
	{ 1300, -400, Vector2.new(0, -1), { { "<", "HIGHWAY", Map.Highway.from }, { "v", "SWAMP", function() return regionCenter("swamp") end } } },
	{ 1560, 500, Vector2.new(-1, 0), { { ">", "SWAMP PORT", Vector2.new(1685, 520) }, { "", "Ferry to Thimble Keys" } } },
	{ 1480, -1170, Vector2.new(-1, 0), { { ">", "ASH DOCK", ASH_DOCK }, { "", "Ferry to Bobbin Rock" } } },
}

-- A junction sign's text: one line per place, "^ HOMESTEAD 880" or "MIRROR LAKE 340 >" (arrows keep their side).
-- Distances are rounded to 10 studs. Returns the text and the distances for the self-tests.
local function junctionText(j)
	local RoadGraph = require(script.Parent.RoadGraph)
	local dist = RoadGraph.distances(Vector2.new(j[1], j[2]))
	local lines, numbers = {}, {}
	for _, line in j[4] do
		local arrow, name, target = line[1], line[2], line[3]
		if type(target) == "function" then
			target = target()
		end
		if not target then
			table.insert(lines, name)
			continue
		end
		local d = dist[RoadGraph.nearest(target)]
		if d == math.huge then
			table.insert(lines, (arrow == ">" and "%s >" or "%s %s"):format(name, arrow))
			continue
		end
		local n = math.max(10, math.floor(d / 10 + 0.5) * 10)
		table.insert(numbers, { name = name, distance = n, target = target })
		if arrow == ">" then
			table.insert(lines, ("%s %d >"):format(name, n))
		else
			table.insert(lines, ("%s %s %d"):format(arrow, name, n))
		end
	end
	return table.concat(lines, "\n"), numbers
end
Regions.junctions = JUNCTIONS
Regions.junctionText = junctionText

-- A sign at the roadside wherever a road crosses into another region: its name and the hay that grows there.
local function borderSigns(folder)
	local placed = {}
	local count = 0
	for _, road in Map.Roads do
		-- A road out of Meadow's gate starts in Meadow, so its first region gets a sign too.
		local start = road.points[1]
		local current = WorldShape.meadowDistance(start.X, start.Y) < 4 and "meadow" or nil
		local candidate, run = nil, 0
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			local dir = (b - a).Unit
			local n = math.max(1, math.ceil((b - a).Magnitude / 8))
			for k = 0, n - 1 do
				local p = a:Lerp(b, k / n)
				local r = WorldShape.inMeadow(p.X, p.Y) and "meadow" or WorldShape.regionAt(p.X, p.Y)
				local id = r and (r == "meadow" and r or r.id)
				if not id or id == current then
					candidate, run = nil, 0
					continue
				end
				if id ~= candidate then
					candidate, run = id, 0
				end
				run += 1
				-- The new region has to hold for 40 studs, so a wobbly border doesn't sprout a row of signs.
				if run < 5 then
					continue
				end
				local first = current == nil
				current, candidate, run = id, nil, 0
				if first or id == "meadow" then
					continue
				end
				local at = p - dir * 16 + Vector2.new(-dir.Y, dir.X) * (Map.RoadWidth / 2 + 4)
				local near = false
				for _, q in placed do
					if (q - at).Magnitude < 80 then
						near = true
						break
					end
				end
				if near then
					continue
				end
				table.insert(placed, at)
				local region = WorldShape.region(id)
				local hay = GloveConfig.HayTypes[region.hayType]
				local text = string.upper(region.name)
				if hay then
					text ..= ("\n%s, tier %d"):format(hay.name, hay.tier)
				end
				signpost(folder, at.X, at.Y, -dir, text, 13)
				count += 1
			end
		end
	end
	return count
end

-- Labels that read from far off, so the big landmarks find you: the Spindle on the skyline, the snow peak, Bobbin.
local function skyline(folder)
	for _, def in {
		{ "spindle", "THE SPINDLE" },
		{ "snow", "SNOW PEAK" },
		{ "bobbin", "BOBBIN ROCK" },
	} do
		local peak = WorldShape.region(def[1]).peak
		local top = WorldShape.heightAt(peak.center.X, peak.center.Y)
		-- A persistent model so the label streams to every client however far away it is.
		local holder = Instance.new("Model")
		holder.Name = def[2]
		holder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		holder.Parent = folder
		local anchor = part(holder, "SkylineLabel", Vector3.new(1, 1, 1), CFrame.new(peak.center.X, top + 30, peak.center.Y), Rustic.Stone, nil, nil, false)
		anchor.Transparency = 1
		anchor.CanQuery = false
		billboard(anchor, def[2], Vector3.zero, 4000)
	end
end

function Regions.build(worldFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Isles"
	folder.Parent = worldFolder
	local rng = Random.new(Map.Seed)
	local trees, made = 0, 0

	for _, r in WorldShape.regions do
		-- A plain Model per region (Default streaming, never Atomic): parts stream one by one, and the region can be
		-- found, pivoted or budgeted as a unit (Config/WorldMap PartBudget).
		local sub = Instance.new("Model")
		sub.Name = r.name
		sub.Parent = folder
		palette = PALETTE[r.id] or {}
		local landmark = LANDMARKS[r.id]
		if landmark then
			-- One broken landmark shouldn't take the rest of the map down with it.
			local ok, err = pcall(landmark, sub, rng)
			if not ok then
				warn(("[Needlewood] %s landmarks failed: %s"):format(r.name, tostring(err)))
			end
			claimParts(sub)
		end
		for _, planting in PLANTING[r.id] or {} do
			trees += plant(sub, r, planting[1], planting[2], rng)
		end
		rocks(sub, r, 18, rng)
		if r.id == "valley" or r.id == "shore" or r.id == "homestead" then
			herd(sub, r, r.id == "homestead" and 6 or 12, rng)
			windmill(sub, r.cx + r.rx * 0.35, r.cz - r.rz * 0.2)
		end
		hayFields(r, rng)
		palette = {}
		made += 1
		task.wait() -- spread the work out so the server keeps ticking
	end

	local cave = Instance.new("Model")
	cave.Name = "Crystal Cave"
	cave.Parent = folder
	LANDMARKS.cave(cave, rng)

	local sea = Instance.new("Model")
	sea.Name = "Graveyard of Ships"
	sea.Parent = folder
	graveyard(sea, rng)

	local sky = Instance.new("Model")
	sky.Name = "Sky Island"
	sky.Parent = folder
	skyIsland(sky, rng)

	local signs = Instance.new("Model")
	signs.Name = "Signs"
	signs.Parent = folder
	for _, j in JUNCTIONS do
		local ok, text = pcall(junctionText, j)
		if not ok then
			warn("[Needlewood] junction sign distances failed: " .. tostring(text))
			local names = {}
			for _, line in j[4] do
				table.insert(names, line[2])
			end
			text = table.concat(names, "\n")
		end
		signpost(signs, j[1], j[2], j[3], text, 14)
	end
	local ok, borders = pcall(borderSigns, signs)
	if not ok then
		warn("[Needlewood] Region signs failed: " .. tostring(borders))
		borders = 0
	end
	local skyOk, skyErr = pcall(skyline, signs)
	if not skyOk then
		warn("[Needlewood] Skyline labels failed: " .. tostring(skyErr))
	end
	print(("[Needlewood] %d junction signs, %d region signs"):format(#JUNCTIONS, borders))

	print(("[Needlewood] Stitched Isles: %d regions, %d trees, %d hay fields"):format(made, trees, #Regions.fields))
	return folder
end

return Regions

end

MODULES["Services.Highway"] = function(script)
-- The Longstitch Highway to Thimble Keys: a bridge off the desert coast with a toll gate, the Midway Rest Stop, then a
-- glass tube that dips under the sea and climbs onto the keys. All parts; the terrain under it stays sea, and
-- WorldShape keeps the tube's inside dry. Any truck can drive it, trailer and all. Heights: Config/WorldMap Highway.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local WorldShape = require(script.Parent.WorldShape)

local Highway = {}

local IRON = Color3.new(0.48, 0.48, 0.47)
local ASPHALT = Color3.fromRGB(78, 76, 72)
local STEP = 20 -- deck pieces along X
local SLAB = 1.2 -- deck thickness
local SEA = Map.SeaLevel

local function part(parent, name, size, cframe, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanTouch = false
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Where the highway's center line is at an X, on the deck top.
local function point(x)
	local hw = Map.Highway
	local t = (x - hw.from.X) / (hw.to.X - hw.from.X)
	local z = hw.from.Y + (hw.to.Y - hw.from.Y) * t
	return Vector3.new(x, WorldShape.highwayY(x), z)
end

local function sign(parent, cframe, text, width)
	local board = part(parent, "Sign", Vector3.new(width or 18, 4, 0.4), cframe, Rustic.PaintGreen, Enum.Material.WoodPlanks)
	WorldLabel.surface(board, text, { Enum.NormalId.Front, Enum.NormalId.Back }, { color = Color3.fromRGB(236, 230, 210) })
	return board
end

function Highway.build(worldFolder)
	local hw = Map.Highway
	local folder = Instance.new("Folder")
	folder.Name = "Longstitch Highway"
	folder.Parent = worldFolder
	local W = hw.width
	local x0, x1 = hw.from.X, hw.to.X

	for x = x0, x1 - STEP, STEP do
		local a, b = point(x), point(math.min(x + STEP, x1))
		local mid = (a + b) / 2
		local along = CFrame.lookAt(mid, b)
		local length = (b - a).Magnitude + 0.3
		local deck = part(folder, "Deck", Vector3.new(W, SLAB, length), along * CFrame.new(0, -SLAB / 2, 0), ASPHALT, Enum.Material.Asphalt)
		deck.CustomPhysicalProperties = PhysicalProperties.new(2, 0.8, 0, 1, 1)
		part(folder, "Stripe", Vector3.new(0.5, 0.05, length * 0.5), along * CFrame.new(0, 0.03, 0), Rustic.PaintCream, Enum.Material.SmoothPlastic)

		local underSea = math.max(a.Y, b.Y) < SEA + 1
		if underSea then
			-- The tube: glass walls and roof, a light strip down the middle of the ceiling.
			local top = hw.tubeTop
			for _, side in { -1, 1 } do
				part(folder, "TubeWall", Vector3.new(1, top, length), along * CFrame.new(side * (W / 2 + 0.5), top / 2, 0), Color3.fromRGB(150, 190, 200), Enum.Material.Glass, 0.45)
			end
			part(folder, "TubeRoof", Vector3.new(W + 2, 1, length), along * CFrame.new(0, top + 0.5, 0), Color3.fromRGB(150, 190, 200), Enum.Material.Glass, 0.45)
			if (x - x0) % (STEP * 2) == 0 then
				local lamp = part(folder, "TubeLight", Vector3.new(2, 0.3, length * 0.6), along * CFrame.new(0, top - 0.2, 0), Color3.fromRGB(255, 236, 200), Enum.Material.Neon)
				lamp.CanCollide = false
				local l = Instance.new("PointLight")
				l.Range = 30
				l.Brightness = 1.2
				l.Color = Color3.fromRGB(255, 230, 190)
				l.Parent = lamp
			end
		else
			-- Guard rails on the open bridge.
			for _, side in { -1, 1 } do
				part(folder, "Rail", Vector3.new(0.6, 1.6, length), along * CFrame.new(side * (W / 2 - 0.3), 0.8, 0), IRON, Enum.Material.Metal)
			end
		end

		-- Piers every 60 studs where the deck stands over the sea.
		local ground = WorldShape.heightAt(mid.X, mid.Z)
		if not underSea and (x - x0) % 60 == 0 and ground < mid.Y - 4 then
			local bottom = math.min(ground, SEA) - 6
			local height = mid.Y - SLAB - bottom
			for _, side in { -1, 1 } do
				part(folder, "Pier", Vector3.new(3, height, 3), along * CFrame.new(side * (W / 2 - 3), -SLAB - height / 2, 0), Rustic.Stone, Enum.Material.Concrete)
			end
			part(folder, "PierCap", Vector3.new(W, 1.6, 3.4), along * CFrame.new(0, -SLAB - 0.8, 0), Rustic.Stone, Enum.Material.Concrete)
		end
	end

	-- The toll gate (the toll in planks comes with the economy; for now the barrier stands open).
	local toll = point(hw.toll)
	local tollCF = CFrame.lookAt(toll, point(hw.toll + 10))
	part(folder, "TollBooth", Vector3.new(4, 7, 6), tollCF * CFrame.new(W / 2 + 2.6, 3.5, 0), Rustic.PaintCream, Enum.Material.WoodPlanks)
	part(folder, "TollRoof", Vector3.new(6, 0.6, 8), tollCF * CFrame.new(W / 2 + 2.6, 7.3, 0), Rustic.PaintRedDark, Enum.Material.WoodPlanks)
	part(folder, "TollArm", Vector3.new(0.5, 12, 0.5), tollCF * CFrame.new(W / 2 - 1, 7, 0) * CFrame.Angles(0, 0, math.rad(8)), Rustic.PaintRed, Enum.Material.SmoothPlastic)
	sign(folder, tollCF * CFrame.new(0, 13, -4), "LONGSTITCH HIGHWAY\nTHIMBLE KEYS 820 studs", 22)
	for _, side in { -1, 1 } do
		part(folder, "SignPost", Vector3.new(0.6, 13, 0.6), tollCF * CFrame.new(side * 10, 6.5, -4), IRON, Enum.Material.Metal)
	end

	-- The Midway Rest Stop: a wide platform beside the deck with a fuel pump and a trading stall.
	local rest = point(hw.restStop.x)
	local restCF = CFrame.lookAt(rest, point(hw.restStop.x + 10))
	local size = hw.restStop.size
	local pad = restCF * CFrame.new(W / 2 + size.Y / 2, 0, 0)
	part(folder, "RestStopDeck", Vector3.new(size.Y, SLAB, size.X), pad * CFrame.new(0, -SLAB / 2, 0), ASPHALT, Enum.Material.Asphalt)
	for _, dx in { -1, 1 } do
		for _, dz in { -1, 1 } do
			local height = rest.Y - SEA + 8
			part(folder, "RestPier", Vector3.new(3, height, 3), pad * CFrame.new(dx * (size.Y / 2 - 3), -SLAB - height / 2, dz * (size.X / 2 - 3)), Rustic.Stone, Enum.Material.Concrete)
		end
	end
	for _, z in { -size.X / 2 + 0.3, size.X / 2 - 0.3 } do
		part(folder, "RestRail", Vector3.new(size.Y, 1.6, 0.6), pad * CFrame.new(0, 0.8, z), IRON, Enum.Material.Metal)
	end
	part(folder, "RestRail", Vector3.new(0.6, 1.6, size.X), pad * CFrame.new(size.Y / 2 - 0.3, 0.8, 0), IRON, Enum.Material.Metal)
	part(folder, "FuelPump", Vector3.new(2.4, 5, 2), pad * CFrame.new(-6, 2.5, -10), Rustic.PaintRed, Enum.Material.Metal)
	part(folder, "PumpCanopy", Vector3.new(14, 0.6, 18), pad * CFrame.new(-6, 9, -10), Rustic.PaintCream, Enum.Material.Metal)
	for _, z in { -18, -2 } do
		part(folder, "CanopyPost", Vector3.new(0.6, 9, 0.6), pad * CFrame.new(-6, 4.5, z), IRON, Enum.Material.Metal)
	end
	part(folder, "Stall", Vector3.new(10, 4, 3), pad * CFrame.new(12, 2, 12), Rustic.WoodDark, Enum.Material.WoodPlanks)
	part(folder, "StallAwning", Vector3.new(12, 0.4, 7), pad * CFrame.new(12, 8, 13), Rustic.PaintBlue, Enum.Material.Fabric)
	sign(folder, pad * CFrame.new(0, 12, size.X / 2 - 1), "MIDWAY REST STOP", 18)

	-- Signs at the tube.
	local into = Map.Highway.Profile[3][1] + 40
	local signAt = point(into)
	sign(folder, CFrame.lookAt(signAt, point(into + 10)) * CFrame.new(0, 14, 0), "UNDERSEA TUBE\nHeadlights on", 18)
	return folder
end

return Highway

end

MODULES["Services.Ferry"] = function(script)
-- Ferries and the zeppelin: big roll-on, roll-off decks that carry trucks with their trailers hitched.
--
-- A ferry runs between two piers on a timetable: it boards at one pier (gates open, a ramp plate bridges the gap),
-- sounds a warning, then lashes every truck and trailer on its deck down for the crossing and sails to the other
-- pier, where it lets them go. Drive on at one end, drive off the far end, no reversing. The deck is a physics body
-- held on its course by rigid align constraints and owned by the server, so people walking on it ride along.
-- Bales stay loose in the beds; the lashed truck is part of the ferry's body while it sails (Vehicles.luau gives
-- their physics to the server while a vehicle has the OnFerry attribute).
--
-- The zeppelin to Sky Island is the same machine with a gondola for a deck.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local Rustic = require(Shared.Config.Rustic)
local WorldLabel = require(Shared.WorldLabel)
local Prices = require(Shared.Config.Prices)
local Vehicles = require(script.Parent.Vehicles)
local Bank = require(script.Parent.Bank)
local Data = require(script.Parent.Data)
local Props = require(script.Parent.Props)
local WorldShape = require(script.Parent.WorldShape)

local Ferry = {}

local IRON = Color3.new(0.48, 0.48, 0.47)
local IRON_DARK = Color3.new(0.40, 0.38, 0.35)
local SEA = Map.SeaLevel
local GATE_H = 3.2
local LASH_HEIGHT = 16 -- how far above the deck a vehicle can be and still get lashed

local shuttles = {}

local function part(parent, name, size, cframe, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if collide == false then
		p.CanCollide = false
	end
	p.Parent = parent
	return p
end

-- Floating text goes through the shared WorldLabel helper.
local function boardLabel(parent, offset, distance)
	return WorldLabel.billboard(parent, "", { offset = offset, kind = "sign", distance = distance or 220, color = Color3.fromRGB(240, 232, 210) })
end

local function yawOf(cframe)
	local look = cframe.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- Piers --------------------------------------------------------------------------------------------------------

-- A plank pier on posts from the shore out to where the ferry docks, its deck level with the ferry's.
local function buildPier(parent, shore, pierEnd, deckTop, width, name)
	local model = Instance.new("Model")
	model.Name = name .. " Pier"
	local a = Vector3.new(shore.X, deckTop, shore.Y)
	local b = Vector3.new(pierEnd.X, deckTop, pierEnd.Y)
	local dir = (b - a).Unit
	-- Start a little inland so the pier meets the quay with no step.
	a -= dir * 20
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	local deck = part(model, "PierDeck", Vector3.new(width, 1.2, length), cf * CFrame.new(0, -0.6, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	deck.CustomPhysicalProperties = PhysicalProperties.new(1, 0.8, 0, 1, 1)
	for _, side in { -1, 1 } do
		part(model, "PierRail", Vector3.new(0.6, 1.6, length), cf * CFrame.new(side * (width / 2 - 0.3), 0.8, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	for d = 0, length, 16 do
		for _, side in { -1, 1 } do
			local p = cf * CFrame.new(side * (width / 2 - 1.5), 0, -length / 2 + d)
			local bottom = math.min(WorldShape.heightAt(p.X, p.Z), SEA) - 4
			local height = deckTop - 1.2 - bottom
			if height > 1 then
				part(model, "PierPost", Vector3.new(1.6, height, 1.6), CFrame.new(p.X, bottom + height / 2, p.Z), Rustic.WoodDark, Enum.Material.Wood)
			end
		end
	end
	-- A lamp post and the departures board at the end.
	local endCF = CFrame.lookAt(b, b + dir) * CFrame.new(width / 2 - 2, 0, 6)
	part(model, "LampPost", Vector3.new(0.6, 12, 0.6), endCF * CFrame.new(0, 6, 0), IRON, Enum.Material.Metal)
	local lamp = part(model, "Lamp", Vector3.new(1.2, 1.2, 1.2), endCF * CFrame.new(0, 12.4, 0), Color3.fromRGB(255, 220, 160), Enum.Material.Neon, false)
	local l = Instance.new("PointLight")
	l.Range = 40
	l.Color = Color3.fromRGB(255, 220, 160)
	l.Parent = lamp
	local board = part(model, "Departures", Vector3.new(10, 5, 0.5), CFrame.lookAt(a + dir * 24, a) * CFrame.new(-(width / 2 + 3), 6, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	part(model, "BoardPost", Vector3.new(0.6, 6, 0.6), board.CFrame * CFrame.new(0, -5.5, 0), Rustic.WoodDark, Enum.Material.Wood)
	model.PrimaryPart = deck
	model.Parent = parent
	return model, board
end

-- The deck -----------------------------------------------------------------------------------------------------

-- Deck life (cosmetic, nothing here touches hay or needles) ----------------------------------------------------------

local SNACKS = { "a hay-dusted pretzel", "a cup of chowder", "a toffee apple", "a mug of cocoa", "a fish sandwich" }
local CATCHES = {
	{ "an old boot", 30 },
	{ "a herring", 25 },
	{ "a mackerel", 20 },
	{ "a tangle of twine", 15 },
	{ "a crab, who lets go and leaves", 8 },
	{ "a message in a bottle (it just says HELLO)", 2 },
}
local fishing = {} -- player -> true while a line is out

local function prompt(parent, action, object, hold)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = 8
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local function catch()
	local total = 0
	for _, c in CATCHES do
		total += c[2]
	end
	local pick = math.random() * total
	for _, c in CATCHES do
		pick -= c[2]
		if pick <= 0 then
			return c[1]
		end
	end
	return CATCHES[1][1]
end

local function deckLife(spots)
	if spots.counter then
		prompt(spots.counter, ("Buy a snack ($%d)"):format(Prices.Travel.snack or 15), "Galley").Triggered:Connect(function(player)
			local ok, why = Bank.charge(player, Prices.Travel.snack or 15, "Ferry snack")
			Data.toast(player, ok and ("You enjoy %s and watch the sea."):format(SNACKS[math.random(#SNACKS)]) or (why or "Not enough cash for a snack."))
		end)
	end
	if spots.board then
		CollectionService:AddTag(spots.board, "BountyBoard")
		prompt(spots.board, "Read", "Bounty board").Triggered:Connect(function(player)
			Data.toast(player, "Today's bounties are pinned here. Open your quest log, Bounties tab, to track them.")
		end)
	end
	if spots.fishing then
		prompt(spots.fishing, "Cast a line", "Fishing spot", 2).Triggered:Connect(function(player)
			if fishing[player] then
				return
			end
			fishing[player] = true
			task.delay(math.random(3, 7), function()
				fishing[player] = nil
				if player.Parent then
					player:SetAttribute("FishCaught", (player:GetAttribute("FishCaught") or 0) + 1)
					Data.toast(player, ("You reel in %s!"):format(catch()))
				end
			end)
		end)
	end
end

-- Builds a shuttle's deck (ferry hull or zeppelin gondola) centered on cframe, deck top at cframe's height.
-- Returns the model, its root deck part and the gate parts at each end.
local function buildDeck(def, cframe, parent)
	local model = Instance.new("Model")
	model.Name = def.name
	local L, W = def.length, def.width
	local root = part(model, "Deck", Vector3.new(W, 1.2, L), cframe * CFrame.new(0, -0.6, 0), def.zeppelin and Rustic.Wood or IRON, def.zeppelin and Enum.Material.WoodPlanks or Enum.Material.DiamondPlate)
	root.CustomPhysicalProperties = PhysicalProperties.new(3, 0.9, 0, 1, 1)
	model.PrimaryPart = root

	local visuals = {}
	local snacks = {}
	local function look(name, size, offset, color, material, collide, shape)
		local p = part(model, name, size, cframe * offset, color, material, collide)
		if shape then
			p.Shape = shape
		end
		table.insert(visuals, p)
		return p
	end

	-- Side rails, and lane stripes for three lanes of trucks.
	for _, side in { -1, 1 } do
		look("Bulwark", Vector3.new(1, GATE_H, L), CFrame.new(side * (W / 2 - 0.5), GATE_H / 2, 0), def.zeppelin and Rustic.WoodDark or IRON_DARK, Enum.Material.Metal)
	end
	for _, x in { -W / 6, W / 6 } do
		look("LaneStripe", Vector3.new(0.5, 0.05, L - 8), CFrame.new(x, 0.03, 0), Rustic.PaintYellow, Enum.Material.SmoothPlastic, false)
	end

	-- Gates across both ends: shut while moving, open (and out of the way) while boarding.
	local gates = {}
	for _, z in { -L / 2 + 0.4, L / 2 - 0.4 } do
		local gate = look("Gate", Vector3.new(W - 2, GATE_H, 0.6), CFrame.new(0, GATE_H / 2, z), Rustic.PaintYellow, Enum.Material.Metal)
		table.insert(gates, gate)
	end

	if def.zeppelin then
		-- The gondola hangs under a long canvas envelope on struts high enough for a truck to pass under.
		local high = 26
		look("Envelope", Vector3.new(L * 0.95, 26, 26), CFrame.new(0, high + 14, 0) * CFrame.Angles(0, math.pi / 2, 0), Rustic.Cloth, Enum.Material.Fabric, true, Enum.PartType.Cylinder)
		for _, z in { -L * 0.47, L * 0.47 } do
			look("EnvelopeEnd", Vector3.new(26, 26, 26), CFrame.new(0, high + 14, z), Rustic.Cloth, Enum.Material.Fabric, true, Enum.PartType.Ball)
		end
		for _, x in { -W / 2 + 0.6, W / 2 - 0.6 } do
			for _, z in { -L * 0.35, 0, L * 0.35 } do
				look("Strut", Vector3.new(0.6, high, 0.6), CFrame.new(x, high / 2, z), Rustic.WoodDark, Enum.Material.Wood)
			end
		end
		for _, side in { -1, 1 } do
			look("Propeller", Vector3.new(0.4, 10, 1.2), CFrame.new(side * 15, high + 6, L * 0.48), Rustic.WoodDark, Enum.Material.Wood)
		end
		look("Fin", Vector3.new(0.6, 14, 12), CFrame.new(0, high + 28, L * 0.45), Rustic.PaintRed, Enum.Material.Fabric)
	else
		-- A ferry hull under the deck (it never collides, so the sea floor can't snag it), a wheelhouse on the
		-- south rail clear of the lanes, and a funnel.
		look("Hull", Vector3.new(W + 2, 7, L), CFrame.new(0, -4.7, 0), IRON_DARK, Enum.Material.Metal, false)
		look("Waterline", Vector3.new(W + 2.2, 1, L + 0.2), CFrame.new(0, -3.2, 0), Rustic.PaintRedDark, Enum.Material.Metal, false)
		local house = CFrame.new(W / 2 + 4, 0, 0)
		look("WheelhouseBase", Vector3.new(7, 4, 36), house * CFrame.new(0, -2, 0), IRON_DARK, Enum.Material.Metal)
		look("Wheelhouse", Vector3.new(7, 10, 26), house * CFrame.new(0, 5, 0), Rustic.PaintCream, Enum.Material.Metal)
		look("WheelhouseRoof", Vector3.new(8, 0.6, 28), house * CFrame.new(0, 10.3, 0), Rustic.PaintRedDark, Enum.Material.Metal)
		look("Windows", Vector3.new(7.1, 2.2, 22), house * CFrame.new(0, 7, 0), Rustic.Glass, Enum.Material.Glass, false)
		look("Funnel", Vector3.new(4, 9, 4), house * CFrame.new(0, 15, 6), IRON_DARK, Enum.Material.Metal)
		look("FunnelBand", Vector3.new(4.2, 1.4, 4.2), house * CFrame.new(0, 18, 6), Rustic.PaintRed, Enum.Material.Metal, false)

		-- The promenade along the north rail, for drivers stretching their legs on the crossing: a snack stand, a
		-- bounty board and a fishing spot at the stern. Up a step and outside the bulwark, so it never takes a lane.
		local walk = CFrame.new(-(W / 2 + 4), 0, 0)
		look("PromenadeBase", Vector3.new(7, 4, 70), walk * CFrame.new(0, -2, 0), IRON_DARK, Enum.Material.Metal)
		look("Promenade", Vector3.new(7, 0.4, 70), walk * CFrame.new(0, 0.2, 0), Rustic.Wood, Enum.Material.WoodPlanks)
		look("PromenadeRail", Vector3.new(0.4, 3, 70), walk * CFrame.new(-3.3, 1.9, 0), Rustic.WoodDark, Enum.Material.Wood)
		-- Snack stand.
		local stand = walk * CFrame.new(0.5, 0, -22)
		local counter = look("SnackCounter", Vector3.new(3, 3.2, 8), stand * CFrame.new(-1.5, 2, 0), Rustic.PaintCream, Enum.Material.WoodPlanks)
		local standLook = { counter }
		standLook[2] = look("SnackAwning", Vector3.new(5, 0.3, 9), stand * CFrame.new(-1, 6.2, 0) * CFrame.Angles(0, 0, math.rad(-12)), Rustic.PaintRed, Enum.Material.Fabric, false)
		for _, z in { -4, 4 } do
			standLook[#standLook + 1] = look("SnackPole", Vector3.new(0.3, 4.4, 0.3), stand * CFrame.new(1.2, 4, z), Rustic.WoodDark, Enum.Material.Wood, false)
		end
		snacks.counter = look("SnackSign", Vector3.new(0.2, 1.2, 5), stand * CFrame.new(0, 3.9, 0), Rustic.PaintYellow, Enum.Material.WoodPlanks, false)
		-- Bounty board.
		local board = look("FerryBountyBoard", Vector3.new(0.4, 4, 6), walk * CFrame.new(-2.8, 3.6, 4), Rustic.Wood, Enum.Material.WoodPlanks)
		snacks.board = board
		-- Fishing spot at the stern rail.
		snacks.fishing = look("FishingSpot", Vector3.new(2, 0.3, 2), walk * CFrame.new(-1.5, 0.45, 30), Rustic.WoodDark, Enum.Material.Wood, false)
		-- The Blender snack stand (service side +X, toward the lanes, like this one) and fishing spot when imported.
		-- Each is only a look, welded to its part, which keeps the prompt and stays the look until the mesh loads.
		table.insert(standLook, snacks.counter)
		local deckTop = (cframe * walk).Y + 0.4
		local standMesh = Props.make("ferry_snack_stand", cframe * stand * CFrame.new(-0.9, 3.3, 0))
		if standMesh then
			Props.restOn(standMesh, deckTop)
			Props.weldTo(standMesh, counter, standLook)
		end
		local spotMesh = Props.make("fishing_spot", cframe * walk * CFrame.new(-1.5, 2, 30))
		if spotMesh then
			Props.restOn(spotMesh, deckTop)
			Props.weldTo(spotMesh, snacks.fishing, snacks.fishing)
		end
	end

	-- Everything rides on the deck.
	for _, p in visuals do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Anchored = false
		p.Massless = true
	end
	model.Parent = parent
	deckLife(snacks)
	return model, root, gates
end

-- Lashing ------------------------------------------------------------------------------------------------------

local function setDrive(model, enabled)
	local chassis = model.PrimaryPart
	if not chassis then
		return
	end
	for _, name in { "Drive", "Steer" } do
		local c = chassis:FindFirstChild(name)
		if c then
			if name == "Steer" and enabled then
				c.CFrame = CFrame.Angles(0, yawOf(chassis.CFrame), 0)
			end
			c.Enabled = enabled
		end
	end
end

local function giveBack(model)
	local owner = Players:GetPlayerByUserId(model:GetAttribute("OwnerId") or 0)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and not p.Anchored then
			pcall(function()
				p:SetNetworkOwner(owner)
			end)
		end
	end
end

-- Is a vehicle standing on this deck?
local function onDeck(shuttle, model)
	local chassis = model.PrimaryPart
	if not chassis or chassis.Anchored then
		return false
	end
	local spot = shuttle.root.CFrame:PointToObjectSpace(chassis.Position)
	return math.abs(spot.X) < shuttle.def.width / 2 and math.abs(spot.Z) < shuttle.def.length / 2 and spot.Y > -2 and spot.Y < LASH_HEIGHT
end

-- Fares -------------------------------------------------------------------------------------------------------

local function tell(player, text)
	if player and Data.get(player) then
		Data.toast(player, text)
	end
end

-- The trailer hitched to a truck, if its owner has one on.
local function trailerOf(truck)
	local id = truck:GetAttribute("TruckId")
	for model in Vehicles.all() do
		if model ~= truck and model:GetAttribute("HitchedTo") == id and model:GetAttribute("OwnerId") == truck:GetAttribute("OwnerId") then
			return model
		end
	end
	return nil
end

-- Rolls an unpaid truck (and its trailer) back onto the pier at this stop, off the deck, keeping its heading.
local function sendBack(model, stop)
	local chassis = model.PrimaryPart
	if not chassis then
		return
	end
	local from = chassis.Position
	local to = stop.edge + stop.inland * 20
	local move = CFrame.new(Vector3.new(to.X - from.X, 0.5, to.Z - from.Z))
	local trailer = trailerOf(model)
	model:PivotTo(move * model:GetPivot())
	if trailer then
		trailer:PivotTo(move * trailer:GetPivot())
	end
end

-- Every truck on the deck pays its fare once per crossing (trailers ride free with their truck). A truck whose
-- owner can't pay is rolled back onto the pier with the reason.
-- The Captain's Barge (the Captain's Log quest reward) is a lifetime pass: its holder's trucks sail free.
local Quests = nil
local function sailsFree(owner)
	if Quests == nil then
		local ok, module = pcall(require, script.Parent.Quests)
		Quests = ok and module or false
	end
	return Quests and Quests.has and Quests.has(owner, "captains_barge") == true
end

local function collectFares(shuttle, stop)
	for model, owner in Vehicles.all() do
		if shuttle.paid[model] or not model:GetAttribute("TruckId") or model:GetAttribute("OnFerry") or not onDeck(shuttle, model) then
			continue
		end
		local fare = sailsFree(owner) and 0 or (shuttle.def.fare or 0)
		local ok, message = Bank.charge(owner, fare, shuttle.def.name .. " fare")
		if ok then
			shuttle.paid[model] = true
			if fare > 0 then
				tell(owner, ("%s: fare $%d paid. Stay on board, the gates close at departure."):format(shuttle.def.name, fare))
			elseif (shuttle.def.fare or 0) > 0 then
				tell(owner, ("%s: the Captain's Barge pass, you sail free. Stay on board."):format(shuttle.def.name))
			end
		else
			tell(owner, ("The %s fare is $%d. %s"):format(shuttle.def.name, fare, message or ""))
			sendBack(model, stop)
		end
	end
end

local function lash(shuttle)
	for model in Vehicles.all() do
		-- Only paid trucks sail (collectFares rolled the others back); trailers ride with them.
		if model:GetAttribute("TruckId") and not shuttle.paid[model] then
			continue
		end
		if not model:GetAttribute("OnFerry") and onDeck(shuttle, model) then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "FerryLash"
			weld.Part0 = shuttle.root
			weld.Part1 = model.PrimaryPart
			weld.Parent = model.PrimaryPart
			model:SetAttribute("OnFerry", shuttle.def.name)
			setDrive(model, false)
			shuttle.lashed[model] = weld
		end
	end
	pcall(function()
		shuttle.root:SetNetworkOwner(nil)
	end)
end

local function unlash(shuttle)
	for model, weld in shuttle.lashed do
		weld:Destroy()
		if model.Parent then
			model:SetAttribute("OnFerry", nil)
			setDrive(model, true)
			giveBack(model)
		end
	end
	shuttle.lashed = {}
	shuttle.paid = {}
	pcall(function()
		shuttle.root:SetNetworkOwner(nil)
	end)
end

-- Timetable ----------------------------------------------------------------------------------------------------

local function setGates(shuttle, closed)
	for _, gate in shuttle.gates do
		gate.CanCollide = closed
		gate.Transparency = closed and 0 or 0.85
	end
	for _, apron in shuttle.aprons do
		apron.CanCollide = not closed
		apron.Transparency = closed and 1 or 0
	end
end

local function setBoards(shuttle, text)
	for _, label in shuttle.labels do
		label.Text = text
	end
end

-- Moves the deck from one stop to the other: speeds up, cruises, slows down.
local function travel(shuttle, from, to)
	local distance = (to.Position - from.Position).Magnitude
	local speed = shuttle.def.speed
	local ramp = math.min(distance / 2, speed * 3)
	local elapsed = 0
	local covered = 0
	local v = 0
	while covered < distance do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		local left = distance - covered
		local target = left < ramp and math.max(2, speed * left / ramp) or speed
		v = math.min(target, v + speed / 3 * dt)
		covered = math.min(distance, covered + v * dt)
		local alpha = covered / distance
		shuttle.align.Position = from.Position:Lerp(to.Position, alpha)
		local remaining = math.ceil((distance - covered) / math.max(v, 1))
		if math.floor(elapsed) ~= math.floor(elapsed - dt) then
			setBoards(shuttle, ("%s\nUnderway, arriving in about %ds"):format(shuttle.def.name:upper(), remaining))
		end
	end
	shuttle.align.Position = to.Position
end

local function run(shuttle)
	local stops = shuttle.stops
	local at = 1
	while shuttle.root.Parent do
		local here, there = stops[at], stops[3 - at]
		-- Boarding.
		setGates(shuttle, false)
		for t = shuttle.def.dock, 1, -1 do
			local text = ("%s\nBoarding at %s for %s\nFare $%d a truck, trailer free\nLeaves in %ds"):format(shuttle.def.name:upper(), here.name, there.name, shuttle.def.fare or 0, t)
			if t <= shuttle.def.warn then
				text ..= "\nAll aboard!"
			end
			setBoards(shuttle, text)
			collectFares(shuttle, here)
			task.wait(1)
		end
		-- Last fares, then lash everything down, close the gates, go.
		collectFares(shuttle, here)
		setGates(shuttle, true)
		lash(shuttle)
		travel(shuttle, here.cframe, there.cframe)
		task.wait(0.5)
		unlash(shuttle)
		at = 3 - at
	end
end

-- Builds one shuttle between two stops. Each stop is { name, cframe (deck top center at the stop, facing the way
-- to the other stop) }. aprons are plates at the piers that bridge the gap while docked.
local function startShuttle(def, stops, parent, labels, aprons)
	local model, root, gates = buildDeck(def, stops[1].cframe, parent)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Course"
	attachment.Position = Vector3.new(0, 0.6, 0) -- the deck top's center
	attachment.Parent = root
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.Position = stops[1].cframe.Position
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = attachment
	orient.RigidityEnabled = true
	orient.CFrame = stops[1].cframe.Rotation
	orient.Parent = root
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local shuttle = {
		def = def,
		model = model,
		root = root,
		gates = gates,
		align = align,
		stops = stops,
		labels = labels,
		aprons = aprons,
		lashed = {},
		paid = {},
	}
	table.insert(labels, boardLabel(root, Vector3.new(0, def.zeppelin and 50 or 16, 0), 320))
	table.insert(shuttles, shuttle)
	task.spawn(run, shuttle)
	return shuttle
end

-- A ramp plate at the end of a pier that bridges onto the docked deck.
local function apron(parent, pierEnd, dir, deckTop, width)
	local p = part(parent, "Apron", Vector3.new(width - 4, 0.4, 5), CFrame.lookAt(pierEnd, pierEnd + dir) * CFrame.new(0, deckTop - pierEnd.Y - 0.15, -1.6), IRON, Enum.Material.DiamondPlate)
	return p
end

function Ferry.build(worldFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Ferries"
	folder.Parent = worldFolder
	local F = Map.Ferry
	local deckTop = F.DeckTop

	for _, route in F.Routes do
		local a2, b2 = route.a.pierEnd, route.b.pierEnd
		local dir2 = (b2 - a2).Unit
		local dir = Vector3.new(dir2.X, 0, dir2.Y)
		local _, boardA = buildPier(folder, route.a.shore, a2, deckTop, 30, route.a.name)
		local _, boardB = buildPier(folder, route.b.shore, b2, deckTop, 30, route.b.name)
		local labels = { boardLabel(boardA, Vector3.new(0, 3, 0)), boardLabel(boardB, Vector3.new(0, 3, 0)) }
		local aprons = {
			apron(folder, Vector3.new(a2.X, deckTop, a2.Y), dir, deckTop, 30),
			apron(folder, Vector3.new(b2.X, deckTop, b2.Y), -dir, deckTop, 30),
		}
		-- The deck docks with its end against the pier end; it always faces from A to B.
		local half = F.Length / 2 + 0.6
		local facing = CFrame.lookAt(Vector3.zero, dir)
		local stopA = CFrame.new(Vector3.new(a2.X, deckTop, a2.Y) + dir * half) * facing
		local stopB = CFrame.new(Vector3.new(b2.X, deckTop, b2.Y) - dir * half) * facing
		startShuttle({
			name = route.name,
			length = F.Length,
			width = F.Width,
			speed = F.Speed,
			dock = F.Dock,
			warn = F.Warn,
			fare = Prices.Travel.ferry,
		}, {
			{ name = route.a.name, cframe = stopA, edge = Vector3.new(a2.X, deckTop, a2.Y), inland = -dir },
			{ name = route.b.name, cframe = stopB, edge = Vector3.new(b2.X, deckTop, b2.Y), inland = dir },
		}, folder, labels, aprons)
	end

	-- The zeppelin: it lands on the Homestead field, and docks beside a platform at the edge of Sky Island.
	local Z = Map.Zeppelin
	local a, b = Z.a.pos, Z.b.pos
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
	local facing = CFrame.lookAt(Vector3.zero, flat)
	local stopA = CFrame.new(a) * facing
	local stopB = CFrame.new(b) * facing
	-- The sky platform runs from the zeppelin's front end onto the island.
	local platformStart = b + flat * (Z.Length / 2 + 0.6)
	local platformLength = 70
	local platformCF = CFrame.lookAt(platformStart + flat * platformLength / 2, platformStart + flat * platformLength)
	local sky = Instance.new("Model")
	sky.Name = "Sky Dock"
	part(sky, "SkyDock", Vector3.new(Z.Width, 1.2, platformLength), platformCF * CFrame.new(0, -0.6, 0), Rustic.Wood, Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		part(sky, "SkyRail", Vector3.new(0.6, 1.6, platformLength), platformCF * CFrame.new(side * (Z.Width / 2 - 0.3), 0.8, 0), Rustic.WoodDark, Enum.Material.Wood)
	end
	local skyBoard = part(sky, "Departures", Vector3.new(10, 5, 0.5), platformCF * CFrame.new(Z.Width / 2 + 3, 6, 10) * CFrame.Angles(0, math.pi / 2, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	sky.Parent = folder
	-- The mooring mast on the field.
	local mast = Instance.new("Model")
	mast.Name = "Mooring Mast"
	local mastBase = stopA * CFrame.new(Z.Width / 2 + 8, 0, 0)
	part(mast, "Mast", Vector3.new(2, 46, 2), mastBase * CFrame.new(0, 23, 0), IRON, Enum.Material.Metal)
	part(mast, "MastTop", Vector3.new(4, 1, 4), mastBase * CFrame.new(0, 46.5, 0), Rustic.PaintRed, Enum.Material.Metal)
	local fieldBoard = part(mast, "Departures", Vector3.new(10, 5, 0.5), mastBase * CFrame.new(0, 6, 3) * CFrame.Angles(0, math.pi / 2, 0), Rustic.WoodDark, Enum.Material.WoodPlanks)
	mast.Parent = folder
	local labels = { boardLabel(fieldBoard, Vector3.new(0, 3, 0)), boardLabel(skyBoard, Vector3.new(0, 3, 0)) }
	startShuttle({
		name = Z.name,
		zeppelin = true,
		length = Z.Length,
		width = Z.Width,
		speed = Z.Speed,
		dock = Z.Dock,
		warn = 6,
		fare = Prices.Travel.zeppelin,
	}, {
		{ name = Z.a.name, cframe = stopA, edge = a - flat * (Z.Length / 2 + 4), inland = -flat },
		{ name = Z.b.name, cframe = stopB, edge = platformStart, inland = flat },
	}, folder, labels, {})
	-- Small ramps at the field, since the gondola's deck sits a step above the grass.
	for _, side in { -1, 1 } do
		local edge = stopA * CFrame.new(0, 0, side * (Z.Length / 2 + 2.5))
		local ramp = Instance.new("WedgePart")
		ramp.Name = "FieldRamp"
		ramp.Size = Vector3.new(Z.Width - 4, 1.2, 4)
		-- A wedge is tallest at its back (+Z); that side meets the gondola.
		ramp.CFrame = edge * CFrame.new(0, -0.6, 0) * CFrame.Angles(0, side > 0 and math.pi or 0, 0)
		ramp.Color = Rustic.Wood
		ramp.Material = Enum.Material.WoodPlanks
		ramp.Anchored = true
		ramp.Parent = folder
	end
	return folder
end

-- The ferries and the zeppelin, for the map: { name, model }.
function Ferry.all()
	return shuttles
end

-- For the self-tests (SelfTests/Map.luau): is a vehicle on this shuttle's deck, and roll one back to a stop's pier.
Ferry.onDeck = onDeck
Ferry.sendBack = sendBack

return Ferry

end

MODULES["Services.WorldMap"] = function(script)
-- The rest of the Stitched Isles around Meadow Farm: opens Meadow's two road exits, writes the islands' terrain in the
-- background, and builds everything on them (Regions), the Longstitch Highway, the ferries and the zeppelin. Also
-- runs the rich field: every few minutes one hay field somewhere on the map gets a gold beam and 2x needles.
-- Config: src/shared/Config/WorldMap.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Config.WorldMap)
local Announce = require(script.Parent.Announce)
local WorldTerrain = require(script.Parent.WorldTerrain)
local Regions = require(script.Parent.Regions)
local Highway = require(script.Parent.Highway)
local Ferry = require(script.Parent.Ferry)
local WorldShape = require(script.Parent.WorldShape)
local WorldClock = require(script.Parent.WorldClock)
local Weather = require(script.Parent.Weather)
local RegionEvents = require(script.Parent.RegionEvents)
local Wilds = require(script.Parent.Wilds)
local RoadPolish = require(script.Parent.RoadPolish)
local HayWagon = require(script.Parent.HayWagon)
local Discoveries = require(script.Parent.Discoveries)
local SpindleDoor = require(script.Parent.SpindleDoor)
local FallSafety = require(script.Parent.FallSafety)
local Festival = require(script.Parent.Festival)

local WorldMap = {}

local RICH_BOOST = 2

-- Meadow was built as a closed valley (gates and invisible walls at its edge). Its roads now lead somewhere.
local function openMeadow(worldFolder)
	local meadow = worldFolder:FindFirstChild("Meadow")
	if not meadow then
		return
	end
	for _, child in meadow:GetChildren() do
		if child.Name == "ClosedGate" or child.Name == "EdgeWall" then
			child:Destroy()
		elseif child.Name == "Signpost" then
			for _, label in child:GetDescendants() do
				if label:IsA("TextLabel") then
					if string.find(label.Text, "COMING SOON") then
						child:Destroy()
						break
					end
					label.Text = string.gsub(label.Text, " %(soon%)", "")
				end
			end
		end
	end
end

-- Invisible walls at the edge of the world, out at sea, so nobody drives or swims off the map.
local function worldWalls(folder)
	local min, max = Map.Bounds.min, Map.Bounds.max
	local mid = (min + max) / 2
	local size = max - min
	for _, def in {
		{ Vector3.new(min.X, 0, mid.Y), Vector3.new(2, 1200, size.Y) },
		{ Vector3.new(max.X, 0, mid.Y), Vector3.new(2, 1200, size.Y) },
		{ Vector3.new(mid.X, 0, min.Y), Vector3.new(size.X, 1200, 2) },
		{ Vector3.new(mid.X, 0, max.Y), Vector3.new(size.X, 1200, 2) },
	} do
		local wall = Instance.new("Part")
		wall.Name = "WorldEdge"
		wall.Size = def[2]
		wall.Position = def[1] + Vector3.new(0, 500, 0)
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CanTouch = false
		wall.Parent = folder
	end
end

-- In Studio: lists anything solid standing in a road lane (a truck would hit it), so a blocked road shows up in the
-- Output the first time the map is built rather than when someone drives into it.
local function auditRoads(folder)
	local half = Map.RoadWidth / 2 - 1
	local blocked = {}
	for _, p in folder:GetDescendants() do
		if not (p:IsA("BasePart") and p.Anchored and p.CanCollide and p.Transparency < 1) then
			continue
		end
		local cf, size = p.ExtentsCFrame, p.ExtentsSize
		local bottom, top = cf.Y - size.Y / 2, cf.Y + size.Y / 2
		for _, o in { Vector3.zero, Vector3.new(size.X / 2, 0, size.Z / 2), Vector3.new(-size.X / 2, 0, size.Z / 2), Vector3.new(size.X / 2, 0, -size.Z / 2), Vector3.new(-size.X / 2, 0, -size.Z / 2) } do
			local at = cf * (o * 0.9)
			local d, h = WorldShape.nearestRoad(at.X, at.Z)
			if d and d < half and top > h + 0.6 and bottom < h + 9 then
				table.insert(blocked, ("%s at (%d, %d) on the %s"):format(p:GetFullName(), at.X, at.Z, select(3, WorldShape.nearestRoad(at.X, at.Z)) or "road"))
				break
			end
		end
	end
	if #blocked > 0 then
		warn(("[Needlewood] %d parts stand in a road lane:\n  %s"):format(#blocked, table.concat(blocked, "\n  ", 1, math.min(#blocked, 25))))
	else
		print("[Needlewood] Road check: every road lane is clear")
	end
end

-- Rich field ------------------------------------------------------------------------------------------------------

local rich = nil -- the field entry that is rich right now
local beacon = nil

-- Puts the rich field's boost on an entry's bales (RichBoost marks them), or takes it back off only the marked ones.
-- Taking it off leaves whatever else the bale earned: a festival bale (FestivalBoost) goes back to the festival's boost.
local function setBoost(entry, boost)
	for b in entry.bales do
		local body = b.body
		if body and body.Parent then
			if boost then
				body:SetAttribute("NeedleBoost", math.max(body:GetAttribute("NeedleBoost") or 1, boost))
				body:SetAttribute("RichBoost", true)
			elseif body:GetAttribute("RichBoost") then
				body:SetAttribute("RichBoost", nil)
				body:SetAttribute("NeedleBoost", body:GetAttribute("FestivalBoost") and Map.FestivalBoost or nil)
			end
		end
	end
end

local function makeBeacon(entry, parent)
	local model = Instance.new("Model")
	model.Name = "RichFieldBeacon"
	-- Always sent to every client, even with StreamingEnabled, so the beam shows from across the map.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(300, 3, 3)
	beam.CFrame = CFrame.new(entry.center + Vector3.new(0, 150, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	beam.Color = Color3.fromRGB(242, 196, 70)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.45
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Parent = model
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 30 - 150, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 6000
	gui.LightInfluence = 0
	gui.Parent = beam
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(250, 214, 110)
	label.TextStrokeTransparency = 0.3
	label.Text = "RICH FIELD\n2x needles"
	label.Parent = gui
	model.Parent = parent
	return model
end

local function pickRich(parent)
	local fields = Regions.fields
	if #fields == 0 then
		return
	end
	if rich then
		setBoost(rich, nil)
		rich.rich = false
	end
	if beacon then
		beacon:Destroy()
		beacon = nil
	end
	local choice
	repeat
		choice = fields[math.random(1, #fields)]
	until choice ~= rich or #fields == 1
	rich = choice
	rich.rich = true
	setBoost(rich, RICH_BOOST)
	beacon = makeBeacon(rich, parent)
	-- For map screens: where the rich field is now (a UI can mark it).
	ReplicatedStorage:SetAttribute("RichField", rich.center)
	ReplicatedStorage:SetAttribute("RichFieldRegion", rich.region)
	-- When it moves on (server time; the HUD countdown strip, Countdown.client.luau).
	ReplicatedStorage:SetAttribute("RichFieldEnds", workspace:GetServerTimeNow() + Map.RichMinutes * 60)
	Announce.say(("Rich field in %s: 2x needles for %d minutes. Follow the gold beam!"):format(rich.region, Map.RichMinutes), "event")
end

function WorldMap.build(worldFolder)
	local folder = Instance.new("Folder")
	folder.Name = "StitchedIsles"
	folder.Parent = worldFolder

	openMeadow(worldFolder)
	worldWalls(folder)
	-- Day and night (the clock, the lamps; the sky colors are client side).
	WorldClock.start()
	Weather.start()

	-- The terrain takes a while, nearest Meadow first; everything on top only needs the shape, so it goes up now.
	task.spawn(function()
		local ok, err = pcall(WorldTerrain.ensure)
		if not ok then
			warn("[Needlewood] Stitched Isles terrain failed: " .. tostring(err))
		end
	end)
	for _, step in {
		{ "regions", Regions.build },
		{ "highway", Highway.build },
		{ "ferries", Ferry.build },
		{ "wilds", Wilds.build },
		{ "road polish", RoadPolish.build },
		{ "road lanterns", RoadPolish.buildLanterns },
		{ "hay wagon", HayWagon.build },
	} do
		local ok, err = pcall(step[2], folder)
		if not ok then
			warn(("[Needlewood] Stitched Isles %s failed: %s"):format(step[1], tostring(err)))
		end
	end

	if RunService:IsStudio() then
		local isles = folder:FindFirstChild("Isles")
		if isles then
			task.spawn(auditRoads, isles)
		end
	end

	-- Moves the rich field on now (the rotation below does this every few minutes; self-tests call it directly).
	function WorldMap.rotateRich()
		pickRich(folder)
	end

	task.spawn(function()
		while folder.Parent do
			pickRich(folder)
			task.wait(Map.RichMinutes * 60)
		end
	end)
	RegionEvents.start()
	Discoveries.start()
	SpindleDoor.start()
	FallSafety.start()
	Festival.start(folder)
end

return WorldMap

end

MODULES["Services.DayNight"] = function(script)
-- The day and night cycle. The server turns Lighting.ClockTime and every client sees it. Rituals and night quests
-- ask this module which part of the day it is. Lengths are in Config/Quests.luau (Time).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestConfig = require(ReplicatedStorage.Shared.Config.Quests)

local DayNight = {}

local T = QuestConfig.Time
local started = false

-- Game hour now, 0 to 24.
function DayNight.hour()
	return Lighting.ClockTime
end

local function inWindow(hour, window)
	local from, to = window[1], window[2]
	if from <= to then
		return hour >= from and hour < to
	end
	return hour >= from or hour < to -- the window wraps past midnight
end

-- window: "day", "dusk", "night" or "midnight" (Config/Quests Time.Windows). Anything else is always true.
function DayNight.is(window)
	local range = window and T.Windows[window]
	if not range then
		return true
	end
	return inWindow(DayNight.hour(), range)
end

-- Real seconds until the window next opens (0 while it is open).
function DayNight.secondsUntil(window)
	local range = window and T.Windows[window]
	if not range or inWindow(DayNight.hour(), range) then
		return 0
	end
	local hours = (range[1] - DayNight.hour()) % 24
	return hours / 24 * T.DayMinutes * 60
end

function DayNight.start()
	if started then
		return
	end
	started = true
	Lighting.ClockTime = T.StartHour
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.5)
			local now = os.clock()
			local hours = (now - last) / (T.DayMinutes * 60) * 24
			last = now
			Lighting.ClockTime = (Lighting.ClockTime + hours) % 24
		end
	end)
end

return DayNight

end

MODULES["Services.WorldClock"] = function(script)
-- The world's clock, for everything outside quests: is it night, and the lamps that come on after sunset.
-- The clock itself is DayNight.luau (Quests thread): a 20-minute day turning Lighting.ClockTime on the server. The
-- sky's colors through the day (golden hour, blue night, each region's haze) are drawn per client in
-- DayNightSky.client.luau.
--
--   WorldClock.isNight()   true from nightfall to dawn (Config/Quests Time.Windows.night), for the Corn Night Maze,
--                          the Ghost Hauler and anything else that only happens in the dark
--   WorldClock.phase()     "midnight" / "night" / "dusk" / "day", from the same Quests windows
--   WorldClock.lampsOn()   true from a little before dark to a little after dawn
--
-- Lamps: a PointLight / SpotLight inside a part named like "Lamp" or "Lantern" (LampPost, PierLamp, Lantern...) or
-- tagged "NightLamp" switches on at dusk and off at dawn, and its part glows only while lit. Tag a lamp
-- "AlwaysLit" to keep it on (cave lamps, the undersea tube).
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local DayNight = require(script.Parent.DayNight)
local Windows = require(game:GetService("ReplicatedStorage").Shared.Config.Quests).Time.Windows

local WorldClock = {}

local LAMPS_ON, LAMPS_OFF = 18.25, 6.25 -- game hours

function WorldClock.hour()
	return DayNight.hour()
end

function WorldClock.isNight()
	return DayNight.is("night")
end

-- "midnight", "night", "dusk" or "day" (Quests' windows, the narrowest that is open now).
function WorldClock.phase()
	for _, window in { "midnight", "night", "dusk", "day" } do
		if Windows[window] and DayNight.is(window) then
			return window
		end
	end
	return "day"
end

function WorldClock.lampsOn(hour)
	hour = hour or DayNight.hour()
	return hour >= LAMPS_ON or hour < LAMPS_OFF
end

local function isLamp(light)
	local holder = light.Parent
	if not (holder and holder:IsA("BasePart")) then
		return false
	end
	if CollectionService:HasTag(holder, "AlwaysLit") or CollectionService:HasTag(light, "AlwaysLit") then
		return false
	end
	if CollectionService:HasTag(holder, "NightLamp") or CollectionService:HasTag(light, "NightLamp") then
		return true
	end
	local name = holder.Name
	return string.find(name, "Lamp") ~= nil or string.find(name, "Lantern") ~= nil
end

local lamps = {} -- light -> its part's lit material

local function setLamp(light, on)
	light.Enabled = on
	local holder = light.Parent
	if holder and holder:IsA("BasePart") then
		if lamps[light] == nil then
			lamps[light] = holder.Material
		end
		holder.Material = on and lamps[light] or Enum.Material.SmoothPlastic
	end
end

local lampsLit = false

local function consider(d)
	if (d:IsA("PointLight") or d:IsA("SpotLight")) and lamps[d] == nil and isLamp(d) then
		setLamp(d, lampsLit)
	end
end

local started = false
function WorldClock.start()
	if started then
		return
	end
	started = true
	DayNight.start()
	-- Atmosphere for the sky script to tint (the place may not have one).
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.28
		atmosphere.Offset = 0.1
		atmosphere.Haze = 1.2
		atmosphere.Glare = 0.3
		atmosphere.Parent = Lighting
	end
	-- Every lamp there is now, and each one built later (plots, machines) as it appears: no rescans.
	lampsLit = WorldClock.lampsOn()
	for _, d in workspace:GetDescendants() do
		consider(d)
	end
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("PointLight") or d:IsA("SpotLight") then
			task.defer(consider, d) -- once its tags and parent are set
		end
	end)
	workspace.DescendantRemoving:Connect(function(d)
		lamps[d] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = WorldClock.lampsOn()
			if now ~= lampsLit then
				lampsLit = now
				for light in lamps do
					if light.Parent then
						setLamp(light, now)
					end
				end
			end
		end
	end)
end

return WorldClock

end

MODULES["Shared.Config.Quests"] = function(script)
-- Quests, rituals, daily bounties and the mystery items they unlock. Server and client both read this file; only the
-- server decides progress (src/server/Services/Quests.luau). Every number is a placeholder to tune from playtests.
--
-- Quest gear is earned, never sold: no cash or Robux price anywhere buys it (GAME_PLAN_V8 section 9).
--
-- Step kinds:
--   event   count game events (Events.luau kinds, plus bale_lifted). filter matches the event's info.
--   own     something the save owns right now: truck, plot, gloves_tier (value), piece_kind (value)
--   visit   walk up to a spot, or to every spot in `spots` (any order)
--   talk    press the prompt on a spot. distinct = counts once each time the spot has moved (the wandering scarecrow).
--           say = what you read or hear there (a toast)
--   collect press the prompt on an item spot, or on every spot in `spots`
--   offer   press the prompt on a spot and pay: needles = { [needleId] = count } from your pocket, needlesEach = that
--           many of every needle type you can reach, cash = dollars
--   pattern hay bales standing on the spot's pads: "stones" (four stones) or "daily" (tonight's 3 x 3 sign).
--           The bales are taken when it completes.
--   find    a rare item that can drop when you break a bale: chance per bale, pity = guaranteed by this many bales
--   run     run a timed maze spot (Quests.Runs): cross its start line, reach its heart. seconds = only a run at least
--           that fast counts
-- when = "day", "dusk", "night" or "midnight" limits a step to that part of the day (see Time below).
-- hint = one line shown under the current step in the quest log; place = a UI Places id (dealer, landoffice, plot...)
-- for steps that send you to a building rather than a quest spot, so GO and "Show the way" work there too.
-- Spots belong to a region. `pos` is a Meadow Farm spot; `world` (X, Z) is a spot out on the Stitched Isles, set on the
-- ground there once the world map is built. A spot whose region is not built yet stands at its `fallback` in Meadow,
-- or waits (its quest says "Opens when ... is built"). A part tagged "QuestAnchor" with attribute SpotId = a spot id
-- (and Region = the region name) moves that spot onto the part, for hand-placed spots in Studio.
-- showWhen = a time window: the spot is only visible then (its prompt still answers, with "come back at ...").
-- inMaze = placed by the corn maze it stands in, not by a position here.
-- npc = a QuestGiver id (Regions townsperson): the spot stands at that person and their Talk prompt answers it.
-- pedestal = built on the part tagged MasterNeedlePedestal (SpindleDoor's Loom Room).
-- sea = (X, Z) out on the water: the spot floats at sea level there once the world map (and its sea) is built.
local Quests = {}

-- The day and night cycle (src/server/Services/DayNight.luau). Hours are game hours, 0-24.
Quests.Time = {
	DayMinutes = 20, -- one full day and night in real minutes
	StartHour = 10,
	Windows = {
		day = { 6, 18 },
		dusk = { 17.5, 20 },
		night = { 19.5, 5.5 },
		midnight = { 23, 1 }, -- about 1.7 real minutes each night
	},
}

Quests.WhenText = {
	day = "in daylight",
	dusk = "at dusk",
	night = "at night",
	midnight = "at midnight",
}

-- Places in the world. pos is on the ground in Meadow Farm (Y is found by a ray at build time). look is what the
-- spot is built as. radius is how close a visit has to be.
Quests.Spots = {
	-- Meadow Farm
	hank_board = { region = "Meadow", name = "Quest board", look = "board", pos = Vector3.new(-12, 0, -2) },
	wander_scarecrow = { region = "Meadow", name = "Wandering scarecrow", look = "scarecrow", wander = true },
	old_scarecrow = {
		region = "Meadow",
		name = "The Old Scarecrow",
		look = "ring",
		pos = Vector3.new(-205, 0, -150),
		radius = 14,
	},
	old_well = { region = "Meadow", name = "The old well", look = "well", pos = Vector3.new(205, 0, -175), radius = 10 },
	old_barn = { region = "Meadow", name = "The Old Barn", look = "barn", pos = Vector3.new(290, 0, -60), radius = 18 },
	barn_key = { region = "Meadow", name = "Rusty barn key", look = "key", pos = Vector3.new(282, 0, -52), item = true },
	journal_1 = {
		region = "Meadow",
		name = "Journal page",
		look = "page",
		pos = Vector3.new(-190, 0, 140),
		item = true,
	},
	journal_2 = {
		region = "Meadow",
		name = "Journal page",
		look = "page",
		pos = Vector3.new(-140, 0, -330),
		item = true,
	},
	journal_3 = { region = "Meadow", name = "Journal page", look = "page", pos = Vector3.new(-235, 0, 30), item = true },
	crop_circle = {
		region = "Meadow",
		name = "Crop circle",
		look = "circle",
		pos = Vector3.new(250, 0, -300),
		radius = 16,
	},
	-- The Corn Night Maze, east of the plots. Its corn walls are built from a fixed seed (Quests.luau LOOKS.maze); the
	-- three keys sit in its deepest dead ends and only show after dark.
	corn_maze = {
		region = "Meadow",
		name = "Heart of the maze",
		look = "maze",
		pos = Vector3.new(262, 0, 150),
		radius = 6,
	},
	maze_key_1 = {
		region = "Meadow",
		name = "Corn key",
		look = "cornkey",
		inMaze = true,
		item = true,
		showWhen = "night",
	},
	maze_key_2 = {
		region = "Meadow",
		name = "Corn key",
		look = "cornkey",
		inMaze = true,
		item = true,
		showWhen = "night",
	},
	maze_key_3 = {
		region = "Meadow",
		name = "Corn key",
		look = "cornkey",
		inMaze = true,
		item = true,
		showWhen = "night",
	},
	-- The Straw Labyrinth, in the far south-west of Meadow: a new maze every UTC day, run against the clock.
	straw_labyrinth = {
		region = "Meadow",
		name = "Straw Labyrinth bell",
		look = "labyrinth",
		pos = Vector3.new(-280, 0, -330),
		radius = 4,
	},
	-- The Drowned Rows: old pilings standing out of the sea south of the Meadow beach. Swim in from the beach side.
	drowned_rows = {
		region = "Meadow",
		name = "Drowned Rows chest",
		look = "rows",
		sea = Vector2.new(300, 1085),
		radius = 5,
	},
	-- The Weaver, chapter 1: words cut in the rock beside the Spindle door, and a spool that rises from Mirror Lake.
	weaver_words = {
		region = "The Spindle",
		name = "Words beside the door",
		look = "plaque",
		world = Vector2.new(163, -979),
		radius = 8,
	},
	weaver_spool = {
		region = "The Spindle",
		name = "Weaver's spool",
		look = "spool",
		world = Vector2.new(262, -880), -- the west shore of Mirror Lake
		showWhen = "midnight",
		item = true,
	},
	-- The Weaver, chapters 2 to 6 and the finale: one Master Needle shard per chapter, region by region.
	tailor_note = {
		region = "Meadow Shore",
		name = "The tailor's note",
		look = "page",
		world = Vector2.new(-238, 668), -- beside the Tailor's Shack
		radius = 8,
	},
	shore_glint = {
		region = "Meadow Shore",
		name = "Glint under the lighthouse",
		look = "shardglint",
		world = Vector2.new(412, 875),
		showWhen = "night",
		item = true,
	},
	stitched_pine = {
		region = "Pine Forest",
		name = "Stitched pine",
		look = "stitchedpine",
		world = Vector2.new(-1110, 90),
		radius = 10,
	},
	old_wren = {
		region = "Homestead Valley",
		name = "Old Wren",
		look = "marker",
		npc = "elder",
		radius = 8,
	},
	well_glint = {
		region = "Homestead Valley",
		name = "Glint in the hub well",
		look = "shardglint",
		world = Vector2.new(4, -1444),
		showWhen = "midnight",
		item = true,
	},
	sunken_stone = {
		region = "Swamp",
		name = "Sunken stone",
		look = "stone",
		world = Vector2.new(1120, 470),
		radius = 10,
	},
	keys_bead_1 = {
		region = "Thimble Keys",
		name = "Bead lantern",
		look = "lantern",
		world = Vector2.new(3020, -250),
		radius = 10,
	},
	keys_bead_2 = {
		region = "Thimble Keys",
		name = "Bead lantern",
		look = "lantern",
		world = Vector2.new(3110, -130),
		radius = 10,
	},
	keys_bead_3 = {
		region = "Thimble Keys",
		name = "Bead lantern",
		look = "lantern",
		world = Vector2.new(3200, -240),
		radius = 10,
	},
	keys_glint = {
		region = "Thimble Keys",
		name = "Glint on the string",
		look = "shardglint",
		world = Vector2.new(3100, -200),
		showWhen = "dusk",
		item = true,
	},
	master_pedestal = {
		region = "The Spindle",
		name = "The Master Needle's pedestal",
		look = "masterneedle",
		pedestal = true,
	},
	golden_bale = {
		region = "Meadow",
		name = "Golden Hay Bale",
		look = "golden",
		showWhen = "midnight",
		pos = Vector3.new(250, 0, -300),
		item = true,
	},

	-- The alien signal stones. Each stands in its own region; until the map has it, by the road out of Meadow toward it.
	signal_pine = {
		region = "Pine Forest",
		name = "Signal stone",
		look = "stone",
		fallback = Vector3.new(163, 0, 392),
		radius = 10,
		world = Vector2.new(-1090, 170),
	},
	signal_valley = {
		region = "Homestead Valley",
		name = "Signal stone",
		look = "stone",
		fallback = Vector3.new(-17, 0, -392),
		radius = 10,
		world = Vector2.new(180, -1450),
	},
	signal_grove = {
		region = "Haunted Grove",
		name = "Signal stone",
		look = "stone",
		fallback = Vector3.new(-330, 0, -250),
		radius = 10,
		world = Vector2.new(-1300, -950),
	},

	-- Old Bessie's parts, one from each of three regions. Traders leave them by the roads out of Meadow until the regions open.
	bessie_carb = {
		region = "Pine Forest",
		name = "Carburetor",
		look = "crate",
		fallback = Vector3.new(137, 0, 380),
		item = true,
		world = Vector2.new(-1240, 232),
	},
	bessie_radiator = {
		region = "Desert Dunes",
		name = "Radiator",
		look = "crate",
		fallback = Vector3.new(-43, 0, -385),
		item = true,
		world = Vector2.new(1312, -236),
	},
	bessie_spring = {
		region = "Snow Peak",
		name = "Seat spring",
		look = "crate",
		fallback = Vector3.new(-43, 0, -360),
		item = true,
		world = Vector2.new(-612, -1574),
	},

	-- Spots that only exist out in their region (no fallback). `world` places them on the Stitched Isles
	-- (Config/WorldMap.luau, Services/Regions.luau landmarks); a QuestAnchor part still overrides it.
	snow_door = { region = "Snow Peak", name = "Hidden door", look = "marker", world = Vector2.new(-1052, -1697) },
	volcano_crater = {
		region = "Volcano",
		name = "Crater rim",
		look = "stone",
		radius = 20,
		world = Vector2.new(1080, -1418),
	},
	graveyard_ghost = {
		region = "Bobbin Rock",
		name = "Captain's ghost",
		look = "ghost",
		world = Vector2.new(2585, -1760),
	},
	captains_log_1 = {
		region = "Bobbin Rock",
		name = "Log page",
		look = "page",
		item = true,
		world = Vector2.new(2770, -1878),
	},
	captains_log_2 = {
		region = "Bobbin Rock",
		name = "Log page",
		look = "page",
		item = true,
		world = Vector2.new(2680, -1960),
	},
	captains_log_3 = {
		region = "Bobbin Rock",
		name = "Log page",
		look = "page",
		item = true,
		world = Vector2.new(2860, -1770),
	},
	pyramid_garage = {
		region = "Desert Dunes",
		name = "Buried garage",
		look = "marker",
		radius = 16,
		world = Vector2.new(1500, -524),
	},
	pyramid_mechanic = {
		region = "Desert Dunes",
		name = "Old mechanic",
		look = "scarecrow",
		world = Vector2.new(1278, -212),
	},
	lantern_1 = {
		region = "Haunted Grove",
		name = "Lantern",
		look = "lantern",
		radius = 8,
		world = Vector2.new(-1073, -835),
	},
	lantern_2 = {
		region = "Haunted Grove",
		name = "Lantern",
		look = "lantern",
		radius = 8,
		world = Vector2.new(-990, -948),
	},
	lantern_3 = {
		region = "Haunted Grove",
		name = "Lantern",
		look = "lantern",
		radius = 8,
		world = Vector2.new(-908, -1060),
	},
	haunted_crossroads = {
		region = "Haunted Grove",
		name = "The crossroads",
		look = "stone",
		radius = 12,
		world = Vector2.new(-1176, -756),
	},
}

-- Where the wandering scarecrow can stand. He moves every WanderMinutes, never to the spot he is on.
Quests.WanderSpots = {
	Vector3.new(-262, 0, -60),
	Vector3.new(-90, 0, -262),
	Vector3.new(232, 0, 64),
	Vector3.new(255, 0, 300),
	Vector3.new(60, 0, -300),
	Vector3.new(-310, 0, 330),
}
Quests.WanderMinutes = 4

-- Quest trucks: built on a cash truck's body (base, from Config/Trucks) with their own name and paint. They are not
-- in the dealer's list and never go in the save's trucks list; the quest log calls them out.
Quests.Trucks = {
	old_bessie = {
		base = "rusty_pickup",
		name = "Old Bessie",
		paint = "PaintCream",
		maxSpeed = 52,
		blurb = "Hank's old pickup, rebuilt. A touch faster than a Rusty Pickup.",
	},
	sandrunner = {
		base = "rusty_pickup",
		name = "Sandrunner",
		paint = "PaintYellow",
		maxSpeed = 58,
		blurb = "The fastest pickup on sand.",
	},
	ghost_hauler = {
		base = "rusty_pickup",
		name = "Ghost Hauler",
		paint = "PaintBlue",
		maxSpeed = 54,
		glow = true,
		when = "night",
		blurb = "Glows in the dark and only comes out at night.",
	},
	starlight_hauler = {
		base = "rusty_pickup",
		name = "Starlight Hauler",
		paint = "PaintBlue",
		maxSpeed = 60,
		glow = true,
		blurb = "The alien collector's own truck. Glows, and outruns everything.",
	},
}

-- Everything a quest can give. kind: gear (a perk on a tool), gloves (an id in Config/Gloves QuestTiers), truck (an id
-- in Trucks above), relic (a mystery item for the collection), unlock (a quest-only build piece in Config/Land).
Quests.Rewards = {
	golden_shovel = {
		kind = "gear",
		name = "Golden Shovel",
		perk = "GoldenShovel",
		blurb = "Your shovel scoops twice as much hay.",
	},
	thread_rake = {
		kind = "gear",
		name = "Thread Rake",
		perk = "ThreadRake",
		blurb = "Every rake stroke pulls loose needles nearby into your pocket.",
	},
	scarecrow_gloves = {
		kind = "gloves",
		name = "Scarecrow Gloves",
		blurb = "Tier 2 gloves stuffed with straw. Wear them from the quest log.",
	},
	frostbite_mitts = {
		kind = "gloves",
		name = "Frostbite Mitts",
		blurb = "Tier 3 gloves. Frozen hay feels like meadow hay.",
	},
	magma_grips = { kind = "gloves", name = "Magma Grips", blurb = "Tier 4 gloves that shrug off the heat." },
	kraken_gauntlets = {
		kind = "gloves",
		name = "Kraken Gauntlets",
		blurb = "Tier 5 gauntlets from the bottom of the sea.",
	},
	starweave_gloves = {
		kind = "gloves",
		name = "Starweave Gloves",
		blurb = "Tier 6. Star hay is no heavier than meadow hay.",
	},
	old_bessie = { kind = "truck", name = "Old Bessie", blurb = "Call her from the quest log." },
	sandrunner = { kind = "truck", name = "Sandrunner", blurb = "Call it from the quest log." },
	ghost_hauler = { kind = "truck", name = "Ghost Hauler", blurb = "Call it from the quest log, at night." },
	starlight_hauler = { kind = "truck", name = "Starlight Hauler", blurb = "Call it from the quest log." },
	alien_collector = {
		kind = "unlock",
		name = "Alien Collector",
		blurb = "A sorter that finds every needle at once while its beam is up, once a day. Build it on your land.",
	},
	starbeam_collector = {
		kind = "unlock",
		name = "Starbeam Collector",
		blurb = "A beacon over one belt tile that pulls a bale of Star hay out of the sky now and then. Build it on your land.",
	},
	-- Daily streak rosettes (Streak below): a little ribbon pinned to your chest, the best one you have earned.
	streak_rosette_bronze = {
		kind = "cosmetic",
		name = "Bronze Rosette",
		blurb = "3 streak days. Pinned to your chest.",
		color = { 176, 124, 72 },
	},
	streak_rosette_silver = {
		kind = "cosmetic",
		name = "Silver Rosette",
		blurb = "7 streak days. Pinned to your chest.",
		color = { 196, 200, 204 },
	},
	streak_rosette_gold = {
		kind = "cosmetic",
		name = "Gold Rosette",
		blurb = "14 streak days. Pinned to your chest.",
		color = { 230, 186, 74 },
	},
	streak_rosette_star = {
		kind = "cosmetic",
		name = "Starlight Rosette",
		blurb = "30 streak days. It glows a little at night.",
		color = { 150, 170, 255 },
		glow = true,
	},
	captains_barge = {
		kind = "unlock",
		name = "Captain's Barge",
		blurb = "The captain's pass: every ferry carries your trucks free, for good.",
	},
	-- Mystery items. Lucky Thimble has a perk; the rest are for the collection and the Spindle.
	lucky_thimble = {
		kind = "relic",
		name = "Lucky Thimble",
		perk = "LuckyThimble",
		blurb = "Broken bales spill an extra needle now and then.",
	},
	golden_hay_bale = {
		kind = "relic",
		name = "Golden Hay Bale",
		blurb = "Warm to the touch. Something in the sky wants it.",
	},
	star_beacon = { kind = "relic", name = "Star Beacon", blurb = "Three parts that hum when put together." },
	corn_moon_charm = {
		kind = "relic",
		name = "Corn Moon Charm",
		blurb = "Three corn keys tied with twine. The crop circle answers to it.",
	},
	straw_crown = {
		kind = "relic",
		name = "Straw Crown",
		blurb = "Woven from the walls of a maze that is gone by morning.",
	},
	drowned_compass = {
		kind = "relic",
		name = "Drowned Compass",
		blurb = "Its needle points at the shore, whichever way you hold it.",
	},
	shard_meadow = {
		kind = "relic",
		name = "Master Needle shard: Meadow",
		blurb = "One of twelve. The Spindle has a slot that fits it.",
	},
	shard_spindle = {
		kind = "relic",
		name = "Master Needle shard: Spindle",
		blurb = "Wound back into the door on a thread from still water. It hums when you face the lake.",
	},
	master_needle = {
		kind = "relic",
		name = "The Master Needle",
		blurb = "Whole again. The isles feel stitched a little tighter.",
	},
	shard_snow = { kind = "relic", name = "Master Needle shard: Snow", blurb = "One of twelve." },
	shard_volcano = { kind = "relic", name = "Master Needle shard: Volcano", blurb = "One of twelve." },
	shard_desert = { kind = "relic", name = "Master Needle shard: Desert", blurb = "One of twelve." },
	shard_haunted = { kind = "relic", name = "Master Needle shard: Haunted", blurb = "One of twelve." },
	shard_bobbin = { kind = "relic", name = "Master Needle shard: Bobbin Rock", blurb = "One of twelve." },
	-- The shards from the Weaver's later chapters (weaver_2 to weaver_6).
	shard_pine = {
		kind = "relic",
		name = "Master Needle shard: Pine Forest",
		blurb = "Cut from the heart of a pine that was sewn shut.",
	},
	shard_homestead = {
		kind = "relic",
		name = "Master Needle shard: Homestead",
		blurb = "Old Wren's grandmother saw it fall into the well.",
	},
	shard_swamp = {
		kind = "relic",
		name = "Master Needle shard: Swamp",
		blurb = "It breathes, slowly, like the reeds.",
	},
	shard_keys = {
		kind = "relic",
		name = "Master Needle shard: Thimble Keys",
		blurb = "Strung between three lanterns like a bead.",
	},
	shard_shore = {
		kind = "relic",
		name = "Master Needle shard: Shore",
		blurb = "Found where the lighthouse beam looks every night.",
	},
}

-- The order mystery items appear in the collection. Unfound ones show as ??? with a hint.
Quests.Collection = {
	{ id = "lucky_thimble", hint = "Something drops to the bottom of the old well at midnight." },
	{ id = "shard_meadow", hint = "The Old Scarecrow keeps what he is given." },
	{ id = "shard_spindle", hint = "Read the words beside the Spindle door." },
	{ id = "golden_hay_bale", hint = "Follow the signal." },
	{ id = "star_beacon", hint = "Deep in a bale, something hums." },
	{ id = "corn_moon_charm", hint = "The corn has paths only the night can show." },
	{ id = "straw_crown", hint = "A maze that changes every day. Be quick." },
	{ id = "drowned_compass", hint = "Rows of old posts stand in the sea past the beach." },
	{ id = "shard_snow", hint = "Behind a door in the snow." },
	{ id = "shard_volcano", hint = "Where the mountain breathes." },
	{ id = "shard_desert", hint = "Under the dunes." },
	{ id = "shard_haunted", hint = "Where the lanterns burn." },
	{ id = "shard_bobbin", hint = "With the ships that never came home." },
	{ id = "shard_pine", hint = "Where the pines grow thickest, one tree is stitched shut." },
	{ id = "shard_homestead", hint = "The oldest townsfolk remember who wove the first bale." },
	{ id = "shard_swamp", hint = "Below the fog, the reeds hold their breath." },
	{ id = "shard_keys", hint = "Out where the islands are strung like beads." },
	{ id = "shard_shore", hint = "The lighthouse looks at it every night." },
	{ id = "master_needle", hint = "Twelve shards, a door, and an empty pedestal." },
}

-- Rare finds for "find" steps: a glowing part that pops out of a broken bale. Only the finder can pick it up.
Quests.Finds = {
	beacon_part = { name = "Beacon part", color = { 120, 210, 255 } },
	frozen_bobbin = { name = "Frozen Bobbin", color = { 190, 225, 255 } },
	breathing_reed = { name = "Breathing reed", color = { 150, 190, 120 } },
}
Quests.FindSeconds = 60 -- a find that is not picked up fades after this long

-- The story quests and rituals, in log order. requires: quests that must be done first. ritual = shown as a ritual.
-- Cash rewards follow Config/Prices.luau: a Meadow bale is about $47 and hand hauling earns about $6,500 an hour, so
-- an early reward pays back part of the purchase the quest asked for (never all of it), and the alien rituals pay
-- what a mid-game farm makes in under an hour. Cash goes through Bank.earn like any other income.
Quests.List = {
	{
		id = "first_haul",
		name = "First Haul",
		giver = "Hank, Homestead Motors",
		region = "Meadow",
		blurb = "Every bale hides needles. The shop only pays $1 for the ones it finds. You can do better.",
		steps = {
			{
				kind = "event",
				event = "bale_lifted",
				count = 1,
				hint = "Walk up to any bale and press F to lift it.",
				text = "Lift a hay bale (Pick up)",
			},
			{
				kind = "event",
				event = "bale_sold",
				count = 1,
				hint = "Carry it onto the SELL HERE pad at camp.",
				place = "sellpad",
				text = "Sell a whole bale on the SELL HERE pad",
			},
			{
				kind = "event",
				event = "bale_broken",
				count = 1,
				hint = "Equip the shovel and click a bale.",
				text = "Break a bale open with the shovel",
			},
			{
				kind = "event",
				event = "needle_found",
				count = 1,
				hint = "Look for a glint in the straw and click it.",
				text = "Pick up a needle that spills out",
			},
		},
		reward = { cash = 150 }, -- about three bales: a thank-you, not a shortcut
	},
	{
		id = "get_a_grip",
		name = "Get a Grip",
		giver = "Hank",
		region = "Meadow",
		requires = { "first_haul" },
		blurb = "Bare hands get tired fast. Gloves let you scoop more and carry heavier hay.",
		steps = {
			{
				kind = "own",
				what = "gloves_tier",
				value = 1,
				hint = "The glove stand is next to the sell pad.",
				place = "gloves",
				text = "Wear Work Gloves or better (glove stand by the shop)",
			},
			{
				kind = "event",
				event = "bale_broken",
				count = 5,
				hint = "Any bale in the meadow counts.",
				text = "Break open 5 bales",
			},
		},
		reward = { cash = 250 }, -- pays back the Work Gloves (Prices.Gloves.work)
	},
	{
		id = "wheels",
		name = "Wheels",
		giver = "Hank",
		region = "Meadow",
		requires = { "first_haul" },
		blurb = "Walking bales one at a time won't make you rich. A truck bed holds nine.",
		steps = {
			{
				kind = "own",
				what = "truck",
				hint = "The dealer is west of camp. The Rusty Pickup is the starter truck.",
				place = "dealer",
				text = "Buy a truck at Homestead Motors",
			},
			{
				kind = "event",
				event = "bale_sold",
				count = 9,
				hint = "Load the bed, back up to the HAY SELL SHOP dock and step on UNLOAD.",
				place = "sellshop",
				text = "Sell a truckload: 9 bales",
			},
		},
		reward = { cash = 600 }, -- a tenth of the Rusty Pickup
	},
	{
		id = "put_down_roots",
		name = "Put Down Roots",
		giver = "Hank",
		region = "Meadow",
		requires = { "wheels" },
		blurb = "Sorted needles sell for $100 each. You need land and a sorter to get them out.",
		steps = {
			{
				kind = "own",
				what = "plot",
				hint = "The Land Office is just north of the plots. The bank lends for land too.",
				place = "landoffice",
				text = "Buy a plot at the Land Office",
			},
			{
				kind = "own",
				what = "piece_kind",
				value = "separator",
				hint = "On your plot press BUILD and place a hand sieve on a belt.",
				place = "plot",
				text = "Build a needle sorter on your land",
			},
			{
				kind = "event",
				event = "needles_sold",
				count = 10,
				hint = "Sorted needles land in your bin. Step on SELL NEEDLES next to it.",
				place = "plot",
				text = "Sell 10 sorted needles",
			},
		},
		reward = { cash = 1250 }, -- half the plot (Prices.Plot)
	},
	{
		id = "wandering_scarecrow",
		name = "The Wandering Scarecrow",
		giver = "A note pinned to a fence post",
		region = "Meadow",
		requires = { "first_haul" },
		blurb = '"He never stands in the same field twice. Find him five times and he\'ll give you something shiny."',
		steps = {
			{
				kind = "talk",
				spot = "wander_scarecrow",
				count = 5,
				distinct = true,
				hint = "He moves to a new field every 4 minutes. Each new field counts once.",
				text = "Find the wandering scarecrow 5 times (he moves every few minutes)",
			},
		},
		reward = { gear = "golden_shovel" },
	},
	{
		id = "scarecrow_bargain",
		name = "The Scarecrow's Bargain",
		giver = "The wandering scarecrow",
		region = "Meadow",
		ritual = true,
		requires = { "wandering_scarecrow" },
		blurb = '"My old friend stands in a ring of stones in the west. Feed him hay at dusk, then a little steel."',
		steps = {
			{
				kind = "visit",
				spot = "old_scarecrow",
				hint = "Head north-west from the dealer, past the road.",
				text = "Find the Old Scarecrow's stone ring, north-west past the dealer",
			},
			{
				kind = "pattern",
				spot = "old_scarecrow",
				pads = "stones",
				when = "dusk",
				hint = "One bale per stone, all four at once, while it's dusk.",
				text = "Set a hay bale on each of the four stones",
			},
			{
				kind = "offer",
				spot = "old_scarecrow",
				needles = { steel = 5 },
				hint = "Keep loose needles in your pocket: click them to pick up.",
				text = "Give the Old Scarecrow 5 steel needles",
			},
		},
		reward = { gloves = "scarecrow_gloves", relic = "shard_meadow" },
	},
	{
		id = "tailors_journal",
		name = "The Tailor's Journal",
		giver = "A torn page in the hay shop",
		region = "Meadow",
		requires = { "first_haul" },
		blurb = '"The Tailor lost his journal in the wind. Three pages, three corners of the meadow."',
		steps = {
			{
				kind = "collect",
				spots = { "journal_1", "journal_2", "journal_3" },
				hint = "One by the pond, one in the north woods, one west of the dealer.",
				text = "Find the 3 journal pages",
			},
			{ kind = "visit", spot = "old_barn", text = "Read them at the Old Barn, east of camp" },
		},
		reward = { gear = "thread_rake" },
	},
	{
		id = "midnight_needle",
		name = "The Midnight Needle",
		giver = "The Tailor's Journal",
		region = "Meadow",
		ritual = true,
		requires = { "tailors_journal" },
		blurb = '"Drop ten needles down the old well when the night is deepest. The well gives back what it likes."',
		steps = {
			{
				kind = "offer",
				spot = "old_well",
				needles = { steel = 10 },
				when = "midnight",
				hint = "Midnight lasts about 2 real minutes. Wait by the well.",
				text = "Drop 10 steel needles down the old well",
			},
		},
		reward = { relic = "lucky_thimble" },
	},
	{
		id = "old_bessie",
		name = "Old Bessie",
		giver = "Hank",
		region = "Meadow",
		requires = { "wheels" },
		blurb = '"My first truck is rusting in the Old Barn. Fix her up and she\'s yours."',
		steps = {
			{ kind = "collect", spot = "barn_key", text = "Find the barn key in the Old Barn" },
			{ kind = "talk", spot = "old_barn", text = "Open the barn and look at Old Bessie" },
			{
				kind = "collect",
				spots = { "bessie_carb", "bessie_radiator", "bessie_spring" },
				hint = "Pine Mill in Pine Forest, the oasis camp in the desert, and the Snow Peak lodge.",
				text = "Bring back a carburetor, a radiator and a seat spring",
			},
			{
				kind = "offer",
				spot = "old_barn",
				cash = 2500,
				hint = "Cash comes from your wallet first, then the bank.",
				text = "Pay $2,500 for the rebuild",
			},
		},
		reward = { truck = "old_bessie" },
	},

	-- The alien collector gauntlet (GAME_PLAN_V7/V8 endgame), split into five quests so progress shows.
	{
		id = "alien_signal",
		name = "The Signal",
		giver = "Static on the truck radio",
		region = "Meadow",
		ritual = true,
		requires = { "put_down_roots", "scarecrow_bargain" },
		blurb = "Something flattened the hay in a perfect ring, and the radio hums at night.",
		steps = {
			{ kind = "visit", spot = "crop_circle", when = "night", text = "Find the crop circle, far north-east" },
			{
				kind = "visit",
				spots = { "signal_pine", "signal_valley", "signal_grove" },
				when = "night",
				hint = "They stand in Pine Forest, Homestead Valley and Haunted Grove, glowing blue.",
				text = "Touch the three signal stones",
			},
		},
		reward = { cash = 5000 },
	},
	{
		id = "alien_golden_bale",
		name = "The Golden Hay Bale",
		giver = "The crop circle",
		region = "Meadow",
		ritual = true,
		requires = { "alien_signal" },
		blurb = "At midnight, something gold rests in the middle of the circle.",
		steps = {
			{ kind = "collect", spot = "golden_bale", when = "midnight", text = "Claim the Golden Hay Bale" },
		},
		reward = { relic = "golden_hay_bale" },
	},
	{
		id = "alien_beacon",
		name = "Beacon Parts",
		giver = "The Golden Hay Bale",
		region = "Meadow",
		ritual = true,
		requires = { "alien_golden_bale" },
		blurb = "The golden bale hums near ordinary hay. Three parts of a beacon are hidden in bales somewhere.",
		steps = {
			{
				kind = "find",
				item = "beacon_part",
				count = 3,
				chance = 1 / 120,
				pity = 250,
				hint = "About 1 bale in 120 hides one, and you're sure to find one within 250. Grab it before it fades.",
				text = "Find 3 beacon parts by breaking bales",
			},
		},
		reward = { relic = "star_beacon" },
	},
	{
		id = "alien_pattern",
		name = "The Pattern",
		giver = "The Star Beacon",
		region = "Meadow",
		ritual = true,
		requires = { "alien_beacon" },
		blurb = "The beacon shows a new sign every day. Lay it out in hay at midnight.",
		steps = {
			{
				kind = "pattern",
				spot = "crop_circle",
				pads = "daily",
				when = "midnight",
				hint = "The sign post shows today's 3 x 3 pattern. Filled squares need a bale, empty ones must stay clear.",
				text = "Lay bales on tonight's sign in the crop circle",
			},
		},
		reward = { cash = 15000 },
	},
	{
		id = "corn_maze",
		name = "The Corn Night Maze",
		giver = "The crop circle",
		region = "Meadow",
		ritual = true,
		requires = { "alien_signal" },
		blurb = "East of the plots, a corn maze grows taller than a truck. After dark, three keys glow in its dead ends.",
		steps = {
			{
				kind = "collect",
				spots = { "maze_key_1", "maze_key_2", "maze_key_3" },
				when = "night",
				hint = "The keys sit in the deepest dead ends and only show after dark.",
				text = "Find the 3 corn keys in the maze",
			},
			{ kind = "talk", spot = "corn_maze", when = "night", text = "Bring them to the heart of the maze" },
		},
		reward = { relic = "corn_moon_charm" },
	},
	{
		id = "weaver_1",
		name = "The Weaver, Chapter 1: Still Water",
		giver = "The Spindle door",
		region = "The Spindle",
		requires = { "first_haul" },
		blurb = "The Weaver who stitched these islands vanished, and the Master Needle broke into twelve shards. "
			.. "The sealed door on the Spindle has a socket for each.",
		steps = {
			{
				kind = "talk",
				spot = "weaver_words",
				say = '"Still water keeps the sky. When the sky is darkest, the dropped thread rises. Wind it home."',
				hint = "The Spindle is the tall peak north of Meadow. Take the North Road; the door is on its east face.",
				text = "Read the words cut beside the Spindle door",
			},
			{
				kind = "collect",
				spot = "weaver_spool",
				when = "midnight",
				hint = "Which water is still enough to hold the sky? Go when the sky is darkest.",
				text = "Find the dropped thread",
			},
			{
				kind = "talk",
				spot = "weaver_words",
				say = "The thread pulls tight into the rock. In the door, a socket starts to glow.",
				hint = "Bring the spool back to the words beside the Spindle door.",
				text = "Wind the thread home",
			},
		},
		reward = { relic = "shard_spindle" },
	},
	{
		id = "weaver_2",
		name = "The Weaver, Chapter 2: The Tailor's Note",
		giver = "The Spindle door",
		region = "Meadow Shore",
		requires = { "weaver_1" },
		blurb = "Old Wren says the tailor on the south shore knew the Weaver. She left before anyone could ask.",
		steps = {
			{
				kind = "talk",
				spot = "tailor_note",
				say = '"The light looks at the same place every night. I could never bring myself to fetch it." (signed T.)',
				hint = "The Tailor's Shack is on the south shore, west of the beach.",
				text = "Read the note at the Tailor's Shack",
			},
			{
				kind = "collect",
				spot = "shore_glint",
				when = "night",
				hint = "What does a lighthouse look at? Go after dark.",
				text = "Find what the light looks at",
			},
		},
		reward = { relic = "shard_shore" },
	},
	{
		id = "weaver_3",
		name = "The Weaver, Chapter 3: The Stitched Pine",
		giver = "The Spindle door",
		region = "Pine Forest",
		requires = { "weaver_2" },
		blurb = "Somewhere in the Pine Forest, one tree was sewn shut with gold thread.",
		steps = {
			{
				kind = "event",
				event = "bale_broken",
				count = 15,
				filter = { hayType = "pine" },
				hint = "Pine hay grows in the west woods. Break the bales open and listen.",
				text = "Break 15 pine bales and follow the thread",
			},
			{
				kind = "talk",
				spot = "stitched_pine",
				when = "dusk",
				say = "The gold stitches loosen at sunset. Something drops into your hand.",
				hint = "The stitches only loosen at sunset.",
				text = "Open the stitched pine at dusk",
			},
		},
		reward = { relic = "shard_pine" },
	},
	{
		id = "weaver_4",
		name = "The Weaver, Chapter 4: The First Bale",
		giver = "The Spindle door",
		region = "Homestead Valley",
		requires = { "weaver_3" },
		blurb = "The oldest townsfolk remember who wove the first bale.",
		steps = {
			{
				kind = "talk",
				spot = "old_wren",
				say = 'Old Wren: "My grandmother saw the Weaver drop something shiny down our well. At midnight, mind. She said it winked."',
				hint = "Old Wren stands by the well in the middle of Homestead. The free Hay Wagon from Base Camp stops there.",
				text = "Ask Old Wren about the first bale",
			},
			{
				kind = "collect",
				spot = "well_glint",
				when = "midnight",
				hint = "Old Wren said midnight.",
				text = "Look into the hub well at midnight",
			},
		},
		reward = { relic = "shard_homestead" },
	},
	{
		id = "weaver_5",
		name = "The Weaver, Chapter 5: Holding Breath",
		giver = "The Spindle door",
		region = "Swamp",
		requires = { "weaver_4" },
		blurb = "Below the fog, the reeds hold their breath.",
		steps = {
			{
				kind = "find",
				item = "breathing_reed",
				count = 1,
				chance = 1 / 40,
				pity = 80,
				filter = { hayType = "swamp" },
				hint = "Break swamp bales. One reed in the hay still breathes. Grab it before it fades.",
				text = "Find a reed that still breathes",
			},
			{
				kind = "offer",
				spot = "sunken_stone",
				when = "night",
				needles = { bog = 20 },
				text = "Lay the reed and 20 bog needles on the sunken stone at night",
			},
		},
		reward = { relic = "shard_swamp" },
	},
	{
		id = "weaver_6",
		name = "The Weaver, Chapter 6: Beads on a String",
		giver = "The Spindle door",
		region = "Thimble Keys",
		requires = { "weaver_5" },
		blurb = "Out where the islands are strung like beads, three lanterns hold a thread between them.",
		steps = {
			{
				kind = "visit",
				spots = { "keys_bead_1", "keys_bead_2", "keys_bead_3" },
				hint = "Three lanterns on three of the Thimble Keys. Take the ferry from Swamp Port.",
				text = "Touch the 3 bead lanterns",
			},
			{
				kind = "collect",
				spot = "keys_glint",
				when = "dusk",
				hint = "The thread between the lanterns catches the sunset.",
				text = "Take the bead from the thread at dusk",
			},
		},
		reward = { relic = "shard_keys" },
	},
	{
		id = "master_needle",
		name = "The Master Needle",
		giver = "The Spindle door",
		region = "The Spindle",
		requires = {
			"scarecrow_bargain",
			"weaver_1",
			"weaver_2",
			"weaver_3",
			"weaver_4",
			"weaver_5",
			"weaver_6",
			"frozen_door",
			"eruption",
			"graveyard_of_ships",
			"buried_garage",
			"lanterns",
		},
		blurb = "Twelve shards. The Spindle door knows you now.",
		steps = {
			{
				kind = "talk",
				spot = "master_pedestal",
				say = "The twelve shards slide together on the pedestal. The Master Needle is whole.",
				hint = "Through the Spindle door, at the end of the Loom Room.",
				text = "Set the shards on the pedestal in the Loom Room",
			},
		},
		reward = { relic = "master_needle", cash = 100000 }, -- about 15 minutes of Volcano-stage income: the biggest one-time payout (Econ)
	},
	{
		id = "straw_labyrinth",
		name = "The Straw Labyrinth",
		giver = "The labyrinth sign",
		region = "Meadow",
		requires = { "first_haul" },
		blurb = "Far south-west of camp, a maze of straw walls is rebuilt every night. A bell waits at its heart.",
		steps = {
			{
				kind = "run",
				spot = "straw_labyrinth",
				hint = "Cross the start line at the entrance, then find the bell. The walls change every day.",
				text = "Run the Straw Labyrinth and ring the bell",
			},
			{
				kind = "run",
				spot = "straw_labyrinth",
				seconds = 45,
				hint = "Leave your hay behind: a heavy load slows you down.",
				text = "Ring the bell within 45 seconds of the start line",
			},
		},
		reward = { relic = "straw_crown", cash = 500 },
	},
	{
		id = "drowned_rows",
		name = "The Drowned Rows",
		giver = "The beach",
		region = "Meadow",
		requires = { "first_haul" },
		blurb = "Past the south beach, rows of old pilings stand in the sea. Something was left on a raft in the middle.",
		steps = {
			{
				kind = "run",
				spot = "drowned_rows",
				hint = "Swim in between the two red buoys and find a way through the pilings to the raft.",
				text = "Swim the Drowned Rows to the raft",
			},
		},
		reward = { relic = "drowned_compass", cash = 750 },
	},
	{
		id = "alien_offering",
		name = "The Offering",
		giver = "The crop circle",
		region = "Meadow",
		ritual = true,
		requires = { "alien_pattern", "corn_maze" },
		blurb = "The collector wants fifty of every needle that grows in the world.",
		steps = {
			{
				kind = "offer",
				spot = "crop_circle",
				needlesEach = 50,
				text = "Offer 50 sorted needles of every kind you can find",
			},
		},
		reward = {
			unlock = { "alien_collector", "starbeam_collector" },
			gloves = "starweave_gloves",
			truck = "starlight_hauler",
		},
	},

	-- Region quests. Their spots appear once the region is built.
	{
		id = "frozen_door",
		name = "The Frozen Door",
		giver = "A trapper's note",
		region = "Snow Peak",
		requires = { "first_haul" },
		blurb = "There is a door in the ice on Snow Peak. It only opens for a Frozen Bobbin.",
		steps = {
			{
				kind = "find",
				item = "frozen_bobbin",
				count = 1,
				chance = 1 / 60,
				pity = 120,
				filter = { hayType = "snow" },
				hint = "Break the frozen hay bales on Snow Peak.",
				text = "Find a Frozen Bobbin in frozen hay",
			},
			{ kind = "talk", spot = "snow_door", text = "Open the hidden door on Snow Peak" },
		},
		reward = { gloves = "frostbite_mitts", relic = "shard_snow" },
	},
	{
		id = "eruption",
		name = "Eruption",
		giver = "A scorched sign",
		region = "Volcano",
		requires = { "first_haul" },
		blurb = "When the volcano rumbles at night, the crater gives up its treasure.",
		steps = {
			{ kind = "visit", spot = "volcano_crater", when = "night", text = "Climb to the crater rim at night" },
			{
				kind = "event",
				event = "bale_broken",
				count = 20,
				filter = { hayType = "volcano" },
				hint = "Ashen hay grows on the Volcano's slopes. Good gloves help with the weight.",
				text = "Break 20 bales of ashen hay",
			},
		},
		reward = { gloves = "magma_grips", relic = "shard_volcano" },
	},
	{
		id = "graveyard_of_ships",
		name = "Graveyard of Ships",
		giver = "A bottle on the beach",
		region = "Bobbin Rock",
		requires = { "first_haul" },
		blurb = "A captain still walks the wrecks at night.",
		steps = {
			{ kind = "talk", spot = "graveyard_ghost", when = "night", text = "Find the captain's ghost at night" },
		},
		reward = { gloves = "kraken_gauntlets", relic = "shard_bobbin" },
	},
	{
		id = "captains_log",
		name = "The Captain's Log",
		giver = "The captain's ghost",
		region = "Bobbin Rock",
		requires = { "graveyard_of_ships" },
		blurb = '"Find my log and my barge is yours."',
		steps = {
			{
				kind = "collect",
				spots = { "captains_log_1", "captains_log_2", "captains_log_3" },
				text = "Find the 3 log pages",
			},
		},
		reward = { unlock = "captains_barge" },
	},
	{
		id = "buried_garage",
		name = "The Buried Garage",
		giver = "A mechanic's map",
		region = "Desert Dunes",
		requires = { "wheels" },
		blurb = "A truck garage is buried under the dunes, with something fast inside.",
		steps = {
			{ kind = "visit", spot = "pyramid_garage", text = "Find the buried garage" },
			{
				kind = "event",
				event = "bale_broken",
				count = 15,
				filter = { hayType = "desert" },
				hint = "Desert grass grows around the dunes and the oasis.",
				text = "Dig it out: break 15 bales of desert grass",
			},
			{ kind = "talk", spot = "pyramid_mechanic", text = "Talk to the old mechanic" },
		},
		reward = { truck = "sandrunner", relic = "shard_desert" },
	},
	{
		id = "lanterns",
		name = "Lanterns in the Fog",
		giver = "Whispers in the Haunted Grove",
		region = "Haunted Grove",
		requires = { "wheels" },
		blurb = "Light the three lanterns, then wait at the crossroads when the night is deepest.",
		steps = {
			{
				kind = "visit",
				spots = { "lantern_1", "lantern_2", "lantern_3" },
				when = "night",
				hint = "They stand along the Haunted Grove road. Visit each one at night.",
				text = "Light the 3 lanterns",
			},
			{ kind = "visit", spot = "haunted_crossroads", when = "midnight", text = "Wait at the crossroads" },
		},
		reward = { truck = "ghost_hauler", relic = "shard_haunted" },
	},
}

-- The gentle daily streak. Finishing any one bounty on a UTC day counts that day. A missed day pauses the streak; it
-- never resets. Rosettes are cosmetic. From LuckyField.fromDays on, each day you also get a personal lucky field (one
-- of the hay fields out on the isles, shown in the Bounties tab): bales you break there sometimes spill an extra
-- needle, a few times a day.
-- Timed maze runs (step kind "run"): the first finish each UTC day pays `cash` (once per maze per save). About six
-- Meadow bales for a minute or two of running: a daily treat, never a living (hauling earns about $6,500 an hour).
-- abandon = a run that has gone on this long (seconds), or wandered this far from the maze (studs), is called off.
Quests.Runs = {
	straw_labyrinth = { name = "Straw Labyrinth", cash = 300, abandon = 600, range = 120 },
	drowned_rows = { name = "Drowned Rows", cash = 400, abandon = 600, range = 140 },
}

Quests.Streak = {
	Milestones = {
		{ days = 3, reward = "streak_rosette_bronze" },
		{ days = 7, reward = "streak_rosette_silver" },
		{ days = 14, reward = "streak_rosette_gold" },
		{ days = 30, reward = "streak_rosette_star" },
	},
	LuckyField = { fromDays = 2, radius = 22, chance = 0.3, perDay = 10 },
}

-- Daily bounties: three a day from this pool, the same three for everyone, new at midnight UTC. Cash only.
Quests.BountiesPerDay = 3
Quests.Bounties = {
	{ id = "sell_bales", event = "bale_sold", count = 15, cash = 450, text = "Sell 15 bales" },
	{ id = "break_bales", event = "bale_broken", count = 12, cash = 300, text = "Break open 12 bales" },
	{ id = "find_needles", event = "needle_found", count = 8, cash = 400, text = "Pick up 8 loose needles" },
	{ id = "sell_sorted", event = "needles_sold", count = 30, cash = 1200, text = "Sell 30 sorted needles" },
	{ id = "sell_hay", event = "hay_sold", count = 300, cash = 350, text = "Sell 300 loose hay" },
	{ id = "rake", event = "raked", count = 25, cash = 150, text = "Rake 25 strokes" },
}

return Quests

end

MODULES["Shared.Config.Weather"] = function(script)
-- Weather by region: what can blow through each one and how it looks. Weather is visual plus a little grip on the
-- road (a wet or snowy truck speeds up and brakes slower). Rain also soaks bales left out under the open sky
-- (Bales.luau, Config/Game WetWeather): heavier and cheaper hay until it dries. It never touches needles.
-- The server (Services/Weather.luau) rolls each region's weather every few minutes and the client
-- (Weather.client.luau) draws the one you stand in.
--
-- Kinds:
--   tint / density   the haze it brings (added to the day's own haze, see DayNightSky.client)
--   grip             truck acceleration and braking, 1 = dry
--   fall             particles around the camera: color, size, speed (studs/s down), drift (sideways), rate
--   cloud            0..1 how much the sky clouds over
export type Kind = {
	name: string,
	tint: Color3,
	density: number,
	grip: number,
	cloud: number,
	fall: { color: Color3, size: number, speed: number, drift: number, rate: number, streak: boolean }?,
}

local rgb = Color3.fromRGB

local Weather = {}

Weather.Kinds = {
	clear = { name = "Clear", tint = rgb(200, 210, 220), density = 0, grip = 1, cloud = 0.25 },
	rain = {
		name = "Rain",
		tint = rgb(130, 140, 150),
		density = 0.12,
		grip = 0.8,
		cloud = 0.85,
		fall = { color = rgb(190, 205, 220), size = 0.12, speed = 90, drift = 4, rate = 400, streak = true },
	},
	snow = {
		name = "Snow",
		tint = rgb(225, 232, 240),
		density = 0.2,
		grip = 0.7,
		cloud = 0.8,
		fall = { color = rgb(250, 250, 255), size = 0.35, speed = 9, drift = 5, rate = 260, streak = false },
	},
	dust = {
		name = "Dust",
		tint = rgb(214, 172, 118),
		density = 0.22,
		grip = 0.9,
		cloud = 0.3,
		fall = { color = rgb(210, 170, 120), size = 0.5, speed = 2, drift = 30, rate = 160, streak = false },
	},
	fog = { name = "Fog", tint = rgb(150, 160, 140), density = 0.32, grip = 0.95, cloud = 0.7 },
	ash = {
		name = "Ash",
		tint = rgb(110, 90, 80),
		density = 0.2,
		grip = 0.9,
		cloud = 0.9,
		fall = { color = rgb(90, 84, 80), size = 0.3, speed = 6, drift = 6, rate = 180, streak = false },
	},
	mist = { name = "Mist", tint = rgb(205, 215, 225), density = 0.14, grip = 1, cloud = 0.5 },
} :: { [string]: Kind }

-- Each region's everyday weather and how often it comes (weights): the haze and mist that give it its mood. Regions
-- not listed stay clear. Rain, snow and dust come as fronts (below), one at a time.
Weather.Regions = {
	meadow = { clear = 6, mist = 1 },
	shore = { clear = 5, mist = 2 },
	valley = { clear = 5, mist = 2 },
	homestead = { clear = 6, mist = 1 },
	spindle = { clear = 4, mist = 2 },
	pine = { clear = 4, mist = 2 },
	haunted = { fog = 5, mist = 2 },
	snow = { clear = 3, mist = 1 },
	volcano = { ash = 4, clear = 3 },
	desert = { clear = 6 },
	swamp = { fog = 4, mist = 3 },
	keys = { clear = 6, mist = 1 },
	bobbin = { clear = 5, mist = 2 },
	sky = { clear = 5, mist = 2 },
	cave = { clear = 1 },
} :: { [string]: { [string]: number } }

Weather.SpellMinutes = { 4, 8 } -- each region's everyday weather lasts this long (real minutes) before it rolls again

-- Fronts (map #25): the weather that matters. Only one front is on the map at a time. The sky over its region
-- clouds over for FrontWarnSeconds first and the server announces it, so players can get loose hay under a roof
-- (rain soaks bales left out, Bales.luau and Config/Game WetWeather). Region events (RegionEvents.luau) that bring
-- their own weather count as the front while they run.
export type Front = { region: string, kind: string, weight: number, text: string }
Weather.Fronts = {
	{ region = "meadow", kind = "rain", weight = 3, text = "Clouds are building over Meadow Farm: rain in a minute. Get loose hay under a roof." },
	{ region = "swamp", kind = "rain", weight = 3, text = "Rain is coming to the Swamp in a minute. Cover any hay you have out there." },
	{ region = "snow", kind = "snow", weight = 2, text = "Snow is coming to Snow Peak in a minute. Roads get slippery." },
	{ region = "desert", kind = "dust", weight = 2, text = "A dust storm is blowing into the Desert Dunes in a minute." },
} :: { Front }
Weather.FrontWarnSeconds = 60
Weather.FrontMinutes = { 3, 5 } -- how long a front lasts once it arrives
Weather.FrontGapMinutes = { 4, 9 } -- clear spell between fronts

-- Thunderstorm (Addiction push H7): about once an hour the whole server gets a storm for a few minutes. It is
-- announced StormWarnSeconds ahead, darkens every sky with lightning, and multiplies the needle mutation odds by
-- StormMutationOdds while it lasts (Weather.needleOdds, read by Needle's roll). It doesn't rain on hay by itself.
Weather.StormEveryMinutes = { 50, 70 } -- gap from one storm's end to the next storm's warning
Weather.StormMinutes = 3
Weather.StormWarnSeconds = 60
Weather.StormMutationOdds = 5
Weather.StormText = "A thunderstorm is rolling in! In 60 seconds, mutated needles are 5x as likely for 3 minutes."
Weather.StormStartText = "Thunderstorm! Mutated needles are 5x as likely for 3 minutes."
-- Weather kinds that make a needle found out in them roll the "Wet" mutation (Weather.needleOdds).
Weather.WetKinds = { rain = true }

return Weather

end

MODULES["Shared.WorldRegions"] = function(script)
-- Which region a point is in, for clients and servers alike (labels, sky tint, weather). Regions are the ovals in
-- Config/WorldMap; Meadow Farm is its square; Sky Island and the Crystal Cave are places of their own. Cheap: a
-- dozen ovals, no terrain math (WorldShape.regionAt on the server is the exact one, coasts included).
local Shared = script.Parent
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)

local WorldRegions = {}

local MEADOW_STYLE = { accent = Color3.fromRGB(133, 61, 48), fog = Color3.fromRGB(189, 199, 194) }
WorldRegions.Meadow = { id = "meadow", name = "Meadow Farm", style = MEADOW_STYLE, hayType = "meadow" }
WorldRegions.Sky = { id = "sky", name = "Sky Island", style = { accent = Color3.fromRGB(200, 170, 90), fog = Color3.fromRGB(214, 226, 240), density = -0.08 }, hayType = "sky" }
WorldRegions.Cave = { id = "cave", name = "Crystal Cave", style = { accent = Color3.fromRGB(150, 110, 200), fog = Color3.fromRGB(70, 60, 90), density = 0.12 }, hayType = "cave" }

-- The region at a Vector3 (or nil out at sea).
function WorldRegions.at(position)
	if position.Y > Map.SkyIsland.top - 60 then
		local d = Vector2.new(position.X, position.Z) - Map.SkyIsland.center
		if d.Magnitude < Map.SkyIsland.radius + 40 then
			return WorldRegions.Sky
		end
	end
	local cave = Map.Cave.chamber
	if (position - cave.center).Magnitude < cave.radius * 1.2 then
		return WorldRegions.Cave
	end
	if math.abs(position.X) < Meadow.HalfSize and math.abs(position.Z) < Meadow.HalfSize then
		return WorldRegions.Meadow
	end
	local best, bestValue = nil, 0
	for _, r in Map.Regions do
		local dx = (position.X - r.center.X) / r.radius.X
		local dz = (position.Z - r.center.Y) / r.radius.Y
		local value = 1 - math.sqrt(dx * dx + dz * dz)
		if value > bestValue then
			best, bestValue = r, value
		end
	end
	return best
end

return WorldRegions

end

MODULES["Shared.Config.Sounds"] = function(script)
-- Every sound in the game, in one place. These start as Roblox's built-in sounds (rbxasset://) so they work with
-- nothing to upload. To use a Creator Store sound instead, paste its id as "rbxassetid://123456" over the id.
-- volume is 0..1 and pitch is a playback speed (1 = as recorded). distance is how far away it can be heard.
--
-- Picking real sounds (Studio > Toolbox > Audio, filter to Roblox-made sounds so they are free to use in any game;
-- right-click a result > Copy Asset ID). Good searches for each:
--   BaleLift      "hay rustle" or "cloth lift"            BaleSetDown   "heavy thud" or "sack drop"
--   BaleBurst     "hay bale break" or "straw rustle"      Scoop         "shovel dig dirt"
--   Rake          "rake leaves" or "rake gravel"          NeedleDing    "small bell ding" or "metal ping"
--   CashRegister  "cash register"                         TruckEngine   "truck engine idle loop" (must loop cleanly)
--   TruckHorn     "truck horn" or "old car horn"
-- A sound that fails to load stays silent; the game keeps running.
return {
	BaleLift = { id = "rbxasset://sounds/swoosh.wav", volume = 0.5, pitch = 0.7, distance = 50 },
	BaleSetDown = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.7, pitch = 0.6, distance = 60 },
	BaleBurst = { id = "rbxasset://sounds/splat.wav", volume = 0.8, pitch = 0.55, distance = 80 },
	Scoop = { id = "rbxasset://sounds/swoosh.wav", volume = 0.45, pitch = 1.3, distance = 40 },
	Rake = { id = "rbxasset://sounds/swoosh.wav", volume = 0.35, pitch = 0.9, distance = 40 },
	-- The ding plays higher for rarer needles: pitch rises by NeedlePitchPerTenfold each time the value is 10x.
	NeedleDing = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, pitch = 1.0, distance = 60 },
	NeedlePitchPerTenfold = 0.45,
	NeedleBaseValue = 100, -- a needle worth this much dings at the base pitch
	-- Played to the seller only, on every sale.
	CashRegister = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 1.6 },
	-- Loops while someone sits in a truck's driver seat. Pitch climbs with speed from idle to full.
	-- Placeholder: Roblox ships no engine sound, so this is a whoosh slowed right down into a low rumble. Swap in a
	-- "truck engine idle loop" id from the Toolbox and set the pitches back near 0.8 to 1.3.
	TruckEngine = { id = "rbxasset://sounds/Rocket whoosh 01.wav", volume = 0.3, distance = 90 },
	EngineIdlePitch = 0.16,
	EngineTopPitch = 0.42,
	EngineTopSpeed = 60, -- studs per second where the engine reaches its top pitch
	-- Q while driving (Vehicles.luau plays it on the truck so everyone near hears it). Placeholder: a ping pitched
	-- right down; swap in a "truck horn" id.
	TruckHorn = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.8, pitch = 0.32, distance = 140 },

	-- Region ambience (RegionAmbience.client.luau): two quiet loops under everything, mixed per region as you walk or
	-- drive in. Placeholders from the default character sounds (the falling-wind and the swimming-water loops);
	-- swap in "wind ambience loop" and "waves loop" / "rain loop" ids from the Toolbox.
	AmbientWind = { id = "rbxasset://sounds/action_falling.mp3", volume = 0.14, pitch = 0.45 },
	AmbientWater = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.1, pitch = 0.55 },
	-- Per region: wind and water as a share of their volume, and the wind's pitch (low = a hollow moan).
	-- Rain anywhere adds water (the weather's patter).
	RegionAmbience = {
		meadow = { wind = 0.35, water = 0, windPitch = 0.45 },
		shore = { wind = 0.4, water = 0.8, windPitch = 0.45 },
		valley = { wind = 0.3, water = 0.35, windPitch = 0.45 },
		homestead = { wind = 0.25, water = 0, windPitch = 0.45 },
		spindle = { wind = 0.7, water = 0, windPitch = 0.4 },
		pine = { wind = 0.55, water = 0, windPitch = 0.4 },
		haunted = { wind = 0.6, water = 0.2, windPitch = 0.3 },
		snow = { wind = 1, water = 0, windPitch = 0.5 },
		volcano = { wind = 0.7, water = 0, windPitch = 0.32 },
		desert = { wind = 0.8, water = 0, windPitch = 0.55 },
		swamp = { wind = 0.2, water = 0.7, windPitch = 0.35 },
		keys = { wind = 0.45, water = 1, windPitch = 0.5 },
		bobbin = { wind = 0.8, water = 0.7, windPitch = 0.4 },
		sky = { wind = 1, water = 0, windPitch = 0.6 },
		cave = { wind = 0.4, water = 0.15, windPitch = 0.22 },
	},
}

end

MODULES["Services.Weather"] = function(script)
-- Rolls each region's everyday weather (Config/Weather Regions: clear, mist, fog, ash) every few minutes and
-- publishes it as a ReplicatedStorage attribute "Weather_<region id>" = kind, which every client reads
-- (Weather.client.luau draws it). Region events can force a spell: Weather.force("desert", "dust", 180).
--
-- Fronts (map #25, Config/Weather Fronts): rain over Meadow or the Swamp, snow on Snow Peak, dust in the desert. One
-- at a time: a front is announced and the sky over its region clouds up for FrontWarnSeconds ("coming"), then it
-- sets the region's weather for a few minutes ("on"). Published as ReplicatedStorage attributes WeatherFront (region
-- id), WeatherFrontKind, WeatherFrontPhase ("coming" | "on") and WeatherFrontAt (server time the phase ends).
-- Hay's wet bales read the region's kind through Weather.get (Bales.rainingOn), so a front's rain soaks loose hay.
--
-- Thunderstorms (H7, Config/Weather Storm*): server-wide, about hourly, warned a minute ahead; Weather.needleOdds is
-- the hook the needle roll calls for the storm's odds and the "Wet" mutation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Weather)
local WorldRegions = require(ReplicatedStorage.Shared.WorldRegions)
local Announce = require(script.Parent.Announce)

local Weather = {}

local forcedUntil = {} -- region id -> os.clock() when a forced spell ends
local forcedKind = {} -- region id -> the kind it was forced to
local front = nil -- { region, kind, phase, ends (os.clock), def }

local function roll(choices)
	local total = 0
	for _, w in choices do
		total += w
	end
	local pick = math.random() * total
	for kind, w in choices do
		pick -= w
		if pick <= 0 then
			return kind
		end
	end
	return "clear"
end

local function between(range)
	return math.random(range[1] * 60, range[2] * 60)
end

function Weather.get(regionId)
	return ReplicatedStorage:GetAttribute("Weather_" .. regionId) or "clear"
end

function Weather.set(regionId, kind)
	assert(Config.Kinds[kind], "unknown weather " .. tostring(kind))
	ReplicatedStorage:SetAttribute("Weather_" .. regionId, kind)
end

-- Hold a region's weather for `seconds` (an event); it rolls normally afterwards.
function Weather.force(regionId, kind, seconds)
	Weather.set(regionId, kind)
	forcedUntil[regionId] = os.clock() + seconds
	forcedKind[regionId] = kind
end

-- The front on the map now, if any: { region, kind, phase = "coming" | "on", ends = os.clock() }.
function Weather.front()
	return front
end

local FRONT_KINDS = {}
for _, def in Config.Fronts do
	FRONT_KINDS[def.kind] = true
end

-- Is a forced spell (an event) bringing front weather anywhere right now?
local function eventFront(now)
	for id, untilT in forcedUntil do
		if now < untilT and FRONT_KINDS[forcedKind[id]] then
			return id
		end
	end
	return nil
end

local function publishFront()
	ReplicatedStorage:SetAttribute("WeatherFront", front and front.region or nil)
	ReplicatedStorage:SetAttribute("WeatherFrontKind", front and front.kind or nil)
	ReplicatedStorage:SetAttribute("WeatherFrontPhase", front and front.phase or nil)
	ReplicatedStorage:SetAttribute("WeatherFrontAt", front and (workspace:GetServerTimeNow() + (front.ends - os.clock())) or nil)
end

local function everyday(id)
	local choices = Config.Regions[id]
	return choices and roll(choices) or "clear"
end

-- Starts a front now ("coming"); `def` is one of Config.Fronts, or a random one by weight.
function Weather.startFront(def)
	if not def then
		local weights = {}
		for i, f in Config.Fronts do
			weights[i] = f.weight
		end
		def = Config.Fronts[tonumber(roll(weights)) or 1]
	end
	front = { region = def.region, kind = def.kind, phase = "coming", ends = os.clock() + Config.FrontWarnSeconds, def = def }
	publishFront()
	pcall(Announce.say, def.text, "event")
	return front
end

-- Moves the front on: coming -> on -> over. Called every few seconds; self-tests call it with `now` pushed forward.
local nextFront = nil
function Weather.stepFront(now)
	now = now or os.clock()
	if front and now >= front.ends then
		if front.phase == "coming" then
			front.phase = "on"
			front.ends = now + between(Config.FrontMinutes)
			Weather.set(front.region, front.kind)
		else
			if not (forcedUntil[front.region] and now < forcedUntil[front.region]) then
				Weather.set(front.region, everyday(front.region))
			end
			front = nil
			nextFront = now + between(Config.FrontGapMinutes)
		end
		publishFront()
	elseif not front and now >= (nextFront or 0) and not eventFront(now) then
		Weather.startFront()
	end
end

-- Thunderstorms (H7): one server-wide storm about every hour. Published as ReplicatedStorage attributes Storm
-- ("coming" | "on" | nil), StormAt (server time the current phase ends), NextStorm (server time the next warning
-- starts), StormStarts (when the next or coming storm breaks) and StormEnds (when the storm on now, or coming, ends),
-- for the HUD strip and the sky (Weather.client).
local storm = nil -- { phase, ends (os.clock) }
local nextStorm = nil -- os.clock() of the next warning

local function serverTime(clock)
	return workspace:GetServerTimeNow() + (clock - os.clock())
end

local function publishStorm()
	ReplicatedStorage:SetAttribute("Storm", storm and storm.phase or nil)
	ReplicatedStorage:SetAttribute("StormAt", storm and serverTime(storm.ends) or nil)
	ReplicatedStorage:SetAttribute("NextStorm", nextStorm and serverTime(nextStorm) or nil)
	-- For the HUD countdown strip (like RichFieldEnds / RegionEventEnds): when the storm breaks and when it ends.
	local starts, ends = nil, nil
	if storm and storm.phase == "on" then
		ends = storm.ends
	elseif storm then
		starts = storm.ends
		ends = storm.ends + Config.StormMinutes * 60
	elseif nextStorm then
		starts = nextStorm + Config.StormWarnSeconds
	end
	ReplicatedStorage:SetAttribute("StormStarts", starts and serverTime(starts) or nil)
	ReplicatedStorage:SetAttribute("StormEnds", ends and serverTime(ends) or nil)
end

function Weather.storm()
	return storm
end

-- Starts a storm's warning now (self-tests, admin). Returns the storm state.
function Weather.startStorm()
	storm = { phase = "coming", ends = os.clock() + Config.StormWarnSeconds }
	nextStorm = nil
	publishStorm()
	pcall(Announce.say, Config.StormText, "event")
	return storm
end

-- Moves the storm on: coming -> on -> over, then schedules the next. Self-tests pass `now` pushed forward.
function Weather.stepStorm(now)
	now = now or os.clock()
	if storm and now >= storm.ends then
		if storm.phase == "coming" then
			storm = { phase = "on", ends = now + Config.StormMinutes * 60 }
			pcall(Announce.say, Config.StormStartText, "event")
		else
			storm = nil
			nextStorm = now + between(Config.StormEveryMinutes)
		end
		publishStorm()
	elseif not storm and nextStorm and now >= nextStorm then
		Weather.startStorm()
	end
end

-- The needle roll's weather hook (Needle.luau owns the roll): how much the weather multiplies the mutation odds for a
-- needle found at `position`, and whether it's found in the rain (the "Wet" mutation). Returns oddsMultiplier, wet.
function Weather.needleOdds(position)
	local odds = (storm and storm.phase == "on") and Config.StormMutationOdds or 1
	local wet = false
	if typeof(position) == "Vector3" then
		local region = WorldRegions.at(position)
		wet = region ~= nil and Config.WetKinds[Weather.get(region.id)] == true
	end
	return odds, wet
end

local started = false
function Weather.start()
	if started then
		return
	end
	started = true
	local nextRoll = {}
	for id in Config.Regions do
		Weather.set(id, everyday(id))
		nextRoll[id] = os.clock() + between(Config.SpellMinutes)
	end
	nextFront = os.clock() + between(Config.FrontGapMinutes)
	nextStorm = os.clock() + between(Config.StormEveryMinutes)
	publishStorm()
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for id in Config.Regions do
				-- A forced spell (an event) just ended: roll fresh weather now, not a whole spell later.
				if forcedUntil[id] and now >= forcedUntil[id] then
					forcedUntil[id], forcedKind[id] = nil, nil
					nextRoll[id] = now
				end
				local busy = (front and front.phase == "on" and front.region == id) or now < (forcedUntil[id] or 0)
				if now >= nextRoll[id] and not busy then
					Weather.set(id, everyday(id))
					nextRoll[id] = now + between(Config.SpellMinutes)
				end
			end
			local ok, err = pcall(Weather.stepFront, now)
			if not ok then
				warn("[Needlewood] weather front: " .. tostring(err))
			end
			local stormOk, stormErr = pcall(Weather.stepStorm, now)
			if not stormOk then
				warn("[Needlewood] thunderstorm: " .. tostring(stormErr))
			end
		end
	end)
end

return Weather

end

MODULES["Services.RegionEvents"] = function(script)
-- One event at a time somewhere on the Stitched Isles, every Prices.RegionEvents.EveryMinutes: Hay Fever on the
-- Meadow Shore, Windfall in the Pine Forest, a Sandstorm on the Dunes, an Avalanche on Snow Peak, Low Tide in the
-- Swamp, an Eruption on the Volcano and, at night only, a Meteor Shower over Mirror Lake Valley.
-- Each one is announced server-wide, sets the region's weather (Weather.force) and drops extra bales of that region's
-- hay near its fields, worth more needles (NeedleBoost, amounts in Prices.RegionEvents). Bales nobody has touched
-- when it ends are taken away again. ReplicatedStorage attributes RegionEvent (name) and RegionEventAt (Vector3) tell
-- map screens where it is.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Prices = require(Shared.Config.Prices)
local Bales = require(script.Parent.Bales)
local Regions = require(script.Parent.Regions)
local WorldShape = require(script.Parent.WorldShape)
local Weather = require(script.Parent.Weather)
local WorldClock = require(script.Parent.WorldClock)
local Announce = require(script.Parent.Announce)

local RegionEvents = {}

RegionEvents.List = {
	{ id = "hay_fever", name = "Hay Fever", region = "shore", weather = "mist", text = "Hay Fever on the %s! The grass has burst into bales. Up to %sx needles." },
	{ id = "windfall", name = "Windfall", region = "pine", weather = "rain", text = "Windfall in the %s! The gale brought bales down off the ridge. Up to %sx needles." },
	{ id = "sandstorm", name = "Sandstorm", region = "desert", weather = "dust", text = "Sandstorm over the %s! Buried bales are coming up. %sx needles." },
	{ id = "avalanche", name = "Avalanche", region = "snow", weather = "snow", text = "Avalanche on %s! Bales tumbled down to the lodge. %sx needles." },
	{ id = "low_tide", name = "Low Tide", region = "swamp", weather = "mist", text = "Low Tide in the %s! Sunken bales are out of the water. %sx needles." },
	{ id = "eruption", name = "Eruption", region = "volcano", weather = "ash", text = "The %s is erupting! Scorched bales on the slopes, %sx needles." },
	{ id = "meteor_shower", name = "Meteor Shower", region = "valley", weather = "clear", night = true, hay = "star", text = "Meteor Shower over %s! Star hay fell into the fields, glowing. %sx needles." },
}

local SPREAD = 26 -- studs around a field's center the event's bales land
local ROAD_CLEAR = 9 -- no event bale lands closer than this to a road's center line

local regionById = {}
for _, r in Map.Regions do
	regionById[r.id] = r
end

local running = nil -- { def, bales = {b = true}, ends }

local function landingSpots(region, count, rng)
	local fields = {}
	for _, entry in Regions.fields do
		if entry.region == region.name then
			table.insert(fields, entry)
		end
	end
	local spots = {}
	if #fields == 0 then
		return spots
	end
	for _ = 1, count * 8 do
		if #spots >= count then
			break
		end
		local entry = fields[rng:NextInteger(1, #fields)]
		local x = entry.center.X + rng:NextNumber(-SPREAD, SPREAD)
		local z = entry.center.Z + rng:NextNumber(-SPREAD, SPREAD)
		local road = WorldShape.nearestRoad(x, z)
		local clear = not road or road > ROAD_CLEAR
		for _, s in spots do
			if (Vector2.new(s.X, s.Z) - Vector2.new(x, z)).Magnitude < 5.5 then
				clear = false
			end
		end
		if clear then
			table.insert(spots, Vector3.new(x, WorldShape.heightAt(x, z), z))
		end
	end
	return spots
end

-- A falling star: a glowing ball streaks down to where a bale lands.
local function streak(target, parent)
	local ball = Instance.new("Part")
	ball.Name = "FallingStar"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(2, 2, 2)
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 226, 150)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CFrame = CFrame.new(target + Vector3.new(120, 260, -60))
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.9, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.6
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 236, 190))
	trail.LightEmission = 1
	trail.Parent = ball
	ball.Parent = parent
	local tween = TweenService:Create(ball, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(target + Vector3.new(0, 3, 0)) })
	tween:Play()
	tween.Completed:Wait()
	ball:Destroy()
end

local function finish()
	local event = running
	if not event then
		return
	end
	running = nil
	for b in event.bales do
		-- Untouched: still lying where it landed, nobody's, not carried.
		if not b.gone and not b.carriedBy and not b.ownerId and b.body.Parent and (b.body.Position - b.spawnPosition).Magnitude < 6 then
			Bales.consume(b)
		end
	end
	ReplicatedStorage:SetAttribute("RegionEvent", nil)
	ReplicatedStorage:SetAttribute("RegionEventAt", nil)
	ReplicatedStorage:SetAttribute("RegionEventEnds", nil)
end

-- Starts an event now (by id); returns the bales it dropped. Ends any running event first.
function RegionEvents.run(id, minutes)
	local def
	for _, e in RegionEvents.List do
		if e.id == id then
			def = e
		end
	end
	assert(def, "unknown region event " .. tostring(id))
	finish()
	local region = regionById[def.region]
	local reward = Prices.RegionEvents[def.id]
	local seconds = (minutes or Prices.RegionEvents.Minutes) * 60
	local rng = Random.new()
	local event = { def = def, bales = {}, ends = os.clock() + seconds }
	running = event

	Weather.force(def.region, def.weather, seconds)
	local spots = landingSpots(region, reward.bales, rng)
	local folder = workspace:FindFirstChild("Needlewood")
	for _, spot in spots do
		if def.id == "meteor_shower" then
			task.spawn(streak, spot, folder or workspace)
		end
		local b = Bales.spawn(spot - Vector3.new(0, 0.35, 0), false, true, def.hay or region.hayType)
		if b then
			if def.hay == "star" then
				-- Fallen stars glow so they can be found in the dark.
				local glow = Instance.new("PointLight")
				glow.Color = Color3.fromRGB(255, 226, 150)
				glow.Range = 14
				glow.Brightness = 1.5
				glow.Parent = b.body
			end
			b.body:SetAttribute("NeedleBoost", reward.boost)
			b.body:SetAttribute("RegionEvent", def.id)
			event.bales[b] = true
		end
	end
	local center = spots[1] or Vector3.new(region.center.X, region.base, region.center.Y)
	ReplicatedStorage:SetAttribute("RegionEvent", def.name)
	ReplicatedStorage:SetAttribute("RegionEventAt", center)
	-- When it ends (server time; the HUD countdown strip, Countdown.client.luau).
	ReplicatedStorage:SetAttribute("RegionEventEnds", workspace:GetServerTimeNow() + seconds)
	Announce.say(def.text:format(region.name, tostring(reward.boost)), "event")

	task.delay(seconds, function()
		if running == event then
			finish()
		end
	end)
	return event.bales
end

function RegionEvents.current()
	return running and running.def or nil
end

RegionEvents.finish = finish

local started = false
function RegionEvents.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local last = nil
		while true do
			task.wait(Prices.RegionEvents.EveryMinutes * 60)
			local choices = {}
			for _, e in RegionEvents.List do
				if e.id ~= last and (not e.night or WorldClock.isNight()) then
					table.insert(choices, e)
				end
			end
			local pick = choices[math.random(1, #choices)]
			last = pick.id
			local ok, err = pcall(RegionEvents.run, pick.id)
			if not ok then
				warn("[Needlewood] region event " .. pick.id .. " failed: " .. tostring(err))
			end
		end
	end)
end

return RegionEvents

end

MODULES["Services.Wilds"] = function(script)
-- The far regions' dangers and secrets (backlog Map #9):
--   * Volcano heat: the crater is too hot to stand in without tier 4 gloves (Iron Gauntlets or Magma Grips). Anyone
--     else is pushed back over the rim with a warning. In the crater: the Ember Cache.
--   * The Ghost Road: a causeway of pale planks from the Wreck of the Bobbin out to Ghost Isle, solid only at night
--     (WorldClock.isNight). At dawn it fades over FADE seconds, then lets go. On Ghost Isle: the Captain's Lantern.
--   * Crystal Cave: the Geode Heart, hidden behind the crystals on the far wall.
--   * Sky Island: the Lost Kite, on a ledge just under the island's west rim.
-- Each secret pays once per save slot (Prices.Secrets) and is kept in state.secrets.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Prices = require(Shared.Config.Prices)
local WorldShape = require(script.Parent.WorldShape)
local WorldClock = require(script.Parent.WorldClock)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Announce = require(script.Parent.Announce)
local Discoveries = require(script.Parent.Discoveries)
local Regions = require(script.Parent.Regions)

local Wilds = {}

local HEAT_TIER = 4 -- gloves at or above this tier shrug off the crater's heat
local HEAT_RADIUS = 105 -- studs from the volcano's peak center, inside the rim
local HEAT_FLOOR = 40 -- studs below the rim top that count as "in the crater" (the outer slopes are fine)
local FADE = 20 -- seconds the Ghost Road takes to fade at dawn

local GHOST = Color3.fromRGB(170, 230, 210)
local GHOST_ROAD = { from = Vector2.new(-1735, -780), to = Vector2.new(-2030, -780), y = 4, width = 16 }
local GHOST_ISLE = { center = Vector2.new(-2075, -780), radius = 42, top = 4 }

local function part(parent, name, size, cframe, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function glow(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
	return l
end

-- Secrets ------------------------------------------------------------------------------------------------------

Wilds.Secrets = {} -- id -> { name, part }

local function found(player, id)
	local state = Data.get(player)
	return state and state.secrets and state.secrets[id] ~= nil
end

local function claimSecret(player, id, name)
	local state = Data.get(player)
	if not state then
		return false
	end
	state.secrets = state.secrets or {}
	-- A secret inside the crater's heat (the Ember Cache) needs the same heat-proof gloves as getting there.
	local spot = Wilds.Secrets[id]
	local hot = id == "ember_cache" or (spot and spot.part and Wilds.inHeat(spot.part.Position))
	if hot and not Wilds.heatProof(player) then
		Data.toast(player, "Too hot to search! Tier 4 gloves (Iron Gauntlets or Magma Grips) handle the crater's heat.")
		return false
	end
	if state.secrets[id] then
		Data.toast(player, ("You already found the %s."):format(name))
		return false
	end
	state.secrets[id] = 1
	local reward = Prices.Secrets[id] or (string.sub(id, 1, 7) == "hidden_" and Prices.Secrets.hidden) or 0
	if reward > 0 then
		Bank.earn(player, reward, "Secret: " .. name)
	end
	Data.toast(player, ("Secret found: the %s! +$%d"):format(name, reward))
	if Discoveries.info(id) then
		Discoveries.discover(player, id) -- stamps it on the map
	end
	Announce.say(("%s found a secret: the %s!"):format(player.DisplayName, name), "gold")
	return true
end
Wilds.claimSecret = claimSecret
Wilds.found = found

local function secret(parent, id, name, cframe, size, color, material)
	local p = part(parent, "Secret_" .. id, size, cframe, color, material)
	p:SetAttribute("SecretId", id)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Search"
	prompt.ObjectText = "?"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	prompt.Triggered:Connect(function(player)
		claimSecret(player, id, name)
	end)
	Wilds.Secrets[id] = { name = name, part = p, prompt = prompt }
	return p
end

-- Volcano heat ---------------------------------------------------------------------------------------------------

local peak = nil
local rimTop = 0

-- True where the crater's heat reaches (inside the rim, below its top).
function Wilds.inHeat(position)
	if not peak then
		return false
	end
	local d = (Vector2.new(position.X, position.Z) - peak.center).Magnitude
	return d < HEAT_RADIUS and position.Y < rimTop + 8 and position.Y > rimTop - HEAT_FLOOR - 120
end

function Wilds.heatProof(player)
	return (player:GetAttribute("GloveTier") or 0) >= HEAT_TIER
end

local warned = {}
local function heatLoop()
	while true do
		task.wait(0.5)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and not humanoid.SeatPart and Wilds.inHeat(root.Position) and not Wilds.heatProof(player) then
				local out = Vector2.new(root.Position.X, root.Position.Z) - peak.center
				out = out.Magnitude > 0.1 and out.Unit or Vector2.new(1, 0)
				-- The client owns its character's physics, so a server velocity alone can be lost: step it back
				-- out of the heat as well, then push.
				character:PivotTo(root.CFrame + Vector3.new(out.X * 6, 3, out.Y * 6))
				root.AssemblyLinearVelocity = Vector3.new(out.X * 55, 45, out.Y * 55)
				if not warned[player] or os.clock() - warned[player] > 8 then
					warned[player] = os.clock()
					Data.toast(player, "Too hot! Tier 4 gloves (Iron Gauntlets or Magma Grips) let you into the crater.")
				end
			end
		end
	end
end

local function volcano(folder)
	local region = WorldShape.region("volcano")
	peak = region and region.peak
	if not peak then
		return
	end
	-- The rim's top: the highest ground on a ring just inside HEAT_RADIUS.
	for a = 0, 7 do
		local p = peak.center + Vector2.new(math.cos(a / 8 * math.pi * 2), math.sin(a / 8 * math.pi * 2)) * (HEAT_RADIUS - 10)
		rimTop = math.max(rimTop, WorldShape.heightAt(p.X, p.Y))
	end
	-- The Ember Cache: an obsidian chest on the crater floor beside the Magma Spindle.
	local x, z = peak.center.X + 34, peak.center.Y - 14
	local y = WorldShape.heightAt(x, z)
	local chest = secret(folder, "ember_cache", "Ember Cache", CFrame.new(x, y + 1.2, z) * CFrame.Angles(0, 0.6, 0), Vector3.new(4, 2.4, 2.6), Color3.fromRGB(30, 24, 28), Enum.Material.Basalt)
	part(folder, "EmberLid", Vector3.new(4.2, 0.5, 2.8), chest.CFrame * CFrame.new(0, 1.45, 0), Color3.fromRGB(230, 110, 40), Enum.Material.Neon, false)
	glow(chest, Color3.fromRGB(255, 130, 60), 16, 1.5)
	task.spawn(heatLoop)
end

-- The Ghost Road -------------------------------------------------------------------------------------------------

local planks = {}
local ghostNight = nil

local function setGhost(solid, seconds)
	for _, p in planks do
		local shown = p:GetAttribute("Shown")
		if solid then
			p.CanCollide = p:GetAttribute("Solid") == true
			TweenService:Create(p, TweenInfo.new(seconds), { Transparency = shown }):Play()
		else
			TweenService:Create(p, TweenInfo.new(seconds), { Transparency = 1 }):Play()
		end
		for _, l in p:GetChildren() do
			if l:IsA("PointLight") then
				l.Enabled = solid
			end
		end
	end
	if not solid then
		task.delay(seconds, function()
			if not WorldClock.isNight() then
				for _, p in planks do
					p.CanCollide = false
				end
			end
		end)
	end
end

local function ghostRoad(folder)
	local road = Instance.new("Folder")
	road.Name = "GhostRoad"
	road.Parent = folder
	local a, b = GHOST_ROAD.from, GHOST_ROAD.to
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local yaw = math.atan2(-dir.X, -dir.Y)
	local segments = math.ceil(length / 30)
	for i = 0, segments - 1 do
		local mid = a + dir * ((i + 0.5) * length / segments)
		local cf = CFrame.new(mid.X, GHOST_ROAD.y - 0.6, mid.Y) * CFrame.Angles(0, yaw, 0)
		local deck = part(road, "GhostPlanks", Vector3.new(GHOST_ROAD.width, 1.2, length / segments + 0.2), cf, GHOST, Enum.Material.Neon)
		deck:SetAttribute("Solid", true)
		deck:SetAttribute("Shown", 0.55)
		table.insert(planks, deck)
		for _, side in { -1, 1 } do
			local post = part(road, "GhostPost", Vector3.new(0.6, 5, 0.6), cf * CFrame.new(side * (GHOST_ROAD.width / 2 + 0.4), 2.5, 0), GHOST, Enum.Material.Neon, false)
			post:SetAttribute("Shown", 0.3)
			table.insert(planks, post)
			if i % 2 == 0 and side == 1 then
				glow(post, GHOST, 22, 0.8)
			end
		end
	end

	-- Ghost Isle: a basalt islet with a drowned lighthouse stump and the Captain's Lantern.
	local isle = GHOST_ISLE
	local rock = part(folder, "GhostIsle", Vector3.new(36, isle.radius * 2, isle.radius * 2), CFrame.new(isle.center.X, isle.top - 18, isle.center.Y) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(58, 56, 64), Enum.Material.Basalt)
	rock.Shape = Enum.PartType.Cylinder
	part(folder, "GhostIsleLanding", Vector3.new(GHOST_ROAD.width, 1, 14), CFrame.new(b.X - dir.X * 2, isle.top - 0.5, b.Y - dir.Y * 2) * CFrame.Angles(0, yaw, 0), Color3.fromRGB(70, 58, 48), Enum.Material.WoodPlanks)
	local stump = part(folder, "LighthouseStump", Vector3.new(16, 12, 12), CFrame.new(isle.center.X - 12, isle.top + 8, isle.center.Y + 8), Color3.fromRGB(150, 146, 150), Enum.Material.Brick)
	stump.Shape = Enum.PartType.Cylinder
	stump.CFrame = stump.CFrame * CFrame.Angles(0, 0, math.rad(90))
	local lantern = secret(folder, "captains_lantern", "Captain's Lantern", CFrame.new(isle.center.X + 10, isle.top + 1, isle.center.Y - 6), Vector3.new(1.4, 2, 1.4), Color3.fromRGB(150, 230, 200), Enum.Material.Neon)
	glow(lantern, GHOST, 18, 1.2)

	ghostNight = WorldClock.isNight()
	setGhost(ghostNight, 0)
	task.spawn(function()
		while road.Parent do
			task.wait(1)
			Wilds.refreshGhost()
		end
	end)
end

-- Brings the Ghost Road in line with the clock now (the loop above does this every second).
function Wilds.refreshGhost()
	local now = WorldClock.isNight()
	if now ~= ghostNight then
		ghostNight = now
		setGhost(now, now and 3 or FADE)
	end
end

function Wilds.ghostSolid()
	return planks[1] ~= nil and planks[1].CanCollide
end

-- Cave and sky ---------------------------------------------------------------------------------------------------

local function cave(folder)
	local c = Map.Cave.chamber
	local floorY = c.center.Y - c.radius * 0.45 + 4
	local x, z = c.center.X + c.radius * 0.78, c.center.Z + c.radius * 0.3
	local geode = secret(folder, "geode_heart", "Geode Heart", CFrame.new(x, floorY + 1.6, z), Vector3.new(3.2, 3.2, 3.2), Color3.fromRGB(150, 110, 200), Enum.Material.Glass)
	geode.Shape = Enum.PartType.Ball
	glow(geode, Color3.fromRGB(180, 140, 255), 12, 1)
end

local function sky(folder)
	local s = Map.SkyIsland
	-- A stone ledge jutting out just under the west rim; drop off the edge to land on it.
	local x, z = s.center.X - s.radius - 2, s.center.Y
	local ledge = part(folder, "KiteLedge", Vector3.new(18, 2, 14), CFrame.new(x, s.top - 16, z), Color3.fromRGB(150, 146, 140), Enum.Material.Slate)
	local kite = secret(folder, "lost_kite", "Lost Kite", ledge.CFrame * CFrame.new(-3, 2.4, 0) * CFrame.Angles(0.5, 0.3, 0.2), Vector3.new(3.4, 0.2, 4.4), Color3.fromRGB(200, 70, 60), Enum.Material.Fabric)
	part(folder, "KiteTail", Vector3.new(0.2, 0.2, 6), kite.CFrame * CFrame.new(0, 0, 4.6), Color3.fromRGB(240, 220, 160), Enum.Material.Fabric, false)
end

-- Hidden spots -------------------------------------------------------------------------------------------------
-- One per region: a hollow tree, a buried shed, a stone cairn or a sunken chest, a short walk off one of the region's
-- roads. No marker points at it. An Old Sign at the roadside gives the clue in paces and a compass direction
-- ("north" is -Z). Finding it pays Prices.Secrets.hidden once per slot and stamps it as a discovery.

local HIDDEN = {
	shore = { kind = "tree", name = "Hollow Driftwood Oak", riddle = "the old oak is hollow" },
	valley = { kind = "tree", name = "Hollow Willow", riddle = "a willow keeps a secret" },
	homestead = { kind = "cairn", name = "Founders' Cairn", riddle = "the first settlers stacked their stones" },
	spindle = { kind = "cairn", name = "Echo Cairn", riddle = "stones that listen" },
	pine = { kind = "tree", name = "Hollow Pine", riddle = "one pine is empty inside" },
	haunted = { kind = "tree", name = "Whispering Oak", riddle = "the dead tree whispers" },
	snow = { kind = "shed", name = "Buried Ski Shed", riddle = "a roof pokes out of the snow" },
	volcano = { kind = "cairn", name = "Ash Cairn", riddle = "stones the ash forgot" },
	desert = { kind = "shed", name = "Buried Prospector's Shed", riddle = "the sand swallowed a shed" },
	swamp = { kind = "chest", name = "Sunken Bog Chest", riddle = "a chest sinks in the mud" },
	keys = { kind = "chest", name = "Castaway's Chest", riddle = "a castaway buried his chest" },
	bobbin = { kind = "shed", name = "Spool Shed", riddle = "a shed full of thread, half buried" },
}
Wilds.Hidden = {} -- region id -> { id, name, part, sign = Vector3, spot = Vector3 }

local DIRECTIONS = { "east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east" }
local function compass(dx, dz)
	-- +X east, +Z south.
	local a = math.atan2(dz, dx)
	return DIRECTIONS[(math.floor(a / (math.pi / 4) + 0.5) % 8) + 1]
end

-- A spot in this region 50 to 120 studs off one of its roads: dry, fairly level, away from fields.
local function hiddenSpot(region, rng)
	local pieces = {}
	for _, road in Map.Roads do
		for k = 1, #road.points - 1 do
			local a, b = road.points[k], road.points[k + 1]
			for t = 0.2, 0.8, 0.2 do
				local p = a:Lerp(b, t)
				local reach = math.max(region.radius.X, region.radius.Y) + 150
				if (p - region.center).Magnitude < reach and not WorldShape.inMeadow(p.X, p.Y) then
					local dir = (b - a).Unit
					table.insert(pieces, { p = p, n = Vector2.new(-dir.Y, dir.X) })
				end
			end
		end
	end
	for _ = 1, 200 do
		if #pieces == 0 then
			return nil
		end
		local piece = pieces[rng:NextInteger(1, #pieces)]
		local side = rng:NextInteger(0, 1) * 2 - 1
		local spot = piece.p + piece.n * side * rng:NextNumber(50, 120) + Vector2.new(rng:NextNumber(-20, 20), rng:NextNumber(-20, 20))
		local d = WorldShape.nearestRoad(spot.X, spot.Y)
		local h, water = WorldShape.column(spot.X, spot.Y)
		local level = true
		for _, o in { Vector2.new(4, 0), Vector2.new(-4, 0), Vector2.new(0, 4), Vector2.new(0, -4) } do
			local h2, w2 = WorldShape.column(spot.X + o.X, spot.Y + o.Y)
			if w2 or math.abs(h2 - h) > 2.5 then
				level = false
			end
		end
		local clear = WorldShape.regionAt(spot.X, spot.Y) == region and not water and level and (not d or d > 30)
		for _, entry in Regions.fields do
			if clear and (Vector2.new(entry.center.X, entry.center.Z) - spot).Magnitude < 40 then
				clear = false
			end
		end
		if clear then
			return Vector3.new(spot.X, h, spot.Y), piece.p
		end
	end
	return nil
end

local function hiddenLook(parent, kind, at, rng)
	local cf = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	if kind == "tree" then
		local trunk = part(parent, "HollowTrunk", Vector3.new(5, 14, 5), cf * CFrame.new(0, 6.5, 0), Color3.fromRGB(92, 74, 54), Enum.Material.Wood)
		trunk.Shape = Enum.PartType.Cylinder
		trunk.CFrame = trunk.CFrame * CFrame.Angles(0, 0, math.rad(90))
		part(parent, "HollowCanopy", Vector3.new(14, 9, 14), cf * CFrame.new(0, 16, 0), Color3.fromRGB(86, 110, 62), Enum.Material.Grass, false)
		part(parent, "Hollow", Vector3.new(2.4, 3.2, 0.4), cf * CFrame.new(0, 2.2, -2.45), Color3.fromRGB(28, 22, 18), Enum.Material.SmoothPlastic, false)
		return cf * CFrame.new(0, 2.2, -3)
	elseif kind == "shed" then
		part(parent, "BuriedRoofL", Vector3.new(7, 0.5, 9), cf * CFrame.new(-1.9, 1.3, 0) * CFrame.Angles(0, 0, math.rad(30)), Color3.fromRGB(110, 80, 60), Enum.Material.WoodPlanks)
		part(parent, "BuriedRoofR", Vector3.new(7, 0.5, 9), cf * CFrame.new(1.9, 1.3, 0) * CFrame.Angles(0, 0, math.rad(-30)), Color3.fromRGB(110, 80, 60), Enum.Material.WoodPlanks)
		part(parent, "ShedChimney", Vector3.new(1, 2.4, 1), cf * CFrame.new(2, 2.4, 2.5), Color3.fromRGB(120, 110, 104), Enum.Material.Brick)
		return cf * CFrame.new(0, 1.2, -5)
	elseif kind == "chest" then
		part(parent, "SunkChest", Vector3.new(3.6, 1.6, 2.4), cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0.15, 0, 0.1), Color3.fromRGB(80, 60, 44), Enum.Material.WoodPlanks)
		part(parent, "SunkChestBand", Vector3.new(3.7, 0.3, 2.5), cf * CFrame.new(0, 0.9, 0) * CFrame.Angles(0.15, 0, 0.1), Color3.fromRGB(120, 110, 100), Enum.Material.Metal)
		return cf * CFrame.new(0, 0.8, 0)
	end
	-- cairn
	for i = 0, 3 do
		local r = 2.6 - i * 0.5
		local stone = part(parent, "CairnStone", Vector3.new(r, 1.2, r * 0.9), cf * CFrame.new(0, 0.6 + i * 1.1, 0) * CFrame.Angles(0, i * 0.7, 0), Color3.fromRGB(128, 122, 116), Enum.Material.Slate)
		stone.Shape = Enum.PartType.Block
	end
	return cf * CFrame.new(0, 1, -1.8)
end

local function hiddenSpots(folder)
	local signpost = Regions.signpost
	for _, r in Map.Regions do
		local def = HIDDEN[r.id]
		local region = WorldShape.region(r.id)
		if def and region then
			local rng = Random.new(Map.Seed * 31 + #r.id * 7 + string.byte(r.id, 1))
			local at, roadPoint = hiddenSpot(region, rng)
			if at then
				local id = "hidden_" .. r.id
				local holder = Instance.new("Model")
				holder.Name = "Hidden_" .. r.id
				holder.Parent = folder
				local findAt = hiddenLook(holder, def.kind, at, rng)
				local ground = WorldShape.column(findAt.X, findAt.Z)
				if findAt.Y < ground + 0.6 then
					findAt = findAt + Vector3.new(0, ground + 0.6 - findAt.Y, 0) -- never inside a slope
				end
				-- The find itself: a small dark bundle you search in the hollow, under the roof, in the chest.
				local find = secret(holder, id, def.name, findAt, Vector3.new(1.2, 0.8, 1.2), Color3.fromRGB(70, 56, 44), Enum.Material.Fabric)
				find.CanCollide = false
				Discoveries.addHidden(id, def.name)
				local offset = Vector2.new(at.X, at.Z) - roadPoint
				local paces = math.floor(offset.Magnitude / 2.5 / 5 + 0.5) * 5
				local text = ("OLD SIGN\n%d paces %s,\n%s"):format(paces, compass(offset.X, offset.Y), def.riddle)
				if signpost then
					signpost(holder, roadPoint.X, roadPoint.Y, offset.Unit, text, 12)
				end
				Wilds.Hidden[r.id] = { id = id, name = def.name, part = find, spot = at, sign = roadPoint }
			else
				warn("[Needlewood] no hidden spot found in " .. r.name)
			end
		end
	end
end

function Wilds.build(folder)
	local wilds = Instance.new("Folder")
	wilds.Name = "Wilds"
	wilds.Parent = folder
	for _, step in { { "volcano", volcano }, { "ghost road", ghostRoad }, { "cave", cave }, { "sky", sky }, { "hidden spots", hiddenSpots } } do
		local ok, err = pcall(step[2], wilds)
		if not ok then
			warn(("[Needlewood] Wilds %s failed: %s"):format(step[1], tostring(err)))
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		warned[player] = nil
	end)
end

return Wilds

end

MODULES["Services.RoadPolish"] = function(script)
-- Finishing on the roads: where a road crosses water (bog pools on the Swamp Road, the Dune Cut's creek) its causeway
-- becomes a timber bridge, with guard rails on the water side, trestle legs down into the water and a name board at
-- each end. The driving surface stays the terrain causeway WorldShape lays at road height, so a truck with a trailer
-- crosses it like any road (the rails stand outside the 16-stud lane). Roads with a steep drop beside them get the
-- same rail on that side.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Map = require(ReplicatedStorage.Shared.Config.WorldMap)
local Rustic = require(ReplicatedStorage.Shared.Config.Rustic)
local WorldShape = require(script.Parent.WorldShape)

local RoadPolish = {}

local STEP = 8 -- studs between rail posts
local ROAD_HALF = Map.RoadWidth / 2
local PROBE = ROAD_HALF + 5 -- how far out from the center line to look for water or a drop
local RAIL_AT = ROAD_HALF + 1.5 -- rail posts stand just off the lane
local DROP = 4 -- a drop this much below the road at PROBE gets a rail
local MIN_RUN = 3 -- posts; shorter stretches are left plain

RoadPolish.bridges = {} -- { road, from = Vector3, to = Vector3, side }

local function part(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- One side of a road along one straight piece: the runs of samples that need a rail. Each run is a list of
-- { post = Vector3 (top of the road at the rail line), water = bool, bed = ground height out there }.
local function runsAlong(a, b, side)
	local dir = (b - a).Unit
	local normal = Vector2.new(-dir.Y, dir.X) * side
	local runs, current = {}, nil
	local steps = math.floor((b - a).Magnitude / STEP)
	for k = 0, steps do
		local p = a + dir * (k * STEP)
		local need = nil
		if not WorldShape.inMeadow(p.X, p.Y) then
			local _, h = WorldShape.nearestRoad(p.X, p.Y)
			if h then
				local q = p + normal * PROBE
				local ground, water = WorldShape.column(q.X, q.Y)
				if water or ground < h - DROP then
					local r = p + normal * RAIL_AT
					need = { post = Vector3.new(r.X, h, r.Y), water = water ~= nil, bed = ground }
				end
			end
		end
		if need then
			current = current or {}
			table.insert(current, need)
		elseif current then
			table.insert(runs, current)
			current = nil
		end
	end
	if current then
		table.insert(runs, current)
	end
	return runs
end

local function rail(folder, run)
	local wood, dark = Rustic.Wood, Rustic.WoodDark
	for i, s in run do
		part(folder, "RailPost", Vector3.new(0.7, 3.2, 0.7), CFrame.new(s.post + Vector3.new(0, 1.6, 0)), dark, Enum.Material.Wood)
		if s.water then
			-- A trestle leg down to the bed under the water.
			local depth = math.max(2, s.post.Y - s.bed)
			part(folder, "Trestle", Vector3.new(1, depth, 1), CFrame.new(s.post + Vector3.new(0, -depth / 2, 0)), dark, Enum.Material.Wood)
		end
		local nextOne = run[i + 1]
		if nextOne then
			local mid = (s.post + nextOne.post) / 2 + Vector3.new(0, 2.6, 0)
			local length = (nextOne.post - s.post).Magnitude
			part(folder, "Rail", Vector3.new(0.4, 0.5, length + 0.6), CFrame.lookAt(mid, nextOne.post + Vector3.new(0, 2.6, 0)), wood, Enum.Material.Wood)
		end
	end
end

-- A name board on a post at the rail line, its face along the road (so it never reaches into the lane), readable
-- from both sides as a truck rolls past.
local function nameBoard(folder, at, along, text)
	local across = Vector3.new(-along.Z, 0, along.X)
	local cf = CFrame.lookAt(at + Vector3.new(0, 4.4, 0), at + Vector3.new(0, 4.4, 0) + across)
	local board = part(folder, "BridgeBoard", Vector3.new(7, 1.6, 0.3), cf, Rustic.PaintCream, Enum.Material.WoodPlanks)
	part(folder, "BridgeBoardPost", Vector3.new(0.5, 4, 0.5), CFrame.new(at + Vector3.new(0, 2, 0)), Rustic.WoodDark, Enum.Material.Wood)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(280, 64)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Merriweather
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(40, 32, 26)
		label.Text = text
		label.Parent = gui
		gui.Parent = board
	end
end

function RoadPolish.build(parent)
	local folder = Instance.new("Folder")
	folder.Name = "RoadPolish"
	folder.Parent = parent
	local posts = 0
	for _, road in Map.Roads do
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			for _, side in { -1, 1 } do
				for _, run in runsAlong(a, b, side) do
					if #run >= MIN_RUN then
						rail(folder, run)
						posts += #run
						local wet = 0
						for _, s in run do
							wet += s.water and 1 or 0
						end
						if wet >= MIN_RUN then
							local first, last = run[1].post, run[#run].post
							table.insert(RoadPolish.bridges, { road = road.name, from = first, to = last, side = side })
							-- Name boards once per bridge, on the left-hand rail only.
							if side == 1 then
								local name = road.name:gsub(" Road", ""):gsub(" Lane", ""):gsub(" Cut", "")
								local along = (last - first).Unit
								nameBoard(folder, first - along * 5, along, name:upper() .. " BRIDGE")
								nameBoard(folder, last + along * 5, along, name:upper() .. " BRIDGE")
							end
						end
					end
				end
			end
		end
	end
	print(("[Needlewood] road polish: %d rail posts, %d bridge sides"):format(posts, #RoadPolish.bridges))
end

-- Road lanterns (#26): a lantern post every LANTERN_STEP studs along the isles' roads, alternating sides, standing
-- just off the lane on ground at road height (never on a bridge or over a drop). The lantern part's name holds
-- "Lantern", so WorldClock lights it at dusk and puts it out at dawn. They go in their own "Lighting" container so
-- the part budget (Config/WorldMap PartBudget) counts them on their own.
local LANTERN_STEP = 110
local LANTERN_AT = ROAD_HALF + 2.5
local WARM = Color3.fromRGB(255, 196, 110)
RoadPolish.lanterns = {} -- Vector3 of each lantern

function RoadPolish.buildLanterns(parent)
	local folder = Instance.new("Folder")
	folder.Name = "Lighting"
	folder.Parent = parent
	local count, side = 0, 1
	for _, road in Map.Roads do
		local carried = LANTERN_STEP / 2 -- distance since the last lantern, carried round bends
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			local length = (b - a).Magnitude
			local dir = (b - a).Unit
			local t = LANTERN_STEP - carried
			while t <= length do
				local p = a + dir * t
				side = -side
				local q = p + Vector2.new(-dir.Y, dir.X) * (side * LANTERN_AT)
				local d, h = WorldShape.nearestRoad(p.X, p.Y)
				local ground, water = WorldShape.column(q.X, q.Y)
				local lane = WorldShape.nearestRoad(q.X, q.Y)
				if d and h and not water and not WorldShape.inMeadow(q.X, q.Y) and math.abs(ground - h) < 2.5 and ground > Map.SeaLevel + 1 and (not lane or lane >= ROAD_HALF + 1) then
					local base = CFrame.new(q.X, ground, q.Y)
					part(folder, "LanternPost", Vector3.new(0.5, 9, 0.5), base * CFrame.new(0, 4.5, 0), Rustic.WoodDark, Enum.Material.Wood)
					local lamp = part(folder, "RoadLantern", Vector3.new(1, 1.4, 1), base * CFrame.new(0, 9.4, 0), WARM, Enum.Material.Neon)
					lamp.CanCollide = false
					lamp.CastShadow = false
					local light = Instance.new("PointLight")
					light.Color = WARM
					light.Range = 22
					light.Brightness = 1.1
					light.Shadows = false
					light.Parent = lamp
					table.insert(RoadPolish.lanterns, lamp.Position)
					count += 1
				end
				t += LANTERN_STEP
			end
			carried = length - (t - LANTERN_STEP)
		end
	end
	print(("[Needlewood] %d road lanterns"):format(count))
end

return RoadPolish

end

MODULES["Services.HayWagon"] = function(script)
-- The Hay Wagon: a free, slow ride for players (no cargo) on a loop from base camp up the North Road to Homestead,
-- back to camp, then down the South road and the Swamp Road to Swamp Port and back. New players see the isles
-- before they own a truck; trucks stay the way to haul. A little tractor pulls it.
--
-- It is anchored and moved along the road every frame, and nothing on it collides, so it never blocks a lane or
-- shoves a truck: riders sit in its seats (a Ride prompt seats you; jump to get off). It waits STOP_SECONDS at each
-- stop, where a signpost lists the stops.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)
local Rustic = require(Shared.Config.Rustic)
local WorldShape = require(script.Parent.WorldShape)
local Regions = require(script.Parent.Regions)
local Props = require(script.Parent.Props)

local HayWagon = {}

local SPEED = 14 -- studs per second
local STOP_SECONDS = 20
local STEP = 4 -- studs between route samples
local SEATS = 6
local LANE_OFFSET = 4 -- keeps to the right-hand side of the road

local function roadPoints(list, name)
	for _, road in list do
		if road.name == name then
			return road.points
		end
	end
	error("no road " .. name)
end

local function concat(...)
	local out = {}
	for _, list in { ... } do
		for _, p in list do
			if #out == 0 or (out[#out] - p).Magnitude > 0.5 then
				table.insert(out, p)
			end
		end
	end
	return out
end

local function reversed(list)
	local out = {}
	for i = #list, 1, -1 do
		table.insert(out, list[i])
	end
	return out
end

-- The loop as legs: { stop name at the end, polyline }.
local function legs()
	local camp = Vector2.new(0, 26)
	local north = concat({ camp }, roadPoints(Meadow.Roads, "North"), roadPoints(Map.Roads, "North Road"))
	local south = concat({ camp, Vector2.new(120, 26) }, roadPoints(Meadow.Roads, "South"), { Vector2.new(150, 640) }, roadPoints(Map.Roads, "Swamp Road"))
	return {
		{ stop = "Homestead", line = north },
		{ stop = "Base Camp", line = reversed(north) },
		{ stop = "Swamp Port", line = south },
		{ stop = "Base Camp", line = reversed(south) },
	}
end

-- Dense samples along a polyline at road height, kept to the right of the center line.
local function sample(line)
	local out = {}
	for i = 1, #line - 1 do
		local a, b = line[i], line[i + 1]
		local dir = (b - a).Unit
		local right = Vector2.new(-dir.Y, dir.X)
		local n = math.max(1, math.floor((b - a).Magnitude / STEP))
		for k = 0, n - 1 do
			local p = a:Lerp(b, k / n) + right * LANE_OFFSET
			table.insert(out, Vector3.new(p.X, WorldShape.heightAt(p.X, p.Y), p.Y))
		end
	end
	local last = line[#line]
	table.insert(out, Vector3.new(last.X, WorldShape.heightAt(last.X, last.Y), last.Y))
	-- Smooth the heights so terrain noise doesn't make it hop.
	for _ = 1, 2 do
		for i = 2, #out - 1 do
			local y = (out[i - 1].Y + out[i].Y * 2 + out[i + 1].Y) / 4
			out[i] = Vector3.new(out[i].X, y, out[i].Z)
		end
	end
	return out
end

local function part(parent, name, size, cframe, color, material, shape)
	local p = Instance.new(name == "Seat" and "Seat" or "Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Wood
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = name == "Seat"
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Builds the wagon at the origin, facing -Z; returns the model and its seats.
local function buildWagon(parent)
	local model = Instance.new("Model")
	model.Name = "HayWagon"
	local origin = CFrame.new()
	local bed = part(model, "Bed", Vector3.new(8, 0.8, 14), origin * CFrame.new(0, 2.4, 2), Rustic.Wood, Enum.Material.WoodPlanks)
	model.PrimaryPart = bed
	local wagonLook, tractorLook = { bed }, {} -- the part looks the Blender wagon and tractor replace
	for _, side in { -1, 1 } do
		wagonLook[#wagonLook + 1] = part(model, "Rail", Vector3.new(0.4, 1.4, 14), origin * CFrame.new(side * 3.9, 3.5, 2), Rustic.WoodDark)
		for _, z in { -3, 7 } do
			wagonLook[#wagonLook + 1] = part(model, "Wheel", Vector3.new(0.6, 3.2, 3.2), origin * CFrame.new(side * 4.3, 1.6, z), Rustic.WoodDark, Enum.Material.Wood, Enum.PartType.Cylinder)
		end
	end
	-- A heap of hay down the middle to lean on, and benches facing out.
	wagonLook[#wagonLook + 1] = part(model, "HayHeap", Vector3.new(2.4, 1.6, 12), origin * CFrame.new(0, 3.6, 2), Color3.fromRGB(189, 168, 112), Enum.Material.Grass)
	local seats = {}
	for i = 0, SEATS - 1 do
		local side = i % 2 == 0 and -1 or 1
		local z = -2 + math.floor(i / 2) * 4
		local seat = part(model, "Seat", Vector3.new(2, 0.6, 2), origin * CFrame.new(side * 2.5, 3.1, z) * CFrame.Angles(0, side * math.pi / 2, 0), Rustic.PaintRed, Enum.Material.Fabric)
		seat.CanTouch = true
		table.insert(seats, seat)
	end
	-- The tractor in front.
	local t = origin * CFrame.new(0, 0, -9)
	tractorLook[#tractorLook + 1] = part(model, "TractorBody", Vector3.new(4, 3, 6), t * CFrame.new(0, 3, 0), Rustic.PaintGreen, Enum.Material.Metal)
	tractorLook[#tractorLook + 1] = part(model, "TractorHood", Vector3.new(3, 2, 3), t * CFrame.new(0, 3.5, -3.5), Rustic.PaintGreen, Enum.Material.Metal)
	tractorLook[#tractorLook + 1] = part(model, "TractorStack", Vector3.new(0.5, 3, 0.5), t * CFrame.new(1, 6, -3), Color3.fromRGB(60, 58, 56), Enum.Material.Metal)
	for _, side in { -1, 1 } do
		tractorLook[#tractorLook + 1] = part(model, "TractorWheel", Vector3.new(1.2, 4.4, 4.4), t * CFrame.new(side * 2.6, 2.2, 1.5), Color3.fromRGB(40, 38, 36), Enum.Material.Rubber, Enum.PartType.Cylinder)
		tractorLook[#tractorLook + 1] = part(model, "TractorFront", Vector3.new(0.8, 2.4, 2.4), t * CFrame.new(side * 1.8, 1.2, -3.5), Color3.fromRGB(40, 38, 36), Enum.Material.Rubber, Enum.PartType.Cylinder)
	end
	part(model, "Driver", Vector3.new(1.6, 2.6, 1), t * CFrame.new(0, 5.6, 1.5), Color3.fromRGB(120, 92, 70), Enum.Material.Fabric)
	part(model, "DriverHat", Vector3.new(2.2, 0.5, 2.2), t * CFrame.new(0, 7.2, 1.5), Color3.fromRGB(189, 168, 112), Enum.Material.Fabric)
	local board = part(model, "WagonBoard", Vector3.new(6, 1.4, 0.3), origin * CFrame.new(0, 5.2, 9.2), Rustic.PaintCream, Enum.Material.WoodPlanks)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(300, 70)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Merriweather
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(40, 32, 26)
	label.Text = "FREE HAY WAGON"
	label.Parent = gui
	gui.Parent = board
	table.insert(wagonLook, board)

	-- The Blender wagon (origin at the bed center, board at the back, tongue to the front) and tractor, when
	-- imported. Only looks, welded to the bed; the seats, driver and prompt stay parts, and each client keeps the
	-- part wagon until the meshes have loaded.
	local wagonMesh = Props.make("hay_wagon", origin * CFrame.new(0, 2.75, 2 - 0.58))
	if wagonMesh then
		Props.restOn(wagonMesh, origin.Y)
		wagonMesh.Parent = model
		Props.weldTo(wagonMesh, bed, wagonLook)
	end
	local tractorMesh = Props.make("farm_tractor", t * CFrame.new(0, 3.5, -0.65))
	if tractorMesh then
		Props.restOn(tractorMesh, origin.Y)
		tractorMesh.Parent = model
		Props.weldTo(tractorMesh, bed, tractorLook)
	end

	-- Ride: seats you in a free seat (riders only, no cargo).
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ride"
	prompt.ObjectText = "Free hay wagon"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = bed
	prompt.Triggered:Connect(function(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.SeatPart then
			return
		end
		for _, seat in seats do
			if not seat.Occupant then
				seat:Sit(humanoid)
				return
			end
		end
	end)
	model.Parent = parent
	return model, seats, label
end

HayWagon.legs = {} -- { stop, samples }

function HayWagon.build(parent)
	local folder = Instance.new("Folder")
	folder.Name = "HayWagon"
	folder.Parent = parent
	for _, leg in legs() do
		table.insert(HayWagon.legs, { stop = leg.stop, samples = sample(leg.line) })
	end
	-- A stop sign at each stop.
	local seen = {}
	for _, leg in HayWagon.legs do
		if not seen[leg.stop] then
			seen[leg.stop] = true
			local at = leg.samples[#leg.samples]
			local text = ("HAY WAGON STOP\n%s\nFree: Camp, Homestead, Swamp Port"):format(leg.stop:upper())
			if Regions.signpost then
				pcall(Regions.signpost, folder, at.X + 12, at.Z, Vector2.new(-1, 0), text, 12)
			end
		end
	end

	local model, seats, label = buildWagon(folder)
	HayWagon.model, HayWagon.seats = model, seats
	local state = { leg = 1, i = 1, along = 0, wait = STOP_SECONDS }
	HayWagon.state = state

	local function place()
		local samples = HayWagon.legs[state.leg].samples
		local a = samples[state.i]
		local b = samples[math.min(state.i + 1, #samples)]
		local p = a:Lerp(b, state.along)
		local ahead = samples[math.min(state.i + 3, #samples)]
		local dir = Vector3.new(ahead.X - p.X, 0, ahead.Z - p.Z)
		if dir.Magnitude < 0.1 then
			dir = model:GetPivot().LookVector
		end
		model:PivotTo(CFrame.lookAt(p, p + dir.Unit))
	end

	-- Moves the wagon dt seconds along the loop (tests call this directly).
	function HayWagon.step(dt)
		if state.wait > 0 then
			state.wait -= dt
			label.Text = ("FREE HAY WAGON\nnext: %s"):format(HayWagon.legs[state.leg].stop)
			return
		end
		local samples = HayWagon.legs[state.leg].samples
		local move = SPEED * dt
		while move > 0 do
			local a, b = samples[state.i], samples[state.i + 1]
			if not b then
				-- End of the leg: a stop, then the next leg.
				state.leg = state.leg % #HayWagon.legs + 1
				state.i, state.along, state.wait = 1, 0, STOP_SECONDS
				break
			end
			local length = math.max(0.01, (b - a).Magnitude)
			local left = (1 - state.along) * length
			if move < left then
				state.along += move / length
				move = 0
			else
				move -= left
				state.i += 1
				state.along = 0
			end
		end
		place()
	end

	place()
	RunService.Heartbeat:Connect(function(dt)
		if model.Parent then
			HayWagon.step(math.min(dt, 0.1))
		end
	end)
end

return HayWagon

end

MODULES["Services.Discoveries"] = function(script)
-- Exploration as a progression track: the first visit to each region (Config/WorldMap Regions, plus Sky Island and
-- the Crystal Cave) and each landmark (Config/WorldMap Discoveries) pays Prices.Discovery once per save slot and
-- stamps it as found. Kept in state.discovered and published as the player attribute "Discovered" ("old_well,pine,...")
-- for the map's stamps and the collection book's pages. Discoveries.all() lists every one in order, for those pages.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Prices = require(Shared.Config.Prices)
local WorldRegions = require(Shared.WorldRegions)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local WorldShape = require(script.Parent.WorldShape)

local Discoveries = {}

local CHECK_EVERY = 1 -- seconds

-- Every discovery: { id, name, kind = "region" | "landmark", at = Vector2? (landmarks), radius }
local list = {}
local byId = {}

local function add(entry)
	table.insert(list, entry)
	byId[entry.id] = entry
end

for _, r in Map.Regions do
	add({ id = r.id, name = r.name, kind = "region" })
end
add({ id = WorldRegions.Sky.id, name = WorldRegions.Sky.name, kind = "region" })
add({ id = WorldRegions.Cave.id, name = WorldRegions.Cave.name, kind = "region" })
local landmarks = {}
for _, d in Map.Discoveries do
	local at = d.at
	if d.flat then
		for _, zone in Map.Flat do
			if zone.name == d.flat then
				at = (zone.min + zone.max) / 2
			end
		end
	end
	if at then
		local entry = { id = d.id, name = d.name, kind = "landmark", at = at, radius = d.radius }
		add(entry)
		table.insert(landmarks, entry)
	end
end

-- Where the first-visit camera pan looks (#24): the region's first landmark, else its peak, else its middle.
-- Sky Island looks at the zeppelin platform; the Crystal Cave has no pan (the camera would clip the rock).
local focusCache = {}
function Discoveries.focus(id)
	if focusCache[id] ~= nil then
		return focusCache[id] or nil
	end
	local at = nil
	if id == WorldRegions.Sky.id then
		at = Map.Zeppelin.b.pos
	elseif id ~= WorldRegions.Cave.id then
		for _, entry in landmarks do
			local y = WorldShape.heightAt(entry.at.X, entry.at.Y)
			local region = WorldRegions.at(Vector3.new(entry.at.X, y + 2, entry.at.Y))
			if region and region.id == id then
				at = Vector3.new(entry.at.X, math.max(y, Map.SeaLevel), entry.at.Y)
				break
			end
		end
		local r = not at and WorldShape.region(id)
		if r then
			local c = r.peak and r.peak.center or Vector2.new(r.cx, r.cz)
			at = Vector3.new(c.X, math.max(WorldShape.heightAt(c.X, c.Y), Map.SeaLevel), c.Y)
		end
	end
	focusCache[id] = at or false
	return at
end

local introRemote = nil

-- A discovery made by finding something rather than by walking up to it (Wilds hidden spots): stamped by
-- Discoveries.discover when it's found; kind "hidden" pays nothing here (the find pays its own reward).
function Discoveries.addHidden(id, name)
	if not byId[id] then
		add({ id = id, name = name, kind = "hidden" })
	end
end

function Discoveries.all()
	return list
end

function Discoveries.info(id)
	return byId[id]
end

local function publish(player)
	local state = Data.get(player)
	local ids = {}
	for id in (state and state.discovered or {}) do
		table.insert(ids, id)
	end
	table.sort(ids)
	player:SetAttribute("Discovered", table.concat(ids, ","))
	player:SetAttribute("DiscoveredCount", #ids)
end

function Discoveries.has(player, id)
	local state = Data.get(player)
	return state ~= nil and state.discovered ~= nil and state.discovered[id] ~= nil
end

-- Marks a discovery found for this player (first time only); returns true when it was new.
function Discoveries.discover(player, id)
	local entry = byId[id]
	local state = Data.get(player)
	if not entry or not state then
		return false
	end
	state.discovered = state.discovered or {}
	if state.discovered[id] then
		return false
	end
	state.discovered[id] = 1
	local reward = Prices.Discovery[entry.kind] or 0
	if reward > 0 then
		Bank.earn(player, reward, "Discovered " .. entry.name)
	end
	local count = 0
	for _ in state.discovered do
		count += 1
	end
	if entry.kind ~= "hidden" then -- a hidden find already said so
		Data.toast(player, ("Discovered: %s! +$%d   (%d of %d)"):format(entry.name, reward, count, #list))
	end
	-- First time in a region on this save: a short camera pan over its landmark (RegionIntro.client.luau).
	local focus = entry.kind == "region" and Discoveries.focus(id)
	if focus and introRemote then
		task.spawn(function()
			pcall(player.RequestStreamAroundAsync, player, focus, 4)
			if player.Parent then
				pcall(introRemote.FireClient, introRemote, player, entry.name, focus)
			end
		end)
	end
	publish(player)
	return true
end

-- What a player standing at this position discovers (region first, then any landmark in reach).
function Discoveries.at(position)
	local found = {}
	local region = WorldRegions.at(position)
	if region and region.id ~= WorldRegions.Meadow.id then
		table.insert(found, region.id)
	end
	local flat = Vector2.new(position.X, position.Z)
	for _, entry in landmarks do
		if (flat - entry.at).Magnitude <= entry.radius then
			table.insert(found, entry.id)
		end
	end
	return found
end

local started = false
function Discoveries.start()
	if started then
		return
	end
	started = true
	introRemote = Instance.new("RemoteEvent")
	introRemote.Name = "RegionIntro"
	introRemote.Parent = ReplicatedStorage
	Data.loaded.Event:Connect(publish)
	for _, player in Players:GetPlayers() do
		if Data.get(player) then
			publish(player)
		end
	end
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and Data.get(player) then
					for _, id in Discoveries.at(root.Position) do
						if not Discoveries.has(player, id) then
							Discoveries.discover(player, id)
						end
					end
				end
			end
		end
	end)
end

return Discoveries

end

MODULES["Services.SpindleDoor"] = function(script)
-- The Spindle's sealed door (Regions LANDMARKS.spindle builds it): twelve sockets in a ring, one per Master Needle
-- shard (Quests owns the shards; Config/Quests Collection lists them in order). A socket glows while anyone on this
-- server holds its shard, so the door shows the whole server's progress. Each player's own count is the attribute
-- SpindleShards; with all twelve the door lets that player through (SpindleDoor.client opens it on their screen
-- only) into the Loom Room carved into the mountain behind it, where the Master Needle's empty pedestal waits
-- (tagged MasterNeedlePedestal, for Quests to hook the ending on).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestConfig = require(ReplicatedStorage.Shared.Config.Quests)
local WorldTerrain = require(script.Parent.WorldTerrain)
local Data = require(script.Parent.Data)
local WorldClock = require(script.Parent.WorldClock)
local Props = require(script.Parent.Props)

local SpindleDoor = {}

SpindleDoor.SLOTS = 12
local CHECK_EVERY = 2
local GOLD = Color3.fromRGB(242, 183, 5)

-- Shard ids in slot order: the shards in the collection, in its order (more arrive as Quests adds them).
local shards = {}
for _, entry in QuestConfig.Collection do
	if string.sub(entry.id, 1, 6) == "shard_" and #shards < SpindleDoor.SLOTS then
		table.insert(shards, entry.id)
	end
end
SpindleDoor.shards = shards

local Quests = nil
local function has(player, id)
	if not Quests then
		local ok, module = pcall(require, script.Parent.Quests)
		Quests = ok and module or false
	end
	return Quests and Quests.has and Quests.has(player, id) == true
end

-- How many shards this player holds.
function SpindleDoor.count(player)
	local n = 0
	for _, id in shards do
		if has(player, id) then
			n += 1
		end
	end
	return n
end

local function setSocket(socket, lit)
	if socket:GetAttribute("Lit") == lit then
		return
	end
	socket:SetAttribute("Lit", lit)
	socket.Transparency = lit and 0 or 0.6
	local glow = socket:FindFirstChildOfClass("PointLight")
	if lit and not glow then
		glow = Instance.new("PointLight")
		glow.Color = GOLD
		glow.Range = 8
		glow.Brightness = 1.2
		glow.Parent = socket
	end
	if glow then
		glow.Enabled = lit
	end
end

-- Lights the sockets and publishes each player's count. Called every few seconds; tests call it directly.
function SpindleDoor.refresh()
	local held = {}
	for _, player in Players:GetPlayers() do
		local n = 0
		for slot, id in shards do
			if has(player, id) then
				held[slot] = true
				n += 1
			end
		end
		player:SetAttribute("SpindleShards", n)
	end
	local lit = 0
	for _, socket in CollectionService:GetTagged("ShardSocket") do
		setSocket(socket, held[socket:GetAttribute("Slot") or 0] == true)
		if socket:GetAttribute("Lit") then
			lit += 1
		end
	end
	-- The Spindle glows as its sockets fill (#26): a gold light on the door that grows with every lit socket, brighter
	-- at night so the mountain's face shows from the valley.
	for _, door in CollectionService:GetTagged("SpindleDoor") do
		local glow = door:FindFirstChild("SpindleGlow")
		if not glow then
			glow = Instance.new("PointLight")
			glow.Name = "SpindleGlow"
			glow.Color = GOLD
			glow.Shadows = false
			glow.Parent = door
			CollectionService:AddTag(glow, "AlwaysLit")
		end
		local night = WorldClock.isNight()
		glow.Enabled = lit > 0
		glow.Range = math.min(60, 16 + lit * 3.5)
		glow.Brightness = lit / SpindleDoor.SLOTS * (night and 5 or 2)
		door:SetAttribute("Glow", lit / SpindleDoor.SLOTS)
	end
end

local function part(parent, name, size, cframe, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.Parent = parent
	return p
end

-- The Loom Room behind the door: carved out of the Spindle once the terrain is down, floored and lit.
local function loomRoom(door)
	local folder = Instance.new("Folder")
	folder.Name = "LoomRoom"
	folder.Parent = door.Parent
	local base = door.CFrame * CFrame.new(0, -10, 0) -- the door's foot; its back (+Z) faces into the mountain
	local depth, width, height = 40, 12, 16
	local room = base * CFrame.new(0, height / 2, 2 + depth / 2)
	local waited = 0
	while not WorldTerrain.isReady() and waited < 600 do
		task.wait(5)
		waited += 5
	end
	pcall(function()
		workspace.Terrain:FillBlock(room, Vector3.new(width, height, depth), Enum.Material.Air)
	end)
	local stone = Color3.fromRGB(150, 142, 160)
	part(folder, "LoomFloor", Vector3.new(width, 1, depth), base * CFrame.new(0, -0.5, 2 + depth / 2), Color3.fromRGB(96, 86, 120), Enum.Material.Slate)
	for _, side in { -1, 1 } do
		part(folder, "LoomWall", Vector3.new(1, height, depth), room * CFrame.new(side * (width / 2 + 0.5), 0, 0), stone, Enum.Material.Slate)
	end
	part(folder, "LoomCeiling", Vector3.new(width + 2, 1, depth), room * CFrame.new(0, height / 2 + 0.5, 0), stone, Enum.Material.Slate)
	part(folder, "LoomBack", Vector3.new(width, height, 1), room * CFrame.new(0, 0, depth / 2 + 0.5), stone, Enum.Material.Slate)
	for i = 1, 3 do
		local lamp = part(folder, "LoomLamp", Vector3.new(0.8, 0.8, 0.8), room * CFrame.new(width / 2 - 0.8, 3, -depth / 2 + i * 10), GOLD, Enum.Material.Neon, false)
		CollectionService:AddTag(lamp, "AlwaysLit")
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 18
		light.Parent = lamp
	end
	local pedestal = part(folder, "MasterNeedlePedestal", Vector3.new(4, 4, 4), base * CFrame.new(0, 2, 2 + depth - 5), stone, Enum.Material.Marble)
	CollectionService:AddTag(pedestal, "MasterNeedlePedestal")
	-- The Blender pedestal (Config/Props loom_pedestal, 4 x 4 x 4 with its Cradle on top), when imported: a look on
	-- the part, which stays the finale's spot.
	local mesh = Props.make("loom_pedestal", pedestal.CFrame)
	if mesh then
		Props.restOn(mesh, pedestal.Position.Y - pedestal.Size.Y / 2)
		Props.weldTo(mesh, pedestal, pedestal)
	end
end

local started = false
function SpindleDoor.start()
	if started then
		return
	end
	started = true
	local door = CollectionService:GetTagged("SpindleDoor")[1]
	if door then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Inspect"
		prompt.ObjectText = "The Spindle Door"
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = door
		prompt.Triggered:Connect(function(player)
			local n = SpindleDoor.count(player)
			Data.toast(player, n >= SpindleDoor.SLOTS and "The door knows you. It opens." or ("Twelve sockets. You hold %d of the shards."):format(n))
		end)
		task.spawn(loomRoom, door)
	end
	task.spawn(function()
		while true do
			pcall(SpindleDoor.refresh)
			task.wait(CHECK_EVERY)
		end
	end)
end

return SpindleDoor

end

MODULES["Services.FallSafety"] = function(script)
-- Fall safety (map #22): a player or truck that drops through the world (a hole in the terrain, off a cliff edge the
-- sea doesn't catch, a glitch under a building) is caught below KILL_Y and set back on the nearest road, facing along
-- it, never sent all the way back to camp. A truck comes back with its hitched trailer (Vehicles.recover "rescue").
-- Roblox would destroy anything below FallenPartsDestroyHeight (-500); the catch is far above that.
--
-- FallSafety.target(position) is the landing spot for any point, and the offline map check (tools/mapcheck) asks it
-- for points all over the map to prove every landing is dry with headroom.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)
local WorldShape = require(script.Parent.WorldShape)
local Data = require(script.Parent.Data)
local Vehicles = require(script.Parent.Vehicles)

local FallSafety = {}

FallSafety.KILL_Y = Map.SeaFloor - 40 -- below the deepest sea floor: nothing should ever be down here
local STEP = 12 -- studs between candidate road points
local CHECK_EVERY = 0.5
local DRY = Map.SeaLevel + 1 -- a landing must stand this far above the sea

-- Every road point (Meadow's roads and the isles' roads), with the road's name and its direction.
local points = nil
local function roadPoints()
	if points then
		return points
	end
	points = {}
	for _, list in { Meadow.Roads, Map.Roads } do
		for _, road in list do
			for i = 1, #road.points - 1 do
				local a, b = road.points[i], road.points[i + 1]
				local dir = (b - a).Unit
				local n = math.max(1, math.ceil((b - a).Magnitude / STEP))
				for k = 0, n do
					local p = a:Lerp(b, k / n)
					local y = WorldShape.heightAt(p.X, p.Y)
					if y > DRY then
						table.insert(points, { x = p.X, z = p.Y, y = y, dir = dir, name = road.name })
					end
				end
			end
		end
	end
	return points
end
FallSafety.roadPoints = roadPoints

-- The landing for a fall at position: the nearest dry road point, standing on it, facing along the road.
-- Returns a ground CFrame (feet on the road) and the road's name.
function FallSafety.target(position)
	local best, bestD = nil, math.huge
	for _, p in roadPoints() do
		local d = (p.x - position.X) ^ 2 + (p.z - position.Z) ^ 2
		if d < bestD then
			best, bestD = p, d
		end
	end
	if not best then
		local camp = Vector3.new(0, 0, 14)
		return CFrame.new(camp), "camp"
	end
	local at = Vector3.new(best.x, best.y, best.z)
	return CFrame.lookAt(at, at + Vector3.new(best.dir.X, 0, best.dir.Y)), best.name
end

local function roadLabel(name)
	if name == "camp" then
		return "base camp"
	end
	return ("the %s"):format(name)
end

local busy = {}

local function catchPlayer(player, root)
	busy[player] = true
	local ground, name = FallSafety.target(root.Position)
	pcall(player.RequestStreamAroundAsync, player, ground.Position, 5)
	local character = player.Character
	if character and character.Parent and root.Parent then
		character:PivotTo(ground * CFrame.new(0, 4, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		if Data.get(player) then
			Data.toast(player, ("You fell through the world. Back on %s."):format(roadLabel(name)))
		end
	end
	busy[player] = nil
end

local function catchTruck(player, truck)
	busy[truck] = true
	local ground, name = FallSafety.target(truck.PrimaryPart.Position)
	pcall(player.RequestStreamAroundAsync, player, ground.Position, 5)
	if truck.Parent and truck.PrimaryPart then
		local ok = Vehicles.recover(player, "rescue", ground)
		if ok and Data.get(player) then
			Data.toast(player, ("Your truck fell through the world. It's back on %s."):format(roadLabel(name)))
		end
	end
	busy[truck] = nil
end

-- An unhitched trailer has no truck to come back with: it is set back on the road by itself.
local function catchTrailer(player, trailer)
	busy[trailer] = true
	local ground, name = FallSafety.target(trailer.PrimaryPart.Position)
	if trailer.Parent and trailer.PrimaryPart then
		trailer:PivotTo(ground * CFrame.new(0, 4, 0))
		for _, p in trailer:GetDescendants() do
			if p:IsA("BasePart") then
				p.AssemblyLinearVelocity = Vector3.zero
				p.AssemblyAngularVelocity = Vector3.zero
			end
		end
		if Data.get(player) then
			Data.toast(player, ("Your trailer fell through the world. It's back on %s."):format(roadLabel(name)))
		end
	end
	busy[trailer] = nil
end

-- One pass: anyone or any player truck below the kill floor is put back on a road.
function FallSafety.step()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- A seated driver goes with the truck below.
		if root and not busy[player] and root.Position.Y < FallSafety.KILL_Y and not (humanoid and humanoid.SeatPart) then
			task.spawn(catchPlayer, player, root)
		end
	end
	for model, owner in Vehicles.all() do
		local chassis = model.PrimaryPart
		if chassis and not busy[model] and model:GetAttribute("TruckId") and chassis.Position.Y < FallSafety.KILL_Y then
			task.spawn(catchTruck, owner, model)
		elseif chassis and not busy[model] and model:GetAttribute("TrailerId") and not model:GetAttribute("HitchedTo") and chassis.Position.Y < FallSafety.KILL_Y then
			task.spawn(catchTrailer, owner, model)
		end
	end
end

local started = false
function FallSafety.start()
	if started then
		return
	end
	started = true
	task.spawn(roadPoints)
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			local ok, err = pcall(FallSafety.step)
			if not ok then
				warn("[Needlewood] fall safety: " .. tostring(err))
			end
		end
	end)
end

return FallSafety

end

MODULES["Services.RoadGraph"] = function(script)
-- The road network as a graph (map #23): Meadow's roads, the isles' roads and the Longstitch Highway, sampled every
-- STEP studs, with a junction wherever two roads come within JOIN studs. RoadGraph.distances(from) gives the driving
-- distance from the road point nearest `from` to every other point; RoadGraph.distance(from, to) the one number.
-- Signposts print these (Regions.luau JUNCTIONS) so a sign can never drift from the roads it points down.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local Meadow = require(Shared.Config.Meadow)

local RoadGraph = {}

local STEP = 16
local JOIN = 10 -- road points this close are one junction
local CELL = 64
local END_JOIN = 30 -- a road's end joins the nearest point of another road this close

type Node = { x: number, z: number, road: string, links: { [number]: number } }

local nodes: { Node }? = nil
local grid: { [string]: { number } } = {}

local function key(x: number, z: number): string
	return math.floor(x / CELL) .. "," .. math.floor(z / CELL)
end

local function build(): { Node }
	local list: { Node } = {}
	local function link(a: number, b: number)
		if a == b then
			return
		end
		local na, nb = list[a], list[b]
		local d = math.sqrt((na.x - nb.x) ^ 2 + (na.z - nb.z) ^ 2)
		if not na.links[b] or na.links[b] > d then
			na.links[b] = d
			nb.links[a] = d
		end
	end
	local roads = {}
	for _, road in Meadow.Roads do
		table.insert(roads, { name = road.name, points = road.points })
	end
	for _, road in Map.Roads do
		table.insert(roads, { name = road.name, points = road.points })
	end
	table.insert(roads, { name = "Longstitch Highway", points = { Map.Highway.from, Map.Highway.to } })
	local ends: { number } = {} -- each road's first and last point
	for _, road in roads do
		local prev: number? = nil
		local first = #list + 1
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			local n = math.max(1, math.ceil((b - a).Magnitude / STEP))
			for k = (i == 1 and 0 or 1), n do
				local p = a:Lerp(b, k / n)
				table.insert(list, { x = p.X, z = p.Y, road = road.name, links = {} })
				local index = #list
				local cell = key(p.X, p.Y)
				grid[cell] = grid[cell] or {}
				table.insert(grid[cell], index)
				if prev then
					link(prev, index)
				end
				prev = index
			end
		end
		table.insert(ends, first)
		table.insert(ends, #list)
	end
	-- Junctions: any two points of different roads within JOIN studs.
	for index, node in list do
		local cx, cz = math.floor(node.x / CELL), math.floor(node.z / CELL)
		for dx = -1, 1 do
			for dz = -1, 1 do
				for _, other in (grid[(cx + dx) .. "," .. (cz + dz)] or {}) :: { number } do
					local o = list[other]
					if o.road ~= node.road and (o.x - node.x) ^ 2 + (o.z - node.z) ^ 2 <= JOIN * JOIN then
						link(index, other)
					end
				end
			end
		end
	end
	-- A road that ends on another road (between its sample points) joins it at the nearest point.
	for _, e in ends do
		local node = list[e]
		local best, bestD = nil, END_JOIN * END_JOIN
		local cx, cz = math.floor(node.x / CELL), math.floor(node.z / CELL)
		for dx = -1, 1 do
			for dz = -1, 1 do
				for _, other in (grid[(cx + dx) .. "," .. (cz + dz)] or {}) :: { number } do
					local o = list[other]
					local d = (o.x - node.x) ^ 2 + (o.z - node.z) ^ 2
					if o.road ~= node.road and d < bestD then
						best, bestD = other, d
					end
				end
			end
		end
		if best then
			link(e, best)
		end
	end
	-- Roads that end on the same plaza or port (a flat zone) are joined across it.
	for _, zone in Map.Flat do
		local inside = {}
		for _, e in ends do
			local n = list[e]
			if n.x >= zone.min.X - JOIN and n.x <= zone.max.X + JOIN and n.z >= zone.min.Y - JOIN and n.z <= zone.max.Y + JOIN then
				table.insert(inside, e)
			end
		end
		for i = 1, #inside do
			for k = i + 1, #inside do
				link(inside[i], inside[k])
			end
		end
	end
	return list
end

function RoadGraph.nodes(): { Node }
	if not nodes then
		nodes = build()
	end
	return nodes :: { Node }
end

-- The index of the road point nearest a spot, and how far off the road the spot is.
function RoadGraph.nearest(at: Vector2): (number, number)
	local best, bestD = 1, math.huge
	for index, node in RoadGraph.nodes() do
		local d = (node.x - at.X) ^ 2 + (node.z - at.Y) ^ 2
		if d < bestD then
			best, bestD = index, d
		end
	end
	return best, math.sqrt(bestD)
end

-- Dijkstra from the road point nearest `from`: distance to every node (math.huge if unreachable by road).
function RoadGraph.distances(from: Vector2): { number }
	local list = RoadGraph.nodes()
	local start = RoadGraph.nearest(from)
	local dist = table.create(#list, math.huge)
	dist[start] = 0
	-- A small binary heap of { distance, node }.
	local heap: { { number } } = { { 0, start } }
	local function push(item: { number })
		table.insert(heap, item)
		local i = #heap
		while i > 1 do
			local parent = i // 2
			if heap[parent][1] <= heap[i][1] then
				break
			end
			heap[parent], heap[i] = heap[i], heap[parent]
			i = parent
		end
	end
	local function pop(): { number }
		local top = heap[1]
		local last = table.remove(heap) :: { number }
		if #heap > 0 then
			heap[1] = last
			local i = 1
			while true do
				local l, r, small = i * 2, i * 2 + 1, i
				if l <= #heap and heap[l][1] < heap[small][1] then
					small = l
				end
				if r <= #heap and heap[r][1] < heap[small][1] then
					small = r
				end
				if small == i then
					break
				end
				heap[small], heap[i] = heap[i], heap[small]
				i = small
			end
		end
		return top
	end
	while #heap > 0 do
		local item = pop()
		local d, index = item[1], item[2]
		if d <= dist[index] then
			for other, w in list[index].links do
				local nd = d + w
				if nd < dist[other] then
					dist[other] = nd
					push({ nd, other })
				end
			end
		end
	end
	return dist
end

-- Driving distance between two spots, by road (each snapped to its nearest road point).
function RoadGraph.distance(from: Vector2, to: Vector2): number
	local dist = RoadGraph.distances(from)
	local target = RoadGraph.nearest(to)
	return dist[target]
end

return RoadGraph

end

MODULES["Services.Festival"] = function(script)
-- The weekly region festival (Addiction push H11). Each week one region (Config/WorldMap FestivalOrder, in turn,
-- counted from FestivalEpoch so every server agrees) holds its hay festival:
--   * its field bales carry FestivalBoost times the needles (NeedleBoost; never stacked on the rich field's 2x),
--   * bunting and a banner go up beside its first field,
--   * a player who visits it that week earns that week's festival ribbon (cosmetic, saved as state.festivals,
--     published as the player attribute FestivalRibbons = count).
-- ReplicatedStorage attributes for the HUD countdown strip: FestivalRegion (id), FestivalName and FestivalEnds
-- (server time the week ends).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.WorldMap)
local WorldRegions = require(Shared.WorldRegions)
local WorldShape = require(script.Parent.WorldShape)
local Regions = require(script.Parent.Regions)
local Data = require(script.Parent.Data)
local Announce = require(script.Parent.Announce)

local Festival = {}

local CHECK_EVERY = 15 -- seconds
local FLAG_COLORS = { Color3.fromRGB(196, 72, 60), Color3.fromRGB(232, 190, 84), Color3.fromRGB(80, 128, 168), Color3.fromRGB(236, 228, 206) }

local names = {}
for _, r in Map.Regions do
	names[r.id] = r.name
end

-- The week number for a unix time (0 = the week starting FestivalEpoch).
function Festival.week(t)
	return math.floor((t - Map.FestivalEpoch) / Map.FestivalWeek)
end

-- The festival region for a week number.
function Festival.regionFor(week)
	local order = Map.FestivalOrder
	return order[week % #order + 1]
end

-- This week's festival: { week, region, name, starts, ends } (unix times).
function Festival.at(t)
	local week = Festival.week(t)
	local region = Festival.regionFor(week)
	local starts = Map.FestivalEpoch + week * Map.FestivalWeek
	return { week = week, region = region, name = names[region] or region, starts = starts, ends = starts + Map.FestivalWeek }
end

local current = nil
local folder = nil

function Festival.current()
	return current
end

local function part(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Bunting round the region's first field: four poles with flag strings between them, and a banner.
local function decorate(fest)
	if folder then
		folder:ClearAllChildren()
	end
	local entry = nil
	for _, f in Regions.fields do
		if f.region == fest.name then
			entry = f
			break
		end
	end
	if not entry or not folder then
		return
	end
	local c = entry.center
	local corners = {}
	for i, o in { Vector2.new(-15, -15), Vector2.new(15, -15), Vector2.new(15, 15), Vector2.new(-15, 15) } do
		local x, z = c.X + o.X, c.Z + o.Y
		local y = WorldShape.heightAt(x, z)
		part(folder, "FestivalPole", Vector3.new(0.5, 10, 0.5), CFrame.new(x, y + 5, z), Color3.fromRGB(92, 70, 52), Enum.Material.Wood)
		corners[i] = Vector3.new(x, y + 9.6, z)
	end
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		local n = 7
		for k = 1, n do
			local p = a:Lerp(b, k / (n + 1)) - Vector3.new(0, math.sin(k / (n + 1) * math.pi) * 1.5, 0)
			local flag = part(folder, "FestivalFlag", Vector3.new(0.1, 1.2, 1), CFrame.lookAt(p, p + (b - a)) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, -0.6, 0), FLAG_COLORS[(i + k) % #FLAG_COLORS + 1])
			flag.CanCollide = false
			flag.CastShadow = false
		end
	end
	local top = corners[1]:Lerp(corners[2], 0.5) + Vector3.new(0, 1.5, 0)
	local banner = part(folder, "FestivalBanner", Vector3.new(14, 3, 0.3), CFrame.new(top), Color3.fromRGB(196, 72, 60))
	banner.CanCollide = false
	pcall(Regions.billboard, banner, ("%s HAY FESTIVAL\n+50%% needles all week"):format(string.upper(fest.name)), Vector3.new(0, 3, 0), 300)
end

-- Gives the festival's fields their boost (and takes it back from last week's), every few seconds so regrown bales
-- get it too. The rich field's own 2x is left alone.
local function boostFields(fest)
	for _, entry in Regions.fields do
		local on = entry.region == fest.name
		for b in entry.bales do
			local body = b.body
			if body and body.Parent then
				local marked = body:GetAttribute("FestivalBoost") == true
				if on then
					-- Marked even under a bigger boost (the rich field's 2x), so the bale drops back to the
					-- festival's boost, not to none, when the rich field moves on.
					if (body:GetAttribute("NeedleBoost") or 1) < Map.FestivalBoost then
						body:SetAttribute("NeedleBoost", Map.FestivalBoost)
					end
					if not marked then
						body:SetAttribute("FestivalBoost", true)
					end
				elseif marked then
					body:SetAttribute("FestivalBoost", nil)
					if not body:GetAttribute("RichBoost") then
						body:SetAttribute("NeedleBoost", nil)
					end
				end
			end
		end
	end
end

local function publish(player)
	local state = Data.get(player)
	local n = 0
	for _ in (state and state.festivals or {}) do
		n += 1
	end
	player:SetAttribute("FestivalRibbons", n)
end

-- A player standing in the festival region earns this week's ribbon (once). Returns true when it was new.
function Festival.visit(player, position)
	local state = Data.get(player)
	local region = current and WorldRegions.at(position)
	if not state or not region or region.id ~= current.region then
		return false
	end
	state.festivals = state.festivals or {}
	local key = current.week .. ":" .. current.region
	if state.festivals[key] then
		return false
	end
	state.festivals[key] = 1
	publish(player)
	Data.toast(player, ("Festival ribbon: %s Hay Festival! Bales here hold 50%% more needles all week."):format(current.name))
	return true
end

-- Moves the festival on when the week turns (and on start). `t` is a unix time (tests pass their own).
function Festival.refresh(t)
	local fest = Festival.at(t or os.time())
	local changed = not current or current.week ~= fest.week
	current = fest
	ReplicatedStorage:SetAttribute("FestivalRegion", fest.region)
	ReplicatedStorage:SetAttribute("FestivalName", fest.name)
	ReplicatedStorage:SetAttribute("FestivalEnds", fest.ends)
	if changed then
		pcall(decorate, fest)
		if t == nil then
			pcall(Announce.say, ("This week's festival: %s! Its hay holds 50%% more needles until the week turns."):format(fest.name), "event")
		end
	end
	boostFields(fest)
	return fest
end

local started = false
function Festival.start(parent)
	if started then
		return
	end
	started = true
	folder = Instance.new("Model")
	folder.Name = "Festival"
	folder.Parent = parent
	Data.loaded.Event:Connect(publish)
	Festival.refresh()
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			local ok, err = pcall(Festival.refresh)
			if not ok then
				warn("[Needlewood] festival: " .. tostring(err))
			end
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					pcall(Festival.visit, player, root.Position)
				end
			end
		end
	end)
end

return Festival

end

local t0 = os.clock()
local world = Instance.new("Folder")
world.Name = "Needlewood"
world.Parent = workspace
local meadow = Instance.new("Folder")
meadow.Name = "Meadow"
meadow.Parent = world
local WorldMap = require({ __path = "Services.WorldMap" })
WorldMap.build(world)
local isles = world:FindFirstChild("StitchedIsles")
local function count(folder)
	local parts, models, guis, lights = 0, 0, 0, 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then parts += 1 elseif d.ClassName == "Model" then models += 1 elseif d:IsA("LayerCollector") then guis += 1 elseif d:IsA("Light") then lights += 1 end
	end
	return parts, models, guis, lights
end
for _, child in isles:GetChildren() do
	local p, m, g, l = count(child)
	print(("%-22s parts %6d  models %5d  guis %4d  lights %3d"):format(child.Name, p, m, g, l))
	if child.Name == "Isles" then
		for _, sub in child:GetChildren() do
			local p2 = count(sub)
			print(("    %-26s parts %6d"):format(sub.Name, p2))
		end
	end
end
local p, m, g, l = count(isles)
print(("TOTAL parts %d models %d guis %d lights %d; field bales %d; time %.2fs; warnings %d"):format(p, m, g, l, BALES, os.clock() - t0, #warnings))
for tag, n in TAGS do print("tag", tag, n) end
local Shape = require({ __path = "Services.WorldShape" })
local Map = require({ __path = "Shared.Config.WorldMap" })
local half = Map.RoadWidth / 2 - 1
local n = 0
for _, p in isles:FindFirstChild("Isles"):GetDescendants() do
	if p:IsA("BasePart") and p.Anchored and p.CanCollide and p.Transparency < 1 then
		local c, size = p.CFrame, p.Size
		local s = Vector3.new(math.abs(size.X), math.abs(size.Y), math.abs(size.Z))
		for _, o in { Vector3.zero, Vector3.new(s.X/2,0,s.Z/2), Vector3.new(-s.X/2,0,s.Z/2), Vector3.new(s.X/2,0,-s.Z/2), Vector3.new(-s.X/2,0,-s.Z/2) } do
			local at = c * (o * 0.9)
			local d, h, name = Shape.nearestRoad(at.X, at.Z)
			if d and d < half and c.Y + 4 > h + 0.6 and c.Y - 4 < h + 9 then
				n += 1
				print("BLOCK", p:GetFullName(), math.floor(at.X), math.floor(at.Z), name, math.floor(d), math.floor(c.Y - h))
				break
			end
		end
	end
end
print("blocking", n)

-- Every road starts at Meadow's edge, on another road, on a flat zone (plaza, port) or at the highway.
local loose = 0
for r, road in Map.Roads do
	local start = road.points[1]
	local joined = Shape.meadowDistance(start.X, start.Y) < 4 or Shape.highwayDistance(start.X, start.Y) < Map.Highway.width
	for _, zone in Map.Flat do
		if Shape.rectDistance(start.X, start.Y, zone.min, zone.max) <= 0 then
			joined = true
		end
	end
	for other = 1, #Map.Roads do
		local pts = Map.Roads[other].points
		for i = 1, #pts - 1 do
			if other ~= r and Shape.segment(start.X, start.Y, pts[i].X, pts[i].Y, pts[i + 1].X, pts[i + 1].Y) < 4 then
				joined = true
			end
		end
	end
	if not joined then
		loose += 1
		print("WARN loose road start", road.name, start.X, start.Y)
	end
end
print("loose road starts", loose)

-- The clock: night is night, noon is not, lamps follow.
local WorldClock = require({ __path = "Services.WorldClock" })
local Lighting = game:GetService("Lighting")
local clockOk = true
for _, case in { { 0, true, true }, { 12, false, false }, { 18.5, false, true }, { 21, true, true }, { 6.5, false, false } } do
	Lighting.ClockTime = case[1]
	if WorldClock.isNight() ~= case[2] or WorldClock.lampsOn() ~= case[3] then
		clockOk = false
		print("WARN clock wrong at hour", case[1], WorldClock.isNight(), WorldClock.lampsOn())
	end
end
Lighting.ClockTime = 23.5
if WorldClock.phase() ~= "midnight" then clockOk = false end
Lighting.ClockTime = 18
if WorldClock.phase() ~= "dusk" then clockOk = false end
print("clock", clockOk and "ok" or "WRONG", "atmosphere", Lighting:FindFirstChildOfClass("Atmosphere") and "made" or "missing")

-- Weather: every region has a known kind on the board, and an event can force one.
local Weather = require({ __path = "Services.Weather" })
local WeatherConfig = require({ __path = "Shared.Config.Weather" })
local weatherOk = true
for _, r in Map.Regions do
	local kind = Weather.get(r.id)
	if not WeatherConfig.Regions[r.id] or not WeatherConfig.Kinds[kind] then
		weatherOk = false
		print("WARN weather missing for region", r.id, kind)
	end
end
Weather.force("desert", "dust", 60)
if Weather.get("desert") ~= "dust" then weatherOk = false print("WARN weather force did not stick") end
local SoundsConfig = require({ __path = "Shared.Config.Sounds" })
for _, id in { "meadow", "sky", "cave" } do
	if not SoundsConfig.RegionAmbience[id] then weatherOk = false print("WARN no ambience for", id) end
end
for _, r in Map.Regions do
	if not SoundsConfig.RegionAmbience[r.id] then weatherOk = false print("WARN no ambience for", r.id) end
end
-- Fronts (#25): one at a time, warned a minute ahead, then on in its region, then gone; rain only comes as a front
-- over Meadow or the Swamp.
do
	for id, choices in WeatherConfig.Regions do
		for kind in choices do
			for _, f in WeatherConfig.Fronts do
				if f.kind == kind then weatherOk = false print("WARN everyday weather brings a front kind", id, kind) end
			end
		end
	end
	local t = 1000000
	local fr = Weather.startFront(WeatherConfig.Fronts[1])
	if fr.phase ~= "coming" or game:GetService("ReplicatedStorage"):GetAttribute("WeatherFront") ~= "meadow" then weatherOk = false print("WARN front not published") end
	if Weather.get("meadow") == "rain" then weatherOk = false print("WARN front rained before its warning") end
	Weather.stepFront(os.clock() + WeatherConfig.FrontWarnSeconds + 1)
	if Weather.get("meadow") ~= "rain" or Weather.front().phase ~= "on" then weatherOk = false print("WARN front never arrived") end
	Weather.stepFront(os.clock() + t)
	if Weather.front() ~= nil or Weather.get("meadow") == "rain" then weatherOk = false print("WARN front never cleared") end
	-- An event's own weather holds the next front back.
	Weather.force("snow", "snow", t * 10)
	Weather.stepFront(os.clock() + t * 3)
	if Weather.front() ~= nil then weatherOk = false print("WARN a front started during an event") end
	Weather.force("snow", "clear", 0)
end
-- Thunderstorms (H7): warned, then on with 5x odds, then gone with the next one scheduled about an hour out.
do
	local RS = game:GetService("ReplicatedStorage")
	local base = Weather.needleOdds(Vector3.new(0, 5, 0))
	if base ~= 1 then weatherOk = false print("WARN needle odds not 1 without a storm", base) end
	Weather.startStorm()
	if RS:GetAttribute("Storm") ~= "coming" or Weather.needleOdds(Vector3.new(0, 5, 0)) ~= 1 then weatherOk = false print("WARN storm warning wrong") end
	local now = os.clock() + WeatherConfig.StormWarnSeconds + 1
	Weather.stepStorm(now)
	if RS:GetAttribute("Storm") ~= "on" or Weather.needleOdds(Vector3.new(0, 5, 0)) ~= WeatherConfig.StormMutationOdds then weatherOk = false print("WARN storm never broke") end
	Weather.stepStorm(now + WeatherConfig.StormMinutes * 60 + 1)
	local nextAt = RS:GetAttribute("NextStorm")
	if RS:GetAttribute("Storm") ~= nil or not nextAt then weatherOk = false print("WARN storm never cleared or no next storm") end
	if not RS:GetAttribute("StormStarts") or RS:GetAttribute("StormEnds") ~= nil then weatherOk = false print("WARN StormStarts/StormEnds not published between storms") end
	-- Rain makes a needle found out in it wet; clear weather doesn't.
	Weather.set("meadow", "rain")
	local _, wet = Weather.needleOdds(Vector3.new(0, 5, 0))
	Weather.set("meadow", "clear")
	local _, dry = Weather.needleOdds(Vector3.new(0, 5, 0))
	if not wet or dry then weatherOk = false print("WARN wet mutation flag wrong", wet, dry) end
	-- Expected mutation rate: storms add (odds - 1) * minutes / cycle of today's rate.
	local cycle = (WeatherConfig.StormEveryMinutes[1] + WeatherConfig.StormEveryMinutes[2]) / 2 + WeatherConfig.StormWarnSeconds / 60 + WeatherConfig.StormMinutes
	local factor = 1 + (WeatherConfig.StormMutationOdds - 1) * WeatherConfig.StormMinutes / cycle
	print(("storm mutation rate x%.2f of today (cycle %.0f min)"):format(factor, cycle))
	if factor > 2 then weatherOk = false print("WARN storms more than double mutations") end
end
print("weather", weatherOk and "ok" or "WRONG")

-- Region events: each one drops its bales near its region's fields, off the roads, with the Prices boost.
local RegionEvents = require({ __path = "Services.RegionEvents" })
local Prices = require({ __path = "Shared.Config.Prices" })
local WorldShapeE = require({ __path = "Services.WorldShape" })
local eventsOk = true
for _, e in RegionEvents.List do
	local reward = Prices.RegionEvents[e.id]
	local dropped = RegionEvents.run(e.id, 1)
	local n, onRoad = 0, 0
	for b in dropped do
		n += 1
		local d = WorldShapeE.nearestRoad(b.spawnPosition.X, b.spawnPosition.Z)
		if d and d < 6 then onRoad += 1 end
		if b.body:GetAttribute("NeedleBoost") ~= reward.boost then eventsOk = false end
	end
	if n < reward.bales * 0.6 or onRoad > 0 then
		eventsOk = false
		print("WARN event", e.id, "dropped", n, "of", reward.bales, "on road", onRoad)
	end
	print(("event %-14s %2d bales"):format(e.id, n))
end
RegionEvents.finish()
print("events", eventsOk and "ok" or "WRONG")

-- Wilds: the four secrets exist, the crater is hot, the Ghost Road holds only at night.
local Wilds = require({ __path = "Services.Wilds" })
local wildsOk = true
for _, id in { "ember_cache", "captains_lantern", "geode_heart", "lost_kite" } do
	if not Wilds.Secrets[id] or not Prices.Secrets[id] then
		wildsOk = false
		print("WARN secret missing", id)
	end
end
local ember = Wilds.Secrets.ember_cache
if ember and not Wilds.inHeat(ember.part.Position) then
	wildsOk = false
	print("WARN the Ember Cache is outside the crater's heat", ember.part.Position)
end
local quarry = Vector3.new(740, 30, -1300)
if Wilds.inHeat(quarry) then wildsOk = false print("WARN heat reaches the quarry") end
Lighting.ClockTime = 0
Wilds.refreshGhost()
if not Wilds.ghostSolid() then wildsOk = false print("WARN the Ghost Road is not solid at midnight") end
local hiddenCount = 0
for rid, h in Wilds.Hidden do
	hiddenCount += 1
	local d = (Vector2.new(h.spot.X, h.spot.Z) - h.sign).Magnitude
	if d < 40 or d > 220 then wildsOk = false print("WARN hidden spot too near or far from its sign", rid, d) end
end
for _, r in Map.Regions do
	if not Wilds.Hidden[r.id] then wildsOk = false print("WARN no hidden spot in", r.id) end
end
print("hidden spots", hiddenCount)
print("wilds", wildsOk and "ok" or "WRONG")

-- Discoveries: every landmark is found standing on it, every region standing in its middle, and nothing in Meadow.
local Discoveries = require({ __path = "Services.Discoveries" })
local discOk = true
local function finds(position, id)
	for _, got in Discoveries.at(position) do
		if got == id then return true end
	end
	return false
end
for _, entry in Discoveries.all() do
	local p
	if entry.kind == "landmark" then
		p = Vector3.new(entry.at.X, 20, entry.at.Y)
	else
		for _, r in Map.Regions do
			if r.id == entry.id then p = Vector3.new(r.center.X, WorldShapeE.heightAt(r.center.X, r.center.Y) + 3, r.center.Y) end
		end
	end
	if p and not finds(p, entry.id) then
		discOk = false
		print("WARN discovery not found where it stands", entry.id)
	end
end
if #Discoveries.at(Vector3.new(0, 5, 0)) > 0 then discOk = false print("WARN Meadow counts as a discovery") end
print("discoveries", #Discoveries.all(), discOk and "ok" or "WRONG")

-- The Spindle door: twelve numbered sockets, one door, and the shard order from the quest collection.
local SpindleDoor = require({ __path = "Services.SpindleDoor" })
local CS = game:GetService("CollectionService")
local slots = {}
for _, socket in CS:GetTagged("ShardSocket") do
	slots[socket:GetAttribute("Slot") or 0] = true
end
local spindleOk = #CS:GetTagged("SpindleDoor") == 1 and #SpindleDoor.shards >= 6
for i = 1, 12 do
	if not slots[i] then spindleOk = false print("WARN Spindle socket missing", i) end
end
print("spindle door", #SpindleDoor.shards, "shards known", spindleOk and "ok" or "WRONG")
if not spindleOk then print("WARN spindle door") end

-- Road polish: bridges found, and no rail, trestle or board stands inside a 16-stud lane (a truck and trailer fit).
local RoadPolish = require({ __path = "Services.RoadPolish" })
local polishOk = #RoadPolish.bridges > 0
local inLane = 0
local function walk(o)
	for _, c in o:GetChildren() do
		if c.ClassName == "Part" then
			local d = WorldShapeE.nearestRoad(c.Position.X, c.Position.Z)
			local reach = math.max(c.Size.X, c.Size.Z) / 2
			if c.Name ~= "Rail" and d and d - math.min(reach, 0.5) < Map.RoadWidth / 2 then
				inLane += 1
				if inLane <= 5 then print("WARN road polish part in a lane", c.Name, c.Position, d) end
			end
		end
		walk(c)
	end
end
for _, d in workspace:GetDescendants() do
	if d.Name == "RoadPolish" then walk(d) end
end
print("road polish", #RoadPolish.bridges, "bridge sides", inLane == 0 and polishOk and "ok" or "WRONG")

-- Ferry deck life: each ferry (not the zeppelin) has its snack stand, bounty board and fishing spot.
local deckLifeOk, decks = true, 0
for _, d in workspace:GetDescendants() do
	if d.Name == "Promenade" then
		decks += 1
		local m = d.Parent
		for _, need in { "SnackSign", "FerryBountyBoard", "FishingSpot" } do
			local p = m:FindFirstChild(need)
			if not p or not p:FindFirstChildOfClass("ProximityPrompt") then
				deckLifeOk = false
				print("WARN ferry deck missing", need, m.Name)
			end
		end
	end
end
if decks ~= #Map.Ferry.Routes then deckLifeOk = false print("WARN ferry decks with a promenade", decks) end
print("ferry deck life", decks, deckLifeOk and "ok" or "WRONG")

-- The hay wagon: a dry route at road height, no hops, and the loop comes round in a sensible time.
local HayWagon = require({ __path = "Services.HayWagon" })
local wagonOk = #HayWagon.legs == 4 and HayWagon.model ~= nil and #HayWagon.seats == 6
local wet, hop = 0, 0
for _, leg in HayWagon.legs do
	for i, p in leg.samples do
		local h, water = WorldShapeE.column(p.X, p.Z)
		if water and water > p.Y + 0.5 and not WorldShapeE.inMeadow(p.X, p.Z) then wet += 1 end
		local nextP = leg.samples[i + 1]
		if nextP and math.abs(nextP.Y - p.Y) > 1.5 then hop += 1 end
	end
end
if wet > 0 or hop > 0 then wagonOk = false print("WARN hay wagon route: wet samples", wet, "hops", hop) end
local seconds, startLeg = 0, HayWagon.state.leg
local lapped = false
for _ = 1, 20000 do
	HayWagon.step(0.25)
	seconds += 0.25
	if HayWagon.state.leg == startLeg and seconds > 60 and HayWagon.state.wait > 0 then lapped = true break end
end
if not lapped then wagonOk = false print("WARN hay wagon never finished its loop") end
print(("hay wagon loop %.1f min, %s"):format(seconds / 60, wagonOk and "ok" or "WRONG"))

-- Part budget: the whole map's share of the 40,000-part Workspace budget (Main.server.luau) is 12,000.
local mapParts = 0
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then mapParts += 1 end
end
print("map parts", mapParts, mapParts <= 12000 and "within 12000" or "WARN over the map's 12000 share")

-- Reachability (backlog Map #16): can a Rusty Pickup towing a Medium Trailer get everywhere from spawn?
-- Runs after check.luau has built the map. Prints REACH lines; a WARN for anything out of reach, a road too narrow
-- or too steep, or a field / secret / landmark underwater or inside rock.
local RMap = require({ __path = "Shared.Config.WorldMap" })
local RShape = require({ __path = "Services.WorldShape" })
local RRegions = require({ __path = "Services.Regions" })
local RWilds = require({ __path = "Services.Wilds" })

local COMBO_WIDTH = 10.9 -- the widest part of the pickup (its bed); the medium trailer is narrower
local COMBO_MARGIN = 2 -- studs to spare on a lane
local OFFROAD_SLOPE = 0.45 -- rise per stud a pickup with a trailer can still pull up off-road
local OFFROAD_REACH = 70 -- a field this far from its road is too far to back a trailer to
local WALK = 260 -- a landmark may be a short walk or climb from where the truck parks

local problems = 0
local function warn(...)
	problems += 1
	print("WARN reach", ...)
end

-- Nodes: "meadow", "highway", "sky", "road:<i>", "flat:<name>". Edges where they touch.
local edges = {}
local function link(a, b)
	edges[a] = edges[a] or {}
	edges[b] = edges[b] or {}
	edges[a][b] = true
	edges[b][a] = true
end
local function touches(p, i)
	-- Which nodes does this point (a road end) sit on?
	local hit = {}
	if RShape.meadowDistance(p.X, p.Y) < 4 or RShape.inMeadow(p.X, p.Y) then
		table.insert(hit, "meadow")
	end
	if RShape.highwayDistance(p.X, p.Y) < RMap.Highway.width then
		table.insert(hit, "highway")
	end
	for _, zone in RMap.Flat do
		if RShape.rectDistance(p.X, p.Y, zone.min, zone.max) <= 2 then
			table.insert(hit, "flat:" .. zone.name)
		end
	end
	for j, road in RMap.Roads do
		if j ~= i then
			for k = 1, #road.points - 1 do
				local a, b = road.points[k], road.points[k + 1]
				if RShape.segment(p.X, p.Y, a.X, a.Y, b.X, b.Y) < 4 then
					table.insert(hit, "road:" .. j)
					break
				end
			end
		end
	end
	return hit
end
for i, road in RMap.Roads do
	-- A road links to whatever any of its points touch (ends usually, but a flat it runs through counts too).
	for _, p in road.points do
		for _, node in touches(p, i) do
			link("road:" .. i, node)
		end
	end
end
-- Ferries join the flat zones (ports) their piers stand in; the zeppelin joins its field to Sky Island.
local function flatAt(p)
	local best, bestD = nil, math.huge
	for _, zone in RMap.Flat do
		local d = RShape.rectDistance(p.X, p.Y, zone.min, zone.max)
		if d < bestD then
			best, bestD = zone, d
		end
	end
	return best and bestD < 30 and "flat:" .. best.name or nil
end
for _, route in RMap.Ferry.Routes do
	local a, b = flatAt(route.a.shore), flatAt(route.b.shore)
	if not a or not b then
		warn("ferry has no port flat at a pier", route.name, a, b)
	else
		link(a, b)
	end
end
local zf = flatAt(Vector2.new(RMap.Zeppelin.a.pos.X, RMap.Zeppelin.a.pos.Z))
if zf then
	link(zf, "sky")
else
	warn("zeppelin field is not a flat zone")
end

-- Everything reachable from spawn (Meadow).
local reached = { meadow = true }
local queue = { "meadow" }
while #queue > 0 do
	local node = table.remove(queue, 1)
	for other in edges[node] or {} do
		if not reached[other] then
			reached[other] = true
			table.insert(queue, other)
		end
	end
end
local roadsReached = 0
for i, road in RMap.Roads do
	if reached["road:" .. i] then
		roadsReached += 1
	else
		warn("road not reachable from Meadow", road.name)
	end
end
if not reached.highway then
	warn("the Longstitch Highway is not reachable")
end
if not reached.sky then
	warn("Sky Island is not reachable")
end

-- Lanes wide enough, and grades a loaded pickup and trailer can climb.
if RMap.RoadWidth < COMBO_WIDTH + COMBO_MARGIN then
	warn("roads too narrow", RMap.RoadWidth)
end
if RMap.Highway.width < COMBO_WIDTH + COMBO_MARGIN then
	warn("highway too narrow", RMap.Highway.width)
end
if RMap.Ferry.Width / 3 < COMBO_WIDTH + COMBO_MARGIN then
	warn("ferry lanes too narrow", RMap.Ferry.Width / 3)
end
local steepest, steepAt = 0, nil
for _, road in RMap.Roads do
	for k = 1, #road.points - 1 do
		local a, b = road.points[k], road.points[k + 1]
		local steps = math.floor((b - a).Magnitude / 8)
		local last = nil
		for s = 0, steps do
			local p = a:Lerp(b, s / math.max(steps, 1))
			if not RShape.inMeadow(p.X, p.Y) then
				local _, h = RShape.nearestRoad(p.X, p.Y)
				if h and last then
					local grade = math.abs(h - last.h) / math.max(0.1, (p - last.p).Magnitude)
					if grade > steepest then
						steepest, steepAt = grade, ("%s at (%d, %d)"):format(road.name, p.X, p.Y)
					end
				end
				last = h and { h = h, p = p } or nil
			else
				last = nil
			end
		end
	end
end
if steepest > RMap.MaxGrade + 0.06 then
	warn(("steepest road %.2f at %s"):format(steepest, steepAt))
end

-- Nearest point on any reachable road to (x, z), with that road's index.
local function nearestReachedRoad(x, z)
	local best, bestP, bestI = math.huge, nil, nil
	for i, road in RMap.Roads do
		if reached["road:" .. i] then
			for k = 1, #road.points - 1 do
				local a, b = road.points[k], road.points[k + 1]
				local d, t = RShape.segment(x, z, a.X, a.Y, b.X, b.Y)
				if d < best then
					best, bestP, bestI = d, a:Lerp(b, t), i
				end
			end
		end
	end
	return best, bestP, bestI
end

-- Off-road from the road to a point: dry, and never steeper than the pickup can pull.
local function driveTo(target)
	local d, from = nearestReachedRoad(target.X, target.Y)
	if not from then
		return false, "no road"
	end
	if d > OFFROAD_REACH then
		return false, ("%.0f studs from a road"):format(d)
	end
	local steps = math.max(1, math.floor(d / 4))
	local lastH = nil
	for s = 0, steps do
		local p = from:Lerp(target, s / steps)
		local h, water = RShape.column(p.X, p.Y)
		if water and water > h + 1.5 then
			return false, ("water %.1f deep at (%d, %d)"):format(water - h, p.X, p.Y)
		end
		if lastH and math.abs(h - lastH) / (d / steps) > OFFROAD_SLOPE then
			return false, ("slope %.2f at (%d, %d)"):format(math.abs(h - lastH) / (d / steps), p.X, p.Y)
		end
		lastH = h
	end
	return true
end

local perRegion = {}
for _, entry in RRegions.fields do
	perRegion[entry.region] = (perRegion[entry.region] or 0) + 1
end
for _, r in RMap.Regions do
	if not perRegion[r.name] and r.id ~= "spindle" then -- the Spindle's hay is the Crystal Cave's
		warn("region has no hay field", r.name)
	end
end

-- Hay fields: drive up to every one (the cave field from the cave mouth, Sky Island's by zeppelin).
local fieldsOk, fieldsBad = 0, 0
for _, entry in RRegions.fields do
	local c = entry.center
	if entry.region == "Sky Island" then
		if reached.sky then fieldsOk += 1 else fieldsBad += 1 warn("Sky Island field unreachable") end
	elseif entry.region == "Crystal Cave" then
		local ok, why = driveTo(Vector2.new(RMap.Cave.mouth.X, RMap.Cave.mouth.Z))
		if ok then fieldsOk += 1 else fieldsBad += 1 warn("cave mouth", why) end
	else
		local h, water = RShape.column(c.X, c.Z)
		if water and water > h + 0.5 then
			fieldsBad += 1
			warn("field underwater", entry.region, c)
		elseif c.Y < h - 2 then
			fieldsBad += 1
			warn("field inside the ground", entry.region, c, h)
		else
			local ok, why = driveTo(Vector2.new(c.X, c.Z))
			if ok then fieldsOk += 1 else fieldsBad += 1 warn("field", entry.region, ("(%d, %d)"):format(c.X, c.Z), why) end
		end
	end
end

-- Landmark discoveries a truck can reach (the Graveyard of Ships is seen from the ferry, Ghost Isle is the night
-- road's end, the crater rim is a climb on foot).
local ON_FOOT = { graveyard_of_ships = true, ghost_isle = true, crater_rim = true, spindle_door = false }
local landmarksOk = 0
for _, d in RMap.Discoveries do
	local at = d.at
	if d.flat then
		for _, zone in RMap.Flat do
			if zone.name == d.flat then at = (zone.min + zone.max) / 2 end
		end
	end
	if at and not ON_FOOT[d.id] then
		local _, water = RShape.column(at.X, at.Y)
		local dist = nearestReachedRoad(at.X, at.Y)
		if water and d.id ~= "mirror_lake" then
			warn("landmark underwater", d.id)
		elseif dist > d.radius + WALK then
			warn("landmark far from a road", d.id, ("%.0f"):format(dist))
		else
			landmarksOk += 1
		end
	end
end

-- Quest markers out on the isles (Config/Quests Spots with a world position): a walk from a reachable road, and dry.
local QuestConfig = require({ __path = "Shared.Config.Quests" })
local CLIMBS = { volcano_crater = true, snow_door = true } -- meant to be climbs: up the crater, up the ridge
local questOk, questWet = 0, {}
for id, spot in QuestConfig.Spots do
	local at = spot.world
	if typeof(at) == "Vector2" then
		local h, water = RShape.column(at.X, at.Y)
		local dist = nearestReachedRoad(at.X, at.Y)
		if dist > WALK and not CLIMBS[id] then
			warn("quest marker far from a road", id, ("%.0f"):format(dist))
		elseif water and water > h + 1.5 then
			table.insert(questWet, id) -- may be meant (wrecks); listed, not failed
			questOk += 1
		else
			questOk += 1
		end
	end
end
print("REACH quest markers", questOk, #questWet > 0 and ("in water (by design?): " .. table.concat(questWet, ", ")) or "all dry")

-- Turns: no road bends harder than a pickup and trailer can follow at a junction-like corner.
for _, road in RMap.Roads do
	for k = 2, #road.points - 1 do
		local a = (road.points[k] - road.points[k - 1]).Unit
		local b = (road.points[k + 1] - road.points[k]).Unit
		local bend = math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
		if bend > 100 then
			warn(("%s bends %d degrees at (%d, %d)"):format(road.name, bend, road.points[k].X, road.points[k].Y))
		end
	end
end

-- Secrets above water and out of the rock (the cave's and the sky's are in places of their own).
for id, s in RWilds.Secrets do
	if id ~= "geode_heart" and id ~= "lost_kite" and id ~= "captains_lantern" then
		local p = s.part.Position
		local h, water = RShape.column(p.X, p.Z)
		if water and water > p.Y then
			warn("secret underwater", id)
		elseif p.Y < h - 1 then
			warn("secret inside the rock", id, p.Y, h)
		end
	end
end

print(("REACH roads %d/%d, highway %s, sky %s, fields %d ok %d bad, landmarks %d, steepest road %.3f; %s"):format(
	roadsReached, #RMap.Roads, tostring(reached.highway), tostring(reached.sky), fieldsOk, fieldsBad, landmarksOk, steepest,
	problems == 0 and "ok" or (problems .. " problems")))

-- Signpost distances (#23): every junction sign's places are reachable by road, and each distance is at least the
-- straight line and not an absurd detour.
do
	local RegionsS = require({ __path = "Services.Regions" })
	local signsOk, count = true, 0
	for _, j in RegionsS.junctions do
		local text, numbers = RegionsS.junctionText(j)
		for _, n in numbers do
			count += 1
			local RoadGraphS = require({ __path = "Services.RoadGraph" })
			local snapped = RoadGraphS.nodes()[RoadGraphS.nearest(n.target)]
			local straight = (Vector2.new(snapped.x, snapped.z) - Vector2.new(j[1], j[2])).Magnitude
			if n.distance + 30 < straight or n.distance > straight * 3 + 300 then
				signsOk = false
				print("WARN signpost distance looks wrong", n.name, n.distance, "straight", math.floor(straight))
			end
		end
		print("SIGN", (text:gsub("\n", " | ")))
	end
	print(("signpost distances %d %s"):format(count, signsOk and "ok" or "WRONG"))
end

-- First-visit pans (#24): every region but the cave has a focus on dry ground or the sky platform.
do
	local Disc = require({ __path = "Services.Discoveries" })
	local MapC = require({ __path = "Shared.Config.WorldMap" })
	local ok, n = true, 0
	for _, entry in Disc.all() do
		if entry.kind == "region" then
			local focus = Disc.focus(entry.id)
			if entry.id == "cave" then
				if focus then ok = false print("WARN the cave should have no pan") end
			elseif not focus then
				ok = false
				print("WARN no first-visit pan focus for", entry.id)
			else
				n += 1
				if focus.Y < MapC.SeaLevel then ok = false print("WARN pan focus under the sea", entry.id) end
			end
		end
	end
	print(("region intro pans %d %s"):format(n, ok and "ok" or "WRONG"))
end

-- Part and streaming budget (#21): every container's parts against its slice of Config/WorldMap PartBudget, and the
-- streaming modes: regions are plain Models, Atomic only on small models, Persistent only where it must be.
do
	local Map = require({ __path = "Shared.Config.WorldMap" })
	local root = workspace:FindFirstChild("Needlewood"):FindFirstChild("StitchedIsles")
	local isles = root:FindFirstChild("Isles")
	local function parts(inst)
		local n = 0
		for _, d in inst:GetDescendants() do
			if d:IsA("BasePart") then n += 1 end
		end
		return n
	end
	local rows = {}
	local over, sum = 0, 0
	local function row(name, n, kind)
		local cap = Map.PartBudget[name]
		local status = "ok"
		if not cap then
			status = "WARN no budget"
			over += 1
		elseif n > cap then
			status = "WARN over"
			over += 1
		end
		table.insert(rows, { name = name, n = n, cap = cap, status = status, kind = kind })
	end
	for _, child in root:GetChildren() do
		if child.Name == "Isles" then
			for _, sub in child:GetChildren() do
				row(sub.Name, parts(sub), sub.ClassName)
				if sub.ClassName ~= "Model" then
					print("WARN region container is a " .. sub.ClassName .. ", not a Model:", sub.Name)
				end
			end
		elseif child.Name ~= "WorldEdge" then
			row(child.Name, parts(child), child.ClassName)
		end
	end
	row("Field bales", BALES, "bales")
	local total = 0
	for _, r in rows do total += r.n end
	for _, cap in Map.PartBudget do sum += cap end
	print(("%-22s %6s %6s %5s"):format("BUDGET container", "parts", "slice", "use"))
	for _, r in rows do
		print(("%-22s %6d %6s %4s%%  %s"):format(r.name, r.n, tostring(r.cap or "-"), r.cap and tostring(math.floor(r.n / r.cap * 100)) or "-", r.status))
	end
	print(("budget total %d of slices %d (share %d)"):format(total, sum, Map.PartShare))
	if sum > Map.PartShare then
		print("WARN the slices add up to more than the map's share", sum, Map.PartShare)
	end

	-- Streaming: no region-sized container is Atomic or Persistent; Atomic models stay small (they stream in whole);
	-- Persistent only on the few things every client must always have.
	local PERSISTENT_OK = { RichFieldBeacon = true, ["THE SPINDLE"] = true, ["SNOW PEAK"] = true, ["BOBBIN ROCK"] = true }
	local ATOMIC_MAX = 400
	local atomic, persistent, persistentParts, streamBad = 0, 0, 0, 0
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" then
			local mode = tostring(d.ModelStreamingMode or "")
			if mode:find("Atomic") then
				atomic += 1
				local n = parts(d)
				if n > ATOMIC_MAX then
					streamBad += 1
					print("WARN atomic model too big to stream in whole", d:GetFullName(), n)
				end
			elseif mode:find("Persistent") then
				persistent += 1
				persistentParts += parts(d)
				if not PERSISTENT_OK[d.Name] then
					streamBad += 1
					print("WARN persistent model not on the list", d:GetFullName())
				end
			end
			if d.Parent == isles and mode ~= "" and not mode:find("Default") then
				streamBad += 1
				print("WARN region container streams as", mode, d.Name)
			end
		end
	end
	print(("streaming atomic %d, persistent %d (%d parts), problems %d"):format(atomic, persistent, persistentParts, streamBad))

	-- The table for Health, as markdown.
	local md = { "| Container | Parts | Slice | Use |", "|---|---:|---:|---:|" }
	for _, r in rows do
		table.insert(md, ("| %s | %d | %s | %s |"):format(r.name, r.n, tostring(r.cap or "-"), r.cap and (math.floor(r.n / r.cap * 100) .. "%") or "-"))
	end
	table.insert(md, ("| **Total** | **%d** | **%d** | share %d |"):format(total, sum, Map.PartShare))
	BUDGET_TABLE = table.concat(md, "\n")
	print("BUDGET_TABLE_BEGIN")
	print(BUDGET_TABLE)
	print("BUDGET_TABLE_END")
end

-- Spawn and fall safety (#22): every spawn, ferry and zeppelin landing, tow spot and hay wagon stop stands on ground
-- with headroom, the kill floor is below every bit of ground, and the fall catch lands anywhere on the map on a dry
-- road with headroom.
do
	local Map = require({ __path = "Shared.Config.WorldMap" })
	local Meadow = require({ __path = "Shared.Config.Meadow" })
	local Shape = require({ __path = "Services.WorldShape" })
	local Ferry = require({ __path = "Services.Ferry" })
	local HayWagon = require({ __path = "Services.HayWagon" })
	local FallSafety = require({ __path = "Services.FallSafety" })
	local root = workspace:FindFirstChild("Needlewood")

	local solids = {}
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") and p.Anchored and p.CanCollide and p.Transparency < 1 then
			table.insert(solids, p)
		end
	end
	local function inside(p, at, pad)
		local o = p.CFrame:PointToObjectSpace(at)
		local s = p.Size
		return math.abs(o.X) <= s.X / 2 + pad and math.abs(o.Y) <= s.Y / 2 + pad and math.abs(o.Z) <= s.Z / 2 + pad
	end
	-- Feet at `at`: something to stand on within 3 studs below, nothing solid from knee to above the head.
	local function check(label, at)
		local ground = Shape.heightAt(at.X, at.Z)
		local standing = math.abs(ground - at.Y) <= 3
		local blocker = nil
		for _, p in solids do
			if not standing and (inside(p, at - Vector3.new(0, 0.4, 0), 0) or inside(p, at - Vector3.new(0, 2.5, 0), 0)) then
				standing = true
			end
			if not blocker then
				for _, o in { Vector3.new(0, 1.5, 0), Vector3.new(0, 4, 0), Vector3.new(0, 6.5, 0), Vector3.new(2, 3, 2), Vector3.new(-2, 3, -2), Vector3.new(2, 3, -2), Vector3.new(-2, 3, 2) } do
					if inside(p, at + o, -0.05) then
						blocker = p
						break
					end
				end
			end
		end
		local dry = at.Y > Map.SeaLevel + 0.5
		local ok = standing and not blocker and dry
		if not ok then
			print(("WARN unsafe %s at %d,%d,%d: %s"):format(label, at.X, at.Y, at.Z,
				not dry and "under the sea" or not standing and ("nothing to stand on (ground %d)"):format(ground) or ("blocked by " .. blocker:GetFullName())))
		end
		return ok
	end

	local points, bad = 0, 0
	local function add(label, at)
		points += 1
		if not check(label, at) then bad += 1 end
	end
	add("base camp spawn", Vector3.new(0, 1, 14))
	add("tow spot", Meadow.TowSpot + Vector3.new(0, Shape.heightAt(Meadow.TowSpot.X, Meadow.TowSpot.Z), 0))
	for _, shuttle in Ferry.all() do
		for _, stop in shuttle.stops or {} do
			local land = stop.edge + stop.inland * 20
			add(("%s landing at %s"):format(shuttle.def and shuttle.def.name or "ferry", stop.name), land)
		end
	end
	for _, leg in HayWagon.legs do
		local s = leg.samples[#leg.samples]
		add("hay wagon stop " .. leg.stop, Vector3.new(s.X, Shape.heightAt(s.X, s.Z), s.Z))
	end

	-- The kill floor sits below all ground (sampled every 64 studs).
	local lowest = math.huge
	for x = Map.Bounds.min.X, Map.Bounds.max.X, 64 do
		for z = Map.Bounds.min.Y, Map.Bounds.max.Y, 64 do
			lowest = math.min(lowest, Shape.heightAt(x, z))
		end
	end
	if lowest - 10 < FallSafety.KILL_Y then
		print("WARN the kill floor is not far enough below the lowest ground", FallSafety.KILL_Y, lowest)
		bad += 1
	end

	-- Falls anywhere (every 192 studs) land on a dry road with headroom; spot-check each landing once.
	local landings, seen = 0, {}
	for x = Map.Bounds.min.X, Map.Bounds.max.X, 192 do
		for z = Map.Bounds.min.Y, Map.Bounds.max.Y, 192 do
			local ground, name = FallSafety.target(Vector3.new(x, FallSafety.KILL_Y - 5, z))
			local key = math.floor(ground.Position.X) .. "," .. math.floor(ground.Position.Z)
			if not seen[key] then
				seen[key] = true
				landings += 1
				if not check("fall landing on " .. tostring(name), ground.Position) then bad += 1 end
			end
		end
	end
	print(("safety spawns %d, fall landings %d, lowest ground %.0f, kill floor %d, %s"):format(points, landings, lowest, FallSafety.KILL_Y, bad == 0 and "ok" or ("WARN " .. bad .. " unsafe")))
end

-- Night lights (#26): road lanterns, door lanterns and shop glows all follow the clock (WorldClock's naming rule),
-- no lantern post stands in a lane, every long road has lanterns, and the Spindle door carries its shard glow.
do
	local Map = require({ __path = "Shared.Config.WorldMap" })
	local Shape = require({ __path = "Services.WorldShape" })
	local SpindleDoorL = require({ __path = "Services.SpindleDoor" })
	local CS = game:GetService("CollectionService")
	local root = workspace:FindFirstChild("Needlewood")
	local ok, lamps, doors = true, 0, 0
	for _, d in root:GetDescendants() do
		if d.Name == "RoadLantern" or d.Name == "DoorLantern" or d.Name == "LampGlow" then
			lamps += 1
			if d.Name == "DoorLantern" then doors += 1 end
			if not d:FindFirstChildOfClass("PointLight") then ok = false print("WARN lamp with no light", d:GetFullName()) end
			if CS:HasTag(d, "AlwaysLit") then ok = false print("WARN night lamp tagged AlwaysLit", d:GetFullName()) end
		elseif d.Name == "LanternPost" then
			local dist = Shape.nearestRoad(d.Position.X, d.Position.Z)
			if dist and dist < Map.RoadWidth / 2 + 0.5 then ok = false print("WARN lantern post in a lane", math.floor(d.Position.X), math.floor(d.Position.Z)) end
		end
	end
	-- Long roads get lanterns.
	local RoadPolishL = require({ __path = "Services.RoadPolish" })
	for _, road in Map.Roads do
		local length = 0
		for i = 1, #road.points - 1 do length += (road.points[i + 1] - road.points[i]).Magnitude end
		local n = 0
		for _, at in RoadPolishL.lanterns do
			local d = Shape.nearestRoad(at.X, at.Z)
			for i = 1, #road.points - 1 do
				local a, b = road.points[i], road.points[i + 1]
				if Shape.segment(at.X, at.Z, a.X, a.Y, b.X, b.Y) < Map.RoadWidth / 2 + 4 then n += 1 break end
			end
		end
		if length >= 400 and n == 0 then ok = false print("WARN no lanterns on", road.name, math.floor(length)) end
	end
	SpindleDoorL.refresh()
	local glowOk = false
	for _, door in CS:GetTagged("SpindleDoor") do
		local glow = door:FindFirstChild("SpindleGlow")
		glowOk = glow ~= nil and CS:HasTag(glow, "AlwaysLit") and glow.Enabled == false
	end
	if not glowOk then ok = false print("WARN Spindle glow missing or lit with no shards") end
	print(("night lights %d lamps (%d road, %d door), %s"):format(lamps, #RoadPolishL.lanterns, doors, ok and "ok" or "WRONG"))
end

-- Weekly festival (H11): the rotation is fixed by the week number, visits every region in turn, every festival region
-- has a field to boost, and refresh boosts that week's bales, decorates, and publishes the countdown attributes.
do
	local Map = require({ __path = "Shared.Config.WorldMap" })
	local Fest = require({ __path = "Services.Festival" })
	local RegionsF = require({ __path = "Services.Regions" })
	local RS = game:GetService("ReplicatedStorage")
	local ok = true
	local ids, seen = {}, {}
	for _, r in Map.Regions do ids[r.id] = r.name end
	for _, id in Map.FestivalOrder do
		if not ids[id] then ok = false print("WARN festival region unknown", id) end
		if seen[id] then ok = false print("WARN festival region twice", id) end
		seen[id] = true
		local has = false
		for _, f in RegionsF.fields do if f.region == ids[id] then has = true end end
		if not has then ok = false print("WARN festival region has no field", id) end
	end
	for id in ids do if not seen[id] then print("note: region never hosts a festival", id) end end
	-- Deterministic: the same time gives the same festival; a week later, the next region.
	local t = Map.FestivalEpoch + 10 * Map.FestivalWeek + 3600
	local a, b = Fest.at(t), Fest.at(t)
	local nextWeek = Fest.at(t + Map.FestivalWeek)
	if a.region ~= b.region or a.week ~= 10 or nextWeek.region == a.region or a.ends ~= Map.FestivalEpoch + 11 * Map.FestivalWeek then
		ok = false print("WARN festival rotation not deterministic", a.region, nextWeek.region, a.week)
	end
	local fest = Fest.refresh(t)
	if RS:GetAttribute("FestivalRegion") ~= fest.region or RS:GetAttribute("FestivalEnds") ~= fest.ends then ok = false print("WARN festival attributes missing") end
	local boosted, other = 0, 0
	for _, f in RegionsF.fields do
		for bale in f.bales do
			local boost = bale.body:GetAttribute("NeedleBoost") or 1
			if f.region == fest.name and boost >= Map.FestivalBoost then boosted += 1 end
			if f.region ~= fest.name and bale.body:GetAttribute("FestivalBoost") then other += 1 end
		end
	end
	if boosted == 0 or other > 0 then ok = false print("WARN festival boost wrong", boosted, other) end
	-- The next week moves the boost and the bunting.
	local fest2 = Fest.refresh(t + Map.FestivalWeek)
	local stale = 0
	for _, f in RegionsF.fields do
		for bale in f.bales do
			if f.region == fest.name and bale.body:GetAttribute("FestivalBoost") then stale += 1 end
		end
	end
	if stale > 0 then ok = false print("WARN last week's festival bales kept their boost", stale) end
	local flags = 0
	for _, d in workspace:GetDescendants() do if d.Name == "FestivalFlag" then flags += 1 end end
	if flags == 0 then ok = false print("WARN no festival bunting") end
	print(("festival %s then %s, %d bales boosted, %d flags, %s"):format(fest.region, fest2.region, boosted, flags, ok and "ok" or "WRONG"))
end
