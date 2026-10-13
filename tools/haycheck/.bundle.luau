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

MODULES["Shared.Config.Game"] = function(script)
-- Tunable numbers for the first slice. All placeholders to adjust from playtests.
local Prices = require(script.Parent.Prices)
return {
	CarryCapacity = 60, -- hay a player can hold in their arms and pockets at once
	NeedleChancePerHay = Prices.needleChance("meadow"), -- Meadow bales hide 2 needles on average (Config/Prices)
	AutosaveSeconds = 60,

	-- TESTING: every player has endless cash, so shops can be tried without grinding. Real balances are kept and
	-- saved as normal underneath. Studio only, so a live server never hands out free money (refunds of free buys
	-- would otherwise mint real cash). Set it to true or false outright to change that (ECONOMY.md, "Test money").
	InfiniteMoney = game:GetService("RunService"):IsStudio(),

	-- Hay pieces: a bale breaks into loose pieces, tools move them
	HayPerPiece = 1,
	-- Per spill wave (3 per bale): a needle you can see and pick up. A quarter of a bale's hidden needles on average.
	VisibleNeedleChance = Prices.NeedlesPerBale.meadow * Prices.VisibleNeedleShare / 3,
	PiecesPerBale = 90, -- small straw strands spilled by one bale
	-- A burst bale spills its strands in clumps of this many (one part each, worth every strand in it), so a crew
	-- breaking ten bales at once makes 300 parts, not 900, and the loose cap no longer eats hay. 1 = single strands.
	StrandsPerClump = 3,
	MaxHayPiles = 30, -- raked piles past this lose their oldest, so piles can't pile up without end
	MaxLoosePieces = 450, -- the oldest pieces vanish past this, so the server never fills with hay
	LooseHayLifetime = 90, -- seconds before untouched hay shrinks away
	LooseNeedleLifetime = 600, -- a spilled needle or a raked pile nobody picks up stays this long
	MaxLooseNeedles = 120, -- past this many lying around, the oldest needle goes
	BaleRefillSeconds = 45, -- placeholder until we decide how bales refill

	-- Tools
	ShovelReach = 9, -- with no click aim, a bale this close and in front of you gets smashed
	ToolReach = 18, -- how far from you a click can be for a tool to act on it
	PickupReach = 10, -- how close the Pick up button shows
	ShovelPieces = 12, -- strands per scoop
	ShovelRadius = 3, -- pieces this close to the clicked spot get scooped, nearest first
	ScoopCooldownSeconds = 0.85,
	-- Scoop combo: scoops landing within ComboWindowSeconds of each other chain. From ComboStart scoops on, each
	-- scoop takes ComboBonusPieces more strands per link past the start, up to ComboMaxBonus.
	-- Wheelbarrow: how many bales it holds, and the share of their weight you feel while pushing it.
	WheelbarrowBales = 3,
	WheelbarrowLoadFactor = 0.3,
	ComboWindowSeconds = 1.6,
	ComboStart = 3,
	ComboBonusPieces = 2,
	ComboMaxBonus = 10,
	RakeRadius = 6, -- strands this close to the click get gathered
	RakeGatherDistance = 2.5, -- the rake pulls hay to this far in front of you
	-- Hay piles: raking at least PileMin strands together into one spot packs them into a single pile the shovel
	-- takes in one scoop (it ignores the per-scoop size; only your carry room limits it).
	PileMin = 40,
	-- Fields grow hay as loose piles, never bales (Hay.spawnFieldPile): one pile holds a bale's worth of strands, the
	-- shovel scoops from it and each rake stroke pulls this many strands off it. A cleared pile grows back after
	-- BaleRefillSeconds.
	FieldPileStrands = 90,
	RakeFieldStrands = 9,
	PileRadius = 3,
	RakeBeltReach = 5, -- a rake stroke ending this close to a conveyor belt flicks the hay up onto it
	RakeStrokeSeconds = 0.45, -- how long one stroke keeps pulling
	RakeMaxSpeed = 16,
	RakeCooldownSeconds = 0.75,

	-- Carrying a whole bale
	CarryWalkSpeed = 8,
	StackReach = 9, -- a bale set down lands on top of a stack up to this high in front of you
	-- Hold click (or G) with a bale to charge a throw, then let go to lob it. A plain click still sets it down.
	TossRange = 10, -- studs on flat ground at full charge
	TossMinRange = 3, -- at the least charge that throws at all
	TossMinPower = 0.12, -- charge below this (0..1) just sets the bale down
	TossChargeSeconds = 0.9, -- holding this long is full power
	TossFlightSeconds = 2.5, -- the server flies a thrown bale this long, then Roblox picks its owner again
	-- Wet hay. A bale out under the open sky while its region rains soaks through after WetSoakSeconds: it weighs
	-- WetWeightFactor times as much and its hay sells at WetPriceFactor of the price (needles in it are unharmed)
	-- until it dries, in the open once the rain stops (WetDrySeconds) or at once on a drying rack. Strands spilled
	-- from a wet bale are wet too.
	WetWeather = { rain = true },
	WetSoakSeconds = 20,
	WetDrySeconds = 150,
	WetWeightFactor = 1.5,
	WetPriceFactor = Prices.WetHayShare,
	-- Pouring the hay in your arms (shovel click on a truck bed, hopper, belt or sell pad).
	PourStrands = 40, -- strands per click; click again for more
	PourFlightSeconds = 0.55,
	PourSpread = 1.2, -- studs around the clicked spot
	PourStagger = 0.008, -- seconds between strands, so it streams out
	GoldenBaleOneIn = Prices.GoldenBale.oneIn, -- a field bale grows golden 1 time in this many (Config/Prices)
	GoldenBaleNeedles = Prices.GoldenBale.needles, -- a golden bale spills this many times the needles
	CatchRadius = 4.5, -- a thrown bale this close to a bare-handed farm crew teammate is caught
	CatchWindowSeconds = 1.6, -- how long after the throw a catch can happen
	DoubleCarryTier = 3, -- a shovel of this tier (Reinforced) and up lets you carry two bales, one on top of the other
	StackMin = 3, -- a neat stack of this many bales or more is kept (no despawn) and gets a "Stack N" label
	DroppedBaleSeconds = 180, -- a dropped bale disappears after this long

	-- Scoop animation tuning (degrees of right-arm swing and seconds). Easy to adjust from playtests.
	DigBackDegrees = -35,
	DigForwardDegrees = 30,
	LiftDegrees = 75,
	DigBackSeconds = 0.16,
	DigForwardSeconds = 0.14,
	HayFlightSeconds = 0.4,

	-- Rake animation: reach out, then drag back
	RakeReachDegrees = 85,
	RakeDragDegrees = 20,
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

MODULES["Shared.HayMath"] = function(script)
-- Pure hay math, with no Roblox services, so tools/haycheck can test it headless. Every function takes the config
-- tables it reads (Config/Game as game, Config/Gloves as gloves), so the tests can feed it the real configs or their
-- own. Gloves.luau, Tools.luau, Gameplay.luau and Bales.luau use these.
local HayMath = {}

-- Walk speed wearing glove (a Config/Gloves tier) and carrying weight of hay whose hardest tier is hayTier. The gloves
-- add their carrySpeed and take away relief of the slowdown; each tier the gloves fall short of the hay multiplies
-- the slowdown by (1 + UnderGearedSlow). Never faster than walking empty-handed, never slower than MinWalkSpeed.
function HayMath.speed(glove: any, baseSpeed: number, weight: number, hayTier: number?, gloves: any): number
	if weight <= 0 then
		return baseSpeed
	end
	local short = math.max(0, (hayTier or 0) - glove.tier)
	local slow = weight * gloves.SlowPerWeight * (1 - glove.relief) * (1 + gloves.UnderGearedSlow * short)
	return math.clamp(baseSpeed + (glove.carrySpeed or 0) - slow, gloves.MinWalkSpeed, baseSpeed)
end

-- Weight of one loose strand of hay (a Config/Gloves HayTypes entry); wet hay is heavier.
function HayMath.pieceWeight(hay: any, wet: boolean?, game: any): number
	return hay.weight * game.HayPerPiece * (wet and game.WetWeightFactor or 1)
end

-- Weight of a whole bale of hay: packed tight, so a fraction (BaleWeightFactor) of the strands inside; wet is heavier.
function HayMath.baleWeight(hay: any, wet: boolean?, game: any, gloves: any): number
	return game.PiecesPerBale * game.HayPerPiece * hay.weight * gloves.BaleWeightFactor * (wet and game.WetWeightFactor or 1)
end

-- Strands one shovel scoop picks up of hay at hayTier, before the combo: fewer for each tier the gloves fall short,
-- never fewer than 2.
function HayMath.scoopSize(glove: any, hayTier: number?, game: any, gloves: any): number
	local base = game.ShovelPieces + glove.scoopBonus
	local short = math.max(0, (hayTier or 0) - glove.tier)
	return math.max(2, math.floor(base * (1 - gloves.UnderGearedScoop * short) + 0.5))
end

-- Extra strands the combo adds to the count-th quick scoop in a row (0 until ComboStart, capped at ComboMaxBonus).
function HayMath.comboExtra(count: number, game: any): number
	if count < game.ComboStart then
		return 0
	end
	return math.min((count - game.ComboStart + 1) * game.ComboBonusPieces, game.ComboMaxBonus)
end

-- What rain costs at the sell pad: wet hay sells at wetFactor of hayPrice (needles in it are unharmed).
function HayMath.wetPenalty(wetHay: number, hayPrice: number, wetFactor: number): number
	return math.floor(math.max(wetHay, 0) * hayPrice * (1 - wetFactor))
end

-- How a pour splits the hay in your arms. load = { hay, sorted, needles, wet } (hay amounts in hay units, needles a
-- count). Pours up to maxStrands strands, sorted hay first (it is the kind with no hidden needles left). The hidden
-- needles rolled for the unsorted hay leave with it in proportion, and the wet hay in proportion to the whole, so a
-- pour never makes needles or dries hay. Returns { n, sortedOut, needlesOut, wetOut } (strand counts, and needles).
function HayMath.pourSplit(load: any, maxStrands: number, hayPerPiece: number): any
	local held = math.floor(load.hay / hayPerPiece)
	local n = math.min(held, maxStrands)
	if n <= 0 then
		return { n = 0, sortedOut = 0, needlesOut = 0, wetOut = 0 }
	end
	local sortedHeld = math.min(math.floor((load.sorted or 0) / hayPerPiece), held)
	local sortedOut = math.min(n, sortedHeld)
	local unsortedHeld = held - sortedHeld
	local unsortedOut = n - sortedOut
	local needles = load.needles or 0
	local needlesOut = 0
	if unsortedHeld > 0 then
		needlesOut = if unsortedOut == unsortedHeld then needles else math.min(needles, math.floor(needles * unsortedOut / unsortedHeld + 0.5))
	end
	local wetHeld = math.floor((load.wet or 0) / hayPerPiece)
	local wetOut = if n == held then wetHeld else math.min(n, wetHeld, math.floor(wetHeld * n / held + 0.5))
	return { n = n, sortedOut = sortedOut, needlesOut = needlesOut, wetOut = wetOut }
end

-- Launch speed (up and forward, each) for a 45 degree toss at power 0..1 to land TossMinRange..TossRange studs away
-- on flat ground under gravity.
function HayMath.tossSpeed(power: number, game: any, gravity: number): number
	local range = game.TossMinRange + (game.TossRange - game.TossMinRange) * math.clamp(power, 0, 1)
	return math.sqrt(range * gravity) / math.sqrt(2)
end

-- Splits a bale's strands into clumps of perClump (the last one smaller when it does not divide), so every strand
-- is spilled exactly once.
function HayMath.clumps(strands: number, perClump: number): { number }
	perClump = math.max(1, math.floor(perClump))
	local out = {}
	local left = strands
	while left > 0 do
		local n = math.min(perClump, left)
		table.insert(out, n)
		left -= n
	end
	return out
end

-- What one shovel scoop takes from the pieces in reach, nearest first. pieces: { { strands = n, pile = bool } }.
-- A raked pile goes in whole (as far as room allows) and ignores the scoop size; strands and clumps count against
-- the scoop size (scoop) as well as the room left in your arms (room), and a clump bigger than what is left is
-- split. Returns how many strands to take from each piece (0 = leave it).
function HayMath.scoopPlan(pieces: { any }, room: number, scoop: number): { number }
	local takes = {}
	for i, piece in pieces do
		local n = piece.strands
		local take
		if piece.pile then
			take = math.min(n, room)
		else
			take = math.min(n, room, scoop)
			scoop -= math.max(take, 0)
		end
		take = math.max(take, 0)
		room -= take
		takes[i] = take
	end
	return takes
end

return HayMath

end

MODULES["Shared.ToolGuide"] = function(script)
-- One plain line per hand tool, shovel tier and the wheelbarrow, for the hotbar tooltips, the shovel rack and the
-- shop, built from the configs so the numbers are always the real ones ("Steel Shovel: carries 90 hay a load, ..."). The same
-- pattern as PieceGuide (Conveyor thread) for plot pieces.
--
--   ToolGuide.tool("Shovel" | "Rake" | "Wheelbarrow")
--   ToolGuide.glove(def)          -- def: a Config/Gloves Tiers or QuestTiers entry (a shovel tier)
local Shared = script.Parent
local Game = require(Shared.Config.Game)
local Gloves = require(Shared.Config.Gloves)
local Prices = require(Shared.Config.Prices)
local HayMath = require(Shared.HayMath)

local ToolGuide = {}

local WALK = 16 -- Roblox's default walk speed, what every avatar starts with

local function percent(x: number): string
	return ("%d%%"):format(math.round(x * 100))
end

-- Walk speed carrying one dry meadow bale with this shovel.
local function baleSpeed(def: any): number
	local meadow = Gloves.HayTypes.meadow
	return HayMath.speed(def, WALK, HayMath.baleWeight(meadow, false, Game, Gloves), meadow.tier, Gloves)
end

-- The rarest hays this shovel handles with no extra slowdown, by name ("Desert grass and Frozen hay").
local function rated(def: any): string?
	local bestTier = -1
	for _, hay: any in Gloves.HayTypes do
		if hay.tier <= def.tier and hay.tier > bestTier then
			bestTier = hay.tier
		end
	end
	local names = {}
	for _, hay: any in Gloves.HayTypes do
		if hay.tier == bestTier then
			table.insert(names, hay.name)
		end
	end
	table.sort(names)
	if #names == 0 then
		return nil
	elseif #names == 1 then
		return names[1]
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

function ToolGuide.glove(def: any): string
	local load = Game.CarryCapacity + def.carryBonus
	if def.tier == 0 then
		return ("%s: carries %d hay a load. Walk %.1f with a meadow bale. Better shovels carry more, scoop more and slow you less under a load."):format(
			def.name,
			load,
			baleSpeed(def)
		)
	end
	local parts = {
		("carries %d hay a load (%d more)"):format(load, def.carryBonus),
		("%d more per scoop"):format(def.scoopBonus),
		("%s less slowdown"):format(percent(def.relief)),
	}
	local line = ("%s: %s. Walk %.1f with a meadow bale (Old Shovel %.1f)."):format(
		def.name,
		table.concat(parts, ", "),
		baleSpeed(def),
		baleSpeed(Gloves.Tiers[1])
	)
	local hay = rated(def)
	if hay then
		line ..= (" Rated up to %s."):format(hay)
	end
	if def.tier >= Game.DoubleCarryTier then
		line ..= " Carries two bales at once."
	end
	return line
end

function ToolGuide.tool(kind: string): string
	if kind == "Shovel" then
		return ("Click a hay pile or loose hay to scoop %d strands (more with a better shovel and quick combos). With a load on it, click your parked wheelbarrow to tip it in, or a truck bed, belt or the sell pad to pour %d. Click a bale to smash it."):format(
			Game.ShovelPieces,
			Game.PourStrands
		)
	elseif kind == "Rake" then
		return ("Pulls loose hay within %d studs toward you, and a few strands off a field's pile each stroke. Rake %d or more strands together for a pile the shovel takes in one go. End a stroke at a belt to flick the hay onto it."):format(
			Game.RakeRadius,
			Game.PileMin
		)
	elseif kind == "Wheelbarrow" then
		return ("Put it away to park it, then tip shovel loads in: every %d hay presses a bale. Rolling, it holds %d bales and you feel %s of their weight. Click a bale to load it, or a truck bed to tip the load in."):format(
			Game.PiecesPerBale,
			Game.WheelbarrowBales,
			percent(Game.WheelbarrowLoadFactor)
		)
	end
	return ""
end

-- The wheelbarrow's shop line, with its price.
function ToolGuide.wheelbarrowShop(): string
	return ("Wheelbarrow ($%d): fill it from your shovel and every %d hay presses a bale. Holds %d bales to roll to the truck."):format(
		Prices.Wheelbarrow,
		Game.PiecesPerBale,
		Game.WheelbarrowBales
	)
end

return ToolGuide

end

MODULES["Shared.Config.HayLooks"] = function(script)
-- How each region's hay looks (ids match Config/Gloves HayTypes). colors: the strand palette, the first is the bale's
-- own color. length/thick: strand size in studs. dust: the cloud a burst bale throws up. motes (optional): a few
-- drifting specks of that color in the burst, for the stranger hays. material (optional): strand material, Fabric
-- by default. Muted and weathered, in the Rustic style; only the far-off hays get a little glow.
type Look = {
	colors: { { number } },
	length: { number },
	thick: { number },
	dust: { number },
	motes: { number }?,
	material: string?,
}

local looks: { [string]: Look } = {
	meadow = {
		colors = { { 189, 168, 112 }, { 219, 204, 153 }, { 205, 189, 136 }, { 168, 149, 95 }, { 133, 115, 71 }, { 150, 148, 96 } },
		length = { 0.5, 1.1 },
		thick = { 0.1, 0.14 },
		dust = { 175, 160, 125 },
	},
	pine = { -- needles of rust-brown pine straw, thin and long
		colors = { { 138, 96, 62 }, { 160, 112, 70 }, { 120, 84, 56 }, { 112, 104, 70 } },
		length = { 0.9, 1.5 },
		thick = { 0.06, 0.09 },
		dust = { 130, 110, 85 },
	},
	desert = { -- pale, dry and brittle short grass
		colors = { { 214, 196, 150 }, { 228, 212, 170 }, { 200, 178, 128 }, { 190, 170, 120 } },
		length = { 0.35, 0.8 },
		thick = { 0.08, 0.12 },
		dust = { 214, 190, 140 },
	},
	snow = { -- frosted grey-white hay
		colors = { { 200, 204, 196 }, { 216, 220, 214 }, { 180, 184, 170 }, { 170, 172, 150 } },
		length = { 0.5, 1.1 },
		thick = { 0.1, 0.14 },
		dust = { 225, 230, 235 },
		motes = { 240, 246, 255 },
	},
	swamp = { -- dark wet reeds, long and thick
		colors = { { 96, 104, 70 }, { 84, 92, 60 }, { 110, 112, 76 }, { 74, 78, 52 } },
		length = { 1.0, 1.7 },
		thick = { 0.14, 0.2 },
		dust = { 90, 96, 70 },
	},
	keys = { -- pale salt-bleached sea grass, thin and wiry
		colors = { { 196, 190, 150 }, { 176, 178, 136 }, { 210, 200, 164 }, { 150, 160, 120 } },
		length = { 0.8, 1.4 },
		thick = { 0.08, 0.12 },
		dust = { 214, 206, 178 },
	},
	bobbin = { -- coppery thread-like grass, fine and long
		colors = { { 168, 120, 78 }, { 150, 104, 66 }, { 186, 140, 92 }, { 132, 94, 62 } },
		length = { 1.0, 1.6 },
		thick = { 0.06, 0.09 },
		dust = { 150, 118, 88 },
		motes = { 220, 180, 110 },
	},
	volcano = { -- scorched hay with ash
		colors = { { 92, 80, 70 }, { 70, 62, 56 }, { 120, 92, 66 }, { 140, 96, 60 } },
		length = { 0.4, 0.9 },
		thick = { 0.1, 0.14 },
		dust = { 80, 74, 70 },
		motes = { 210, 120, 60 },
	},
	cave = { -- pale crystal-flecked stalks
		colors = { { 170, 176, 186 }, { 150, 160, 176 }, { 186, 186, 196 }, { 140, 150, 160 } },
		length = { 0.5, 1.0 },
		thick = { 0.1, 0.13 },
		dust = { 150, 156, 170 },
		motes = { 170, 210, 230 },
	},
	sky = { -- soft cloud hay, light and fluffy
		colors = { { 226, 228, 230 }, { 210, 216, 226 }, { 236, 236, 232 }, { 200, 208, 220 } },
		length = { 0.4, 0.9 },
		thick = { 0.14, 0.2 },
		dust = { 235, 238, 245 },
		motes = { 255, 255, 255 },
	},
	haunted = { -- grey-violet phantom straw
		colors = { { 120, 112, 130 }, { 100, 94, 112 }, { 140, 132, 146 }, { 88, 84, 96 } },
		length = { 0.6, 1.3 },
		thick = { 0.08, 0.12 },
		dust = { 110, 104, 120 },
		motes = { 150, 220, 200 },
	},
	star = { -- night-blue straw with a faint glow
		colors = { { 70, 72, 96 }, { 90, 94, 130 }, { 120, 116, 160 }, { 200, 186, 120 } },
		length = { 0.6, 1.2 },
		thick = { 0.08, 0.12 },
		dust = { 80, 84, 120 },
		motes = { 255, 230, 150 },
		material = "Glass",
	},
}

return looks

end

MODULES["Shared.Config.Finds"] = function(script)
-- Foreign objects: odd things that turn up when a bale bursts. Each broken bale rolls for one find (rarest first),
-- skipped for sorted bales. Click a find to keep it; it goes in your collection (saved with the slot) and the first
-- of each kind pays a finder's reward. oneIn is the chance per broken bale. prop names the Rustic Blender model
-- once there is one; until then the find is a simple part of size, color and material. Rewards live in Config/Prices.
local Prices = require(script.Parent.Prices)

return {
	DespawnSeconds = 300, -- an unclaimed find fades after this long
	PickupReach = 12,
	OwnerSeconds = 60, -- only whoever broke the bale can keep its find this long; after that anyone can
	Items = {
		{
			id = "boot",
			name = "Old boot",
			oneIn = 50,
			reward = Prices.FinderRewards.boot,
			prop = "old_boot",
			size = { 0.9, 1.1, 1.6 },
			color = { 92, 74, 54 },
			material = "Leather",
		},
		{
			id = "horseshoe",
			name = "Horseshoe",
			oneIn = 150,
			reward = Prices.FinderRewards.horseshoe,
			prop = "horseshoe",
			size = { 1.1, 0.15, 1.1 },
			color = { 107, 94, 84 },
			material = "Metal",
		},
		{
			id = "key",
			name = "Rusty key",
			oneIn = 300,
			reward = Prices.FinderRewards.key,
			prop = "rusty_key",
			size = { 0.25, 0.08, 0.8 },
			color = { 140, 96, 62 },
			material = "Metal",
		},
		{
			id = "radio",
			name = "Old radio",
			oneIn = 600,
			reward = Prices.FinderRewards.radio,
			prop = "old_radio",
			size = { 1.4, 1, 0.7 },
			color = { 128, 105, 77 },
			material = "Wood",
		},
		{
			id = "ring",
			name = "Lost ring",
			oneIn = 1000,
			reward = Prices.FinderRewards.ring,
			prop = "lost_ring",
			size = { 0.4, 0.4, 0.1 },
			color = { 212, 175, 85 },
			material = "Metal",
		},
		{
			id = "fossil",
			name = "Fossil",
			oneIn = 2000,
			reward = Prices.FinderRewards.fossil,
			prop = "fossil",
			size = { 1.2, 0.3, 1 },
			color = { 196, 186, 166 },
			material = "Slate",
		},
	},
}

end

MODULES["Shared.Config.Needles"] = function(script)
-- Needle types by barrel map. sortedValue is what one sells for sorted (Config/Prices).
local Prices = require(script.Parent.Prices)
return {
	{ id = "steel", name = "Steel", map = "Meadow", sortedValue = Prices.Needles.steel },
	{ id = "pine", name = "Pine", map = "Pine Forest", sortedValue = Prices.Needles.pine },
	{ id = "sand", name = "Sand", map = "Desert", sortedValue = Prices.Needles.sand },
	{ id = "ice", name = "Ice", map = "Snow Peak", sortedValue = Prices.Needles.ice },
	{ id = "bog", name = "Bog", map = "Swamp", sortedValue = Prices.Needles.bog },
	{ id = "coral", name = "Coral", map = "Thimble Keys", sortedValue = Prices.Needles.coral },
	{ id = "obsidian", name = "Obsidian", map = "Volcano", sortedValue = Prices.Needles.obsidian },
	{ id = "brass", name = "Brass", map = "Bobbin Rock", sortedValue = Prices.Needles.brass },
	{ id = "geode", name = "Geode", map = "Cave", sortedValue = Prices.Needles.geode },
	{ id = "cloud", name = "Cloud", map = "Sky Island", sortedValue = Prices.Needles.cloud },
	{ id = "phantom", name = "Phantom", map = "Haunted Grove", sortedValue = Prices.Needles.phantom },
	{ id = "cosmic", name = "Cosmic", map = "Star Hay", sortedValue = Prices.Needles.cosmic },
}

end

MODULES["Shared.Config.Props"] = function(script)
-- The Rustic Blender props (blender/exports/rustic/*.glb). Import them into Studio once (see SETUP.md) and the game
-- swaps its part-built bale and tools for the meshes. Any prop that is missing falls back to the old parts.
return {
	-- Where the imported models live. Rojo leaves ServerStorage alone, so they survive syncs.
	Folder = "RusticProps",

	-- Every prop by its .glb file name. A model named after the file (hay_bale) or the Blender object (HayBale)
	-- both count, and only props listed here are looked for. The number is the prop's longest side in studs,
	-- measured from the .glb (0.28 m per stud), so it comes out the right size whatever unit Studio imported it in.
	-- Callers that stretch a prop over a part-built body pass their own size instead.
	Sizes = {
		-- Hay, tools and small props
		hay_bale = 4.6,
		round_bale = 3.7,
		basic_shovel = 2.73,
		wide_scoop = 2.8,
		garden_rake = 5.09,
		pitchfork = 5.3,
		steel_fork = 5.2,
		hay_hook = 1.27,
		hand_sieve = 13.66,
		silver_sieve_net = 3.7,
		magnet_wand = 3.9,
		needle_tweezers = 2.35,
		needle_tray = 3.0,
		sorter_boost_oil = 1.57,
		barrel_auger = 4.6,
		hay_vacuum_hose = 3.8,
		wheelbarrow = 5.5,
		hay_crate = 3.2,
		log = 5.1,
		fence_post_set = 12.65,
		road_tile = 6.0,
		-- Gloves: one right glove each, fingers +Y, back of hand -Z (GloveLooks.luau fits them to the hand)
		work_gloves = 1.87,
		leather_gloves = 2.28,
		reinforced_gloves = 1.77,
		iron_gauntlets = 2.1,
		starlight_gloves = 1.87,
		-- Vehicles and trailers
		rusty_pickup = 27.57, -- the first truck (Vehicles.luau stretches it over the part-built truck)
		farm_flatbed = 24.49,
		box_truck = 29.49,
		semi_rig = 25.3,
		heavy_hauler = 36.0,
		starlight_hauler = 25.3,
		small_trailer = 15.8,
		medium_trailer = 30.3,
		large_trailer = 35.2,
		double_trailer = 39.0,
		bale_rack_trailer = 30.8,
		wagon_trailer = 11.6,
		pull_wagon = 11.3,
		two_wheel_handcart = 9.36,
		rowboat = 12.6,
		sailboat = 15.3,
		cargo_barge = 75.8,
		-- Conveyors and machines
		conveyor_straight = 6.2,
		conveyor_corner = 6.04,
		conveyor_ramp = 8.1,
		conveyor_sorter = 12.0,
		merger = 6.0,
		splitter = 6.2,
		needle_type_splitter = 8.5,
		optical_sorter = 12.0,
		magnet_drum = 16.11,
		-- the small decor versions of the first sorter tiers (Blender batch 4)
		hand_sieve_table = 5.92,
		shaker_table_small = 9.01,
		magnet_drum_small = 11.82,
		shaker_table = 13.66,
		hopper_feeder = 10.6,
		hay_baler = 18.6,
		hay_press = 12.1,
		needle_bundler = 6.4,
		needle_polisher = 5.4,
		alloy_mixer = 10.5,
		alien_collector = 12.4,
		-- Region treat machines (Treat.luau): two belt cells long, belt along X, belt top 3.5
		thawing_shed = 14.59,
		drying_rack = 12.0,
		ash_sifter = 12.39,
		starbeam_collector = 22.0, -- one 6x6 tile, as tall as the part-built tower in Starbeam.luau
		-- Buildings and storage
		bale_rack = 18.3,
		barn = 41.9,
		garage = 43.7,
		greenhouse = 28.3,
		harbor_dock = 52.0,
		mill = 37.9,
		mill_bin_large = 15.3,
		mill_bin_medium = 9.3,
		mill_bin_small = 4.6,
		museum = 34.0,
		needle_forge = 32.6,
		needle_vault = 7.1,
		observatory = 24.5,
		sell_depot = 27.9,
		silo_large = 36.5,
		silo_mega = 58.0,
		silo_small = 21.2,
		sorter_shed = 25.1,
		warehouse = 50.0,
		workshop = 24.45,

		-- From /mnt/project-files/art-review/MODEL_SPECS.md, measured from the Blender export (02bba19).
		-- Region scatter
		oak_tree_a = 15.4,
		oak_tree_b = 17.9,
		oak_tree_c = 14.3,
		pine_tree_a = 21.1,
		pine_tree_b = 25.9,
		pine_tree_c = 17.0,
		snowpine_tree_a = 21.3,
		snowpine_tree_b = 18.1,
		cactus_a = 9,
		cactus_b = 7,
		dead_tree_a = 16.3,
		dead_tree_b = 13.0,
		reeds_clump = 3.05,
		rock_a = 4.53,
		rock_b = 3.15,
		rock_c = 1.55,
		dune_mound = 28.9,
		firefly = 0.3,
		-- Landmarks and hub buildings
		homestead_bank = 27.4,
		bounty_board = 8.91,
		trading_post = 24.2,
		windmill = 29.3,
		spindle_landmark = 120.06,
		region_sign = 6.31,
		road_sign = 6.22,
		field_bale_chute = 15.95,
		-- Items and collectibles
		wheelbarrow_loaded = 8.14,
		needle_bundle = 1.29, -- the NeedleBundle part in Needle.luau is 1.3 x 0.55 x 0.55
		needle_display_wall = 7.83,
		old_boot = 1.51,
		horseshoe = 0.88,
		lost_ring = 0.6,
		fossil = 1.4,
		old_radio = 1.75,
		scarecrow = 7,
		golden_shovel = 2.65,
		rusty_key = 0.93, -- a find (Config/Finds.luau)
		-- Quest relics (Config/Quests reward ids): single meshes, no rig
		drowned_compass = 0.99,
		straw_crown = 1.45,
		corn_moon_charm = 1.05,
		lucky_thimble = 0.5,
		-- Quest set pieces (Blender ac0af86)
		loom_pedestal = 4.04,
		labyrinth_arch = 13.07,
		labyrinth_bell = 7.05,
		-- Rides and set pieces (Blender batch 4)
		hay_wagon = 16.05,
		farm_tractor = 8.68,
		ferry_snack_stand = 9.04,
		fishing_spot = 3.04,
		needle_lite = 1.2, -- low-poly ground needle (46 tris), one shared mesh tinted per needle
		needle_tiny = 1.2, -- the 26-tri one, no eye
		rarity_needle = 1.2, -- the one needle mesh every rarity tier shares (same length as the game's needle)
		-- Robux truck skins: each one the length of the cash truck tier Prices.Robux sells it as (measured from each .glb)
		homestead_classic = 27.57,
		timber_wolf_4x4 = 24.5, -- Farm Flatbed tier
		midnight_express = 29.49,
		prairie_schooner = 36.0, -- Heavy Hauler tier, canvas Cover
		founders_semi = 25.3,

		-- The 02bba19 batch, measured from each .glb
		-- Region bales: every bale is the same size as hay_bale
		bale_cave = 4.69,
		bale_desert = 4.69,
		bale_haunted = 4.69,
		bale_pine = 4.69,
		bale_sky = 4.66,
		bale_snow = 4.69,
		bale_star = 4.68,
		bale_swamp = 4.69,
		bale_seagrass = 4.68, -- Thimble Keys (hay type "keys")
		bale_thread = 4.69, -- Bobbin Rock (hay type "bobbin")
		bale_volcano = 4.69,
		golden_hay_bale = 4.63,
		-- Needles: the 12 types and the rarity set share one shape; the bin has a NeedleFill mesh
		master_needle_shard = 1.52,
		needle_anchor = 1.18,
		needle_bin = 6,
		needle_bog = 1.2,
		needle_cloud = 1.21,
		needle_common = 1.2,
		needle_coral = 1.21,
		needle_brass = 1.2,
		needle_cosmic = 1.2,
		needle_epic = 1.2,
		needle_geode = 1.21,
		needle_giant = 3.62,
		needle_glitch = 1.19,
		needle_ice = 1.21,
		needle_legendary = 1.2,
		needle_obsidian = 1.2,
		needle_pearl = 1.25,
		needle_phantom = 1.21,
		needle_pine = 1.2,
		needle_rainbow = 1.2,
		needle_rare = 1.2,
		needle_sand = 1.2,
		needle_steel = 1.2,
		needle_uncommon = 1.2,
		-- More gloves
		cotton_gloves = 1.68,
		frostbite_mitts = 2.43,
		insulated_gloves = 1.96,
		kraken_gauntlets = 2.04,
		magma_grips = 1.95,
		scarecrow_gloves = 2.06,
		starweave_gloves = 1.87,
		-- Special vehicles
		captains_barge = 80.1,
		ghost_hauler = 36.06,
		old_bessie = 32.2,
		public_ferry = 116.2,
		sandrunner = 28.0,
		zeppelin = 60.4,
		-- Quest gear
		barn_key = 1.46,
		beacon_part_1 = 2.11,
		beacon_part_2 = 1.66,
		beacon_part_3 = 1.76,
		captains_log = 1.71,
		corn_maze_key_1 = 1.11,
		corn_maze_key_2 = 1.15,
		corn_maze_key_3 = 1.17,
		crop_circle_marker = 3.05,
		frozen_bobbin = 1.24,
		tailor_journal_page = 1.49,
		thread_rake = 4.84,
		-- Hub, regions and landmarks: face -Z, origin at ground center
		bobbin_captain_shack = 22.9,
		buried_pyramid_garage = 66.5,
		cave_entrance = 34.7,
		corn_maze_gate = 28.8,
		display_stand = 4.9,
		ferry_dock = 40.0,
		haunted_barn = 35.6,
		hay_buyer = 10.2,
		hay_sell_shop = 35.3,
		homestead_motors = 67.7,
		land_office = 23.0,
		loading_dock = 18.9,
		longstitch_highway_sign = 36.0,
		meadow_windmill = 40.0,
		pine_lodge = 31.6,
		plot_fence_sign = 14.6,
		snow_cabin = 22.4,
		straw_labyrinth_gate = 36.9,
		swamp_stilt_house = 33.2,
		the_spindle = 119.9,
		thimble_lighthouse = 43.2,
		volcano_forge = 30.7,
		zeppelin_dock = 47.2,
	},

	-- Hay types whose bale mesh is named differently from the hay type (Bales.luau looks for bale_<hayType>).
	BaleForHay = {
		keys = "bale_seagrass",
		bobbin = "bale_thread",
	},

	-- Held tools: how far below the hand the end of the handle sits.
	GripFromEnd = 0.6,
}

end

MODULES["Services.Hay"] = function(script)
-- Loose hay. A broken bale spills into a pile of small straw strands with the odd needle hidden among them. The
-- shovel scoops pieces up, the rake drags them across the ground, and pieces left on the sell pad sell. Every
-- piece is a small real part, capped at MaxLoosePieces so the server stays light. A piece is one strand, a clump of
-- a few (a burst bale spills clumps, Config.StrandsPerClump) or a raked pile; Hay.strandsIn says how many.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local Groups = require(script.Parent.Groups)
-- The game's one shared needle (Needle.luau, from the conveyor work) when it is present, so a needle spilled from
-- a bale looks, picks up and sells the same as one anywhere else. Without it, a local stand-in is used.
local NeedleModule = script.Parent:FindFirstChild("Needle")
local Needle = NeedleModule and require(NeedleModule)

local Hay = {}

local rng = Random.new()
local pieces = {} -- piece part -> time it last moved or was made
local count = 0 -- loose straw strands (needles are counted apart, so they never crowd out new hay)
local needleCount = 0
local needleSet = {} -- piece -> true for the visible needles among the pieces
local fieldSet = {} -- piece -> true for the piles a field grows (never faded, trimmed or counted against the caps)

-- Forgets a piece however it leaves the world. Returns true if it was still known.
local function forget(piece)
	if not pieces[piece] then
		return false
	end
	pieces[piece] = nil
	if fieldSet[piece] then
		fieldSet[piece] = nil
	elseif needleSet[piece] then
		needleSet[piece] = nil
		needleCount -= 1
	else
		count -= 1
	end
	return true
end
local overlap = OverlapParams.new()

local HayLooks = require(ReplicatedStorage.Shared.Config.HayLooks)
local Prices = require(ReplicatedStorage.Shared.Config.Prices)

-- A bale's or strand's boost (NeedleBoost, MutationBoost): a positive number, else 1.
function Hay.boostOf(part, name)
	local v = part:GetAttribute(name)
	return (typeof(v) == "number" and v > 0 and v == v) and v or 1
end

-- The boosts a bale passes on to its strands, and strands to the pile or bale they end up in.
Hay.BoostAttributes = { "NeedleBoost", "MutationBoost" }

-- The chance each unit of hay in this bale or strand hides a needle: its hay type's (Prices.needleChance), times its
-- NeedleBoost (rich field, chute, region event, Hay Market; a golden bale's strands carry its golden multiple), and a
-- golden bale's GoldenBaleNeedles. Capped at 1.
function Hay.needleChanceOf(part)
	local chance = Prices.needleChance(part:GetAttribute("HayType")) * Hay.boostOf(part, "NeedleBoost")
	if part:GetAttribute("GoldenField") == true then
		chance *= Config.GoldenBaleNeedles
	end
	return math.min(chance, 1)
end

-- The look for a hay type (Config/HayLooks), meadow when unknown.
function Hay.look(hayType)
	return HayLooks[hayType or "meadow"] or HayLooks.meadow
end

Hay.folder = nil

function Hay.init(parent)
	local folder = Instance.new("Folder")
	folder.Name = "LooseHay"
	folder.Parent = parent
	Hay.folder = folder
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { folder }

	-- Hay nobody touches for a while shrinks away so the world never clogs up.
	task.spawn(function()
		while true do
			task.wait(3)
			local now = os.clock()
			for piece, born in pieces do
				if fieldSet[piece] then
					continue -- a field's own pile stays until it is cleared, then grows back (Hay.spawnFieldPile)
				end
				-- Needles stay much longer than straw, so there is time to find them, but not forever.
				local life = if needleSet[piece] or piece:GetAttribute("Strands")
					then Config.LooseNeedleLifetime
					else Config.LooseHayLifetime
				if now - born > life then
					Hay.fadeOut(piece)
				end
			end
		end
	end)
end

function Hay.isPiece(part)
	return pieces[part] ~= nil
end

function Hay.remove(piece)
	forget(piece)
	piece:Destroy()
end

function Hay.fadeOut(piece)
	if not forget(piece) then
		return
	end
	piece.CanCollide = false
	local tween = TweenService:Create(piece, TweenInfo.new(0.6), { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		piece:Destroy()
	end)
end

-- Past the caps the oldest strand (or, for needles, the oldest needle) goes, so the server never fills up.
local function trimKind(isNeedle, over)
	while over() do
		local oldest, oldestTime = nil, math.huge
		for piece, born in pieces do
			-- Piles are a player's raked work, so the cap never takes them.
			local kindMatches = (needleSet[piece] == true) == isNeedle and not Hay.isPile(piece)
			if born < oldestTime and kindMatches then
				oldest, oldestTime = piece, born
			end
		end
		if not oldest then
			return
		end
		Hay.remove(oldest)
	end
end

-- Past MaxHayPiles the oldest pile goes (the strand cap never takes piles).
local function trimPiles()
	while true do
		local piles, oldest, oldestTime = 0, nil, math.huge
		for piece, born in pieces do
			if Hay.isPile(piece) and not fieldSet[piece] then
				piles += 1
				if born < oldestTime then
					oldest, oldestTime = piece, born
				end
			end
		end
		if piles <= Config.MaxHayPiles or not oldest then
			return
		end
		Hay.remove(oldest)
	end
end

-- What is loose right now, for the self-tests and for spotting a leak: strands (piles count as one), needles, and
-- every piece the module still tracks (which should always be strands + needles).
function Hay.stats()
	local tracked = 0
	for _ in pieces do
		tracked += 1
	end
	return { strands = count, needles = needleCount, tracked = tracked }
end

local function trim()
	trimKind(false, function()
		return count > Config.MaxLoosePieces
	end)
	trimKind(true, function()
		return needleCount > Config.MaxLooseNeedles
	end)
end

-- A loose strand of straw: thin, a little bent, in a spread of weathered hay colors.
-- A strand in its region's colors and shape.
-- A clump of several strands is the same strand a little longer and about twice as thick (three strands' volume).
local function makeStraw(hayType, strands)
	local look = Hay.look(hayType)
	local c = look.colors[rng:NextInteger(1, #look.colors)]
	local grow = strands > 1 and math.sqrt(strands) * 0.9 or 1
	local thick = rng:NextNumber(look.thick[1], look.thick[2]) * grow
	local piece = Instance.new("Part")
	piece.Name = "Straw"
	local length = rng:NextNumber(look.length[1], look.length[2]) * (strands > 1 and 1.15 or 1)
	piece.Size = Vector3.new(length, thick, thick * rng:NextNumber(0.85, 1.15))
	if strands > 1 then
		piece:SetAttribute("Strands", strands)
	end
	piece.Color = Color3.fromRGB(c[1], c[2], c[3])
	piece.Material = look.material and Enum.Material[look.material] or Enum.Material.Fabric
	piece.CustomPhysicalProperties = PhysicalProperties.new(0.3, 1.2, 0, 1, 1)
	return piece
end

local function addGlint(piece)
	local glint = Instance.new("ParticleEmitter")
	glint.Name = "Glint"
	glint.Rate = 1.2
	glint.Lifetime = NumberRange.new(0.25, 0.4)
	glint.Speed = NumberRange.new(0)
	glint.LightEmission = 1
	glint.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	glint.Color = ColorSequence.new(Color3.new(1, 1, 1))
	glint.Parent = piece
end

-- A needle hiding in the hay: a thin steel sliver that catches the light now and then, so a sharp eye can spot it.
-- hayType picks the needle kind (a Pine bale spills Pine needles) when the shared needle knows how.
local function makeNeedle(cframe, ownerId, hayType)
	if Needle then
		local needleId = hayType and Needle.forHay and Needle.forHay(hayType) or nil
		local piece = Needle.make(cframe, ownerId, needleId)
		addGlint(piece)
		return piece
	end
	local piece = Instance.new("Part")
	piece.Name = "Needle"
	piece.Shape = Enum.PartType.Cylinder
	piece.Size = Vector3.new(0.75, 0.09, 0.09)
	piece.Color = Color3.fromRGB(196, 198, 202)
	piece.Material = Enum.Material.Metal
	piece.Reflectance = 0.35
	piece.CustomPhysicalProperties = PhysicalProperties.new(2, 0.8, 0, 1, 1)
	piece:SetAttribute("Needle", true)
	addGlint(piece)
	return piece
end

-- kind is "Needle" for a visible needle (of the kind found in hayType), otherwise a strand of hayType's straw, or a
-- clump of strands (default 1) worth that many.
function Hay.spawnPiece(position, velocity, ownerId, kind, hayType, strands)
	local cframe = CFrame.new(position)
		* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.4, 0.4))
	local piece = kind == "Needle" and makeNeedle(cframe, ownerId, hayType) or makeStraw(hayType, strands or 1)
	piece.CFrame = cframe
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.CollisionGroup = Groups.Loose
	piece.AssemblyLinearVelocity = velocity
	piece.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
	piece:SetAttribute("OwnerId", ownerId)
	pieces[piece] = os.clock()
	if kind == "Needle" then
		needleSet[piece] = true
		needleCount += 1
	else
		count += 1
	end
	-- A needle can be clicked up and destroyed elsewhere, so forget a piece however it leaves.
	piece.Destroying:Connect(function()
		forget(piece)
	end)
	piece.Parent = Hay.folder
	-- The server simulates loose hay. Otherwise a nearby player's client owns each strand's physics and quietly
	-- overrides the rake's pull, which is why raking used to feel weak.
	pcall(function()
		piece:SetNetworkOwner(nil)
	end)
	trim()
	return piece
end

function Hay.isNeedle(part)
	if Needle and Needle.isNeedle(part) then
		return true
	end
	return part:GetAttribute("Needle") == true
end

-- What a found needle is worth: the shared needle's full value, or the raw $1 without it.
function Hay.needleValue(part)
	return Needle and Needle.value(part) or 1
end

-- True when needles are the shared kind, which players pick up by clicking rather than with the shovel.
Hay.sharedNeedles = Needle ~= nil

-- Pieces within radius of position, nearest first, at most max of them.
function Hay.near(position, radius, max)
	local found = {}
	for _, part in workspace:GetPartBoundsInRadius(position, radius, overlap) do
		if pieces[part] then
			table.insert(found, part)
		end
	end
	table.sort(found, function(a, b)
		return (a.Position - position).Magnitude < (b.Position - position).Magnitude
	end)
	while max and #found > max do
		table.remove(found)
	end
	return found
end

-- The scooped pieces leave the world at once and arc into the player's chest.
function Hay.flyToPlayer(root, list)
	for i, piece in list do
		forget(piece)
		piece.Anchored = true
		piece.CanCollide = false
		local from = piece.Position
		task.delay((i - 1) * 0.04, function()
			local started = os.clock()
			local duration = Config.HayFlightSeconds
			while piece.Parent do
				local alpha = (os.clock() - started) / duration
				if alpha >= 1 or not root.Parent then
					break
				end
				local target = root.Position + Vector3.new(0, 1, 0)
				local control = (from + target) / 2 + Vector3.new(0, 4, 0)
				local inv = 1 - alpha
				local pos = inv * inv * from + 2 * inv * alpha * control + alpha * alpha * target
				piece.CFrame = CFrame.new(pos) * (piece.CFrame - piece.CFrame.Position) * CFrame.Angles(0.2, 0.3, 0)
				RunService.Heartbeat:Wait()
			end
			piece:Destroy()
		end)
	end
end

-- The rake gathers. For a short stroke every strand around the click slides along the ground toward a spot just in
-- front of the player, so a scattered spill gets pulled into a neat row. Strands keep their own fall and tumble a
-- little, but they are steered rather than flung, which suits small light straw.
-- How many strands a loose piece stands for: 1, or a whole pile's worth.
function Hay.strandsIn(piece)
	return piece:GetAttribute("Strands") or 1
end

-- A raked pile (one scoop takes all of it); a clump of strands is not one.
function Hay.isPile(piece)
	return piece.Name == "HayPile"
end

-- Sizes a pile's mound to how much hay is in it.
local function shapePile(pile, n)
	local width = math.min(1.6 + n * 0.035, 6)
	local height = math.min(0.5 + n * 0.012, 2.2)
	pile.Size = Vector3.new(width, height, width * 0.85)
	pile:SetAttribute("Strands", n)
end

-- Takes n strands off a pile or clump (for a scoop that has less room than it holds). The rest stays.
function Hay.takeFromPile(pile, n)
	local left = Hay.strandsIn(pile) - n
	if left <= 0 then
		Hay.remove(pile)
	elseif Hay.isPile(pile) then
		shapePile(pile, left)
	else
		pile:SetAttribute("Strands", left > 1 and left or nil)
	end
end

-- The strands, attributes and boosts a field pile passes to hay that leaves it loose (a rake spill): its hay type,
-- wetness and boosts, with a golden pile's GoldenBaleNeedles folded into NeedleBoost like a golden bale's strands.
local function fieldAttributes(pile)
	local attrs = {
		HayType = pile:GetAttribute("HayType"),
		Wet = pile:GetAttribute("Wet"),
		MutationBoost = pile:GetAttribute("MutationBoost"),
	}
	local needleBoost = Hay.boostOf(pile, "NeedleBoost")
	if pile:GetAttribute("GoldenField") == true then
		needleBoost *= Config.GoldenBaleNeedles
	end
	if math.abs(needleBoost - 1) > 1e-6 then
		attrs.NeedleBoost = needleBoost
	end
	return attrs
end

-- A field's hay: a mound of a bale's worth of loose strands (Config.FieldPileStrands) that the shovel scoops from
-- and the rake pulls strands off. It is anchored and never fades; once it is cleared, onCleared() runs (Bales
-- grows a fresh one there). position is the ground point under it.
function Hay.spawnFieldPile(position, hayType, onCleared)
	hayType = hayType or "meadow"
	local look = Hay.look(hayType)
	local c = look.colors[1]
	local pile = Instance.new("Part")
	pile.Name = "HayPile"
	pile.Anchored = true
	pile.Color = Color3.fromRGB(c[1], c[2], c[3])
	pile.Material = Enum.Material.Fabric
	pile.CollisionGroup = Groups.Loose
	pile.TopSurface = Enum.SurfaceType.Smooth
	pile.BottomSurface = Enum.SurfaceType.Smooth
	local mound = Instance.new("SpecialMesh")
	mound.MeshType = Enum.MeshType.Sphere
	mound.Parent = pile
	pile:SetAttribute("HayType", hayType)
	pile:SetAttribute("Field", true)
	shapePile(pile, Config.FieldPileStrands)
	pile.CFrame = CFrame.new(position + Vector3.new(0, pile.Size.Y / 2 - 0.15, 0))
	pieces[pile] = os.clock()
	fieldSet[pile] = true
	pile.Destroying:Connect(function()
		forget(pile)
		if onCleared then
			onCleared()
		end
	end)
	-- Fields can be laid out before Hay.init makes the folder; they join it as soon as it is there.
	if Hay.folder then
		pile.Parent = Hay.folder
	else
		task.spawn(function()
			while not Hay.folder do
				task.wait()
			end
			if pieces[pile] then -- not scooped away in the meantime
				pile.Parent = Hay.folder
			end
		end)
	end
	return pile
end

-- True for a pile a field grows (Hay.spawnFieldPile).
function Hay.isFieldPile(piece)
	return fieldSet[piece] == true
end

-- Packs the loose strands raked around a spot into one pile, once there are PileMin of them (an existing pile there
-- grows instead). Sorted hay only piles with sorted hay, so a pile is sorted or not as a whole.
local function packPile(at, ownerId)
	local groups = {}
	for _, piece in Hay.near(at, Config.PileRadius, nil) do
		if not needleSet[piece] and not fieldSet[piece] then
			local key = piece:GetAttribute("Sorted") and "sorted" or "raw"
			groups[key] = groups[key] or { strands = 0, parts = {}, pile = nil, boosts = {} }
			local g = groups[key]
			for _, name in Hay.BoostAttributes do
				g.boosts[name] = (g.boosts[name] or 0) + Hay.strandsIn(piece) * Hay.boostOf(piece, name)
			end
			if Hay.isPile(piece) and not g.pile then
				g.pile = piece
			else
				table.insert(g.parts, piece)
			end
			g.strands += Hay.strandsIn(piece)
		end
	end
	for key, g in groups do
		if g.strands >= Config.PileMin and (#g.parts > 0) then
			local pile = g.pile
			if not pile then
				local first = g.parts[1]
				local hayType = first:GetAttribute("HayType") or "meadow"
				local look = Hay.look(hayType)
				local c = look.colors[1]
				pile = Instance.new("Part")
				pile.Name = "HayPile"
				pile.Color = Color3.fromRGB(c[1], c[2], c[3])
				pile.Material = Enum.Material.Fabric
				pile.CollisionGroup = Groups.Loose
				pile.CustomPhysicalProperties = PhysicalProperties.new(0.6, 1.5, 0, 1, 1)
				-- A rounded mound: a sphere mesh stretched to the part (a Ball part would have to stay round).
				local mound = Instance.new("SpecialMesh")
				mound.MeshType = Enum.MeshType.Sphere
				mound.Parent = pile
				pile:SetAttribute("HayType", hayType)
				if key == "sorted" then
					pile:SetAttribute("Sorted", true)
				end
				pile:SetAttribute("OwnerId", ownerId)
				shapePile(pile, g.strands)
				pile.CFrame = CFrame.new(at.X, at.Y + pile.Size.Y / 2, at.Z)
				pieces[pile] = os.clock()
				count += 1
				pile.Destroying:Connect(function()
					forget(pile)
				end)
				pile.Parent = Hay.folder
				pcall(function()
					pile:SetNetworkOwner(nil)
				end)
				trimPiles()
			end
			for _, piece in g.parts do
				Hay.remove(piece)
			end
			-- The pile keeps its strands' boosts, weighted by how many strands brought each.
			for name, sum in g.boosts do
				local boost = sum / g.strands
				pile:SetAttribute(name, math.abs(boost - 1) > 1e-6 and boost or nil)
			end
			-- Grow it upward, so the bigger mound does not sink into the ground and pop out.
			local oldHeight = pile.Size.Y
			shapePile(pile, g.strands)
			pile.CFrame += Vector3.new(0, (pile.Size.Y - oldHeight) / 2, 0)
			pieces[pile] = os.clock()
		end
	end
end

-- The conveyor belt nearest position within radius, and the spot on its top surface closest to position (kept off
-- the rails), or nil when there is none.
function Hay.beltNear(position, radius)
	local best, bestSpot, bestDistance = nil, nil, math.huge
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Hay.folder }
	for _, part in workspace:GetPartBoundsInRadius(position, radius, params) do
		if CollectionService:HasTag(part, "ConveyorBelt") then
			local localPos = part.CFrame:PointToObjectSpace(position)
			local half = part.Size / 2
			local spot = part.CFrame
				* Vector3.new(
					math.clamp(localPos.X, -half.X + 0.4, half.X - 0.4),
					half.Y + 0.3,
					math.clamp(localPos.Z, -half.Z + 0.4, half.Z - 0.4)
				)
			local distance = (spot - position).Magnitude
			if distance < bestDistance then
				best, bestSpot, bestDistance = part, spot, distance
			end
		end
	end
	return best, bestSpot
end

-- Raking hay onto a belt: the strands around center are flicked up in a short arc onto the belt's top near landAt,
-- where the belt carries them into the line (a baler packs them, a sorter sorts them). Belts stand well off the
-- ground, so hay is lifted onto them rather than dragged. Raked piles stay where they are (shovel them instead).
-- Returns how many went up.
function Hay.rakeOntoBelt(center, belt, landAt, radius, ownerId)
	local list = Hay.near(center, radius, nil)
	local flight = 0.5
	local gravity = Vector3.new(0, -workspace.Gravity, 0)
	local along = belt.CFrame:VectorToWorldSpace(Vector3.new(1, 0, 0))
	local across = belt.CFrame:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local half = belt.Size / 2
	local sent = 0
	for i, piece in list do
		if not Hay.isPile(piece) and piece.Parent then
			if not needleSet[piece] then
				piece:SetAttribute("OwnerId", ownerId)
			end
			pieces[piece] = os.clock()
			-- Spread along the belt a little so the hay lands as a row, not a heap.
			local target = landAt + along * rng:NextNumber(-1, 1) * math.min(half.X - 0.4, 1.5)
				+ across * rng:NextNumber(-1, 1) * math.min(half.Z - 0.4, 1.5)
			local from = piece.Position
			local velocity = (target - from - 0.5 * gravity * flight * flight) / flight
			task.delay((i - 1) * 0.01, function()
				if piece.Parent then
					piece.AssemblyLinearVelocity = velocity
					piece.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
				end
			end)
			sent += 1
		end
	end
	return sent
end

function Hay.rake(center, gatherAt, radius, ownerId)
	local found = Hay.near(center, radius, nil)
	local list = {}
	for _, piece in found do
		if fieldSet[piece] then
			-- A field's pile stays put: the tines pull a few clumps off its near side, which come along with the rest.
			local take = math.min(Config.RakeFieldStrands, Hay.strandsIn(piece))
			local attrs = fieldAttributes(piece)
			local from = piece.Position
			local toward = Vector3.new(gatherAt.X - from.X, 0, gatherAt.Z - from.Z)
			local side = toward.Magnitude > 0.1 and toward.Unit or Vector3.zero
			local spill = from + side * (piece.Size.X / 2) + Vector3.new(0, 0.6, 0)
			Hay.takeFromPile(piece, take)
			local left = take
			while left > 0 do
				local n = math.min(Config.StrandsPerClump, left)
				left -= n
				local clump = Hay.spawnPiece(
					spill + Vector3.new(rng:NextNumber(-0.8, 0.8), 0, rng:NextNumber(-0.8, 0.8)),
					side * 4,
					ownerId,
					"Straw",
					attrs.HayType,
					n
				)
				for name, value in attrs do
					clump:SetAttribute(name, value)
				end
				table.insert(list, clump)
			end
		else
			table.insert(list, piece)
		end
	end
	for _, piece in list do
		-- Raked straw is paid to the raker; a visible needle stays with whoever's bale it came from.
		if not needleSet[piece] then
			piece:SetAttribute("OwnerId", ownerId)
		end
		pieces[piece] = os.clock()
		-- Each strand stops a slightly different distance short of the gather spot, so they pile in a row, not a point.
		piece:SetAttribute("RakeStop", rng:NextNumber(0.6, 2.2))
	end
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < Config.RakeStrokeSeconds do
			for _, piece in list do
				if piece.Parent and pieces[piece] then
					local toward = Vector3.new(gatherAt.X - piece.Position.X, 0, gatherAt.Z - piece.Position.Z)
					local distance = toward.Magnitude
					local fall = math.min(piece.AssemblyLinearVelocity.Y, 2)
					if distance > (piece:GetAttribute("RakeStop") or 1) then
						local speed = math.clamp(distance * 2.2, 3, Config.RakeMaxSpeed)
						piece.AssemblyLinearVelocity = toward.Unit * speed + Vector3.new(0, fall, 0)
					else
						piece.AssemblyLinearVelocity = Vector3.new(0, fall, 0)
					end
				end
			end
			RunService.Heartbeat:Wait()
		end
		-- Raking a big enough heap together packs it into one pile the shovel can take at once.
		task.wait(0.25)
		packPile(gatherAt - Vector3.new(0, 2.5, 0), ownerId)
	end)
	return #list
end

return Hay

end

MODULES["Services.Bales"] = function(script)
-- Wrapped hay bales. Bare hands lift a whole bale and carry it. Set one down and it lands on whatever is in front
-- of you, so bales stack into piles. The shovel cuts a bale open: the twine snaps and the hay spills into a pile of
-- loose pieces (see Hay.luau). Bales are real physical blocks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config.Game)
local GloveConfig = require(ReplicatedStorage.Shared.Config.Gloves)
local Data = require(script.Parent.Data)
local Avatar = require(script.Parent.Avatar)
local Hay = require(script.Parent.Hay)
local Groups = require(script.Parent.Groups)
local Tutorial = require(script.Parent.Tutorial)
local Props = require(script.Parent.Props)
local PropsConfig = require(ReplicatedStorage.Shared.Config.Props)
local Gloves = require(script.Parent.Gloves)
local Feedback = require(script.Parent.Feedback)
local Events = require(script.Parent.Events)
local Finds = require(script.Parent.Finds)
local Announce = require(script.Parent.Announce)
local Weather = require(script.Parent.Weather)
local HayMath = require(ReplicatedStorage.Shared.HayMath)
local Boosts = require(ReplicatedStorage.Shared.Boosts)
local BOOST_TERMS = Boosts.terms(require(ReplicatedStorage.Shared.Config.Prices))
local LandConfig = require(ReplicatedStorage.Shared.Config.Land)
local WorldRegions = require(ReplicatedStorage.Shared.WorldRegions)

local Bales = {}

local rng = Random.new()
local folder = nil
local dropOff = nil -- the pad where set-down bales are kept for later
local byBody = {} -- bale body part -> bale record

local SIZE = Vector3.new(4.6, 2.6, 3.2) -- length, height, depth of one bale
local CARRY_OFFSET = CFrame.new(0, 0.4, -2.8)
local TWINE = Color3.fromRGB(97, 84, 66)
local TWINE_X = { -1.2, 1.2 } -- two bands of twine around the bale

-- Turns a bale's Pick up button on or off for everyone. The Usable attribute tells each client too, since clients
-- also hide the buttons locally while a tool is out (Main.client.luau).
local function setUsable(b, on)
	b.prompt:SetAttribute("Usable", on)
	b.prompt.Enabled = on
end

-- The bale's own color: the first of its hay's colors (Config/HayLooks).
local function hayColor(hayType)
	local c = Hay.look(hayType).colors[1]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function buildBale(position, hayType)
	hayType = hayType or "meadow"
	local body = Instance.new("Part")
	body.Name = "HayBale"
	body:SetAttribute("HayType", hayType) -- Config/Gloves hay type; set another for rarer bales
	body.Size = SIZE
	body.CFrame = CFrame.new(position + Vector3.new(0, SIZE.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0)
	body.Color = hayColor(hayType)
	body.Material = Enum.Material.Fabric
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Anchored = true
	-- Heavy and grippy with no bounce, so a stack settles instead of sliding apart. The heavy friction and elasticity
	-- weights make the bale's own grip and zero bounce win against whatever it rests on (a slick metal truck bed, a
	-- springy floor), so two bales stacked in a moving pickup ride it out instead of skating or popping apart.
	body.CustomPhysicalProperties = PhysicalProperties.new(1.2, 1.4, 0, 50, 100)

	-- The Rustic bale mesh, stretched over the hitbox so stacking and carrying work exactly as before. The body
	-- stays the real physics block and click target. Each client hides the part look once the mesh has loaded.
	-- Each region's hay has its own bale mesh (bale_pine, bale_star, ...); the meadow bale is hay_bale.
	local regionalName = PropsConfig.BaleForHay[hayType] or ("bale_%s"):format(hayType)
	local regional = hayType ~= "meadow" and Props.has(regionalName)
	local mesh = Props.make(regional and regionalName or "hay_bale", body.CFrame, SIZE)
	if mesh then
		-- Tint the meadow mesh for rarer hay that has no mesh of its own (an untextured mesh takes the color; a
		-- textured one keeps its own).
		if hayType ~= "meadow" and not regional then
			for _, d in mesh:GetDescendants() do
				if d:IsA("MeshPart") then
					d.Color = body.Color
				end
			end
		end
		Props.weldTo(mesh, body, body)
	end

	-- The twine bands wrap the part bale. They are visual only and ride along with it.
	for _, x in TWINE_X do
		local band = Instance.new("Part")
		band.Name = "Twine"
		band.Size = Vector3.new(0.12, SIZE.Y + 0.06, SIZE.Z + 0.06)
		band.CFrame = body.CFrame * CFrame.new(x, 0, 0)
		band.Color = TWINE
		band.Material = Enum.Material.Fabric
		band.CanCollide = false
		band.CanQuery = false
		band.Massless = true
		band.Parent = body
		local weld = Instance.new("Weld")
		weld.Part0 = body
		weld.Part1 = band
		weld.C0 = CFrame.new(x, 0, 0)
		weld.Parent = band
	end

	-- The small Pick up / Put down button. Click or tap it (or press its key). It lives on the bale, so
	-- while you carry it the button travels with you and puts it down.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = (GloveConfig.HayTypes[hayType] or GloveConfig.HayTypes.meadow).name .. " bale"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.PickupReach
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.UIOffset = Vector2.new(0, 24)
	prompt.Parent = body

	CollectionService:AddTag(body, "HayBale")
	return body, prompt
end

-- Removes a bale from the world for good (sold, smashed, or timed out).
function Bales.consume(b)
	if b.gone then
		return
	end
	b.gone = true
	byBody[b.body] = nil
	b.body:Destroy()
end

-- The nearest bale standing within reach and roughly in front of the player, or nil.
function Bales.inFront(root, reach)
	local look = root.CFrame.LookVector
	local best, bestDistance = nil, reach
	for body, b in byBody do
		if not b.gone and not b.carriedBy and not b.breaking then
			local offset = body.Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local distance = flat.Magnitude
			local facing = distance < 0.01 or flat.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) > 0.3
			if distance < bestDistance and facing then
				best, bestDistance = b, distance
			end
		end
	end
	return best
end

function Bales.fromPart(part)
	return byBody[part] or (part.Parent and byBody[part.Parent]) or nil
end

-- True when the bale rests on the drop-off pad (checked in the pad's own flat space, ignoring height).
function Bales.isAtDropOff(b)
	if not dropOff or b.gone then
		return false
	end
	local spot = dropOff.CFrame:PointToObjectSpace(b.body.Position)
	return math.abs(spot.X) <= dropOff.Size.X / 2 and math.abs(spot.Z) <= dropOff.Size.Z / 2 and spot.Y < 8
end

-- Bales left out in the world disappear after a while. Bales on the drop-off pad, in a truck, or in a neat stack of
-- Config.StackMin or more are kept.
local function startDespawnTimer(b)
	b.dropToken += 1
	local token = b.dropToken
	local function check()
		if b.gone or b.carriedBy or b.home or b.dropToken ~= token then
			return
		end
		if Bales.isAtDropOff(b) or b.body:GetAttribute("InTruck") or b.inStack then
			task.delay(Config.DroppedBaleSeconds, check) -- still stored or riding in a truck, look again later
			return
		end
		Bales.consume(b)
	end
	task.delay(Config.DroppedBaleSeconds, check)
end

function Bales.setDropOff(part)
	dropOff = part
end

-- A home bale is gone from its spot (smashed or lifted), so a fresh one grows back there.
local function scheduleRegrow(b)
	if not b.home then
		return
	end
	b.home = false
	local function regrow()
		-- Wait while anything (a bale put back on its spot, say) is in the way, so a new bale never spawns inside it.
		local center = b.spawnPosition + Vector3.new(0, SIZE.Y / 2, 0)
		for _, part in workspace:GetPartBoundsInBox(CFrame.new(center), SIZE * 0.9) do
			if Bales.fromPart(part) then
				task.delay(5, regrow)
				return
			end
		end
		local fresh = Bales.spawn(b.spawnPosition, true, true, b.hayType)
		if b.onRegrow then
			b.onRegrow(fresh)
		end
	end
	task.delay(Config.BaleRefillSeconds, regrow)
end

local function debrisPart(shape, size, cframe, color, material, velocity)
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.CollisionGroup = Groups.Loose
	part.AssemblyLinearVelocity = velocity
	part.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
	part.Parent = Hay.folder
	task.delay(7, function()
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(1), { Transparency = 1 }):Play()
			Debris:AddItem(part, 1.1)
		end
	end)
	return part
end

-- Straw and dust thrown up when the bale bursts.
local function burstEffects(position, hayType)
	local look = Hay.look(hayType)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position
	anchor.Parent = Hay.folder

	local straw = Instance.new("ParticleEmitter")
	straw.Rate = 0
	straw.Lifetime = NumberRange.new(0.6, 1.1)
	straw.Speed = NumberRange.new(10, 22)
	straw.SpreadAngle = Vector2.new(180, 180)
	straw.Acceleration = Vector3.new(0, -25, 0)
	straw.Color = ColorSequence.new(hayColor(hayType))
	straw.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	straw.Parent = anchor

	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.8, 1.4)
	dust.Speed = NumberRange.new(3, 8)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Color = ColorSequence.new(Color3.fromRGB(look.dust[1], look.dust[2], look.dust[3]))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust.Parent = anchor

	straw:Emit(40)
	dust:Emit(18)
	-- The stranger hays throw up a few drifting specks: ash embers, frost, crystal glints, star dust.
	if look.motes then
		local motes = Instance.new("ParticleEmitter")
		motes.Rate = 0
		motes.Lifetime = NumberRange.new(1.2, 2.2)
		motes.Speed = NumberRange.new(1, 4)
		motes.SpreadAngle = Vector2.new(180, 180)
		motes.Acceleration = Vector3.new(0, 1.5, 0)
		motes.LightEmission = 0.6
		motes.Color = ColorSequence.new(Color3.fromRGB(look.motes[1], look.motes[2], look.motes[3]))
		motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		motes.Parent = anchor
		motes:Emit(24)
	end
	Debris:AddItem(anchor, 2.5)
end

-- The shovel cuts a bale open: it shudders, the twine snaps, the bale bursts into flakes, and the hay
-- pours out in three waves into a pile.
function Bales.breakOpen(player, b)
	if b.gone or b.carriedBy or b.breaking then
		return
	end
	b.breaking = true
	setUsable(b, false)
	Tutorial.mark(player, "broke")
	scheduleRegrow(b)

	task.spawn(function()
		local body = b.body
		body.Anchored = true
		body.AssemblyLinearVelocity = Vector3.zero
		local rest = body.CFrame
		for _ = 1, 6 do
			body.CFrame = rest * CFrame.new(rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.1, 0.1), rng:NextNumber(-0.2, 0.2))
			task.wait(0.04)
		end

		local center = rest.Position
		-- Which hay this bale holds (set by whoever placed it; meadow by default). Its strands carry it on.
		local hayType = b.body:GetAttribute("HayType") or "meadow"
		-- A rich field (WorldMap.luau) marks its bales with NeedleBoost: that many times the needles.
		local boost = b.body:GetAttribute("NeedleBoost") or 1
		local mutation = b.body:GetAttribute("MutationBoost") -- a Hay Market bale's mutation odds ride on its strands
		local wet = b.body:GetAttribute("Wet") == true -- a soaked bale spills soaked hay
		-- A golden field bale (1 in GoldenBaleOneIn) holds GoldenBaleNeedles times the needles on top of that.
		local golden = b.body:GetAttribute("GoldenField") == true
		if golden then
			boost *= Config.GoldenBaleNeedles
			Announce.say(("%s broke open a golden bale!"):format(player.DisplayName), "gold")
		end
		-- The play-together bonus only stacks up to Prices.Boosts.Cap (Boosts.fit, CEO H13); its strands keep the result.
		if b.body:GetAttribute("TogetherBoost") == true then
			local together = LandConfig.TogetherBonus or 1
			boost = Boosts.fit(BOOST_TERMS, boost / together, 1, together, 1)
		end
		Bales.consume(b)
		burstEffects(center + Vector3.new(0, 1.5, 0), hayType)
		Feedback.play("BaleBurst", center)
		Feedback.juice(player, "burst")
		Events.fire(player, "bale_broken", 1, { position = center, hayType = hayType })
		-- The first bale a player ever breaks always shows them a glinting needle: that is the hook.
		-- A sorted bale has had its needles taken out, so it spills none.
		local sorted = b.sorted == true
		local promiseNeedle = not sorted and Gloves.firstBaleBreak(player)

		local baleOwner = player.UserId
		-- The twine snaps and flies off, and the bale's packed hay bursts into flakes.
		for _, x in TWINE_X do
			debrisPart(
				Enum.PartType.Block,
				Vector3.new(0.12, 0.12, SIZE.Z + 0.5),
				rest * CFrame.new(x, SIZE.Y / 2, 0),
				TWINE,
				Enum.Material.Fabric,
				Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(10, 14), rng:NextNumber(-6, 6))
			)
		end
		for i = 1, 6 do
			local x = -SIZE.X / 2 + (i - 0.5) * SIZE.X / 6
			local flake = rest * CFrame.new(x, 0, 0)
			local out = (flake.Position - center).Unit
			debrisPart(
				Enum.PartType.Block,
				Vector3.new(SIZE.X / 6, SIZE.Y * 0.8, SIZE.Z * 0.8),
				flake,
				hayColor(hayType),
				Enum.Material.Fabric,
				out * rng:NextNumber(6, 10) + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(5, 9), rng:NextNumber(-2, 2))
			)
		end

		-- The hay pours out in waves so it looks like it spills, not like it teleports. It comes out in clumps of a few
		-- strands (Config.StrandsPerClump), every strand of the bale accounted for.
		local waves = 3
		local clumps = HayMath.clumps(Config.PiecesPerBale, Config.StrandsPerClump or 1)
		local perWave = math.ceil(#clumps / waves)
		for wave = 1, waves do
			for k = (wave - 1) * perWave + 1, math.min(wave * perWave, #clumps) do
				local offset = Vector3.new(rng:NextNumber(-1.2, 1.2), 2 + wave * 0.5, rng:NextNumber(-1.2, 1.2))
				local velocity = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(3, 8), rng:NextNumber(-4, 4))
				local piece = Hay.spawnPiece(center + offset, velocity, baleOwner, nil, hayType, clumps[k])
				piece:SetAttribute("HayType", hayType)
				if boost ~= 1 then
					piece:SetAttribute("NeedleBoost", boost)
				end
				if mutation then
					piece:SetAttribute("MutationBoost", mutation)
				end
				if sorted then
					piece:SetAttribute("Sorted", true)
				end
				if wet then
					Bales.wetPiece(piece)
				end
			end
			-- Now and then a needle tumbles out with the hay.
			if not sorted and (rng:NextNumber() < Config.VisibleNeedleChance * boost or (promiseNeedle and wave == waves)) then
				promiseNeedle = false
				local offset = Vector3.new(rng:NextNumber(-1, 1), 2 + wave * 0.5, rng:NextNumber(-1, 1))
				local needle = Hay.spawnPiece(
					center + offset,
					Vector3.new(rng:NextNumber(-3, 3), 5, rng:NextNumber(-3, 3)),
					baleOwner,
					"Needle",
					hayType
				)
				Feedback.needle(needle, Hay.needleValue(needle))
			end
			task.wait(0.22)
		end
		-- Once in a while something odd was baled up with the hay (Config/Finds).
		if not sorted then
			Finds.roll(center + Vector3.new(0, 2, 0), baleOwner)
		end
	end)
end

function Bales.pickup(player, b)
	local state = Data.get(player)
	local root = Avatar.getRoot(player)
	if not state or not root or b.gone or b.carriedBy or b.breaking then
		return
	end
	-- One bale in your arms, or two (one on top of the other) with Reinforced gloves or better.
	local second = state.carryBale ~= nil
	if second and (state.carryExtra or not Bales.canDoubleCarry(player)) then
		return
	end
	if Avatar.equippedKind(player) ~= nil then
		return -- only bare hands lift a whole bale; with a tool out, a click belongs to the tool
	end
	if (b.body.Position - root.Position).Magnitude > Config.PickupReach + 4 then
		return
	end

	b.carriedBy = player
	b.ownerId = b.ownerId or player.UserId -- the first to haul it keeps it, so nobody can lift another's bale to sell
	b.dropToken += 1
	if second then
		state.carryExtra = b
	else
		state.carryBale = b
	end

	-- The bale itself is welded in front of the player, so what you carry is the real bale. A second rides on top.
	local offset = second and CARRY_OFFSET * CFrame.new(0, SIZE.Y + 0.05, 0) or CARRY_OFFSET
	b.body.Anchored = false
	b.body.CanCollide = false
	b.body.Massless = true
	b.body.CFrame = root.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = b.body
	weld.C0 = offset
	weld.Parent = b.body
	b.carryWeld = weld
	b.prompt.ActionText = "Put down"

	scheduleRegrow(b)
	Feedback.play("BaleLift", b.body)
	Avatar.setCarry(player)
	Avatar.refreshSpeed(player) -- setCarry skips this when already carrying, and the second bale weighs too
	Data.sync(player)
end

-- True when this player's gloves are good enough to carry two bales at once (Config.DoubleCarryTier).
function Bales.canDoubleCarry(player)
	local glove = Gloves.get(player)
	return glove ~= nil and (glove.tier or 0) >= Config.DoubleCarryTier
end

-- Sets a bale down square to the player on top of whatever is in front: the ground, or another bale, so bales stack.
local function setDown(b, root)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local spot = root.Position + flat * (SIZE.Z / 2 + 2.2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { b.body, root.Parent, Hay.folder }
	local down = workspace:Raycast(spot + Vector3.new(0, Config.StackReach, 0), Vector3.new(0, -Config.StackReach - 20, 0), params)
	local floorY = down and down.Position.Y or (root.Position.Y - 3)
	local center = Vector3.new(spot.X, floorY + SIZE.Y / 2 + 0.05, spot.Z)
	b.body.CFrame = CFrame.lookAt(center, center + flat)
	b.body.Massless = false
	b.body.CanCollide = true
	b.body.Anchored = false
	b.body.AssemblyLinearVelocity = Vector3.zero
	b.body.AssemblyAngularVelocity = Vector3.zero
	b.prompt.ActionText = "Pick up"
	-- A set-down bale is a loose physical block: never welded or anchored, so it can ride in a truck bed and slide
	-- or tip like real cargo. Roblox picks its network owner automatically, so a bale in a moving truck follows the
	-- driver's physics instead of lagging behind.
	pcall(function()
		b.body:SetNetworkOwnershipAuto()
	end)
end

-- Lobs a bale forward from where it is held. power 0..1 sets the range, from a short toss to Config.TossRange studs
-- on flat ground. The bale flies loose with real physics and lands however it lands.
local function toss(b, root, power, lift)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	-- A 45 degree lob: speed for the range under this place's gravity, the same up and forward.
	local speed = HayMath.tossSpeed(power, Config, workspace.Gravity)
	b.body.Massless = false
	b.body.CanCollide = true
	b.body.Anchored = false
	b.body.CFrame = b.body.CFrame + Vector3.new(0, lift, 0)
	b.prompt.ActionText = "Pick up"
	-- The server flies it, so the throw is the same for everyone, then hands it back to Roblox once it has landed.
	pcall(function()
		b.body:SetNetworkOwner(nil)
	end)
	b.body.AssemblyLinearVelocity = flat * speed + Vector3.new(0, speed, 0) + root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	b.body.AssemblyAngularVelocity = root.CFrame.RightVector * -rng:NextNumber(1, 3)
	local token = b.dropToken
	task.delay(Config.TossFlightSeconds, function()
		if not b.gone and not b.carriedBy and b.dropToken == token and not b.body:GetAttribute("InTruck") then
			pcall(function()
				b.body:SetNetworkOwnershipAuto()
			end)
		end
	end)
end

-- Lets go of everything the player holds (the carried bale and a second on top). Returns the bales, bottom first,
-- or nil if a carried bale has gone away (then the player's hands are simply freed).
local function letGo(player, state)
	local held = {}
	for _, b in { state.carryBale, state.carryExtra } do
		if b and not b.gone then
			if b.carryWeld then
				b.carryWeld:Destroy()
				b.carryWeld = nil
			end
			b.carriedBy = nil
			table.insert(held, b)
		end
	end
	state.carryBale = nil
	state.carryExtra = nil
	Data.sync(player)
	Avatar.clearCarry(player)
	return held
end

-- Put the carried bale down in front of you. It lands square on the ground or on top of the bale there. A second
-- carried bale goes down on top of the first.
function Bales.drop(player)
	local state = Data.get(player)
	if not state or not state.carryBale then
		return
	end
	local root = Avatar.getRoot(player)
	for _, b in letGo(player, state) do
		if not root or not root.Parent then
			Bales.consume(b)
		else
			setDown(b, root)
			Feedback.play("BaleSetDown", b.body)
			startDespawnTimer(b)
		end
	end
end

-- Crew hand-offs. Set by whoever knows the farm crews (Land.luau, or Tools.luau's fallback):
-- function(thrower, catcher) -> true when catcher may catch thrower's bales.
Bales.isTeammate = nil

-- While a thrown bale is in the air, a bare-handed teammate it flies close to catches it (Config.CatchRadius), so a
-- crew can pass bales down a line into a truck bed.
function Bales.watchForCatch(b, thrower)
	if not Bales.isTeammate then
		return
	end
	local token = b.dropToken
	local started = os.clock()
	task.spawn(function()
		while os.clock() - started < Config.CatchWindowSeconds do
			task.wait()
			if b.gone or b.carriedBy or b.dropToken ~= token then
				return
			end
			-- Not in the thrower's own crew's hands at the very start: someone standing beside the thrower lets it fly.
			if os.clock() - started < 0.2 then
				continue
			end
			-- Landed and settled: too late to catch.
			if os.clock() - started > 0.3 and b.body.AssemblyLinearVelocity.Magnitude < 2 then
				return
			end
			for _, player in Players:GetPlayers() do
				if player ~= thrower then
					local root = Avatar.getRoot(player)
					if
						root
						and (root.Position - b.body.Position).Magnitude <= Config.CatchRadius
						and Bales.isTeammate(thrower, player)
					then
						local state = Data.get(player)
						local free = state and (not state.carryBale or (not state.carryExtra and Bales.canDoubleCarry(player)))
						if free and Avatar.equippedKind(player) == nil then
							Bales.pickup(player, b)
							if b.carriedBy == player then
								Feedback.play("BaleLift", b.body, 1.2)
								Events.fire(player, "bale_caught", 1, { from = thrower.UserId })
								return
							end
						end
					end
				end
			end
		end
	end)
end

-- Throw the carried bale(s) forward. power is 0..1 from how long the throw was charged. A tiny power (a plain click)
-- just sets the bale down instead.
function Bales.toss(player, power)
	local state = Data.get(player)
	if not state or not state.carryBale then
		return
	end
	power = typeof(power) == "number" and power == power and math.clamp(power, 0, 1) or 0
	local root = Avatar.getRoot(player)
	if not root or power < Config.TossMinPower then
		Bales.drop(player)
		return
	end
	for i, b in letGo(player, state) do
		toss(b, root, power, (i - 1) * 0.2)
		Feedback.play("BaleLift", b.body, 0.8)
		startDespawnTimer(b)
		Bales.watchForCatch(b, player)
	end
end

-- Loads a bale into something the player moves (a wheelbarrow): welded to anchor at offset, out of play until
-- released. Returns true if it was loaded.
function Bales.stow(player, b, anchor, offset)
	if b.gone or b.carriedBy or b.breaking then
		return false
	end
	b.carriedBy = player
	b.ownerId = b.ownerId or player.UserId -- the first to haul it keeps it, so nobody can lift another's bale to sell
	b.dropToken += 1
	setUsable(b, false)
	b.body.Anchored = false
	b.body.CanCollide = false
	b.body.CanQuery = false -- so bales set down from the same barrow stack on the ground, not on this one
	b.body.Massless = true
	b.body.CFrame = anchor.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = anchor
	weld.Part1 = b.body
	weld.C0 = offset
	weld.Parent = b.body
	b.carryWeld = weld
	scheduleRegrow(b)
	Feedback.play("BaleLift", b.body)
	return true
end

-- Takes a stowed bale out and drops it loose at cframe (into a truck bed, say), with real physics from there.
function Bales.releaseAt(b, cframe)
	if b.gone then
		return
	end
	if b.carryWeld then
		b.carryWeld:Destroy()
		b.carryWeld = nil
	end
	b.carriedBy = nil
	setUsable(b, true)
	b.body.CFrame = cframe
	b.body.Massless = false
	b.body.CanCollide = true
	b.body.CanQuery = true
	b.body.Anchored = false
	b.body.AssemblyLinearVelocity = Vector3.zero
	b.body.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		b.body:SetNetworkOwnershipAuto()
	end)
	Feedback.play("BaleSetDown", b.body)
	startDespawnTimer(b)
end

-- Takes a stowed bale out and sets it down in front of the player (or gets rid of it if the player is gone).
function Bales.release(b, root)
	if b.gone then
		return
	end
	if b.carryWeld then
		b.carryWeld:Destroy()
		b.carryWeld = nil
	end
	b.carriedBy = nil
	setUsable(b, true)
	if not root or not root.Parent then
		Bales.consume(b)
		return
	end
	setDown(b, root)
	b.body.CanQuery = true
	Feedback.play("BaleSetDown", b.body)
	startDespawnTimer(b)
end

-- Fields grow loose hay, never bales: a home spot gets a field pile (Hay.spawnFieldPile) that grows back
-- Config.BaleRefillSeconds after it is cleared. The record has the fields callers use on a home bale (body, hayType,
-- home, onRegrow), so a region can tint it, boost it and hear about the regrow; b.field marks it as a pile, and
-- b.noRegrow = true stops it growing back.
local function spawnFieldPile(position, fadeIn, hayType)
	local b = { hayType = hayType, home = true, field = true, spawnPosition = position }
	b.body = Hay.spawnFieldPile(position, hayType, function()
		if b.noRegrow then
			return -- set by whoever takes the field away for good (a self-test)
		end
		task.delay(Config.BaleRefillSeconds, function()
			if folder and folder.Parent then
				local fresh = spawnFieldPile(position, true, hayType)
				if b.onRegrow then
					b.onRegrow(fresh)
				end
			end
		end)
	end)
	-- Now and then a field grows a golden pile: it glints, and holds Config.GoldenBaleNeedles times the needles.
	if rng:NextInteger(1, Config.GoldenBaleOneIn) == 1 then
		Bales.makeGolden(b, fadeIn)
	end
	if fadeIn then
		local shown = b.body.Transparency
		b.body.Transparency = 1
		TweenService:Create(b.body, TweenInfo.new(0.7), { Transparency = shown }):Play()
	end
	return b
end

-- position is the ground point under the bale. home is a field's own spot: it grows a hay pile there instead of a
-- bale (spawnFieldPile above), which grows back once cleared. hayType is a Config/Gloves hay (meadow when nil). Set
-- b.onRegrow(fresh) to hear about the pile that grows back.
function Bales.spawn(position, home, fadeIn, hayType)
	if home then
		return spawnFieldPile(position, fadeIn, hayType)
	end
	local body, prompt = buildBale(position, hayType)
	local b = {
		hayType = hayType,
		body = body,
		prompt = prompt,
		home = home,
		spawnPosition = position,
		carriedBy = nil,
		ownerId = nil,
		carryWeld = nil,
		dropToken = 0,
		breaking = false,
		gone = false,
	}
	byBody[body] = b
	body.Parent = folder

	if fadeIn then
		local info = TweenInfo.new(0.7)
		for _, part in { body, unpack(body:GetDescendants()) } do
			if part:IsA("BasePart") and part.Transparency < 1 then
				local shown = part.Transparency
				part.Transparency = 1
				TweenService:Create(part, info, { Transparency = shown }):Play()
			end
		end
	end

	prompt.Triggered:Connect(function(player)
		if b.carriedBy == player then
			Bales.drop(player)
		elseif not b.carriedBy then
			Bales.pickup(player, b)
		end
	end)
	return b
end

-- Turns a bale golden: gold twine-wrapped hay with a glint and a soft glow, named in its button. announce tells the
-- server one has grown (left off for the bales placed when the world is built, so the start isn't a flood).
function Bales.makeGolden(b, announce)
	local body = b.body
	body:SetAttribute("GoldenField", true)
	body.Color = Color3.fromRGB(222, 182, 72)
	body.Material = Enum.Material.Fabric
	for _, d in body:GetDescendants() do
		if d:IsA("MeshPart") or (d:IsA("BasePart") and d.Name ~= "Twine") then
			pcall(function()
				d.Color = Color3.fromRGB(222, 182, 72)
			end)
		elseif d:IsA("SpecialMesh") then
			d.VertexColor = Vector3.new(1.25, 1.05, 0.45)
		end
	end
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(255, 226, 130)
	sparkles.Parent = body
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 214, 120)
	light.Brightness = 1.2
	light.Range = 10
	light.Parent = body
	if b.prompt then
		b.prompt.ObjectText = "Golden " .. (b.prompt.ObjectText ~= "" and b.prompt.ObjectText or "bale")
	end
	if announce then
		local hay = GloveConfig.HayTypes[b.hayType or "meadow"]
		Announce.say(
			("A golden %s has grown in the %s fields!"):format(b.field and "hay pile" or "bale", hay and hay.map or "Meadow"),
			"gold"
		)
	end
end

-- Wet hay (Config.WetWeather). A wet bale is darker and drips; its weight (Gloves) and price (Gameplay) follow the
-- Wet attribute.
local WET_DARKEN = 0.62

local function tintAll(body, factor)
	for _, d in { body, unpack(body:GetDescendants()) } do
		if d:IsA("BasePart") and d.Name ~= "Twine" then
			local base = d:GetAttribute("DryColor")
			if factor < 1 then
				if not base then
					d:SetAttribute("DryColor", d.Color)
					base = d.Color
				end
				d.Color = Color3.new(base.R * factor, base.G * factor, base.B * factor)
			elseif base then
				d.Color = base
				d:SetAttribute("DryColor", nil)
			end
		end
	end
end

-- Soaks a bale: heavier, worth less, darker, and dripping until it dries.
function Bales.wet(b)
	if b.gone or b.body:GetAttribute("Wet") then
		return false
	end
	b.body:SetAttribute("Wet", true)
	b.dryFor = 0
	tintAll(b.body, WET_DARKEN)
	local drips = Instance.new("ParticleEmitter")
	drips.Name = "WetDrips"
	drips.Rate = 6
	drips.Lifetime = NumberRange.new(0.4, 0.7)
	drips.Speed = NumberRange.new(0, 0.5)
	drips.Acceleration = Vector3.new(0, -30, 0)
	drips.EmissionDirection = Enum.NormalId.Bottom
	drips.Size = NumberSequence.new(0.08)
	drips.Color = ColorSequence.new(Color3.fromRGB(170, 190, 210))
	drips.Transparency = NumberSequence.new(0.3, 1)
	drips.Parent = b.body
	return true
end

-- Dries a wet bale (the sun, or Conveyor's drying rack). Returns true if it was wet.
function Bales.dry(b)
	if b.gone or not b.body:GetAttribute("Wet") then
		return false
	end
	b.body:SetAttribute("Wet", nil)
	b.rainFor, b.dryFor = 0, 0
	tintAll(b.body, 1)
	local drips = b.body:FindFirstChild("WetDrips")
	if drips then
		drips:Destroy()
	end
	return true
end

-- Marks a loose strand as wet (spilled from a wet bale, or poured from a wet load).
function Bales.wetPiece(piece)
	piece:SetAttribute("Wet", true)
	local c = piece.Color
	piece.Color = Color3.new(c.R * WET_DARKEN, c.G * WET_DARKEN, c.B * WET_DARKEN)
end

-- Whether rain falls on this spot: its region is in wet weather and nothing overhead shelters it.
local skyParams = RaycastParams.new()
skyParams.FilterType = Enum.RaycastFilterType.Exclude
function Bales.rainingOn(position, ignore)
	local region = WorldRegions.at(position)
	if not region or not Config.WetWeather[Weather.get(region.id)] then
		return false
	end
	skyParams.FilterDescendantsInstances = ignore
	return workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, 120, 0), skyParams) == nil
end

-- Every few seconds: bales out in the rain soak, wet bales out of it dry.
local WEATHER_TICK = 5
local function weatherTick()
	local ignore = { folder, Hay.folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, b in byBody do
		if not b.gone and not b.carriedBy and not b.breaking and b.body.Parent then
			if Bales.rainingOn(b.body.Position, ignore) then
				b.dryFor = 0
				b.rainFor = (b.rainFor or 0) + WEATHER_TICK
				if b.rainFor >= Config.WetSoakSeconds then
					Bales.wet(b)
				end
			else
				b.rainFor = 0
				if b.body:GetAttribute("Wet") then
					b.dryFor = (b.dryFor or 0) + WEATHER_TICK
					if b.dryFor >= Config.WetDrySeconds then
						Bales.dry(b)
					end
				end
			end
		end
	end
end

-- The "Stack N" label over the top of a neat stack.
local function stackLabel(top, n)
	local gui = top.body:FindFirstChild("StackLabel")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "StackLabel"
		gui.Size = UDim2.fromOffset(90, 28)
		gui.StudsOffset = Vector3.new(0, SIZE.Y / 2 + 1.2, 0)
		gui.MaxDistance = 50
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.TextColor3 = Color3.fromRGB(240, 214, 140)
		text.TextStrokeTransparency = 0.4
		text.Parent = gui
		gui.Parent = top.body
	end
	gui.Text.Text = ("Stack %d"):format(n)
end

-- Finds neat stacks: bales resting one on another, square on top within a stud or so. Every bale in a stack of
-- Config.StackMin or more is marked inStack (kept, see startDespawnTimer) and the top one shows the count.
local function scanStacks()
	local list = {}
	for _, b in byBody do
		if not b.gone and not b.carriedBy and not b.breaking and b.body.Parent then
			b.wasInStack, b.inStack = b.inStack, false
			table.insert(list, b)
		end
	end
	table.sort(list, function(a, c)
		return a.body.Position.Y < c.body.Position.Y
	end)
	local columns = {}
	for _, b in list do
		local p = b.body.Position
		local placed = false
		for _, column in columns do
			local top = column[#column].body.Position
			local flat = Vector3.new(p.X - top.X, 0, p.Z - top.Z).Magnitude
			if flat < 1.4 and math.abs(p.Y - top.Y - SIZE.Y) < 0.6 then
				table.insert(column, b)
				placed = true
				break
			end
		end
		if not placed then
			table.insert(columns, { b })
		end
	end
	for _, column in columns do
		local neat = #column >= Config.StackMin
		for _, b in column do
			b.inStack = neat
		end
		if neat then
			stackLabel(column[#column], #column)
		end
	end
	for _, b in list do
		local label = b.body:FindFirstChild("StackLabel")
		local isTop = false
		if b.inStack then
			for _, column in columns do
				if column[#column] == b then
					isTop = true
				end
			end
		end
		if label and not isTop then
			label:Destroy()
		end
		-- A bale that just left a stack starts its normal countdown again.
		if b.wasInStack and not b.inStack and not b.home then
			startDespawnTimer(b)
		end
		b.wasInStack = nil
	end
end

-- A bale does not stay stuck to a player who left the game: whatever they held goes, and their hands are free.
function Bales.playerLeft(player)
	for _, b in byBody do
		if b.carriedBy == player and not b.gone then
			Bales.consume(b)
		end
	end
	local state = Data.get(player)
	if state then
		state.carryBale = nil
		state.carryExtra = nil
	end
end

function Bales.init(worldFolder)
	folder = worldFolder

	task.spawn(function()
		while true do
			task.wait(WEATHER_TICK)
			local ok, err = pcall(weatherTick)
			if not ok then
				warn("[Needlewood] wet bales: " .. tostring(err))
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(scanStacks)
			if not ok then
				warn("[Needlewood] bale stacks: " .. tostring(err))
			end
		end
	end)

	local function watch(player)
		local function onCharacter(character)
			local humanoid = character:WaitForChild("Humanoid")
			humanoid.Died:Connect(function()
				Bales.drop(player)
			end)
		end
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			task.spawn(onCharacter, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	Players.PlayerRemoving:Connect(Bales.playerLeft)
end

return Bales

end

MODULES["Services.Finds"] = function(script)
-- Foreign objects that tumble out of a burst bale now and then (Config/Finds). A find is a real part on the ground;
-- click it to keep it. Kept finds are counted per save slot (state.finds) and published as the player attribute
-- "Finds" ("boot:2,ring:1") for the collection book. The first of each kind a slot ever finds pays its finder's
-- reward, once: state.findsPaid remembers it, so trading the find away and finding another never pays again (and a
-- find received in a trade pays nothing; the receiver is paid only when they find one themselves).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local FindsConfig = require(ReplicatedStorage.Shared.Config.Finds)
local Data = require(script.Parent.Data)
local Bank = require(script.Parent.Bank)
local Announce = require(script.Parent.Announce)
local Feedback = require(script.Parent.Feedback)
local Groups = require(script.Parent.Groups)
local Props = require(script.Parent.Props)

local Finds = {}

local rng = Random.new()
local byId = {}
for _, def in FindsConfig.Items do
	byId[def.id] = def
end
-- Rarest first, so one roll per bale gives each item its own odds.
local rarestFirst = table.clone(FindsConfig.Items)
table.sort(rarestFirst, function(a, b)
	return a.oneIn > b.oneIn
end)

local function publish(player)
	local state = Data.get(player)
	local list = {}
	for id, count in (state and state.finds or {}) do
		table.insert(list, ("%s:%d"):format(id, count))
	end
	table.sort(list)
	player:SetAttribute("Finds", table.concat(list, ","))
end

local function keep(player, part, def)
	local state = Data.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not state or not root or not part.Parent then
		return
	end
	if (part.Position - root.Position).Magnitude > FindsConfig.PickupReach + 2 then
		return
	end
	-- The find is the bale breaker's for a while, so nobody nearby can grab it (and its one-time reward) first.
	local ownerId = part:GetAttribute("OwnerId")
	local claimUntil = part:GetAttribute("ClaimUntil")
	if ownerId and ownerId ~= player.UserId and claimUntil and workspace:GetServerTimeNow() < claimUntil then
		Data.toast(player, "Someone else broke that bale. Their find is theirs for now.")
		return
	end
	part:Destroy()
	state.finds = state.finds or {}
	state.findsPaid = state.findsPaid or {}
	local first = not state.findsPaid[def.id]
	if first then
		state.findsPaid[def.id] = 1
	end
	state.finds[def.id] = (state.finds[def.id] or 0) + 1
	publish(player)
	Feedback.needle(root, def.reward * 2)
	if first then
		Bank.earn(player, def.reward, "Finder's reward")
		Feedback.sale(player, def.reward)
		Data.toast(player, ("New find: %s! +$%d"):format(def.name, def.reward))
		if def.oneIn >= 1000 then
			Announce.say(("%s found a %s!"):format(player.DisplayName, def.name:lower()), "gold")
		end
	else
		Data.toast(player, ("%s (you have %d)"):format(def.name, state.finds[def.id]))
	end
end

local function spawnFind(def, position, velocity, ownerId)
	local part = Instance.new("Part")
	part.Name = "Find_" .. def.id
	part.Size = Vector3.new(def.size[1], def.size[2], def.size[3])
	part.Color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	part.Material = Enum.Material[def.material] or Enum.Material.SmoothPlastic
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	part.CollisionGroup = Groups.Loose
	part.AssemblyLinearVelocity = velocity
	part:SetAttribute("FindId", def.id)
	if ownerId then
		part:SetAttribute("OwnerId", ownerId)
		part:SetAttribute("ClaimUntil", workspace:GetServerTimeNow() + (FindsConfig.OwnerSeconds or 60))
	end

	-- Catches the eye like a needle does.
	local glint = Instance.new("Sparkles")
	glint.SparkleColor = Color3.fromRGB(255, 240, 200)
	glint.Parent = part

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = FindsConfig.PickupReach
	click.MouseClick:Connect(function(player)
		keep(player, part, def)
	end)
	click.Parent = part

	local model = def.prop and Props.has(def.prop) and Props.make(def.prop, part.CFrame, math.max(part.Size.X, part.Size.Y, part.Size.Z))
	if model then
		Props.weldTo(model, part, part)
	end
	part.Parent = workspace
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	Debris:AddItem(part, FindsConfig.DespawnSeconds)
	return part
end

-- One roll for a burst bale. Returns the find part, or nil when nothing turned up. ownerId (whoever broke the bale)
-- alone can keep it for FindsConfig.OwnerSeconds.
function Finds.roll(position, ownerId)
	for _, def in rarestFirst do
		if rng:NextInteger(1, def.oneIn) == 1 then
			return spawnFind(def, position, Vector3.new(rng:NextNumber(-3, 3), 7, rng:NextNumber(-3, 3)), ownerId)
		end
	end
	return nil
end

function Finds.info(id)
	return byId[id]
end

-- Saves from before findsPaid: every kind already on the shelf has been paid for.
local function onLoaded(player)
	local state = Data.get(player)
	if state then
		state.findsPaid = state.findsPaid or {}
		for id, count in state.finds or {} do
			if count > 0 then
				state.findsPaid[id] = 1
			end
		end
	end
	publish(player)
end

-- Test hook (SelfTests/HayTools): keeps a find as if the player clicked it, with no reach check or part. claimedBy
-- (a UserId) makes it a find someone else broke out of a bale a moment ago.
function Finds.keepForTest(player, id, claimedBy)
	local def = byId[id]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not def or not root then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.Transparency = 1
	part.CanCollide = false
	part.Position = root.Position
	if claimedBy then
		part:SetAttribute("OwnerId", claimedBy)
		part:SetAttribute("ClaimUntil", workspace:GetServerTimeNow() + (FindsConfig.OwnerSeconds or 60))
	end
	part.Parent = workspace
	keep(player, part, def)
	if part.Parent then
		part:Destroy() -- not kept: the test leaves nothing lying around
	end
end

function Finds.init()
	Data.loaded.Event:Connect(onLoaded)
	for _, player in Players:GetPlayers() do
		if Data.get(player) then
			publish(player)
		end
	end
end

return Finds

end

-- Fuzz of the hand loop, offline: the real Bales.luau, Hay.luau and Finds.luau (bundled by run.py with mapcheck's
-- mock), with a few fake players doing random things in a random order: lift (one or two bales), set down, throw,
-- barrow-style stow and release, leave the game and come back, bales consumed and spawned, loose hay spilled, finds
-- kept and traded away. After every step it checks:
--   no stuck bales      a bale is carried by a player exactly when that player's hands (or barrow) hold it, and a bale
--                        nobody holds is free physics (no carry weld, not massless, its button usable)
--   no orphaned owner   a bale's owner, once set, never changes, and a gone bale is gone everywhere
--   the loose caps hold loose strands and needles never pass MaxLoosePieces / MaxLooseNeedles
--   nothing pays twice  a finder's reward is paid at most once per kind per slot, whatever is traded
-- Physics (where a bale lands) is not simulated; this is about the bookkeeping.

-- More of the Roblox API than the map build needs ------------------------------------------------------------------
OverlapParams = { new = function() return {} end }
RaycastParams = { new = function() return {} end }
NumberSequence = { new = function(...) return { ... } end }
NumberSequenceKeypoint = { new = function(...) return { ... } end }
ColorSequence = { new = function(...) return { ... } end }
NumberRange = { new = function(...) return { ... } end }
TweenInfo = { new = function(...) return { ... } end }
workspace.Raycast = function() return nil end
workspace.GetPartBoundsInBox = function() return {} end
workspace.GetPartBoundsInRadius = function() return {} end
workspace.Gravity = 196.2
do
	-- Parts tell Hay when they are destroyed; here the hook is simply there.
	local mt = getmetatable(Instance.new("Part"))
	local index = mt.__index
	mt.__index = function(o, k)
		if k == "Destroying" or k == "MouseClick" then
			return { Connect = function() return { Disconnect = function() end } end }
		end
		if k == "Emit" or k == "SetNetworkOwner" then
			return function() end
		end
		if k == "AssemblyLinearVelocity" or k == "AssemblyAngularVelocity" then
			return rawget(o, "_props")[k] or Vector3.zero
		end
		return index(o, k)
	end
end

-- Fake services around the real modules -----------------------------------------------------------------------------
local states = {} -- player -> save state (nil while they are away)
local roots = {} -- player -> HumanoidRootPart
local gloveTier = {} -- player -> 0..5
local earned = {} -- player -> { [findId] = times paid }
local paidFinds = {}

MODULES["Services.Data"] = function()
	return {
		get = function(player) return states[player] end,
		sync = function() end,
		toast = function() end,
		save = function() end,
		loaded = { Event = { Connect = function() end } },
	}
end
MODULES["Services.Avatar"] = function()
	return {
		getRoot = function(player) return roots[player] end,
		equippedKind = function() return nil end,
		setCarry = function() end,
		clearCarry = function() end,
		refreshSpeed = function() end,
	}
end
MODULES["Services.Gloves"] = function()
	local Gloves = require({ __path = "Shared.Config.Gloves" })
	return {
		get = function(player) return Gloves.Tiers[(gloveTier[player] or 0) + 1] end,
		firstBaleBreak = function() return false end,
		baleWeight = function() return 1, 0 end,
	}
end
MODULES["Services.Bank"] = function()
	return {
		earn = function(player, amount, note)
			if note == "Finder's reward" then
				table.insert(paidFinds, player)
			end
			return amount, 0
		end,
	}
end
MODULES["Services.Needle"] = function()
	return {
		make = function(cframe, ownerId)
			local p = Instance.new("Part")
			p.Name = "Needle"
			p.CFrame = cframe
			p:SetAttribute("Needle", true)
			p:SetAttribute("OwnerId", ownerId)
			return p
		end,
		isNeedle = function(part) return part:GetAttribute("Needle") == true end,
		value = function() return 1 end,
	}
end
MODULES["Services.Weather"] = function() return { get = function() return "clear" end } end
MODULES["Shared.WorldRegions"] = function() return { at = function() return nil end } end
MODULES["Services.Props"] = function() return { has = function() return false end, make = function() return nil end, weldTo = function() end } end
for _, name in { "Groups", "Tutorial", "Feedback", "Events", "Announce" } do
	MODULES["Services." .. name] = function()
		return setmetatable({ Loose = "Loose" }, { __index = function() return function() end end })
	end
end

local Game = require({ __path = "Shared.Config.Game" })
local Hay = require({ __path = "Services.Hay" })
Hay.init(workspace)
local Bales = require({ __path = "Services.Bales" })
local folder = Instance.new("Folder")
folder.Parent = workspace
Bales.init(folder)
local Finds = require({ __path = "Services.Finds" })
local FindsConfig = require({ __path = "Shared.Config.Finds" })

-- The run ---------------------------------------------------------------------------------------------------------------
local rng = Random.new(tonumber(os.getenv and os.getenv("HAY_FUZZ_SEED") or "") or 1234)
local STEPS = 20000
local failed, passed = 0, 0
local firstFail = nil
local function check(name, ok)
	if ok then
		passed += 1
	else
		failed += 1
		if failed <= 20 then
			print("FAIL " .. name)
		end
		firstFail = firstFail or name
	end
end

local players = {}
for i = 1, 4 do
	local character = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(i * 20, 3, 0)
	root.Parent = character
	character.Parent = workspace
	local attributes = {}
	local player = {
		Name = "Fuzz" .. i,
		DisplayName = "Fuzz" .. i,
		UserId = 1000 + i,
		Character = character,
		SetAttribute = function(_, k, v) attributes[k] = v end,
		GetAttribute = function(_, k) return attributes[k] end,
		FindFirstChild = function() return nil end,
		FindFirstChildOfClass = function() return nil end,
	}
	players[i] = player
	roots[player] = root
end
local saved = {} -- player -> what Data saved when they left (finds and findsPaid survive a rejoin)
local function join(player)
	local old = saved[player]
	states[player] = { loadHay = 0, loadNeedles = 0, finds = old and old.finds or {}, findsPaid = old and old.findsPaid or {} }
end
for _, p in players do
	join(p)
end

local bales = {} -- every bale record ever spawned
local firstOwner = {} -- bale -> the first ownerId it had
local stowed = {} -- bale -> player (barrow)
local function spawnBale()
	local p = players[rng:NextInteger(1, #players)]
	local at = roots[p] and roots[p].Position or Vector3.new(0, 0, 0)
	local b = Bales.spawn(at + Vector3.new(rng:NextNumber(-3, 3), -3, rng:NextNumber(-3, 3)), false, false, "meadow")
	table.insert(bales, b)
	return b
end
for _ = 1, 12 do
	spawnBale()
end
local function anyBale()
	return bales[rng:NextInteger(1, #bales)]
end
-- Mostly a live bale within the player's reach (so lifts happen), sometimes any bale at all (gone, held, far).
local function baleFor(player)
	local root = roots[player]
	if root and rng:NextNumber() < 0.8 then
		local near = {}
		for _, b in bales do
			if not b.gone and (b.body.Position - root.Position).Magnitude <= Game.PickupReach then
				table.insert(near, b)
			end
		end
		if #near > 0 then
			return near[rng:NextInteger(1, #near)]
		end
	end
	return anyBale()
end
local function liveCount()
	local n = 0
	for _, b in bales do
		if not b.gone then
			n += 1
		end
	end
	return n
end
local function anyPlayer()
	return players[rng:NextInteger(1, #players)]
end

local heldBefore, extraBefore = {}, {}
local seen = { lifts = 0, doubles = 0, stows = 0, paid = 0, gone = 0 }
local function invariants(step)
	for _, b in bales do
		if b.gone then
			check(("step %d: a gone bale is forgotten"):format(step), Bales.fromPart(b.body) == nil)
		else
			local holder = b.carriedBy
			if holder then
				local s = states[holder]
				local inHands = s and (s.carryBale == b or s.carryExtra == b)
				check(("step %d: a carried bale is in its carrier's hands or barrow"):format(step), inHands or stowed[b] == holder)
				check(("step %d: a carried bale is welded to its carrier"):format(step), b.carryWeld ~= nil)
			else
				check(("step %d: a free bale has no carry weld"):format(step), b.carryWeld == nil)
				check(("step %d: a free bale is not massless"):format(step), b.body.Massless ~= true)
				check(("step %d: nobody's barrow holds a free bale"):format(step), stowed[b] == nil)
			end
			if b.ownerId ~= nil then
				firstOwner[b] = firstOwner[b] or b.ownerId
				check(("step %d: a bale's owner never changes"):format(step), b.ownerId == firstOwner[b])
			end
		end
	end
	for player, s in states do
		if s.carryBale and s.carryBale ~= heldBefore[player] then
			seen.lifts += 1
		end
		if s.carryExtra and s.carryExtra ~= extraBefore[player] then
			seen.doubles += 1
		end
		heldBefore[player], extraBefore[player] = s.carryBale, s.carryExtra
		if s.carryBale then
			check(("step %d: hands hold a live bale"):format(step), not s.carryBale.gone)
			check(("step %d: the bale in hand knows its carrier"):format(step), s.carryBale.carriedBy == player)
		end
		check(("step %d: a second bale only on top of a first"):format(step), s.carryExtra == nil or (s.carryBale ~= nil and s.carryExtra ~= s.carryBale))
		if s.carryExtra then
			check(("step %d: the second bale knows its carrier"):format(step), s.carryExtra.carriedBy == player and not s.carryExtra.gone)
		end
	end
	local stats = Hay.stats()
	check(("step %d: loose strands within the cap"):format(step), stats.strands <= Game.MaxLoosePieces)
	check(("step %d: loose needles within the cap"):format(step), stats.needles <= Game.MaxLooseNeedles)
	check(("step %d: every loose piece is counted"):format(step), stats.tracked == stats.strands + stats.needles)
end

local findIds = {}
for _, item in FindsConfig.Items do
	table.insert(findIds, item.id)
end

for step = 1, STEPS do
	local action = rng:NextInteger(1, 13)
	local p = anyPlayer()
	if action <= 3 then
		if states[p] then
			Bales.pickup(p, baleFor(p))
		end
	elseif action == 4 then
		if states[p] then
			Bales.drop(p)
		end
	elseif action == 5 then
		if states[p] then
			Bales.toss(p, rng:NextNumber())
		end
	elseif action == 6 then
		-- Barrow: stow a bale, or tip one back out.
		local b = baleFor(p)
		if states[p] and Bales.stow(p, b, roots[p], CFrame.new(0, 1, -3)) then
			stowed[b] = p
			seen.stows += 1
		end
		for other, owner in stowed do
			if owner == p and rng:NextNumber() < 0.5 then
				stowed[other] = nil
				if rng:NextNumber() < 0.5 then
					Bales.release(other, roots[p])
				else
					Bales.releaseAt(other, CFrame.new(0, 5, 0))
				end
			end
		end
	elseif action == 7 then
		-- Leave the game (what is held goes away, as the barrow's unload would), then maybe come back.
		if states[p] then
			for b, owner in stowed do
				if owner == p then
					stowed[b] = nil
					Bales.release(b, nil)
				end
			end
			Bales.playerLeft(p)
			saved[p] = states[p]
			states[p] = nil
		else
			join(p)
		end
	elseif action == 8 then
		-- A sell pad or machine takes a bale now and then.
		local b = anyBale()
		if not b.carriedBy and rng:NextNumber() < 0.25 then
			Bales.consume(b)
		end
	elseif action == 9 then
		-- Field regrowth, kept to about forty bales standing.
		if liveCount() < 40 then
			spawnBale()
		end
	elseif action == 10 then
		gloveTier[p] = rng:NextInteger(0, 5)
	elseif action == 11 then
		-- A spill of loose hay (and the odd needle), as a burst bale makes.
		for _ = 1, rng:NextInteger(10, 120) do
			Hay.spawnPiece(Vector3.new(rng:NextNumber(-50, 50), 1, rng:NextNumber(-50, 50)), Vector3.zero, p.UserId, rng:NextNumber() < 0.05 and "Needle" or nil, "meadow", rng:NextInteger(1, 3))
		end
	elseif action == 12 then
		-- Keep a find.
		if states[p] then
			local id = findIds[rng:NextInteger(1, #findIds)]
			local before = #paidFinds
			Finds.keepForTest(p, id)
			if #paidFinds > before then
				seen.paid += 1
				earned[p] = earned[p] or {}
				earned[p][id] = (earned[p][id] or 0) + 1
				check(("step %d: a find's reward pays once per kind"):format(step), earned[p][id] == 1)
			end
		end
	elseif action == 13 then
		-- Trade a find away (Trade.luau takes it off the shelf).
		local s = states[p]
		if s and s.finds then
			for id, count in s.finds do
				if count > 0 and rng:NextNumber() < 0.5 then
					s.finds[id] = count - 1
				end
			end
		end
	end
	invariants(step)
end

-- The part budget (Hay #24): a crew breaks ten bales at once. Count the parts and the strands they hold, with
-- clumps (Config.StrandsPerClump) and with single strands, and check the clumps keep every strand under the cap.
local function burstTen(perClump)
	for _, piece in Hay.folder:GetChildren() do
		Hay.remove(piece)
	end
	local keep = Game.StrandsPerClump
	Game.StrandsPerClump = perClump
	local spawn = task.spawn
	task.spawn = function(fn, ...)
		fn(...)
	end
	local breaker = players[1]
	states[breaker] = states[breaker] or { loadHay = 0, loadNeedles = 0, finds = {}, findsPaid = {} }
	for _ = 1, 10 do
		Bales.breakOpen(breaker, spawnBale())
	end
	task.spawn = spawn
	Game.StrandsPerClump = keep
	local parts, strands = 0, 0
	for _, piece in Hay.folder:GetChildren() do
		if Hay.isPiece(piece) and not Hay.isNeedle(piece) then
			parts += 1
			strands += Hay.strandsIn(piece)
		end
	end
	return parts, strands
end
local singleParts, singleStrands = burstTen(1)
local clumpParts, clumpStrands = burstTen(Game.StrandsPerClump)
local want = 10 * Game.PiecesPerBale
print(("ten bales at once: single strands %d parts holding %d of %d strands; clumps of %d: %d parts holding %d"):format(
	singleParts, singleStrands, want, Game.StrandsPerClump, clumpParts, clumpStrands))
check("ten bales of clumps fit the loose cap", clumpParts <= Game.MaxLoosePieces)
check("ten bales of clumps lose no hay", clumpStrands == want)
check("clumps cut the parts to a third or less", clumpParts * Game.StrandsPerClump <= want)

for _, b in bales do
	if b.gone then
		seen.gone += 1
	end
end
print(("exercised: %d lifts, %d double carries, %d barrow stows, %d finds paid, %d bales gone"):format(seen.lifts, seen.doubles, seen.stows, seen.paid, seen.gone))
-- A run that never lifts, doubles, stows or pays proves nothing: count it as a failure.
check("the fuzz lifted bales", seen.lifts > 100)
check("the fuzz double-carried", seen.doubles > 10)
check("the fuzz used the barrow", seen.stows > 10)
check("the fuzz paid finds", seen.paid > 0)
print(("hand loop fuzz: %d steps, %d bales, %d checks passed, %d failed"):format(STEPS, #bales, passed, failed))
if failed > 0 then
	error("hand loop fuzz failed first at: " .. tostring(firstFail))
end
