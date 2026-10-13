--!nonstrict
-- Put Blender items in game: the Rustic meshes. Every listed prop is made at its size (or cleanly falls back),
-- rigged vehicles face -Z with round wheels, the shovel and rake meshes sit on their handle, and Import 3D leaves
-- nothing behind in the Workspace. Props that were never imported are skipped, not failed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent.Parent.Services
local Props = require(Services.Props)
local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Props)

local function partsOf(model)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

-- The longest side of the box around a model's parts, and its center, in the frame given (world when omitted).
local function measure(parts, frame)
	frame = frame or CFrame.identity
	local low = Vector3.one * math.huge
	local high = -Vector3.one * math.huge
	for _, part in parts do
		local half = part.Size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local corner = frame:PointToObjectSpace(part.CFrame * Vector3.new(half.X * x, half.Y * y, half.Z * z))
					low = low:Min(corner)
					high = high:Max(corner)
				end
			end
		end
	end
	local size = high - low
	return math.max(size.X, size.Y, size.Z), (low + high) / 2
end

-- True when a wheel is round: the two sides across its axle (its thinnest side) match within 2%.
local function round(part)
	local s = part.Size
	local a, b
	if s.X <= s.Y and s.X <= s.Z then
		a, b = s.Y, s.Z
	elseif s.Y <= s.Z then
		a, b = s.X, s.Z
	else
		a, b = s.X, s.Y
	end
	return math.abs(a - b) <= math.max(a, b) * 0.02, ("%.2f x %.2f"):format(a, b)
end

return function(SelfTest)
	SelfTest.register("Props", function(t)
		-- 1. Every name in Sizes: imported ones are made at their listed size, the rest return nil (the caller's
		-- part look stays).
		local names = {}
		for name in Config.Sizes do
			table.insert(names, name)
		end
		table.sort(names)
		local made, wrong, missing, broken = 0, {}, {}, {}
		for _, name in names do
			if Props.has(name) then
				local ok, model = pcall(Props.make, name, t.place())
				if not ok or not model then
					table.insert(broken, name .. (ok and "" or (": " .. tostring(model))))
				else
					t.cleanup(model)
					model.Parent = Workspace
					local length = measure(partsOf(model))
					local want = Config.Sizes[name]
					if math.abs(length - want) > want * 0.03 + 0.02 then
						table.insert(wrong, ("%s %.2f (want %.2f)"):format(name, length, want))
					else
						made += 1
					end
				end
			else
				local ok, model = pcall(Props.make, name, t.place())
				if not ok or model ~= nil then
					table.insert(broken, name .. " (not imported, but make did not return nil)")
				else
					table.insert(missing, name)
				end
			end
		end
		t.check("imported props are made at their listed size", #wrong == 0, #wrong == 0 and ("%d props"):format(made) or table.concat(wrong, ", "))
		t.check("Props.make never errors and falls back cleanly", #broken == 0, #broken > 0 and table.concat(broken, ", ") or nil)
		if #missing > 0 then
			t.skip("not imported yet", ("%d: %s"):format(#missing, table.concat(missing, ", ")))
		end

		-- 2. Rigged vehicles: coupler toward -Z, tailgate toward +Z, and round wheels even when stretched unevenly.
		local rigged = 0
		for _, name in names do
			if Props.has(name) then
				local spot = t.place()
				local stretched = Vector3.new(Config.Sizes[name] * 0.35, Config.Sizes[name] * 0.3, Config.Sizes[name] * 0.95)
				local model = Props.make(name, spot, stretched)
				if model then
					t.cleanup(model)
					local wheels = Props.find(model, "Wheel_")
					local coupler = Props.find(model, "Coupler")
					local tailgate = Props.find(model, "Tailgate")
					if #wheels > 0 or #coupler > 0 or #tailgate > 0 then
						rigged += 1
						local _, center = measure(partsOf(model), spot)
						if #coupler > 0 then
							local z = spot:PointToObjectSpace(coupler[1].Position).Z
							t.check(name .. ": coupler at the front (-Z)", z < center.Z, ("z %.2f"):format(z - center.Z))
						end
						if #tailgate > 0 then
							local z = spot:PointToObjectSpace(tailgate[1].Position).Z
							t.check(name .. ": tailgate at the back (+Z)", z > center.Z, ("z %.2f"):format(z - center.Z))
						end
						if #wheels > 0 then
							local oval = {}
							for _, wheel in wheels do
								local ok, detail = round(wheel)
								if not ok then
									table.insert(oval, wheel.Name .. " " .. detail)
								end
							end
							t.check(name .. ": wheels stay round when stretched", #oval == 0, #oval > 0 and table.concat(oval, ", ") or ("%d wheels"):format(#wheels))
						end
					else
						model:Destroy()
					end
				end
			end
		end
		if rigged == 0 then
			t.skip("rigged vehicles", "no imported prop has Wheel_, Coupler or Tailgate child meshes (import with the hierarchy kept)")
		end

		-- 2b. Named pieces the game drives: wheelbarrow wheel and hay, the bin's needle pile, the schooner's cover.
		for _, want in {
			{ "wheelbarrow_loaded", "Wheel_L1" },
			{ "wheelbarrow_loaded", "HayFill" },
			{ "needle_bin", "NeedleFill" },
			{ "prairie_schooner", "Cover" },
		} do
			if Props.has(want[1]) then
				local model = Props.make(want[1], t.place())
				t.cleanup(model)
				t.check(("%s has its %s piece"):format(want[1], want[2]), model and #Props.find(model, want[2]) > 0)
			else
				t.skip(("%s has its %s piece"):format(want[1], want[2]), "not imported")
			end
		end

		-- 2c. Names that end in their own number resolve to themselves, not to a sibling.
		local numbered = { "beacon_part_1", "beacon_part_2", "beacon_part_3", "corn_maze_key_1", "corn_maze_key_2", "corn_maze_key_3" }
		local sizes = {}
		local imported = 0
		for _, name in numbered do
			if Props.has(name) then
				imported += 1
				local model = Props.make(name, t.place())
				t.cleanup(model)
				sizes[name] = model and measure(partsOf(model))
			end
		end
		if imported == 0 then
			t.skip("numbered props resolve to themselves", "none imported")
		else
			local misnamed = {}
			for name, length in sizes do
				if math.abs(length - Config.Sizes[name]) > Config.Sizes[name] * 0.03 + 0.02 then
					table.insert(misnamed, ("%s %.2f (want %.2f)"):format(name, length, Config.Sizes[name]))
				end
			end
			t.check("numbered props resolve to themselves", #misnamed == 0, #misnamed > 0 and table.concat(misnamed, ", ") or ("%d props"):format(imported))
		end

		-- 2d. Every region bale fits the canonical 4.6 x 2.6 x 3.2 bale box, long side along X.
		for _, hay in { "pine", "desert", "snow", "swamp", "volcano", "cave", "sky", "haunted", "star", "keys", "bobbin" } do
			local name = Config.BaleForHay[hay] or ("bale_" .. hay)
			if Props.has(name) then
				local spot = t.place()
				local model = Props.make(name, spot, Vector3.new(4.6, 2.6, 3.2))
				t.cleanup(model)
				local parts = partsOf(model)
				local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
				for _, part in parts do
					local half = part.Size / 2
					for _, x in { -1, 1 } do
						for _, y in { -1, 1 } do
							for _, z in { -1, 1 } do
								local w = spot:PointToObjectSpace(part.CFrame * (half * Vector3.new(x, y, z)))
								low, high = low:Min(w), high:Max(w)
							end
						end
					end
				end
				local box = high - low
				t.check(name .. " fits the bale box", (box - Vector3.new(4.6, 2.6, 3.2)).Magnitude < 0.15, ("%.2f x %.2f x %.2f"):format(box.X, box.Y, box.Z))
			end
		end

		-- 3. The held tools: each mesh is welded to its handle where the server put it, at the prop's true size.
		local player = t.player(10)
		if not player then
			t.skip("shovel and rake meshes on the handle", "no player joined")
		else
			for _, pair in { { "Shovel", "basic_shovel" }, { "Rake", "garden_rake" } } do
				local tool = player.Backpack:FindFirstChild(pair[1]) or (player.Character and player.Character:FindFirstChild(pair[1]))
				local handle = tool and tool:FindFirstChild("Handle")
				local mesh = handle and handle:FindFirstChild(pair[2])
				if not tool then
					t.skip(pair[1] .. " mesh", "the player has no " .. pair[1])
				elseif not mesh then
					t.skip(pair[1] .. " mesh", pair[2] .. " not imported; the part tool shows")
				else
					-- Rebuild the mesh from its welds alone, so this holds whether or not the tool is in the Workspace.
					local ghosts = {}
					local unwelded = 0
					for _, part in partsOf(mesh) do
						local weld = part:FindFirstChildOfClass("Weld")
						if weld and weld.Part0 == handle then
							table.insert(ghosts, { CFrame = weld.C0 * weld.C1:Inverse(), Size = part.Size })
						else
							unwelded += 1
						end
					end
					t.check(pair[1] .. ": every mesh part welds to the handle", unwelded == 0 and #ghosts > 0, ("%d welded, %d not"):format(#ghosts, unwelded))
					if #ghosts > 0 then
						local length, center = measure(ghosts)
						local offset = mesh:GetAttribute("MeshOffset")
						t.near(pair[1] .. ": mesh at true size", length, Config.Sizes[pair[2]], Config.Sizes[pair[2]] * 0.03)
						t.check(
							pair[1] .. ": mesh sits on the handle where it was placed",
							offset ~= nil and (center - offset).Magnitude < 0.1,
							offset and ("off by %.2f"):format((center - offset).Magnitude) or "no MeshOffset"
						)
					end
				end
			end
		end

		-- 4. Nothing Import 3D made is left lying in the Workspace.
		local stray = {}
		if Workspace:FindFirstChild("Scene") then
			table.insert(stray, "Scene")
		end
		for _, child in Workspace:GetChildren() do
			if child:IsA("Model") and string.match(child.Name, "_Node$") then
				table.insert(stray, child.Name)
			end
		end
		t.check("no Import 3D leftovers in the Workspace", #stray == 0, #stray > 0 and table.concat(stray, ", ") or nil)
	end)
end
