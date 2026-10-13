--!strict
-- Earned tool skins: cosmetic only, never stronger. Finishing a page of the collection book unlocks one, worn on the
-- shovel or rake (ToolSkins.luau). page names what must be complete:
--   "hay"     every hay type broken open (Codex, state.codex.hay)
--   "needles" every needle type found (Codex, state.codex.needles)
--   "finds"   every odd find kept (Finds, state.finds); "finds_common" the three commonest (boot, horseshoe, key)
-- color and material dress the tool's parts; sparkles adds a glint.
return {
	Skins = {
		{ id = "driftwood_rake", name = "Driftwood Rake", tool = "Rake", page = "finds_common", color = { 168, 156, 134 }, material = "Wood" },
		{ id = "golden_shovel", name = "Golden Shovel", tool = "Shovel", page = "hay", color = { 222, 182, 72 }, material = "Metal", sparkles = true },
		{ id = "bone_shovel", name = "Bone Shovel", tool = "Shovel", page = "finds", color = { 226, 218, 196 }, material = "SmoothPlastic" },
		{ id = "starlight_rake", name = "Starlight Rake", tool = "Rake", page = "needles", color = { 120, 140, 210 }, material = "Glass", sparkles = true },
	},
	CommonFinds = { "boot", "horseshoe", "key" },
}
