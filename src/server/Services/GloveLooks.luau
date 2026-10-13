--!nonstrict
-- What gloves look like: the Rustic Blender glove on each hand of whoever wears a pair, and on the glove stand.
-- Gloves.luau decides who owns and wears what (the player attribute "GloveId"); this only adds the meshes. A glove
-- that was not imported shows nothing on the hands and keeps its placeholder on the stand.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GloveConfig = require(ReplicatedStorage.Shared.Config.Gloves)
local Props = require(script.Parent.Props)

local GloveLooks = {}

local byId = {}
for _, def in GloveConfig.Tiers do
	byId[def.id] = def
end
for _, def in GloveConfig.QuestTiers do
	byId[def.id] = def
end

-- The glove is modeled as a right glove, fingers +Y and back of hand -Z. On a hand part the fingers point down
-- (-Y) and the back of the hand faces out: +X on the right hand, -X on the left. Meshes cannot be mirrored, so the
-- left hand wears the same glove turned to face out (its thumb ends up on the outside).
local RIGHT = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(0, -1, 0), Vector3.new(-1, 0, 0))
local LEFT = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))

-- The hand to put a glove on, the point on it where the glove sits, and how long the glove should be.
local function handOf(character, side)
	local hand = character:FindFirstChild(side .. "Hand")
	if hand then
		local length = math.max(hand.Size.X, hand.Size.Y, hand.Size.Z) * 1.4
		return hand, CFrame.new(0, 0.1, 0), length
	end
	local arm = character:FindFirstChild(side .. " Arm") -- R6: the hand is the bottom of the arm
	if arm then
		return arm, CFrame.new(0, -arm.Size.Y / 2 + 0.45, 0), 1.2
	end
	return nil
end

local function weldOn(part, hand, at)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = hand.CFrame * at
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = part
	weld.C0 = at
	weld.Parent = part
end

-- What every pair shows whether or not its mesh is in: a cuff at the wrist in the pair's color and material, metal
-- knuckle plates on Reinforced and up, and a glint on the starlight pairs. Without the mesh, a mitt over the hand
-- too, so no tier ever looks like bare hands.
local function addTrim(def, hand, offset, folder, hasMesh)
	local color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	local material = Enum.Material[def.material or "Fabric"] or Enum.Material.Fabric
	-- The hand itself: an R15 hand part, or the bottom of an R6 arm.
	local size = Vector3.new(hand.Size.X, math.min(hand.Size.Y, 0.9), hand.Size.Z)
	local cuff = Instance.new("Part")
	cuff.Name = "Cuff"
	cuff.Color = color
	cuff.Material = material
	cuff.Size = Vector3.new(size.X + 0.12, 0.22, size.Z + 0.12)
	cuff.Parent = folder
	weldOn(cuff, hand, offset * CFrame.new(0, size.Y / 2 - 0.08, 0))
	if not hasMesh then
		local mitt = Instance.new("Part")
		mitt.Name = "Mitt"
		mitt.Color = color
		mitt.Material = material
		mitt.Size = size + Vector3.new(0.08, 0.04, 0.08)
		mitt.Parent = folder
		weldOn(mitt, hand, offset * CFrame.new(0, -0.02, 0))
	end
	if def.tier >= 3 then
		local plate = Instance.new("Part")
		plate.Name = "Knuckles"
		plate.Color = Color3.fromRGB(118, 116, 110)
		plate.Material = Enum.Material.Metal
		plate.Size = Vector3.new(size.X * 0.8, 0.14, 0.1)
		plate.Parent = folder
		-- Across the back of the hand, near the fingers (the back faces out: the hand's own -Z in either rig).
		weldOn(plate, hand, offset * CFrame.new(0, -size.Y / 2 + 0.25, -size.Z / 2 - 0.08))
	end
	if def.tier >= 5 then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = color:Lerp(Color3.new(1, 1, 1), 0.5)
		sparkles.Parent = cuff
	end
end

-- Dresses a character's hands for the pair with id gloveId (bare hands: nothing). Old gloves come off first.
function GloveLooks.dress(character, gloveId)
	for _, side in { "Right", "Left" } do
		local hand = handOf(character, side)
		local old = hand and hand:FindFirstChild("WornGlove")
		while old do
			old:Destroy()
			old = hand:FindFirstChild("WornGlove")
		end
	end
	local def = byId[gloveId or "bare"]
	if not def or not def.prop then
		return
	end
	for _, side in { "Right", "Left" } do
		local hand, offset, length = handOf(character, side)
		if hand then
			local folder = Instance.new("Model")
			folder.Name = "WornGlove"
			folder:SetAttribute("GloveId", def.id)
			local model = Props.make(def.prop, hand.CFrame * offset, length, side == "Right" and RIGHT or LEFT)
			if model then
				model.Parent = folder
				Props.weldTo(model, hand)
				model.Parent = folder
			end
			addTrim(def, hand, offset, folder, model ~= nil)
			folder.Parent = hand
		end
	end
end

local function dressHands(player)
	local character = player.Character
	if character then
		GloveLooks.dress(character, player:GetAttribute("GloveId"))
	end
end

-- Puts each pair on the glove stand in its Rustic look. The placeholder stays as the fallback until the mesh has
-- loaded on each client, and the Buy / Wear button stays on the placeholder palm.
function GloveLooks.dressStand(stand)
	-- Lying flat on the table: fingers toward -Z of the stand, back of the hand up.
	local flat = CFrame.Angles(0, 0, math.pi) * CFrame.Angles(-math.pi / 2, 0, 0)
	for _, child in stand:GetChildren() do
		local def = byId[child.Name]
		local palm = child:IsA("Model") and child.PrimaryPart
		if def and def.prop and palm then
			local model = Props.make(def.prop, palm.CFrame * CFrame.new(0, 0, -0.25), 1.5, flat)
			if model then
				Props.restOn(model, palm.Position.Y - palm.Size.Y / 2)
				Props.weldTo(model, palm, child)
			end
		end
	end
end

function GloveLooks.start()
	local function watch(player)
		player:GetAttributeChangedSignal("GloveId"):Connect(function()
			dressHands(player)
		end)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("RightHand", 5)
			task.wait(0.5) -- let the rig settle and Gloves publish the worn pair
			dressHands(player)
		end)
		if player.Character then
			task.spawn(dressHands, player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return GloveLooks
