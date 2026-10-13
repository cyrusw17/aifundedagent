--!strict
-- The rare reveal (CEO "Addiction push" H14): how big the moment is when a needle comes out of the hay. Pure, so
-- tests/reveal.luau checks the ladder headlessly; Needle.throw plays it. Effects only: the needle's own color and
-- material are its look (Props, H15), the reveal adds sound, sparkle, camera and banner around it.
--
--   Reveal.of(value, rarity, mult, wetMult) -> {
--     step     0 plain, 1 Epic, 2 Legendary, 3 mutated (Wet counts as a mutation one step up from its type)
--     pitch    multiplies the value-pitched ding (Feedback.needlePitch): rises with each step
--     glint    a slow glint while it hangs in the air (Epic and up)
--     nudge    camera nudge strength on the owner's screen, studs (Epic and up; 0 = none)
--     confetti a confetti burst (any mutation, Wet included)
--     banner   a server banner (real mutations; Wet is too common in rain to announce)
--     clip     worth the slow-motion camera push-in and the rarity card (Epic and up, or any mutation, Wet too)
--     chat     worth a line in server chat (Legendary and up, or a real mutation)
--   }
--   Reveal.allow(r, now, lastClip, lastChat) -> cinematic, chat: the cooldowns (CLIP_GAP per finder, CHAT_GAP per
--     server; a real mutation always gets its cinematic), so a maxed Star line doesn't take over the camera or chat.
local Reveal = {}

Reveal.PITCH_STEP = 0.12 -- per step: 1, 1.12, 1.24, 1.36
Reveal.NUDGE = { [1] = 0.12, [2] = 0.2, [3] = 0.3 }
Reveal.CLIP_SECONDS = 1.5 -- how long the camera push-in lasts
Reveal.CLIP_GAP = 30 -- seconds between one finder's cinematics (real mutations skip the wait)
Reveal.CHAT_GAP = 20 -- seconds between chat lines, server-wide

function Reveal.of(_value: number?, rarity: string?, mult: number?, wetMult: number?)
	local m = mult or 1
	local wet = m > 1 and m == wetMult
	local mutated = m > 1 and not wet
	local step = if rarity == "Legendary" then 2 elseif rarity == "Epic" then 1 else 0
	if mutated then
		step = 3
	elseif wet then
		step = math.min(step + 1, 3)
	end
	return {
		step = step,
		pitch = 1 + Reveal.PITCH_STEP * step,
		glint = step >= 1,
		nudge = Reveal.NUDGE[step] or 0,
		confetti = m > 1,
		banner = mutated,
		mutated = mutated,
		clip = step >= 1,
		chat = rarity == "Legendary" or mutated,
	}
end

function Reveal.allow(r, now: number, lastClip: number?, lastChat: number?): (boolean, boolean)
	local cinematic = r.clip and (r.mutated or lastClip == nil or now - lastClip >= Reveal.CLIP_GAP)
	local chat = r.chat and (lastChat == nil or now - lastChat >= Reveal.CHAT_GAP)
	return cinematic == true, chat == true
end

return Reveal
