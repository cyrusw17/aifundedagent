--!nonstrict
-- The needle vault: a safe on your plot that keeps needles out of your pocket with no parts at all (a bin holds real
-- needle parts; the vault only holds counts), and saves them with the plot. Only the plot's owner opens it.
--
--   local vault = Vault.build(parent, frame, getOwnerId, saved)   -- saved: { [Needle.keyOf key] = count } from a save
--   vault.contents()  -> { [key] = count } for the save (Land stores it with the piece, like the display's pegs)
--   vault.clear()     -> empties it without giving needles back (call it after saving, before freeing a plot)
-- Destroying the vault model otherwise hands its needles back to the owner's pocket (selling the piece).
-- Land treats it like the display: item.wall = Vault.build(...).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Factory = require(ReplicatedStorage.Shared.Config.Factory)
local Data = require(script.Parent.Data)
local Machines = require(script.Parent.Machines)
local Needle = require(script.Parent.Needle)
local Skins = require(script.Parent.Skins)
local Feedback = require(script.Parent.Feedback)

local Vault = {}

local T = Factory.TileSize
local C = Machines.Colors
local part = Machines.part

function Vault.build(parent, frame, getOwnerId, saved)
	local model = Instance.new("Model")
	model.Name = "NeedleVault"
	model.Parent = parent

	local body = part(model, "Safe", Vector3.new(T - 2, 4.4, T - 2.4), frame * CFrame.new(0, 2.2, 0), C.darkMetal, Enum.Material.Metal)
	local door = part(model, "Door", Vector3.new(T - 2.8, 3.6, 0.2), frame * CFrame.new(0, 2.2, -(T - 2.4) / 2 - 0.1), C.metal, Enum.Material.Metal)
	local dial = part(model, "Dial", Vector3.new(0.3, 0.9, 0.9), door.CFrame * CFrame.new(0.8, 0.4, -0.2) * CFrame.Angles(0, math.pi / 2, 0), C.pad, Enum.Material.Metal)
	dial.Shape = Enum.PartType.Cylinder
	local label = Machines.sign(body, "NEEDLE VAULT", Vector3.new(0, 4, 0))
	Skins.dress("needle_vault", body, model, frame)

	local held = {} -- key -> count
	if typeof(saved) == "table" then
		for key, count in saved do
			if typeof(key) == "string" and typeof(count) == "number" and count > 0 then
				held[key] = math.floor(count)
			end
		end
	end

	local function totals()
		local count, value = 0, 0
		for key, n in held do
			local id, mult, polished, grade = Needle.parseKey(key)
			count += n
			value += Needle.priceOf(id, mult, polished, grade) * n
		end
		return count, value
	end

	local function refresh()
		local count, value = totals()
		label.Text = ("NEEDLE VAULT\n%d needles, worth $%d today"):format(count, value)
		model:SetAttribute("Needles", count)
	end
	refresh()

	local function isOwner(player)
		if player.UserId == getOwnerId() then
			return true
		end
		Data.toast(player, "Only this plot's owner can open its vault.")
		return false
	end

	local function prompt(name, action, key, hold)
		local p = Instance.new("ProximityPrompt")
		p.Name = name
		p.ActionText = action
		p.ObjectText = "Needle vault"
		p.KeyboardKeyCode = key
		p.HoldDuration = hold
		p.MaxActivationDistance = 10
		p.RequiresLineOfSight = false
		p.Parent = door
		return p
	end

	prompt("Deposit", "Put pocket needles in", Enum.KeyCode.E, 0.3).Triggered:Connect(function(player)
		if not isOwner(player) or not Data.get(player) then
			return
		end
		local moved = 0
		for _, n in Needle.takeHeld(player) do
			local key = Needle.keyOf(n.id, n.mult, n.polished, n.grade)
			held[key] = (held[key] or 0) + 1
			moved += 1
		end
		if moved == 0 then
			Data.toast(player, "Your pocket has no needles to put away.")
			return
		end
		refresh()
		Feedback.play("Scoop", door)
		Data.toast(player, ("Locked %d needles in the vault."):format(moved))
	end)

	prompt("Withdraw", "Take all needles out", Enum.KeyCode.T, 0.8).Triggered:Connect(function(player)
		if not isOwner(player) or not Data.get(player) then
			return
		end
		local count = totals()
		if count == 0 then
			Data.toast(player, "The vault is empty.")
			return
		end
		for key, n in held do
			Needle.giveKey(player, key, n)
		end
		table.clear(held)
		refresh()
		Data.toast(player, ("Took %d needles out of the vault. Sell them at any SELL NEEDLES pad."):format(count))
	end)

	local vault = { model = model }

	function vault.contents()
		return table.clone(held)
	end

	function vault.clear()
		table.clear(held)
		refresh()
	end

	-- Selling the piece hands everything back to the owner's pocket.
	model.Destroying:Connect(function()
		local owner = Players:GetPlayerByUserId(getOwnerId() or 0)
		if owner and Data.get(owner) then
			for key, n in held do
				Needle.giveKey(owner, key, n)
			end
		end
		table.clear(held)
	end)

	return vault
end

return Vault
