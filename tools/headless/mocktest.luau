-- Checks the mock against known Roblox behaviour: `python3 tools/headless/run.py LUAU --mock-test`.
-- Run it after changing mock*.luau. Every line prints ok or FAIL; the run fails on any FAIL.
local fails = 0
local function check(label, ok, detail)
	if ok then
		print("ok   " .. label)
	else
		fails += 1
		print("FAIL " .. label .. (detail and (" (" .. tostring(detail) .. ")") or ""))
	end
end
local function near(a, b, tol)
	tol = tol or 1e-6
	if typeof(a) == "number" then
		return math.abs(a - b) <= tol
	end
	return (a - b).Magnitude <= tol
end
local function errors(fn, pattern)
	local ok, err = pcall(fn)
	return not ok and (pattern == nil or string.find(tostring(err), pattern, 1, true) ~= nil), err
end

-- Math -----------------------------------------------------------------------------------------------------------
check("Angles(90deg,0,0).LookVector is up", near(CFrame.Angles(math.rad(90), 0, 0).LookVector, Vector3.new(0, 1, 0)))
check("Angles(0,90deg,0).LookVector is -X", near(CFrame.Angles(0, math.rad(90), 0).LookVector, Vector3.new(-1, 0, 0)))
local look = CFrame.lookAt(Vector3.zero, Vector3.new(1, 0, 0))
check("lookAt +X: LookVector", near(look.LookVector, Vector3.new(1, 0, 0)))
check("lookAt +X: RightVector is +Z", near(look.RightVector, Vector3.new(0, 0, 1)))
check("lookAt +X: UpVector", near(look.UpVector, Vector3.new(0, 1, 0)))
check("fromAxisAngle(y) == Angles(0,a,0)", CFrame.fromAxisAngle(Vector3.yAxis, 0.7):FuzzyEq(CFrame.Angles(0, 0.7, 0)))
check("fromAxisAngle(x) == Angles(a,0,0)", CFrame.fromAxisAngle(Vector3.xAxis, -1.1):FuzzyEq(CFrame.Angles(-1.1, 0, 0)))
local c = CFrame.new(3, 4, 5) * CFrame.Angles(0.3, -1.2, 2.0)
check("Inverse * c is identity", (c:Inverse() * c):FuzzyEq(CFrame.identity))
local rx, ry, rz = c:ToEulerAnglesXYZ()
check("ToEulerAnglesXYZ round trip", (CFrame.new(c.Position) * CFrame.Angles(rx, ry, rz)):FuzzyEq(c))
local ox, oy, oz = c:ToOrientation()
check("ToOrientation round trip", (CFrame.new(c.Position) * CFrame.fromOrientation(ox, oy, oz)):FuzzyEq(c))
check("PointToObjectSpace inverts PointToWorldSpace", near(c:PointToObjectSpace(c:PointToWorldSpace(Vector3.new(1, 2, 3))), Vector3.new(1, 2, 3)))
check("ToObjectSpace", (c * c:ToObjectSpace(CFrame.new(9, 9, 9))):FuzzyEq(CFrame.new(9, 9, 9)))
local half = CFrame.new():Lerp(CFrame.new(10, 0, 0) * CFrame.Angles(0, math.rad(90), 0), 0.5)
check("Lerp halfway position", near(half.Position, Vector3.new(5, 0, 0)))
local _, hy = half:ToOrientation()
check("Lerp halfway rotation", near(hy, math.rad(45), 1e-6), math.deg(hy))
check("CFrame.new(pos, lookAt) == lookAt", CFrame.new(Vector3.zero, Vector3.new(0, 0, 5)):FuzzyEq(CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, 5))))
check("CFrame + Vector3", (CFrame.new(1, 2, 3) + Vector3.new(1, 1, 1)).Position == Vector3.new(2, 3, 4))
check("Rotation drops position", CFrame.new(1, 2, 3).Rotation == CFrame.identity)
check("Vector3 Max/Min", Vector3.new(1, 5, 3):Max(Vector3.new(2, 0, 4)) == Vector3.new(2, 5, 4))
check("Vector3 * number", Vector3.new(1, 2, 3) * 2 == Vector3.new(2, 4, 6))
check("Vector3 + number errors", errors(function()
	return Vector3.new() + 1
end, "arithmetic"))
check("Vector3 is immutable", errors(function()
	local v = Vector3.new()
	v.X = 1
end))
check("iterating a Vector3 errors", errors(function()
	for _ in Vector3.new() do
	end
end))
local h, s, v = Color3.new(1, 0, 0):ToHSV()
check("Color3 red ToHSV", h == 0 and s == 1 and v == 1)
check("Color3 Lerp", Color3.new(0, 0, 0):Lerp(Color3.new(1, 1, 1), 0.5) == Color3.new(0.5, 0.5, 0.5))
check("Color3.fromHSV(1/3,1,1) is green", near(Color3.fromHSV(1 / 3, 1, 1).G, 1) and near(Color3.fromHSV(1 / 3, 1, 1).R, 0))
check("Enum items equal themselves", Enum.Material.Wood == Enum.Material.Wood and Enum.Material.Wood ~= Enum.Material.Metal)
check("Enum.Material.Bogus errors", errors(function()
	return Enum.Material.Bogus
end))
check("EnumItem Name/Value", Enum.Material.Wood.Name == "Wood" and typeof(Enum.Material.Wood.Value) == "number")
check("NumberSequence needs t=0..1", errors(function()
	return NumberSequence.new({ NumberSequenceKeypoint.new(0.2, 1), NumberSequenceKeypoint.new(1, 0) })
end))
check("NumberRange min > max errors", errors(function()
	return NumberRange.new(5, 1)
end))
check("typeof", typeof(Vector3.zero) == "Vector3" and typeof(CFrame.identity) == "CFrame" and typeof(Enum.Material.Wood) == "EnumItem" and typeof(Instance.new("Part")) == "Instance")
check("typeof inside a loaded chunk (game modules)", (loadstring("return typeof(...)", "@chunk"))(Vector3.one) == "Vector3")
local r1, r2 = Random.new(7), Random.new(7)
check("Random is deterministic per seed", r1:NextNumber() == r2:NextNumber())
check("NextInteger empty interval errors", errors(function()
	return Random.new(1):NextInteger(5, 1)
end))

-- Instances ------------------------------------------------------------------------------------------------------------
local part = Instance.new("Part")
check("Part IsA BasePart/PVInstance/Instance", part:IsA("BasePart") and part:IsA("PVInstance") and part:IsA("Instance") and not part:IsA("Model"))
check("unknown member errors with MOCK MISSING hint", errors(function()
	return part.Bogus
end, "not a valid member of Part"))
check("Part.Size = number errors", errors(function()
	part.Size = 5
end, "Vector3 expected"))
check("Part.Material = Enum.PartType errors", errors(function()
	part.Material = Enum.PartType.Ball
end))
check("Part.Material = \"Wood\" works", pcall(function()
	part.Material = "Wood"
end) and part.Material == Enum.Material.Wood)
check("Part.Position sets CFrame", (function()
	part.Position = Vector3.new(1, 2, 3)
	return part.CFrame.Position == Vector3.new(1, 2, 3)
end)())
check("method called with . errors", errors(function()
	return part.GetChildren()
end, "Expected ':'"))
local model = Instance.new("Model")
part.Parent = model
check("child by name", model.Part == part and model:FindFirstChild("Part") == part)
check("circular parent errors", errors(function()
	model.Parent = part
end, "circular"))
model:Destroy()
check("Destroy locks Parent", errors(function()
	part.Parent = workspace
end, "locked"))
check("SetAttribute table errors", errors(function()
	Instance.new("Folder"):SetAttribute("X", {})
end))
check("SetAttribute bad name errors", errors(function()
	Instance.new("Folder"):SetAttribute("a b", 1)
end))
check("GetPropertyChangedSignal bad name errors", errors(function()
	Instance.new("Part"):GetPropertyChangedSignal("Bogus")
end))
local m2 = Instance.new("Model")
local a = Instance.new("Part")
a.Size = Vector3.new(2, 2, 2)
a.CFrame = CFrame.new(10, 0, 0)
a.Parent = m2
local b = a:Clone()
b.CFrame = CFrame.new(20, 0, 0)
b.Parent = m2
m2.PrimaryPart = a
m2:PivotTo(CFrame.new(0, 5, 0))
check("Model:PivotTo moves parts", a.Position == Vector3.new(0, 5, 0) and b.Position == Vector3.new(10, 5, 0))
local _, size = m2:GetBoundingBox()
check("GetBoundingBox size", near(size, Vector3.new(12, 2, 2)), size)
check("SetNetworkOwner outside Workspace errors", errors(function()
	a:SetNetworkOwner(nil)
end, "descendent of Workspace"))
local anchored = Instance.new("Part")
anchored.Anchored = true
anchored.Parent = workspace
check("SetNetworkOwner on anchored errors", errors(function()
	anchored:SetNetworkOwner(nil)
end, "Anchored"))
local free = Instance.new("Part")
free.Parent = workspace
local weld = Instance.new("WeldConstraint")
weld.Part0, weld.Part1 = free, anchored
weld.Parent = free
check("SetNetworkOwner welded to anchored errors", errors(function()
	free:SetNetworkOwner(nil)
end, "Anchored"))
weld:Destroy()
check("SetNetworkOwner on free part works", pcall(function()
	free:SetNetworkOwner(nil)
end))
local ev = Instance.new("RemoteEvent")
check("FireClient without Player errors", errors(function()
	ev:FireClient(free)
end, "Player"))
check("Instance.new(\"Bogus\") errors", errors(function()
	Instance.new("Bogus")
end))
local ground = Instance.new("Part")
ground.Anchored = true
ground.Size = Vector3.new(100, 2, 100)
ground.CFrame = CFrame.new(500, 0, 500)
ground.Parent = workspace
local hit = workspace:Raycast(Vector3.new(510, 50, 490), Vector3.new(0, -100, 0))
check("Raycast hits the top of a part", hit and hit.Instance == ground and near(hit.Position.Y, 1) and near(hit.Normal, Vector3.yAxis), hit and hit.Position)
check("GetPartBoundsInBox finds it", table.find(workspace:GetPartBoundsInBox(CFrame.new(540, 0, 540), Vector3.new(4, 4, 4)), ground) ~= nil)
check("GetPartBoundsInBox misses far away", table.find(workspace:GetPartBoundsInBox(CFrame.new(700, 0, 700), Vector3.new(4, 4, 4)), ground) == nil)
local params = RaycastParams.new()
params.FilterDescendantsInstances = { ground }
check("Raycast Exclude filter", workspace:Raycast(Vector3.new(510, 50, 490), Vector3.new(0, -100, 0), params) == nil)
local tagged = Instance.new("Part")
game:GetService("CollectionService"):AddTag(tagged, "T")
check("GetTagged ignores instances outside the DataModel", #game:GetService("CollectionService"):GetTagged("T") == 0)
tagged.Parent = workspace
check("GetTagged finds it once parented", #game:GetService("CollectionService"):GetTagged("T") == 1)

-- DataStores ---------------------------------------------------------------------------------------------------------
local store = game:GetService("DataStoreService"):GetDataStore("Test")
H.run(function()
	check("SetAsync mixed table errors", errors(function()
		store:SetAsync("k", { 1, 2, x = 3 })
	end, "mixed"))
	check("SetAsync Vector3 errors", errors(function()
		store:SetAsync("k", { v = Vector3.new() })
	end, "Vector3"))
	store:SetAsync("k", { a = 1, list = { 1, 2 } })
	local got = store:GetAsync("k")
	check("GetAsync returns a copy", got.a == 1 and got.list[2] == 2)
	local new = store:UpdateAsync("k", function(old)
		old.a += 1
		return old
	end)
	check("UpdateAsync writes", new.a == 2 and store:GetAsync("k").a == 2)
	store:UpdateAsync("k", function()
		return nil
	end)
	check("UpdateAsync nil cancels", store:GetAsync("k").a == 2)
	check("UpdateAsync transform that yields errors", errors(function()
		store:UpdateAsync("k", function(old)
			task.wait(1)
			return old
		end)
	end, "yield"))
end, "datastore tests")
H.advance(2)

-- Scheduler -----------------------------------------------------------------------------------------------------------
local order = {}
H.run(function()
	task.delay(1, function()
		table.insert(order, "delay1")
	end)
	task.spawn(function()
		table.insert(order, "spawn")
		task.wait(0.5)
		table.insert(order, "wait0.5")
	end)
	table.insert(order, "after spawn")
	task.defer(function()
		table.insert(order, "defer")
	end)
end, "scheduler test")
H.advance(2)
check("scheduler order", table.concat(order, ",") == "spawn,after spawn,defer,wait0.5,delay1", table.concat(order, ","))
local ticks = 0
H.run(function()
	while true do
		task.wait(1)
		ticks += 1
	end
end, "loop")
H.advance(10)
check("while true task.wait(1) loop runs ~10 times in 10 s", ticks >= 9 and ticks <= 10, ticks)
local bindable = Instance.new("BindableEvent")
local got
H.run(function()
	got = bindable.Event:Wait()
end, "wait")
bindable:Fire(42)
check("Signal:Wait gets the fired value", got == 42)
local errBefore = #H.errors
H.run(function()
	local x = nil
	return x.y
end, "deliberate error")
check("errors in threads are reported", #H.errors == errBefore + 1)
table.remove(H.errors)

print(fails == 0 and "MOCKTEST PASS" or ("MOCKTEST FAIL " .. fails))
print("HEADLESS_RESULT errors=" .. fails .. " warnings=0")
