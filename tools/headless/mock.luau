-- Headless Roblox: a stand-in for the Roblox engine API, honest enough to boot the whole Needlewood server in the
-- plain luau CLI. See README.md. Rules this file follows:
--   * Behave the way the Roblox docs say, including the errors Roblox throws (wrong property type, unknown member,
--     locked Parent, FireClient without a Player, DataStore values that can't be stored...). A mock that is kinder
--     than Roblox hides bugs; a mock that is harsher invents them.
--   * Anything not mocked fails loudly with "MOCK MISSING: <Class>.<member>". Never return nil for an unknown member.
--   * No physics, no rendering, no network. Time is simulated (H.advance) and threads run on a small scheduler.

H = {} -- harness state and API, used by scenario.luau
H.errors = {} -- { { message, trace, count } }
H.errorIndex = {}
H.warnings = {}
H.notes = {}
H.created = {} -- class -> count
H.createdTotal = 0
H.now = 0 -- simulated seconds since server start
H.frame = 0
H.dt = 1 / 30
H.verbose = false

-- Luau compiles `typeof(x)` in every chunk as a fast built-in call while the global environment is "safe", so game
-- modules (loadstring chunks that don't assign typeof themselves) would skip our typeof below and see "table" for a
-- Vector3. getfenv marks the environment unsafe, which makes every chunk look the global up like Roblox code does.
getfenv(1)
local realClock = os.clock
local realTime = os.time
local EPOCH = 1760000000 -- os.time() at simulated t = 0
local frameRealStart = realClock()

local function fmt(...)
	local n = select("#", ...)
	local parts = table.create(n)
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

-- Errors ------------------------------------------------------------------------------------------------------------
-- Turns a traceback into the lines that matter (game code first; mock frames trimmed).
local function cleanTrace(trace)
	local out = {}
	for line in string.gmatch(trace or "", "[^\n]+") do
		if not string.find(line, "headless_bundle", 1, true) then
			table.insert(out, "    " .. line)
		end
	end
	return table.concat(out, "\n")
end
H.cleanTrace = cleanTrace

function H.reportError(message, trace, context)
	message = tostring(message)
	local key = message .. "\n" .. (trace or "")
	local e = H.errorIndex[key]
	if e then
		e.count += 1
		return
	end
	e = { message = message, trace = cleanTrace(trace), count = 1, context = context, at = H.now }
	H.errorIndex[key] = e
	table.insert(H.errors, e)
	print(("ERROR [t=%.1fs]%s %s"):format(H.now, context and (" (" .. context .. ")") or "", message))
	if e.trace ~= "" then
		print(e.trace)
	end
end

local function note(text)
	if not H.notes[text] then
		H.notes[text] = true
		print("NOTE " .. text)
	end
end
H.note = note

-- Global print/warn, Roblox style.
local rawPrint = print
function warn(...)
	local text = fmt(...)
	table.insert(H.warnings, { text = text, at = H.now })
	rawPrint(("WARN [t=%.1fs] %s"):format(H.now, text))
end
H.print = rawPrint

-- Strict argument checks used everywhere below.
local typeofImpl -- set later
local function argError(fname, n, expected, got)
	error(("invalid argument #%d to '%s' (%s expected, got %s)"):format(n, fname, expected, typeofImpl(got)), 3)
end
local function checkNum(fname, n, v)
	if type(v) ~= "number" then
		argError(fname, n, "number", v)
	end
	return v
end
local function optNum(fname, n, v, default)
	if v == nil then
		return default
	end
	return checkNum(fname, n, v)
end

-- Scheduler ---------------------------------------------------------------------------------------------------------
-- Every Roblox thread is a coroutine. task.spawn resumes it right away; task.wait parks it until simulated time
-- reaches its wake time; H.advance(seconds) steps frames, fires Stepped/Heartbeat, runs tweens and wakes threads.
local WAIT = {} -- yield token
local sleeping = {} -- { { co, wake, start, kind, fn?, args? } }
local deferred = {} -- { { co, args } }
local threadInfo = setmetatable({}, { __mode = "k" }) -- co -> { name }
local cancelled = setmetatable({}, { __mode = "k" })
H.threadCount = 0

local function resume(co, ...)
	if coroutine.status(co) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		local info = threadInfo[co]
		H.reportError(err, debug.traceback(co), info and info.name)
	end
	return ok
end
H.resume = resume

local function newThread(fn, name)
	local co = coroutine.create(fn)
	threadInfo[co] = { name = name }
	H.threadCount += 1
	return co
end
H.newThread = newThread

local function currentThread()
	local co, main = coroutine.running()
	if main or not coroutine.isyieldable() then
		return nil
	end
	return co
end

local function spawnFn(fn, ...)
	if type(fn) == "thread" then
		cancelled[fn] = nil
		resume(fn, ...)
		return fn
	end
	if type(fn) ~= "function" then
		argError("spawn", 1, "function or thread", fn)
	end
	local co = newThread(fn)
	resume(co, ...)
	return co
end

-- Parks the running thread until wake (simulated seconds). Returns what the waker passes.
local function sleepUntil(wake, kind)
	local co = currentThread()
	if not co then
		error("attempt to yield across metamethod/C-call boundary (task.wait called outside a Roblox thread)", 3)
	end
	table.insert(sleeping, { co = co, wake = wake, start = H.now, kind = kind or "wait", frame = H.frame })
	return coroutine.yield(WAIT)
end

-- Parks the running thread until something calls H.wakeThread(co, ...).
local parked = setmetatable({}, { __mode = "k" }) -- co -> why
H.parked = parked
local function park(why)
	local co = currentThread()
	if not co then
		error("attempt to yield outside a Roblox thread (" .. tostring(why) .. ")", 3)
	end
	parked[co] = why
	return co, function()
		return coroutine.yield(WAIT)
	end
end
local function unpark(co, ...)
	parked[co] = nil
	return resume(co, ...)
end

task = {}
function task.spawn(fn, ...)
	return spawnFn(fn, ...)
end
function task.defer(fn, ...)
	local co = type(fn) == "thread" and fn or nil
	if not co then
		if type(fn) ~= "function" then
			argError("defer", 1, "function or thread", fn)
		end
		co = newThread(fn)
	end
	table.insert(deferred, { co = co, args = table.pack(...) })
	return co
end
function task.delay(seconds, fn, ...)
	seconds = optNum("delay", 1, seconds, 0)
	local co = type(fn) == "thread" and fn or nil
	if not co then
		if type(fn) ~= "function" then
			argError("delay", 2, "function or thread", fn)
		end
		co = newThread(fn)
	end
	table.insert(sleeping, { co = co, wake = H.now + math.max(seconds, 0), start = H.now, kind = "delay", args = table.pack(...), frame = H.frame })
	return co
end
function task.wait(seconds)
	seconds = optNum("wait", 1, seconds, 0)
	local start = H.now
	sleepUntil(H.now + math.max(seconds, 0), "wait")
	return H.now - start
end
function task.cancel(co)
	if type(co) ~= "thread" then
		argError("cancel", 1, "thread", co)
	end
	cancelled[co] = true
	parked[co] = nil
	for i = #sleeping, 1, -1 do
		if sleeping[i].co == co then
			table.remove(sleeping, i)
		end
	end
	if coroutine.status(co) == "suspended" then
		coroutine.close(co)
	end
end
function task.synchronize() end
function task.desynchronize() end

-- Legacy globals (deprecated in Roblox, still work).
function wait(seconds)
	local start = H.now
	sleepUntil(H.now + math.max(seconds or 0.03, 0.03), "wait")
	return H.now - start, H.now
end
function spawn(fn)
	task.delay(0, fn)
end
function delay(seconds, fn)
	task.delay(seconds or 0, fn)
end

-- Clocks follow simulated time (plus real time inside the current frame, so time budgets still work).
local function simClock()
	return H.now + (realClock() - frameRealStart)
end
local realOs = os
os = setmetatable({}, { __index = realOs })
os.clock = simClock
os.date = realOs.date
os.difftime = realOs.difftime
function os.time(t)
	if t ~= nil then
		return realTime(t)
	end
	return EPOCH + math.floor(H.now)
end
function tick()
	return EPOCH + simClock()
end
function time()
	return H.now
end
function elapsedTime()
	return H.now
end

-- Run deferred threads (repeats while new ones are deferred, like Roblox's resumption cycle).
local function flushDeferred()
	local guard = 0
	while #deferred > 0 and guard < 100 do
		guard += 1
		local batch = deferred
		deferred = {}
		for _, d in batch do
			if not cancelled[d.co] then
				resume(d.co, table.unpack(d.args, 1, d.args.n))
			end
		end
	end
end
H.flushDeferred = flushDeferred

-- Wakes every sleeper due by now, in wake order.
local function wakeDue()
	local guard = 0
	while guard < 10000 do
		guard += 1
		local bestI, best = nil, nil
		for i, s in sleeping do
			-- a thread that waits always sleeps until at least the next frame, like Roblox
			if s.wake <= H.now + 1e-9 and (s.frame == nil or s.frame < H.frame) and (not best or s.wake < best.wake) then
				bestI, best = i, s
			end
		end
		if not best then
			break
		end
		table.remove(sleeping, bestI)
		if not cancelled[best.co] then
			if best.kind == "delay" then
				resume(best.co, table.unpack(best.args, 1, best.args.n))
			elseif best.kind == "hook" then
				best.fn()
			else
				resume(best.co, H.now - best.start)
			end
		end
		flushDeferred()
	end
end

-- Runs fn at simulated time `at` on the scheduler (used by the mock for timeouts, Debris, tweens finishing).
function H.at(at, fn)
	table.insert(sleeping, { wake = at, kind = "hook", fn = fn, co = false, start = H.now })
end

H.frameHooks = {} -- functions(dt) run each frame before Heartbeat (tweens)

function H.step()
	frameRealStart = realClock()
	H.frame += 1
	local dt = H.dt
	H.now += dt
	if H.fireFrame then
		H.fireFrame("PreSimulation", dt)
		H.fireFrame("Stepped", H.now, dt)
	end
	for _, hook in H.frameHooks do
		hook(dt)
	end
	if H.fireFrame then
		H.fireFrame("PostSimulation", dt)
		H.fireFrame("Heartbeat", dt)
	end
	wakeDue()
	flushDeferred()
end

function H.advance(seconds)
	local stop = H.now + seconds
	while H.now < stop - 1e-9 do
		H.step()
	end
end

-- Runs fn as a fresh Roblox thread right now (used for scripts and scenario steps).
function H.run(fn, name, ...)
	frameRealStart = realClock()
	local co = newThread(fn, name)
	resume(co, ...)
	flushDeferred()
	wakeDue()
	return co
end

function H.sleepers()
	return sleeping
end

-- Datatypes ---------------------------------------------------------------------------------------------------------
local TYPE = {} -- metatable -> Roblox type name
local function datatype(name)
	local mt = { __type = name }
	TYPE[mt] = name
	-- Roblox datatypes are userdata: iterating one or taking its length is an error, not a walk over hidden fields.
	mt.__iter = function()
		error(("attempt to iterate over a %s value"):format(name), 2)
	end
	mt.__len = function()
		error(("attempt to get length of a %s value"):format(name), 2)
	end
	return mt
end
H.datatype = datatype
local function isType(v, mt)
	return getmetatable(v) == mt
end
local function memberError(name, k)
	error(("%s is not a valid member of %s"):format(tostring(k), name), 3)
end
local function readonly(name)
	return function(_, k)
		error(("%s cannot be assigned to (%s is immutable)"):format(tostring(k), name), 2)
	end
end

-- Vector3 --
local V3 = datatype("Vector3")
local V3methods = {}
local function v3(x, y, z)
	return table.freeze(setmetatable({ X = x, Y = y, Z = z }, V3))
end
local function checkV3(fname, n, v)
	if getmetatable(v) ~= V3 then
		argError(fname, n, "Vector3", v)
	end
	return v
end
V3.__index = function(t, k)
	local m = V3methods[k]
	if m then
		return m
	end
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
	elseif k == "Unit" then
		local m2 = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if m2 == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0) -- Roblox returns NaN components for a zero vector's Unit
		end
		return v3(t.X / m2, t.Y / m2, t.Z / m2)
	end
	memberError("Vector3", k)
end
V3.__newindex = readonly("Vector3")
local function arith(name, op)
	return function(a, b)
		error(("attempt to perform arithmetic (%s) on %s and %s"):format(op, typeofImpl(a), typeofImpl(b)), 2)
	end
end
V3.__add = function(a, b)
	if getmetatable(a) ~= V3 or getmetatable(b) ~= V3 then
		arith("Vector3", "add")(a, b)
	end
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	if getmetatable(a) ~= V3 or getmetatable(b) ~= V3 then
		arith("Vector3", "sub")(a, b)
	end
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" and getmetatable(b) == V3 then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" and getmetatable(a) == V3 then
		return v3(a.X * b, a.Y * b, a.Z * b)
	elseif getmetatable(a) == V3 and getmetatable(b) == V3 then
		return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	arith("Vector3", "mul")(a, b)
end
V3.__div = function(a, b)
	if type(b) == "number" and getmetatable(a) == V3 then
		return v3(a.X / b, a.Y / b, a.Z / b)
	elseif type(a) == "number" and getmetatable(b) == V3 then
		return v3(a / b.X, a / b.Y, a / b.Z)
	elseif getmetatable(a) == V3 and getmetatable(b) == V3 then
		return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
	end
	arith("Vector3", "div")(a, b)
end
V3.__idiv = function(a, b)
	local q = V3.__div(a, b)
	return v3(math.floor(q.X), math.floor(q.Y), math.floor(q.Z))
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return ("%s, %s, %s"):format(tostring(a.X), tostring(a.Y), tostring(a.Z))
end
function V3methods.Lerp(a, b, t)
	checkV3("Lerp", 1, b)
	checkNum("Lerp", 2, t)
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3methods.Dot(a, b)
	checkV3("Dot", 1, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3methods.Cross(a, b)
	checkV3("Cross", 1, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3methods.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3methods.Ceil(a)
	return v3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
end
function V3methods.Floor(a)
	return v3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
end
function V3methods.Sign(a)
	return v3(math.sign(a.X), math.sign(a.Y), math.sign(a.Z))
end
function V3methods.Max(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for i = 1, select("#", ...) do
		local b = checkV3("Max", i, (select(i, ...)))
		x, y, z = math.max(x, b.X), math.max(y, b.Y), math.max(z, b.Z)
	end
	return v3(x, y, z)
end
function V3methods.Min(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for i = 1, select("#", ...) do
		local b = checkV3("Min", i, (select(i, ...)))
		x, y, z = math.min(x, b.X), math.min(y, b.Y), math.min(z, b.Z)
	end
	return v3(x, y, z)
end
function V3methods.Angle(a, b, axis)
	checkV3("Angle", 1, b)
	local cross = a:Cross(b)
	local angle = math.atan2(cross.Magnitude, a:Dot(b))
	if axis and cross:Dot(axis) < 0 then
		angle = -angle
	end
	return angle
end
function V3methods.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
end
Vector3 = {
	new = function(x, y, z)
		return v3(optNum("Vector3.new", 1, x, 0), optNum("Vector3.new", 2, y, 0), optNum("Vector3.new", 3, z, 0))
	end,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}
H.v3 = v3

-- Vector2 --
local V2 = datatype("Vector2")
local V2methods = {}
local function v2(x, y)
	return table.freeze(setmetatable({ X = x, Y = y }, V2))
end
V2.__index = function(t, k)
	local m = V2methods[k]
	if m then
		return m
	end
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y)
	elseif k == "Unit" then
		local m2 = math.sqrt(t.X * t.X + t.Y * t.Y)
		return v2(t.X / m2, t.Y / m2)
	end
	memberError("Vector2", k)
end
V2.__newindex = readonly("Vector2")
V2.__add = function(a, b)
	if getmetatable(a) ~= V2 or getmetatable(b) ~= V2 then
		arith("Vector2", "add")(a, b)
	end
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	if getmetatable(a) ~= V2 or getmetatable(b) ~= V2 then
		arith("Vector2", "sub")(a, b)
	end
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__unm = function(a)
	return v2(-a.X, -a.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" and getmetatable(b) == V2 then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" and getmetatable(a) == V2 then
		return v2(a.X * b, a.Y * b)
	elseif getmetatable(a) == V2 and getmetatable(b) == V2 then
		return v2(a.X * b.X, a.Y * b.Y)
	end
	arith("Vector2", "mul")(a, b)
end
V2.__div = function(a, b)
	if type(b) == "number" and getmetatable(a) == V2 then
		return v2(a.X / b, a.Y / b)
	elseif getmetatable(a) == V2 and getmetatable(b) == V2 then
		return v2(a.X / b.X, a.Y / b.Y)
	end
	arith("Vector2", "div")(a, b)
end
V2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2.__tostring = function(a)
	return ("%s, %s"):format(tostring(a.X), tostring(a.Y))
end
function V2methods.Lerp(a, b, t)
	return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end
function V2methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
function V2methods.Cross(a, b)
	return a.X * b.Y - a.Y * b.X
end
function V2methods.Abs(a)
	return v2(math.abs(a.X), math.abs(a.Y))
end
function V2methods.Floor(a)
	return v2(math.floor(a.X), math.floor(a.Y))
end
function V2methods.Ceil(a)
	return v2(math.ceil(a.X), math.ceil(a.Y))
end
function V2methods.Sign(a)
	return v2(math.sign(a.X), math.sign(a.Y))
end
function V2methods.Max(a, b)
	return v2(math.max(a.X, b.X), math.max(a.Y, b.Y))
end
function V2methods.Min(a, b)
	return v2(math.min(a.X, b.X), math.min(a.Y, b.Y))
end
function V2methods.Angle(a, b)
	return math.atan2(a.X * b.Y - a.Y * b.X, a.X * b.X + a.Y * b.Y)
end
function V2methods.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps
end
Vector2 = {
	new = function(x, y)
		return v2(optNum("Vector2.new", 1, x, 0), optNum("Vector2.new", 2, y, 0))
	end,
	zero = v2(0, 0),
	one = v2(1, 1),
	xAxis = v2(1, 0),
	yAxis = v2(0, 1),
}
Vector3int16 = { new = function(x, y, z) return v3(x or 0, y or 0, z or 0) end }
Vector2int16 = { new = function(x, y) return v2(x or 0, y or 0) end }

-- CFrame: position p and rotation matrix rows (m00..m22); columns are RightVector, UpVector, -LookVector --
local CF = datatype("CFrame")
local CFmethods = {}
local function cf(x, y, z, m00, m01, m02, m10, m11, m12, m20, m21, m22)
	return table.freeze(setmetatable({ x, y, z, m00, m01, m02, m10, m11, m12, m20, m21, m22 }, CF))
end
local function checkCF(fname, n, v)
	if getmetatable(v) ~= CF then
		argError(fname, n, "CFrame", v)
	end
	return v
end
local IDENTITY = cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
local function cfMul(a, b)
	local a00, a01, a02, a10, a11, a12, a20, a21, a22 = a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]
	local b00, b01, b02, b10, b11, b12, b20, b21, b22 = b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12]
	return cf(
		a[1] + a00 * b[1] + a01 * b[2] + a02 * b[3],
		a[2] + a10 * b[1] + a11 * b[2] + a12 * b[3],
		a[3] + a20 * b[1] + a21 * b[2] + a22 * b[3],
		a00 * b00 + a01 * b10 + a02 * b20,
		a00 * b01 + a01 * b11 + a02 * b21,
		a00 * b02 + a01 * b12 + a02 * b22,
		a10 * b00 + a11 * b10 + a12 * b20,
		a10 * b01 + a11 * b11 + a12 * b21,
		a10 * b02 + a11 * b12 + a12 * b22,
		a20 * b00 + a21 * b10 + a22 * b20,
		a20 * b01 + a21 * b11 + a22 * b21,
		a20 * b02 + a21 * b12 + a22 * b22
	)
end
local function cfPoint(a, v)
	return v3(
		a[1] + a[4] * v.X + a[5] * v.Y + a[6] * v.Z,
		a[2] + a[7] * v.X + a[8] * v.Y + a[9] * v.Z,
		a[3] + a[10] * v.X + a[11] * v.Y + a[12] * v.Z
	)
end
local function cfVector(a, v)
	return v3(a[4] * v.X + a[5] * v.Y + a[6] * v.Z, a[7] * v.X + a[8] * v.Y + a[9] * v.Z, a[10] * v.X + a[11] * v.Y + a[12] * v.Z)
end
local function cfInverse(a)
	-- rotation transpose; position -R^T p
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = a[4], a[7], a[10], a[5], a[8], a[11], a[6], a[9], a[12]
	local x, y, z = a[1], a[2], a[3]
	return cf(
		-(m00 * x + m01 * y + m02 * z),
		-(m10 * x + m11 * y + m12 * z),
		-(m20 * x + m21 * y + m22 * z),
		m00, m01, m02, m10, m11, m12, m20, m21, m22
	)
end
local function fromAxisAngle(axis, angle)
	local m = axis.Magnitude
	if m == 0 then
		return IDENTITY
	end
	local x, y, z = axis.X / m, axis.Y / m, axis.Z / m
	local c, s = math.cos(angle), math.sin(angle)
	local t = 1 - c
	return cf(0, 0, 0,
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c)
end
local function rx(a)
	local c, s = math.cos(a), math.sin(a)
	return cf(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
end
local function ry(a)
	local c, s = math.cos(a), math.sin(a)
	return cf(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end
local function rz(a)
	local c, s = math.cos(a), math.sin(a)
	return cf(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end
local function fromMatrix(p, r, u, b)
	if not b then
		b = r:Cross(u)
		local m = b.Magnitude
		if m > 0 then
			b = b / m
		end
	end
	return cf(p.X, p.Y, p.Z, r.X, u.X, b.X, r.Y, u.Y, b.Y, r.Z, u.Z, b.Z)
end
local function lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = target - at
	local m = look.Magnitude
	if m == 0 then
		return cf(at.X, at.Y, at.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	look = look / m
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		-- looking straight along up: Roblox picks a perpendicular right vector
		right = look:Cross(v3(0, 0, 1))
		if right.Magnitude < 1e-6 then
			right = look:Cross(v3(1, 0, 0))
		end
	end
	right = right.Unit
	local u = right:Cross(look).Unit
	return fromMatrix(at, right, u, -look)
end
local function quatToCF(x, y, z, qx, qy, qz, qw)
	local n = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	qx, qy, qz, qw = qx / n, qy / n, qz / n, qw / n
	return cf(x, y, z,
		1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw),
		2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw),
		2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy))
end
local function toAxisAngle(c)
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]
	local cosA = math.clamp((m00 + m11 + m22 - 1) / 2, -1, 1)
	local angle = math.acos(cosA)
	if angle < 1e-9 then
		return v3(1, 0, 0), 0
	end
	local x, y, z = m21 - m12, m02 - m20, m10 - m01
	local len = math.sqrt(x * x + y * y + z * z)
	if len < 1e-9 then
		-- 180 degrees: axis from the diagonal
		x = math.sqrt(math.max((m00 + 1) / 2, 0))
		y = math.sqrt(math.max((m11 + 1) / 2, 0))
		z = math.sqrt(math.max((m22 + 1) / 2, 0))
		if m01 < 0 then y = -y end
		if m02 < 0 then z = -z end
		len = math.sqrt(x * x + y * y + z * z)
	end
	return v3(x / len, y / len, z / len), angle
end
CF.__index = function(c, k)
	local m = CFmethods[k]
	if m then
		return m
	end
	if k == "Position" or k == "p" then
		return v3(c[1], c[2], c[3])
	elseif k == "X" then
		return c[1]
	elseif k == "Y" then
		return c[2]
	elseif k == "Z" then
		return c[3]
	elseif k == "LookVector" or k == "lookVector" then
		return v3(-c[6], -c[9], -c[12])
	elseif k == "RightVector" or k == "XVector" then
		return v3(c[4], c[7], c[10])
	elseif k == "UpVector" or k == "YVector" then
		return v3(c[5], c[8], c[11])
	elseif k == "ZVector" then
		return v3(c[6], c[9], c[12])
	elseif k == "Rotation" then
		return cf(0, 0, 0, c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
	elseif k == "R00" then return c[4] elseif k == "R01" then return c[5] elseif k == "R02" then return c[6]
	elseif k == "R10" then return c[7] elseif k == "R11" then return c[8] elseif k == "R12" then return c[9]
	elseif k == "R20" then return c[10] elseif k == "R21" then return c[11] elseif k == "R22" then return c[12]
	end
	memberError("CFrame", k)
end
CF.__newindex = readonly("CFrame")
CF.__mul = function(a, b)
	if getmetatable(a) ~= CF then
		arith("CFrame", "mul")(a, b)
	end
	local mb = getmetatable(b)
	if mb == CF then
		return cfMul(a, b)
	elseif mb == V3 then
		return cfPoint(a, b)
	end
	arith("CFrame", "mul")(a, b)
end
CF.__add = function(a, b)
	if getmetatable(a) ~= CF or getmetatable(b) ~= V3 then
		arith("CFrame", "add")(a, b)
	end
	return cf(a[1] + b.X, a[2] + b.Y, a[3] + b.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
end
CF.__sub = function(a, b)
	if getmetatable(a) ~= CF or getmetatable(b) ~= V3 then
		arith("CFrame", "sub")(a, b)
	end
	return cf(a[1] - b.X, a[2] - b.Y, a[3] - b.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
end
CF.__eq = function(a, b)
	for i = 1, 12 do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end
CF.__tostring = function(c)
	local parts = {}
	for i = 1, 12 do
		parts[i] = tostring(c[i])
	end
	return table.concat(parts, ", ")
end
function CFmethods.Inverse(c)
	return cfInverse(c)
end
function CFmethods.ToWorldSpace(c, ...)
	local n = select("#", ...)
	if n == 0 then
		return c
	end
	local out = {}
	for i = 1, n do
		out[i] = cfMul(c, checkCF("ToWorldSpace", i, (select(i, ...))))
	end
	return table.unpack(out, 1, n)
end
function CFmethods.ToObjectSpace(c, ...)
	local inv = cfInverse(c)
	local n = select("#", ...)
	if n == 0 then
		return inv
	end
	local out = {}
	for i = 1, n do
		out[i] = cfMul(inv, checkCF("ToObjectSpace", i, (select(i, ...))))
	end
	return table.unpack(out, 1, n)
end
function CFmethods.PointToWorldSpace(c, ...)
	local out = {}
	local n = select("#", ...)
	for i = 1, n do
		out[i] = cfPoint(c, checkV3("PointToWorldSpace", i, (select(i, ...))))
	end
	return table.unpack(out, 1, n)
end
function CFmethods.PointToObjectSpace(c, ...)
	local inv = cfInverse(c)
	local out = {}
	local n = select("#", ...)
	for i = 1, n do
		out[i] = cfPoint(inv, checkV3("PointToObjectSpace", i, (select(i, ...))))
	end
	return table.unpack(out, 1, n)
end
function CFmethods.VectorToWorldSpace(c, ...)
	local out = {}
	local n = select("#", ...)
	for i = 1, n do
		out[i] = cfVector(c, checkV3("VectorToWorldSpace", i, (select(i, ...))))
	end
	return table.unpack(out, 1, n)
end
function CFmethods.VectorToObjectSpace(c, ...)
	local inv = cfInverse(c)
	local out = {}
	local n = select("#", ...)
	for i = 1, n do
		out[i] = cfVector(inv, checkV3("VectorToObjectSpace", i, (select(i, ...))))
	end
	return table.unpack(out, 1, n)
end
function CFmethods.GetComponents(c)
	return table.unpack(c, 1, 12)
end
CFmethods.components = CFmethods.GetComponents
function CFmethods.ToEulerAnglesXYZ(c)
	local ry_ = math.asin(math.clamp(c[6], -1, 1))
	local rx_ = math.atan2(-c[9], c[12])
	local rz_ = math.atan2(-c[5], c[4])
	return rx_, ry_, rz_
end
function CFmethods.ToEulerAnglesYXZ(c)
	local rx_ = math.asin(math.clamp(-c[9], -1, 1))
	local ry_ = math.atan2(c[6], c[12])
	local rz_ = math.atan2(c[7], c[8])
	return rx_, ry_, rz_
end
CFmethods.ToOrientation = CFmethods.ToEulerAnglesYXZ
function CFmethods.ToAxisAngle(c)
	return toAxisAngle(c)
end
function CFmethods.Lerp(a, b, t)
	checkCF("Lerp", 1, b)
	checkNum("Lerp", 2, t)
	local rel = cfMul(cfInverse(a.Rotation), b.Rotation)
	local axis, angle = toAxisAngle(rel)
	local rot = cfMul(a.Rotation, fromAxisAngle(axis, angle * t))
	return cf(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, rot[4], rot[5], rot[6], rot[7], rot[8], rot[9], rot[10], rot[11], rot[12])
end
function CFmethods.Orthonormalize(c)
	local r = v3(c[4], c[7], c[10]).Unit
	local u = v3(c[5], c[8], c[11])
	local b = r:Cross(u).Unit
	u = b:Cross(r).Unit
	return fromMatrix(v3(c[1], c[2], c[3]), r, u, b)
end
function CFmethods.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	for i = 1, 12 do
		if math.abs(a[i] - b[i]) > eps then
			return false
		end
	end
	return true
end
function CFmethods.AngleBetween(a, b)
	local _, angle = toAxisAngle(cfMul(cfInverse(a.Rotation), b.Rotation))
	return angle
end
CFrame = {
	identity = IDENTITY,
	new = function(...)
		local n = select("#", ...)
		local a, b, c = ...
		if n == 0 then
			return IDENTITY
		end
		if getmetatable(a) == V3 then
			if b ~= nil then
				checkV3("CFrame.new", 2, b)
				return lookAt(a, b)
			end
			return cf(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		for i = 1, n do
			checkNum("CFrame.new", i, (select(i, ...)))
		end
		if n == 3 then
			return cf(a, b, c, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		elseif n == 7 then
			return quatToCF(...)
		elseif n == 12 then
			return cf(...)
		end
		error("Invalid number of arguments: " .. n, 2)
	end,
	Angles = function(x, y, z)
		return cfMul(cfMul(rx(optNum("CFrame.Angles", 1, x, 0)), ry(optNum("CFrame.Angles", 2, y, 0))), rz(optNum("CFrame.Angles", 3, z, 0)))
	end,
	fromAxisAngle = function(axis, angle)
		checkV3("CFrame.fromAxisAngle", 1, axis)
		return fromAxisAngle(axis, checkNum("CFrame.fromAxisAngle", 2, angle))
	end,
	fromMatrix = function(p, r, u, b)
		checkV3("CFrame.fromMatrix", 1, p)
		checkV3("CFrame.fromMatrix", 2, r)
		checkV3("CFrame.fromMatrix", 3, u)
		return fromMatrix(p, r, u, b)
	end,
	lookAt = function(at, target, up)
		checkV3("CFrame.lookAt", 1, at)
		checkV3("CFrame.lookAt", 2, target)
		return lookAt(at, target, up)
	end,
	lookAlong = function(at, dir, up)
		return lookAt(at, at + dir, up)
	end,
	fromRotationBetweenVectors = function(a, b)
		local axis = a:Cross(b)
		return fromAxisAngle(axis.Magnitude > 0 and axis or v3(0, 1, 0), a:Angle(b))
	end,
}
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.fromEulerAnglesYXZ = function(x, y, z)
	return cfMul(cfMul(ry(y or 0), rx(x or 0)), rz(z or 0))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
CFrame.fromEulerAngles = function(x, y, z, order)
	return CFrame.Angles(x, y, z)
end
H.cf = cf
H.cfInverse = cfInverse
H.cfMul = cfMul

-- Color3 --
local C3 = datatype("Color3")
local C3methods = {}
local function c3(r, g, b)
	return table.freeze(setmetatable({ R = r, G = g, B = b }, C3))
end
C3.__index = function(_, k)
	local m = C3methods[k]
	if m then
		return m
	end
	if k == "r" or k == "g" or k == "b" then
		return nil
	end
	memberError("Color3", k)
end
C3.__newindex = readonly("Color3")
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3.__tostring = function(c)
	return ("%s, %s, %s"):format(tostring(c.R), tostring(c.G), tostring(c.B))
end
local function toHSV(c)
	local r, g, b = c.R, c.G, c.B
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == r then
			h = ((g - b) / d) % 6
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	local s = max == 0 and 0 or d / max
	return h, s, max
end
local function fromHSV(h, s, v)
	h = (h % 1) * 6
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	if i == 0 then return c3(v, t, p) elseif i == 1 then return c3(q, v, p) elseif i == 2 then return c3(p, v, t)
	elseif i == 3 then return c3(p, q, v) elseif i == 4 then return c3(t, p, v) end
	return c3(v, p, q)
end
function C3methods.Lerp(a, b, t)
	if getmetatable(b) ~= C3 then
		argError("Lerp", 1, "Color3", b)
	end
	checkNum("Lerp", 2, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
C3methods.ToHSV = toHSV
function C3methods.ToHex(c)
	local function h(x)
		return ("%02X"):format(math.clamp(math.round(x * 255), 0, 255))
	end
	return h(c.R) .. h(c.G) .. h(c.B)
end
Color3 = {
	new = function(r, g, b)
		return c3(optNum("Color3.new", 1, r, 0), optNum("Color3.new", 2, g, 0), optNum("Color3.new", 3, b, 0))
	end,
	fromRGB = function(r, g, b)
		return c3(optNum("Color3.fromRGB", 1, r, 0) / 255, optNum("Color3.fromRGB", 2, g, 0) / 255, optNum("Color3.fromRGB", 3, b, 0) / 255)
	end,
	fromHSV = function(h, s, v)
		return fromHSV(checkNum("Color3.fromHSV", 1, h), checkNum("Color3.fromHSV", 2, s), checkNum("Color3.fromHSV", 3, v))
	end,
	toHSV = toHSV,
	fromHex = function(hex)
		hex = string.gsub(hex, "#", "")
		if #hex == 3 then
			hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
		end
		local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
		if not (r and g and b) then
			error("Unable to convert characters to hex value", 2)
		end
		return c3(r / 255, g / 255, b / 255)
	end,
}
H.c3 = c3

-- BrickColor (a small palette; BrickColor.new(Color3) picks the nearest of these) --
local BC = datatype("BrickColor")
local PALETTE = {
	{ 1, "White", 242, 243, 243 }, { 194, "Medium stone grey", 163, 162, 165 }, { 26, "Black", 27, 42, 53 },
	{ 21, "Bright red", 196, 40, 28 }, { 23, "Bright blue", 13, 105, 172 }, { 24, "Bright yellow", 245, 205, 48 },
	{ 28, "Dark green", 40, 127, 71 }, { 37, "Bright green", 75, 151, 75 }, { 106, "Bright orange", 218, 133, 65 },
	{ 192, "Reddish brown", 105, 64, 40 }, { 199, "Dark stone grey", 99, 95, 98 }, { 1001, "Institutional white", 248, 248, 248 },
	{ 1003, "Really black", 17, 17, 17 }, { 1004, "Really red", 255, 0, 0 }, { 1010, "Really blue", 0, 0, 255 },
	{ 1020, "Lime green", 0, 255, 0 }, { 1009, "New Yeller", 255, 255, 0 }, { 1019, "Toothpaste", 0, 255, 255 },
	{ 1032, "Hot pink", 255, 0, 191 }, { 1012, "Deep orange", 255, 176, 0 }, { 217, "Brown", 124, 92, 70 },
	{ 5, "Brick yellow", 215, 197, 154 }, { 208, "Light stone grey", 229, 228, 223 }, { 141, "Earth green", 39, 70, 45 },
	{ 119, "Lime green", 164, 189, 71 }, { 102, "Medium blue", 110, 153, 202 }, { 1030, "Pastel brown", 255, 204, 153 },
	{ 38, "Dark orange", 160, 95, 53 }, { 18, "Nougat", 204, 142, 105 }, { 1031, "Royal purple", 98, 37, 209 },
}
local function bc(entry)
	return setmetatable({ Number = entry[1], Name = entry[2], Color = c3(entry[3] / 255, entry[4] / 255, entry[5] / 255), r = entry[3] / 255, g = entry[4] / 255, b = entry[5] / 255 }, BC)
end
BC.__index = function(_, k)
	memberError("BrickColor", k)
end
BC.__newindex = readonly("BrickColor")
BC.__eq = function(a, b)
	return a.Number == b.Number
end
BC.__tostring = function(b)
	return b.Name
end
local function nearestBrick(c)
	local best, bestD = PALETTE[2], math.huge
	for _, e in PALETTE do
		local d = (e[3] / 255 - c.R) ^ 2 + (e[4] / 255 - c.G) ^ 2 + (e[5] / 255 - c.B) ^ 2
		if d < bestD then
			best, bestD = e, d
		end
	end
	return bc(best)
end
BrickColor = {
	new = function(a, g, b)
		if type(a) == "string" then
			for _, e in PALETTE do
				if e[2] == a then
					return bc(e)
				end
			end
			return bc(PALETTE[2])
		elseif type(a) == "number" and g == nil then
			for _, e in PALETTE do
				if e[1] == a then
					return bc(e)
				end
			end
			return bc(PALETTE[2])
		elseif type(a) == "number" then
			return nearestBrick(c3(a, g, b))
		elseif getmetatable(a) == C3 then
			return nearestBrick(a)
		end
		argError("BrickColor.new", 1, "string, number or Color3", a)
	end,
	palette = function(i)
		return bc(PALETTE[(i % #PALETTE) + 1])
	end,
	random = function()
		return bc(PALETTE[math.random(1, #PALETTE)])
	end,
	White = function() return bc(PALETTE[1]) end,
	Gray = function() return bc(PALETTE[2]) end,
	DarkGray = function() return bc(PALETTE[11]) end,
	Black = function() return bc(PALETTE[3]) end,
	Red = function() return bc(PALETTE[4]) end,
	Yellow = function() return bc(PALETTE[6]) end,
	Green = function() return bc(PALETTE[5 + 4]) end,
	Blue = function() return bc(PALETTE[5]) end,
}
H.nearestBrick = nearestBrick

-- UDim / UDim2 --
local UD = datatype("UDim")
local function udim(s, o)
	return setmetatable({ Scale = s, Offset = o }, UD)
end
UD.__index = function(_, k)
	memberError("UDim", k)
end
UD.__newindex = readonly("UDim")
UD.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UD.__add = function(a, b)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UD.__sub = function(a, b)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UD.__unm = function(a)
	return udim(-a.Scale, -a.Offset)
end
UD.__tostring = function(a)
	return ("%s, %s"):format(tostring(a.Scale), tostring(a.Offset))
end
UDim = { new = function(s, o)
	return udim(optNum("UDim.new", 1, s, 0), optNum("UDim.new", 2, o, 0))
end }
local UD2 = datatype("UDim2")
local UD2methods = {}
local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo) }, UD2)
end
UD2.__index = function(t, k)
	if k == "Width" then
		return t.X
	elseif k == "Height" then
		return t.Y
	end
	local m = UD2methods[k]
	if m then
		return m
	end
	memberError("UDim2", k)
end
UD2.__newindex = readonly("UDim2")
UD2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
UD2.__add = function(a, b)
	return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UD2.__sub = function(a, b)
	return udim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
UD2.__unm = function(a)
	return udim2(-a.X.Scale, -a.X.Offset, -a.Y.Scale, -a.Y.Offset)
end
UD2.__tostring = function(a)
	return ("{%s}, {%s}"):format(tostring(a.X), tostring(a.Y))
end
function UD2methods.Lerp(a, b, t)
	local function l(x, y)
		return x + (y - x) * t
	end
	return udim2(l(a.X.Scale, b.X.Scale), l(a.X.Offset, b.X.Offset), l(a.Y.Scale, b.Y.Scale), l(a.Y.Offset, b.Y.Offset))
end
UDim2 = {
	new = function(a, b, c, d)
		if getmetatable(a) == UD then
			return setmetatable({ X = a, Y = b or udim(0, 0) }, UD2)
		end
		return udim2(optNum("UDim2.new", 1, a, 0), optNum("UDim2.new", 2, b, 0), optNum("UDim2.new", 3, c, 0), optNum("UDim2.new", 4, d, 0))
	end,
	fromScale = function(x, y)
		return udim2(optNum("UDim2.fromScale", 1, x, 0), 0, optNum("UDim2.fromScale", 2, y, 0), 0)
	end,
	fromOffset = function(x, y)
		return udim2(0, optNum("UDim2.fromOffset", 1, x, 0), 0, optNum("UDim2.fromOffset", 2, y, 0))
	end,
}

-- Rect --
local RECT = datatype("Rect")
RECT.__index = function(t, k)
	if k == "Width" then
		return t.Max.X - t.Min.X
	elseif k == "Height" then
		return t.Max.Y - t.Min.Y
	end
	memberError("Rect", k)
end
RECT.__newindex = readonly("Rect")
RECT.__eq = function(a, b)
	return a.Min == b.Min and a.Max == b.Max
end
Rect = { new = function(a, b, c, d)
	if getmetatable(a) == V2 then
		return setmetatable({ Min = a, Max = b }, RECT)
	end
	return setmetatable({ Min = v2(a or 0, b or 0), Max = v2(c or 0, d or 0) }, RECT)
end }

-- NumberRange --
local NR = datatype("NumberRange")
NR.__index = function(_, k)
	memberError("NumberRange", k)
end
NR.__newindex = readonly("NumberRange")
NR.__eq = function(a, b)
	return a.Min == b.Min and a.Max == b.Max
end
NR.__tostring = function(a)
	return ("%s %s"):format(tostring(a.Min), tostring(a.Max))
end
NumberRange = { new = function(min, max)
	checkNum("NumberRange.new", 1, min)
	max = optNum("NumberRange.new", 2, max, min)
	if max < min then
		error("NumberRange: invalid range", 2)
	end
	return setmetatable({ Min = min, Max = max }, NR)
end }

-- NumberSequence / ColorSequence (+ keypoints) --
local NSK = datatype("NumberSequenceKeypoint")
NSK.__index = function(_, k)
	memberError("NumberSequenceKeypoint", k)
end
NSK.__newindex = readonly("NumberSequenceKeypoint")
NSK.__eq = function(a, b)
	return a.Time == b.Time and a.Value == b.Value and a.Envelope == b.Envelope
end
NumberSequenceKeypoint = { new = function(t, v, e)
	checkNum("NumberSequenceKeypoint.new", 1, t)
	checkNum("NumberSequenceKeypoint.new", 2, v)
	return setmetatable({ Time = t, Value = v, Envelope = optNum("NumberSequenceKeypoint.new", 3, e, 0) }, NSK)
end }
local NS = datatype("NumberSequence")
NS.__index = function(_, k)
	memberError("NumberSequence", k)
end
NS.__newindex = readonly("NumberSequence")
NS.__eq = function(a, b)
	if #a.Keypoints ~= #b.Keypoints then
		return false
	end
	for i, k in a.Keypoints do
		if k ~= b.Keypoints[i] then
			return false
		end
	end
	return true
end
local function checkKeypoints(name, list, kpType)
	if #list < 2 then
		error(name .. ": requires at least 2 keypoints", 3)
	end
	if #list > 20 then
		error(name .. ": table is too long.", 3)
	end
	for i, k in list do
		if getmetatable(k) ~= kpType then
			error(name .. ": expected array of " .. TYPE[kpType] .. ", got " .. typeofImpl(k) .. " at " .. i, 3)
		end
		if i > 1 and k.Time < list[i - 1].Time then
			error(name .. ": all keypoints must be ordered by time", 3)
		end
	end
	if math.abs(list[1].Time) > 1e-4 then
		error(name .. " time must start at 0", 3)
	end
	if math.abs(list[#list].Time - 1) > 1e-4 then
		error(name .. " time must end at 1", 3)
	end
end
NumberSequence = { new = function(a, b)
	local list
	if type(a) == "number" then
		list = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
	elseif type(a) == "table" and getmetatable(a) == nil then
		checkKeypoints("NumberSequence", a, NSK)
		list = table.clone(a)
	else
		argError("NumberSequence.new", 1, "number or table", a)
	end
	return setmetatable({ Keypoints = table.freeze(list) }, NS)
end }
local CSK = datatype("ColorSequenceKeypoint")
CSK.__index = function(_, k)
	memberError("ColorSequenceKeypoint", k)
end
CSK.__newindex = readonly("ColorSequenceKeypoint")
CSK.__eq = function(a, b)
	return a.Time == b.Time and a.Value == b.Value
end
ColorSequenceKeypoint = { new = function(t, c)
	checkNum("ColorSequenceKeypoint.new", 1, t)
	if getmetatable(c) ~= C3 then
		argError("ColorSequenceKeypoint.new", 2, "Color3", c)
	end
	return setmetatable({ Time = t, Value = c }, CSK)
end }
local CS = datatype("ColorSequence")
CS.__index = function(_, k)
	memberError("ColorSequence", k)
end
CS.__newindex = readonly("ColorSequence")
CS.__eq = function(a, b)
	if #a.Keypoints ~= #b.Keypoints then
		return false
	end
	for i, k in a.Keypoints do
		if k ~= b.Keypoints[i] then
			return false
		end
	end
	return true
end
ColorSequence = { new = function(a, b)
	local list
	if getmetatable(a) == C3 then
		if b ~= nil and getmetatable(b) ~= C3 then
			argError("ColorSequence.new", 2, "Color3", b)
		end
		list = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
	elseif type(a) == "table" and getmetatable(a) == nil then
		checkKeypoints("ColorSequence", a, CSK)
		list = table.clone(a)
	else
		argError("ColorSequence.new", 1, "Color3 or table", a)
	end
	return setmetatable({ Keypoints = table.freeze(list) }, CS)
end }

-- Enum --------------------------------------------------------------------------------------------------------------
-- Categories listed here are checked (Enum.Material.Foo errors like in Roblox); any other category accepts any item
-- name, so code using enums this file doesn't list still runs.
local ENUM_LISTS = {
	Material = "Plastic SmoothPlastic Neon Wood WoodPlanks Marble Slate Concrete Granite Brick Pebble Cobblestone CorrodedMetal DiamondPlate Foil Metal Grass LeafyGrass Sand Fabric Ice Glass ForceField Air Water Rock Glacier Snow Sandstone Mud Basalt Ground CrackedLava Asphalt Salt Limestone Pavement Cardboard Carpet CeramicTiles ClayRoofTiles RoofShingles Leather Plaster Rubber",
	PartType = "Ball Block Cylinder Wedge CornerWedge",
	NormalId = "Right Top Back Left Bottom Front",
	SurfaceType = "Smooth Glue Weld Studs Inlet Universal Hinge Motor SteppingMotor SmoothNoOutlines",
	Font = "Legacy Arial ArialBold SourceSans SourceSansBold SourceSansSemibold SourceSansLight SourceSansItalic Bodoni Garamond Cartoon Code Highway SciFi Arcade Fantasy Antique Gotham GothamMedium GothamBold GothamBlack GothamSemibold AmaticSC Bangers Creepster DenkOne Fondamento FredokaOne GrenzeGotisch IndieFlower JosefinSans Jura Kalam LuckiestGuy Merriweather Michroma Nunito Oswald PatrickHand PermanentMarker Roboto RobotoCondensed RobotoMono Sarpanch SpecialElite TitilliumWeb Ubuntu BuilderSans BuilderSansMedium BuilderSansBold BuilderSansExtraBold Unknown",
	EasingStyle = "Linear Sine Back Quad Quart Quint Bounce Elastic Exponential Circular Cubic",
	EasingDirection = "In Out InOut",
	RaycastFilterType = "Exclude Include Blacklist Whitelist",
	PlaybackState = "Begin Delayed Playing Paused Completed Cancelled",
	HumanoidRigType = "R6 R15",
	HumanoidStateType = "FallingDown Ragdoll GettingUp Jumping Swimming Freefall Flying Landed Running RunningNoPhysics StrafingNoPhysics Climbing Seated PlatformStanding Dead Physics None",
	ActuatorRelativeTo = "Attachment0 Attachment1 World",
	ActuatorType = "None Motor Servo",
	ModelStreamingMode = "Default Atomic Persistent PersistentPerPlayer Nonatomic",
	OrientationAlignmentMode = "OneAttachment TwoAttachment",
	PositionAlignmentMode = "OneAttachment TwoAttachment",
	VelocityConstraintMode = "Line Plane Vector",
	SurfaceGuiSizingMode = "FixedSize PixelsPerStud",
	TextXAlignment = "Left Center Right",
	TextYAlignment = "Top Center Bottom",
	SortOrder = "Name Custom LayoutOrder",
	FillDirection = "Horizontal Vertical",
	HorizontalAlignment = "Center Left Right",
	VerticalAlignment = "Center Top Bottom",
	AutomaticSize = "None X Y XY",
	ZIndexBehavior = "Global Sibling",
	HighlightDepthMode = "AlwaysOnTop Occluded",
	ForceLimitMode = "Magnitude PerAxis",
	ProximityPromptStyle = "Default Custom",
	ProximityPromptExclusivity = "OnePerButton OneGlobally AlwaysShow",
	RenderFidelity = "Automatic Precise Performance",
	CollisionFidelity = "Default Hull Box PreciseConvexDecomposition",
	MeshType = "Head Torso Wedge Prism Pyramid ParallelRamp RightAngleRamp CornerWedge Brick Sphere Cylinder FileMesh",
	CameraType = "Fixed Watch Attach Track Follow Custom Scriptable Orbital",
	RollOffMode = "Inverse Linear LinearSquare InverseTapered",
	ScaleType = "Stretch Slice Tile Fit Crop",
	ApplyStrokeMode = "Contextual Border",
	LineJoinMode = "Round Bevel Miter",
	TextTruncate = "None AtEnd SplitWord",
	FontWeight = "Thin ExtraLight Light Regular Medium SemiBold Bold ExtraBold Heavy",
	FontStyle = "Normal Italic",
	SizeConstraint = "RelativeXY RelativeXX RelativeYY",
	DataStoreRequestType = "GetAsync SetIncrementAsync UpdateAsync GetSortedAsync SetIncrementSortedAsync OnUpdate ListAsync GetVersionAsync RemoveVersionAsync",
	EmissionDirection = "Right Top Back Left Bottom Front",
	ParticleEmitterShape = "Box Sphere Cylinder Disc",
	ParticleOrientation = "FacingCamera FacingCameraWorldUp VelocityParallel VelocityPerpendicular",
	AlignType = "Parallel Perpendicular PrimaryAxisParallel PrimaryAxisPerpendicular PrimaryAxisLookAt AllAxes",
	DisplayDistanceType = "Viewer Subject None",
	HumanoidHealthDisplayType = "DisplayWhenDamaged AlwaysOn AlwaysOff",
	MembershipType = "None BuildersClub TurboBuildersClub OutrageousBuildersClub Premium",
	CreatorType = "User Group",
	ThrottleState = "Default Disabled",
}
local EnumItemMT = datatype("EnumItem")
local EnumMT = datatype("Enum")
local EnumsMT = datatype("Enums")
local enumCats = {}
local function makeItem(cat, name, value)
	local item = setmetatable({ Name = name, Value = value, EnumType = cat }, EnumItemMT)
	cat._items[name] = item
	table.insert(cat._list, item)
	return item
end
EnumItemMT.__index = function(item, k)
	if k == "IsA" then
		return function(self, name)
			return rawget(self, "EnumType")._name == name
		end
	end
	memberError("EnumItem", k)
end
EnumItemMT.__newindex = readonly("EnumItem")
EnumItemMT.__tostring = function(item)
	return "Enum." .. item.EnumType._name .. "." .. item.Name
end
local function getCat(name)
	local cat = enumCats[name]
	if cat then
		return cat
	end
	local list = ENUM_LISTS[name]
	cat = setmetatable({ _name = name, _items = {}, _list = {}, _open = list == nil }, EnumMT)
	enumCats[name] = cat
	if list then
		local i = 0
		for itemName in string.gmatch(list, "%S+") do
			makeItem(cat, itemName, i)
			i += 1
		end
	else
		note("Enum." .. name .. " is not listed in mock.luau, so any item name is accepted")
	end
	return cat
end
EnumMT.__index = function(cat, k)
	local item = cat._items[k]
	if item then
		return item
	end
	if k == "GetEnumItems" then
		return function()
			return table.clone(cat._list)
		end
	elseif k == "FromName" then
		return function(_, n)
			return cat._items[n]
		end
	elseif k == "FromValue" then
		return function(_, v)
			for _, it in cat._list do
				if it.Value == v then
					return it
				end
			end
			return nil
		end
	end
	if cat._open and type(k) == "string" then
		return makeItem(cat, k, #cat._list)
	end
	error(("%s is not a valid member of \"Enum.%s\""):format(tostring(k), cat._name), 2)
end
EnumMT.__newindex = readonly("Enum")
EnumMT.__tostring = function(cat)
	return cat._name
end
Enum = setmetatable({}, EnumsMT)
EnumsMT.__index = function(_, k)
	if k == "GetEnums" then
		return function()
			local out = {}
			for _, c in enumCats do
				table.insert(out, c)
			end
			return out
		end
	end
	return getCat(k)
end
EnumsMT.__newindex = readonly("Enums")
H.EnumItemMT = EnumItemMT
H.enumCat = getCat

-- Coerce an enum property value: EnumItem of the right enum, its name, or its number.
local function coerceEnum(catName, v)
	local cat = getCat(catName)
	if getmetatable(v) == EnumItemMT then
		if v.EnumType == cat then
			return v
		end
		return nil
	elseif type(v) == "string" then
		return cat._items[v]
	elseif type(v) == "number" then
		for _, it in cat._list do
			if it.Value == v then
				return it
			end
		end
	end
	return nil
end
H.coerceEnum = coerceEnum

-- PhysicalProperties --
local PP = datatype("PhysicalProperties")
PP.__index = function(_, k)
	memberError("PhysicalProperties", k)
end
PP.__newindex = readonly("PhysicalProperties")
PP.__eq = function(a, b)
	return a.Density == b.Density and a.Friction == b.Friction and a.Elasticity == b.Elasticity and a.FrictionWeight == b.FrictionWeight and a.ElasticityWeight == b.ElasticityWeight
end
local DENSITY = { Plastic = 0.7, SmoothPlastic = 0.7, Neon = 0.7, Wood = 0.35, WoodPlanks = 0.35, Marble = 2.56, Slate = 2.69, Concrete = 2.4, Granite = 2.69, Brick = 1.92, Pebble = 2.4, Cobblestone = 2.69, CorrodedMetal = 7.85, DiamondPlate = 7.85, Foil = 2.7, Metal = 7.85, Grass = 0.9, Sand = 1.6, Fabric = 0.7, Ice = 0.919, Glass = 2.4, ForceField = 2.4, Rock = 2.69, Snow = 0.9, Mud = 0.9, Ground = 0.9, Asphalt = 2.36, Sandstone = 2.69, Basalt = 2.69 }
H.DENSITY = DENSITY
PhysicalProperties = { new = function(a, friction, elasticity, fw, ew)
	if getmetatable(a) == EnumItemMT then
		return setmetatable({ Density = DENSITY[a.Name] or 0.7, Friction = 0.3, Elasticity = 0.5, FrictionWeight = 1, ElasticityWeight = 1, AcousticAbsorption = 1 }, PP)
	end
	checkNum("PhysicalProperties.new", 1, a)
	checkNum("PhysicalProperties.new", 2, friction)
	checkNum("PhysicalProperties.new", 3, elasticity)
	return setmetatable({
		Density = math.clamp(a, 0.0001, 100),
		Friction = math.clamp(friction, 0, 2),
		Elasticity = math.clamp(elasticity, 0, 1),
		FrictionWeight = math.clamp(fw or 1, 0, 100),
		ElasticityWeight = math.clamp(ew or 1, 0, 100),
		AcousticAbsorption = 1,
	}, PP)
end }

-- TweenInfo --
local TI = datatype("TweenInfo")
TI.__index = function(_, k)
	memberError("TweenInfo", k)
end
TI.__newindex = readonly("TweenInfo")
TweenInfo = { new = function(t, style, dir, repeatCount, reverses, delayTime)
	t = optNum("TweenInfo.new", 1, t, 1)
	if style ~= nil and getmetatable(style) ~= EnumItemMT then
		argError("TweenInfo.new", 2, "EnumItem", style)
	end
	if dir ~= nil and getmetatable(dir) ~= EnumItemMT then
		argError("TweenInfo.new", 3, "EnumItem", dir)
	end
	return setmetatable({
		Time = t,
		EasingStyle = style or Enum.EasingStyle.Quad,
		EasingDirection = dir or Enum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses == true,
		DelayTime = delayTime or 0,
	}, TI)
end }

-- Ray / Region3 --
local RAY = datatype("Ray")
local RAYmethods = {}
RAY.__index = function(r, k)
	if k == "Unit" then
		return setmetatable({ Origin = r.Origin, Direction = r.Direction.Unit }, RAY)
	end
	local m = RAYmethods[k]
	if m then
		return m
	end
	memberError("Ray", k)
end
RAY.__newindex = readonly("Ray")
function RAYmethods.ClosestPoint(r, p)
	local d = r.Direction.Unit
	local t = math.max(0, (p - r.Origin):Dot(d))
	return r.Origin + d * t
end
function RAYmethods.Distance(r, p)
	return (p - r:ClosestPoint(p)).Magnitude
end
Ray = { new = function(o, d)
	checkV3("Ray.new", 1, o)
	checkV3("Ray.new", 2, d)
	return setmetatable({ Origin = o, Direction = d }, RAY)
end }
local R3 = datatype("Region3")
R3.__index = function(r, k)
	if k == "CFrame" then
		local c = (r._min + r._max) / 2
		return CFrame.new(c)
	elseif k == "Size" then
		return r._max - r._min
	elseif k == "ExpandToGrid" then
		return function(self, res)
			checkNum("ExpandToGrid", 1, res)
			local function lo(x)
				return math.floor(x / res) * res
			end
			local function hi(x)
				return math.ceil(x / res) * res
			end
			return setmetatable({ _min = v3(lo(self._min.X), lo(self._min.Y), lo(self._min.Z)), _max = v3(hi(self._max.X), hi(self._max.Y), hi(self._max.Z)) }, R3)
		end
	end
	memberError("Region3", k)
end
R3.__newindex = readonly("Region3")
Region3 = { new = function(a, b)
	checkV3("Region3.new", 1, a)
	checkV3("Region3.new", 2, b)
	return setmetatable({ _min = a, _max = b }, R3)
end }
H.R3 = R3

-- Font --
local FONT = datatype("Font")
FONT.__index = function(f, k)
	if k == "Bold" then
		return rawget(f, "Weight") == Enum.FontWeight.Bold
	end
	memberError("Font", k)
end
FONT.__eq = function(a, b)
	return a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style
end
Font = {
	new = function(family, weight, style)
		if type(family) ~= "string" then
			argError("Font.new", 1, "string", family)
		end
		return setmetatable({ Family = family, Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal }, FONT)
	end,
	fromEnum = function(e)
		if getmetatable(e) ~= EnumItemMT or e.EnumType ~= getCat("Font") then
			argError("Font.fromEnum", 1, "Enum.Font", e)
		end
		local bold = string.find(e.Name, "Bold") or string.find(e.Name, "Black")
		return setmetatable({ Family = "rbxasset://fonts/families/" .. e.Name .. ".json", Weight = bold and Enum.FontWeight.Bold or Enum.FontWeight.Regular, Style = Enum.FontStyle.Normal }, FONT)
	end,
	fromName = function(name, weight, style)
		return setmetatable({ Family = "rbxasset://fonts/families/" .. name .. ".json", Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal }, FONT)
	end,
	fromId = function(id, weight, style)
		return setmetatable({ Family = "rbxassetid://" .. tostring(id), Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal }, FONT)
	end,
}

-- Random (deterministic: xorshift-free LCG over 2^31-1 is too coarse; use a 53-bit split-mix) --
local RANDOM = datatype("Random")
local RANDOMmethods = {}
local randomSeedCounter = 0
local function nextState(r)
	-- Park-Miller on two lanes, combined for 52 bits of randomness
	r._a = (r._a * 48271) % 2147483647
	r._b = (r._b * 16807) % 2147483647
	return ((r._a - 1) * 2147483646 + (r._b - 1)) / (2147483646 * 2147483646)
end
RANDOM.__index = function(_, k)
	local m = RANDOMmethods[k]
	if m then
		return m
	end
	memberError("Random", k)
end
function RANDOMmethods.NextNumber(r, a, b)
	local x = nextState(r)
	if a == nil and b == nil then
		return x
	end
	checkNum("NextNumber", 1, a)
	checkNum("NextNumber", 2, b)
	return a + (b - a) * x
end
function RANDOMmethods.NextInteger(r, a, b)
	checkNum("NextInteger", 1, a)
	checkNum("NextInteger", 2, b)
	a, b = math.floor(a), math.floor(b)
	if b < a then
		error("invalid argument #2 to 'NextInteger' (interval is empty)", 2)
	end
	return a + math.floor(nextState(r) * (b - a + 1))
end
function RANDOMmethods.NextUnitVector(r)
	local z = 2 * nextState(r) - 1
	local t = 2 * math.pi * nextState(r)
	local s = math.sqrt(1 - z * z)
	return v3(s * math.cos(t), s * math.sin(t), z)
end
function RANDOMmethods.Shuffle(r, t)
	for i = #t, 2, -1 do
		local j = r:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
function RANDOMmethods.Clone(r)
	return setmetatable({ _a = r._a, _b = r._b }, RANDOM)
end
Random = { new = function(seed)
	if seed == nil then
		randomSeedCounter += 1
		seed = 12345 + randomSeedCounter
	end
	checkNum("Random.new", 1, seed)
	local s = math.floor(math.abs(seed)) % 2147483646
	local r = setmetatable({ _a = s + 1, _b = (s * 7919) % 2147483646 + 1 }, RANDOM)
	nextState(r)
	return r
end }
math.randomseed(1)

-- DateTime --
local DT = datatype("DateTime")
DT.__index = function(d, k)
	if k == "UnixTimestamp" then
		return math.floor(d._ms / 1000)
	elseif k == "UnixTimestampMillis" then
		return d._ms
	elseif k == "ToIsoDate" then
		return function(self)
			return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(self._ms / 1000))
		end
	elseif k == "ToUniversalTime" or k == "ToLocalTime" then
		return function(self)
			local t = os.date("!*t", math.floor(self._ms / 1000))
			return { Year = t.year, Month = t.month, Day = t.day, Hour = t.hour, Minute = t.min, Second = t.sec, Millisecond = self._ms % 1000 }
		end
	elseif k == "FormatUniversalTime" or k == "FormatLocalTime" then
		return function(self, format)
			return os.date("!%Y-%m-%d %H:%M:%S", math.floor(self._ms / 1000))
		end
	end
	memberError("DateTime", k)
end
DateTime = {
	now = function()
		return setmetatable({ _ms = math.floor((EPOCH + H.now) * 1000) }, DT)
	end,
	fromUnixTimestamp = function(s)
		return setmetatable({ _ms = math.floor(s * 1000) }, DT)
	end,
	fromUnixTimestampMillis = function(ms)
		return setmetatable({ _ms = ms }, DT)
	end,
}

-- RaycastParams / OverlapParams / RaycastResult --
local RP = datatype("RaycastParams")
local RPmethods = {}
local RP_FIELDS = { FilterDescendantsInstances = true, FilterType = true, IgnoreWater = true, CollisionGroup = true, RespectCanCollide = true, BruteForceAllSlow = true }
local function isInstance(v)
	return H.isInstance ~= nil and H.isInstance(v)
end
RP.__index = function(p, k)
	local m = RPmethods[k]
	if m then
		return m
	end
	local f = rawget(p, "_f")
	if RP_FIELDS[k] then
		return f[k]
	end
	memberError(TYPE[getmetatable(p)], k)
end
local function setFilter(p, list)
	if type(list) ~= "table" then
		error("Unable to assign property FilterDescendantsInstances. Array expected, got " .. typeofImpl(list), 3)
	end
	local out = {}
	for i, inst in list do
		if not isInstance(inst) then
			error(("Unable to assign property FilterDescendantsInstances. Instance expected at index %s, got %s"):format(tostring(i), typeofImpl(inst)), 3)
		end
		table.insert(out, inst)
	end
	rawget(p, "_f").FilterDescendantsInstances = out
end
RP.__newindex = function(p, k, v)
	if k == "FilterDescendantsInstances" then
		setFilter(p, v)
		return
	elseif k == "FilterType" then
		local e = coerceEnum("RaycastFilterType", v)
		if not e then
			error("Unable to assign property FilterType. Enum.RaycastFilterType expected", 2)
		end
		if e.Name == "Blacklist" then
			e = Enum.RaycastFilterType.Exclude
		elseif e.Name == "Whitelist" then
			e = Enum.RaycastFilterType.Include
		end
		rawget(p, "_f").FilterType = e
		return
	elseif k == "MaxParts" and getmetatable(p) ~= RP then
		rawget(p, "_f").MaxParts = v
		return
	elseif RP_FIELDS[k] then
		rawget(p, "_f")[k] = v
		return
	end
	memberError(TYPE[getmetatable(p)], k)
end
function RPmethods.AddToFilter(p, x)
	local list = rawget(p, "_f").FilterDescendantsInstances
	if isInstance(x) then
		table.insert(list, x)
	else
		for _, i in x do
			table.insert(list, i)
		end
	end
end
RaycastParams = { new = function()
	return setmetatable({ _f = { FilterDescendantsInstances = {}, FilterType = Enum.RaycastFilterType.Exclude, IgnoreWater = false, CollisionGroup = "Default", RespectCanCollide = false, BruteForceAllSlow = false } }, RP)
end }
local OP = datatype("OverlapParams")
OP.__index = function(p, k)
	if k == "MaxParts" then
		return rawget(p, "_f").MaxParts
	end
	return RP.__index(p, k)
end
OP.__newindex = RP.__newindex
OverlapParams = { new = function()
	return setmetatable({ _f = { FilterDescendantsInstances = {}, FilterType = Enum.RaycastFilterType.Exclude, MaxParts = 0, CollisionGroup = "Default", RespectCanCollide = false, BruteForceAllSlow = false } }, OP)
end }
local RR = datatype("RaycastResult")
RR.__index = function(_, k)
	memberError("RaycastResult", k)
end
RR.__newindex = readonly("RaycastResult")
H.RaycastResult = function(inst, pos, normal, material, distance)
	return setmetatable({ Instance = inst, Position = pos, Normal = normal, Material = material, Distance = distance }, RR)
end

-- Axes / Faces (rare) --
Axes = { new = function(...) return { ... } end }
Faces = { new = function(...) return { ... } end }

-- typeof ------------------------------------------------------------------------------------------------------------
local InstMT -- set in the instance section
local SignalMT, ConnectionMT
typeofImpl = function(v)
	local t = type(v)
	if t ~= "table" and t ~= "userdata" then
		return t
	end
	local mt = getmetatable(v)
	if mt == nil then
		return t
	end
	if mt == InstMT then
		return "Instance"
	end
	local name = TYPE[mt]
	if name then
		return name
	end
	return t
end
typeof = typeofImpl
H.TYPE = TYPE
H.mt = { V3 = V3, V2 = V2, CF = CF, C3 = C3, BC = BC, UD = UD, UD2 = UD2, RECT = RECT, NR = NR, NS = NS, CS = CS, PP = PP, TI = TI, FONT = FONT, EnumItem = EnumItemMT }
