"""Needle rarity glow set: one shared look per rarity tier, so a needle's value reads at a glance.
Colors are the per-type colors from Needle.luau LOOKS (Roblox 0-255). Glow is the one place the
muted Rustic palette is allowed to get bright.

Game mapping per tier: Roblox material, PointLight (range, brightness), pulse period (s, 0 = steady),
and extras. Blender mapping: emission strength for renders.
"""

TIERS = [
    # key, label, material, light range, light brightness, pulse seconds, extras, blender emission
    ("common", "Common", "Metal", 0, 0.0, 0, "none", 0.0),
    ("uncommon", "Uncommon", "Metal", 3, 0.5, 0, "soft light only, no Neon", 0.35),
    ("rare", "Rare", "Neon", 5, 1.0, 0, "steady glow", 1.5),
    ("epic", "Epic", "Neon", 7, 1.5, 2.0, "slow pulse (brightness 1.0 to 1.8)", 3.0),
    ("legendary", "Legendary", "Neon", 9, 2.2, 1.5, "pulse + star motes (ParticleEmitter, 4/s)", 5.0),
    ("mythic", "Mythic (mutated)", "Neon", 8, 2.0, 1.0, "gold, 1.6x size, Sparkles, server banner", 6.0),
]

NEEDLES = [
    # id, name, tier, color
    ("steel", "Steel", "common", (150, 158, 166)),
    ("pine", "Pine", "common", (96, 140, 84)),
    ("sand", "Sand", "common", (214, 186, 120)),
    ("ice", "Ice", "uncommon", (170, 220, 240)),
    ("bog", "Bog", "uncommon", (110, 128, 70)),
    ("obsidian", "Obsidian", "rare", (96, 64, 112)),  # lifted from (60, 40, 70) so the glow reads
    ("geode", "Geode", "rare", (170, 110, 220)),
    ("cloud", "Cloud", "epic", (240, 244, 255)),
    ("phantom", "Phantom", "epic", (120, 230, 210)),
    ("cosmic", "Cosmic", "legendary", (80, 70, 220)),
]
MUTATED = (255, 210, 60)
