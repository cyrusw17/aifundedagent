-- Part and streaming budget (#21): every container's parts against its slice of Config/WorldMap PartBudget, and the
-- streaming modes: regions are plain Models, Atomic only on small models, Persistent only where it must be.
do
	local Map = require({ __path = "Shared.Config.WorldMap" })
	local root = workspace:FindFirstChild("Needlewood"):FindFirstChild("StitchedIsles")
	local isles = root:FindFirstChild("Isles")
	local function parts(inst)
		local n = 0
		for _, d in inst:GetDescendants() do
			if d:IsA("BasePart") then n += 1 end
		end
		return n
	end
	local rows = {}
	local over, sum = 0, 0
	local function row(name, n, kind)
		local cap = Map.PartBudget[name]
		local status = "ok"
		if not cap then
			status = "WARN no budget"
			over += 1
		elseif n > cap then
			status = "WARN over"
			over += 1
		end
		table.insert(rows, { name = name, n = n, cap = cap, status = status, kind = kind })
	end
	for _, child in root:GetChildren() do
		if child.Name == "Isles" then
			for _, sub in child:GetChildren() do
				row(sub.Name, parts(sub), sub.ClassName)
				if sub.ClassName ~= "Model" then
					print("WARN region container is a " .. sub.ClassName .. ", not a Model:", sub.Name)
				end
			end
		elseif child.Name ~= "WorldEdge" then
			row(child.Name, parts(child), child.ClassName)
		end
	end
	row("Field bales", BALES, "bales")
	local total = 0
	for _, r in rows do total += r.n end
	for _, cap in Map.PartBudget do sum += cap end
	print(("%-22s %6s %6s %5s"):format("BUDGET container", "parts", "slice", "use"))
	for _, r in rows do
		print(("%-22s %6d %6s %4s%%  %s"):format(r.name, r.n, tostring(r.cap or "-"), r.cap and tostring(math.floor(r.n / r.cap * 100)) or "-", r.status))
	end
	print(("budget total %d of slices %d (share %d)"):format(total, sum, Map.PartShare))
	if sum > Map.PartShare then
		print("WARN the slices add up to more than the map's share", sum, Map.PartShare)
	end

	-- Streaming: no region-sized container is Atomic or Persistent; Atomic models stay small (they stream in whole);
	-- Persistent only on the few things every client must always have.
	local PERSISTENT_OK = { RichFieldBeacon = true, ["THE SPINDLE"] = true, ["SNOW PEAK"] = true, ["BOBBIN ROCK"] = true }
	local ATOMIC_MAX = 400
	local atomic, persistent, persistentParts, streamBad = 0, 0, 0, 0
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" then
			local mode = tostring(d.ModelStreamingMode or "")
			if mode:find("Atomic") then
				atomic += 1
				local n = parts(d)
				if n > ATOMIC_MAX then
					streamBad += 1
					print("WARN atomic model too big to stream in whole", d:GetFullName(), n)
				end
			elseif mode:find("Persistent") then
				persistent += 1
				persistentParts += parts(d)
				if not PERSISTENT_OK[d.Name] then
					streamBad += 1
					print("WARN persistent model not on the list", d:GetFullName())
				end
			end
			if d.Parent == isles and mode ~= "" and not mode:find("Default") then
				streamBad += 1
				print("WARN region container streams as", mode, d.Name)
			end
		end
	end
	print(("streaming atomic %d, persistent %d (%d parts), problems %d"):format(atomic, persistent, persistentParts, streamBad))

	-- The table for Health, as markdown.
	local md = { "| Container | Parts | Slice | Use |", "|---|---:|---:|---:|" }
	for _, r in rows do
		table.insert(md, ("| %s | %d | %s | %s |"):format(r.name, r.n, tostring(r.cap or "-"), r.cap and (math.floor(r.n / r.cap * 100) .. "%") or "-"))
	end
	table.insert(md, ("| **Total** | **%d** | **%d** | share %d |"):format(total, sum, Map.PartShare))
	BUDGET_TABLE = table.concat(md, "\n")
	print("BUDGET_TABLE_BEGIN")
	print(BUDGET_TABLE)
	print("BUDGET_TABLE_END")
end
