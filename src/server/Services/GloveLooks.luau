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

local function dressHands(player)
	local character = player.Character
	if not character then
		return
	end
	for _, side in { "Right", "Left" } do
		local hand = handOf(character, side)
		local old = hand and hand:FindFirstChild("WornGlove")
		if old then
			old:Destroy()
		end
	end

	local def = byId[player:GetAttribute("GloveId") or "bare"]
	if not def or not def.prop then
		return
	end
	for _, side in { "Right", "Left" } do
		local hand, offset, length = handOf(character, side)
		if hand then
			local model = Props.make(def.prop, hand.CFrame * offset, length, side == "Right" and RIGHT or LEFT)
			if model then
				model.Name = "WornGlove"
				Props.weldTo(model, hand)
			end
		end
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
