-- Weekly festival (H11): the rotation is fixed by the week number, visits every region in turn, every festival region
-- has a field to boost, and refresh boosts that week's bales, decorates, and publishes the countdown attributes.
do
	local Map = require({ __path = "Shared.Config.WorldMap" })
	local Fest = require({ __path = "Services.Festival" })
	local RegionsF = require({ __path = "Services.Regions" })
	local RS = game:GetService("ReplicatedStorage")
	local ok = true
	local ids, seen = {}, {}
	for _, r in Map.Regions do ids[r.id] = r.name end
	for _, id in Map.FestivalOrder do
		if not ids[id] then ok = false print("WARN festival region unknown", id) end
		if seen[id] then ok = false print("WARN festival region twice", id) end
		seen[id] = true
		local has = false
		for _, f in RegionsF.fields do if f.region == ids[id] then has = true end end
		if not has then ok = false print("WARN festival region has no field", id) end
	end
	for id in ids do if not seen[id] then print("note: region never hosts a festival", id) end end
	-- Deterministic: the same time gives the same festival; a week later, the next region.
	local t = Map.FestivalEpoch + 10 * Map.FestivalWeek + 3600
	local a, b = Fest.at(t), Fest.at(t)
	local nextWeek = Fest.at(t + Map.FestivalWeek)
	if a.region ~= b.region or a.week ~= 10 or nextWeek.region == a.region or a.ends ~= Map.FestivalEpoch + 11 * Map.FestivalWeek then
		ok = false print("WARN festival rotation not deterministic", a.region, nextWeek.region, a.week)
	end
	local fest = Fest.refresh(t)
	if RS:GetAttribute("FestivalRegion") ~= fest.region or RS:GetAttribute("FestivalEnds") ~= fest.ends then ok = false print("WARN festival attributes missing") end
	local boosted, other = 0, 0
	for _, f in RegionsF.fields do
		for bale in f.bales do
			local boost = bale.body:GetAttribute("NeedleBoost") or 1
			if f.region == fest.name and boost >= Map.FestivalBoost then boosted += 1 end
			if f.region ~= fest.name and bale.body:GetAttribute("FestivalBoost") then other += 1 end
		end
	end
	if boosted == 0 or other > 0 then ok = false print("WARN festival boost wrong", boosted, other) end
	-- The next week moves the boost and the bunting.
	local fest2 = Fest.refresh(t + Map.FestivalWeek)
	local stale = 0
	for _, f in RegionsF.fields do
		for bale in f.bales do
			if f.region == fest.name and bale.body:GetAttribute("FestivalBoost") then stale += 1 end
		end
	end
	if stale > 0 then ok = false print("WARN last week's festival bales kept their boost", stale) end
	local flags = 0
	for _, d in workspace:GetDescendants() do if d.Name == "FestivalFlag" then flags += 1 end end
	if flags == 0 then ok = false print("WARN no festival bunting") end
	print(("festival %s then %s, %d bales boosted, %d flags, %s"):format(fest.region, fest2.region, boosted, flags, ok and "ok" or "WRONG"))
end
