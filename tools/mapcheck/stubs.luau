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
