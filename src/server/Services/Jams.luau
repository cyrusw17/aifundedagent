--!nonstrict
-- Jams and clears. A bale that sits still on a moving belt for JAM_SECONDS with nothing in front of it (so it is
-- caught on a rail or a corner, not waiting in a queue at a machine) is jammed: it glows amber and gets a "Clear jam"
-- prompt. Clearing lifts it, lines it up with the belt and sends it on its way. Bales queued nose to tail behind a
-- sorter's flap are not jams; that backed-up line is how a player sees a sorter is too slow.
-- Starts itself when first required (Machines.luau requires it).
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Bales = require(script.Parent.Bales)

local Jams = {}

local JAM_SECONDS = 10
local STILL_SPEED = 0.6 -- studs per second; slower than this counts as not moving
local CHECK_SECONDS = 1
local GLOW = Color3.fromRGB(255, 176, 60)

local stillSince = {} -- bale body -> os.clock() it stopped
local jammed = {} -- bale body -> { highlight, prompt }

local downParams = RaycastParams.new()
downParams.FilterType = Enum.RaycastFilterType.Include

-- The belt a body rests on, or nil.
local function beltUnder(body)
	downParams.FilterDescendantsInstances = CollectionService:GetTagged("ConveyorBelt")
	local hit = Workspace:Raycast(body.Position, Vector3.new(0, -4, 0), downParams)
	return hit and hit.Instance
end

-- True when something solid sits right in front of the body along dir: another bale, a machine's flap. Then the
-- bale is queuing, not jammed.
local function blockedAhead(body, dir)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { body }
	local reach = math.max(body.Size.X, body.Size.Z) / 2 + 1
	local ahead = CFrame.new(body.Position + dir * reach)
	for _, p in Workspace:GetPartBoundsInBox(ahead, Vector3.new(2.5, 2, 2.5), params) do
		if p.CanCollide and not CollectionService:HasTag(p, "ConveyorBelt") and p.Name ~= "Rail" and p.Name ~= "RampRail" then
			return true
		end
	end
	return false
end

local function unjam(body)
	local j = jammed[body]
	if j then
		j.highlight:Destroy()
		j.prompt:Destroy()
		jammed[body] = nil
	end
	stillSince[body] = nil
end

local function clear(body)
	local belt = beltUnder(body)
	if not belt or not body.Parent then
		unjam(body)
		return
	end
	local v = belt.AssemblyLinearVelocity
	local dir = v.Magnitude > 0.01 and v.Unit or belt.CFrame.LookVector
	-- Lift it clear of whatever caught it, square it to the belt, and push it along.
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local look = flat.Magnitude > 0.01 and flat.Unit or Vector3.zAxis
	local at = Vector3.new(belt.Position.X, body.Position.Y + 1, belt.Position.Z)
	body.CFrame = CFrame.lookAt(at, at + look) * CFrame.Angles(0, math.pi / 2, 0)
	body.AssemblyLinearVelocity = dir * 6
	body.AssemblyAngularVelocity = Vector3.zero
	unjam(body)
end

local function markJammed(body)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = GLOW
	highlight.OutlineColor = GLOW
	highlight.FillTransparency = 0.6
	highlight.Parent = body
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClearJam"
	prompt.ActionText = "Clear jam"
	prompt.ObjectText = "Stuck bale"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function()
		clear(body)
	end)
	prompt.Parent = body
	jammed[body] = { highlight = highlight, prompt = prompt }
end

local function check()
	local now = os.clock()
	for _, body in CollectionService:GetTagged("HayBale") do
		local b = Bales.fromPart(body)
		if not b or b.gone or b.carriedBy or body.Anchored then
			unjam(body)
			continue
		end
		local belt = beltUnder(body)
		local beltV = belt and belt.AssemblyLinearVelocity
		if not belt or beltV.Magnitude < 0.01 or body.AssemblyLinearVelocity.Magnitude > STILL_SPEED then
			unjam(body)
			continue
		end
		if blockedAhead(body, beltV.Unit) then
			stillSince[body] = nil -- queuing behind something: fine
			continue
		end
		stillSince[body] = stillSince[body] or now
		if not jammed[body] and now - stillSince[body] >= JAM_SECONDS then
			markJammed(body)
		end
	end
	for body in stillSince do
		if not body.Parent then
			stillSince[body] = nil
			jammed[body] = nil
		end
	end
end

task.spawn(function()
	while true do
		task.wait(CHECK_SECONDS)
		local ok, err = pcall(check)
		if not ok then
			warn("[Jams] " .. tostring(err))
		end
	end
end)

Jams.clear = clear
return Jams
