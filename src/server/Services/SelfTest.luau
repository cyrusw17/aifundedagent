--!nonstrict
-- Studio self-tests. Set the Workspace attribute RunSelfTests (a boolean, true) in Studio and press Play: once the
-- world is built, every registered suite runs and the Output shows one line per check, then a summary:
--
--   [SelfTest] PASS Vehicles: pickup drives forward on flat ground (31.2 studs in 2 s)
--   [SelfTest] FAIL Vehicles: pickup climbs a 20 degree ramp (rose 0.4 studs, want > 3)
--   [SelfTest] DONE 41 passed, 1 failed, 2 skipped in 6 suites
--
-- Setting the attribute during Play runs them again. Outside Studio nothing here ever runs.
--
-- Adding a suite: make src/server/SelfTests/<Thread>.luau returning a function that registers it:
--
--   return function(SelfTest)
--       SelfTest.register("Conveyor", function(t)
--           local spot = t.place()                       -- a CFrame on a flat, empty test pad off the map
--           local bale = Bales.spawn(spot.Position + Vector3.new(0, 3, 0))
--           t.cleanup(bale.body)                         -- destroyed when the suite ends, pass or fail
--           t.check("bale is free physics", not bale.body.Anchored)
--           t.near("bale length", bale.body.Size.X, 4.6, 0.01)
--           t.wait(1)
--       end)
--   end
--
-- t.check(label, ok, detail?)   PASS when ok is truthy; detail is printed either way
-- t.equal(label, got, want)     PASS when got == want
-- t.near(label, got, want, tol) PASS when |got - want| <= tol
-- t.skip(label, why)            counts as skipped, not failed (say why: no player joined, mesh not imported...)
-- t.player(timeout?)            the first player in the game (waits up to timeout s, default 10), or nil
-- t.place()                     a fresh CFrame on this suite's own 200 x 200 test pad at y 600, far from the map
-- t.center                      the pad's center (CFrame, on its top surface), for tests that need their own layout
-- t.cleanup(instance)           destroyed after the suite
-- t.wait(seconds)
-- A suite that errors, or runs longer than 120 s, is one FAIL line and the next suite still runs.
local RunService = game:GetService("RunService")

local SelfTest = {}

local suites = {} -- { { name, fn } } in registration order
local running = false

function SelfTest.register(name, fn)
	assert(typeof(name) == "string" and typeof(fn) == "function", "SelfTest.register(name, fn)")
	table.insert(suites, { name = name, fn = fn })
end

local PAD_Y = 600
local PAD_SIZE = 200
local SUITE_TIMEOUT = 120

local function makePad(index)
	-- Each suite gets its own pad in a row east of the map, so suites never trip over each other's leftovers.
	local center = Vector3.new(4000 + index * (PAD_SIZE + 50), PAD_Y, 4000)
	local pad = Instance.new("Part")
	pad.Name = "SelfTestPad"
	pad.Anchored = true
	pad.Size = Vector3.new(PAD_SIZE, 2, PAD_SIZE)
	pad.CFrame = CFrame.new(center - Vector3.new(0, 1, 0))
	pad.Material = Enum.Material.Concrete
	pad.Color = Color3.fromRGB(120, 120, 120)
	pad.Parent = workspace
	return pad, center
end

local function runSuite(index, suite, totals)
	local pad, center = makePad(index)
	local trash = { pad }
	local slots = 0
	local finished = false
	local function line(kind, label, detail)
		print(("[SelfTest] %s %s: %s%s"):format(kind, suite.name, label, detail and (" (" .. tostring(detail) .. ")") or ""))
	end
	local t = {}
	function t.check(label, ok, detail)
		if ok then
			totals.passed += 1
			line("PASS", label, detail)
		else
			totals.failed += 1
			line("FAIL", label, detail)
		end
		return ok and true or false
	end
	function t.equal(label, got, want)
		return t.check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
	end
	function t.near(label, got, want, tol)
		local ok = typeof(got) == "number" and math.abs(got - want) <= tol
		return t.check(label, ok, ("got %s, want %s +/- %s"):format(tostring(got), tostring(want), tostring(tol)))
	end
	function t.skip(label, why)
		totals.skipped += 1
		line("SKIP", label, why)
	end
	function t.player(timeout)
		local Players = game:GetService("Players")
		local deadline = os.clock() + (timeout or 10)
		while not Players:GetPlayers()[1] and os.clock() < deadline do
			task.wait(0.2)
		end
		return Players:GetPlayers()[1]
	end
	function t.place()
		-- Spots 30 studs apart in a 6 x 6 grid on the pad.
		local i = slots
		slots += 1
		local x, z = i % 6, math.floor(i / 6) % 6
		return CFrame.new(center + Vector3.new(-75 + x * 30, 0, -75 + z * 30))
	end
	function t.cleanup(instance)
		table.insert(trash, instance)
		return instance
	end
	t.wait = task.wait
	t.center = CFrame.new(center)

	local thread = task.spawn(function()
		local ok, err = xpcall(suite.fn, debug.traceback, t)
		if not ok then
			totals.failed += 1
			line("FAIL", "suite crashed", err)
		end
		finished = true
	end)
	local deadline = os.clock() + SUITE_TIMEOUT
	while not finished and os.clock() < deadline do
		task.wait(0.25)
	end
	if not finished then
		pcall(task.cancel, thread)
		totals.failed += 1
		line("FAIL", "suite timed out", ("still running after %d s"):format(SUITE_TIMEOUT))
	end
	for _, instance in trash do
		pcall(function()
			instance:Destroy()
		end)
	end
end

-- Runs every suite once. Suites in src/server/SelfTests are loaded the first time.
local loaded = false
function SelfTest.runAll()
	if running then
		return
	end
	running = true
	if not loaded then
		loaded = true
		local folder = script.Parent.Parent:FindFirstChild("SelfTests")
		for _, module in (folder and folder:GetChildren() or {}) do
			if module:IsA("ModuleScript") then
				local ok, result = pcall(require, module)
				if ok and typeof(result) == "function" then
					local okRegister, err = pcall(result, SelfTest)
					if not okRegister then
						warn(("[SelfTest] FAIL %s: registering crashed (%s)"):format(module.Name, tostring(err)))
					end
				elseif not ok then
					warn(("[SelfTest] FAIL %s: suite file did not load (%s)"):format(module.Name, tostring(result)))
				end
			end
		end
	end
	local totals = { passed = 0, failed = 0, skipped = 0 }
	local started = os.clock()
	print(("[SelfTest] running %d suites"):format(#suites))
	for index, suite in suites do
		runSuite(index, suite, totals)
	end
	local summary = ("[SelfTest] DONE %d passed, %d failed, %d skipped in %d suites (%.1f s)"):format(
		totals.passed,
		totals.failed,
		totals.skipped,
		#suites,
		os.clock() - started
	)
	if totals.failed > 0 then
		warn(summary)
	else
		print(summary)
	end
	workspace:SetAttribute("SelfTestPassed", totals.passed)
	workspace:SetAttribute("SelfTestFailed", totals.failed)
	running = false
end

-- Called once the world is built. Runs now if the flag is already set, and again whenever it is set during Play.
function SelfTest.start()
	if not RunService:IsStudio() then
		return
	end
	local function maybeRun()
		if workspace:GetAttribute("RunSelfTests") == true then
			task.spawn(function()
				task.wait(3) -- let the world's first physics settle
				SelfTest.runAll()
			end)
		end
	end
	workspace:GetAttributeChangedSignal("RunSelfTests"):Connect(maybeRun)
	maybeRun()
end

return SelfTest
