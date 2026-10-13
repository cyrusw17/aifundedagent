-- Headless checks for src/shared/Reveal.luau. Run: luau tests/reveal.luau (exits non-zero on failure).
local Reveal = require("../src/shared/Reveal")

local failed = 0
local function check(name, ok, detail)
	if not ok then
		failed += 1
		print(("FAIL %s%s"):format(name, detail and (": " .. tostring(detail)) or ""))
	end
end

local WET = 2
local plain = Reveal.of(30, nil, 1, WET)
local epic = Reveal.of(800, "Epic", 1, WET)
local legend = Reveal.of(3000, "Legendary", 1, WET)
local mutated = Reveal.of(30, nil, 9, WET)
local wet = Reveal.of(30, nil, WET, WET)
local wetLegend = Reveal.of(3000, "Legendary", WET, WET)

check("pitch rises with rarity", plain.pitch < epic.pitch and epic.pitch < legend.pitch and legend.pitch < mutated.pitch)
check("a plain needle is a plain moment", plain.step == 0 and plain.pitch == 1 and not plain.glint and plain.nudge == 0 and not plain.confetti and not plain.banner)
check("Epic glints and nudges, no confetti", epic.glint and epic.nudge > 0 and not epic.confetti and not epic.banner)
check("Legendary nudges harder than Epic", legend.nudge > epic.nudge)
check("a mutation gets everything", mutated.glint and mutated.nudge >= legend.nudge and mutated.confetti and mutated.banner and mutated.step == 3)
check("Wet gets confetti but no banner", wet.confetti and not wet.banner and wet.step == 1)
check("Wet lifts a Legendary one step, not past a mutation", wetLegend.step == 3 and not wetLegend.banner)
check("nothing given is plain", Reveal.of(nil, nil, nil, WET).step == 0)
check("the camera nudge stays small", mutated.nudge <= 0.35, mutated.nudge)

if failed > 0 then
	print(("reveal: %d failed"):format(failed))
	error("reveal checks failed")
end
print("reveal: all checks passed")
