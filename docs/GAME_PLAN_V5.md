# Needlewood V5: Report card (round 4)

Two grades, graded on what exists today:
- Design on paper: B (7.6/10)
- Evidence it works: D+ (3.6/10). One prototype, no real playtests, no Roblox build.

## Testing findings (scripted player in headless browser, not people)
- Bug: bag of 150 hay filled in ~1.5s with the first tool, so the Stack would be gone in under a minute. Fixed: smaller hand patch (r 1.15), hay worth 0.2 per depth unit, deeper Stacks (3-8), 110ms dig tick. Re-measured: first sell and Rake purchase ~26s, first needle ~55s with blind sweeping.
- Issue: Legendary pays $3,000 vs hay $1, so rare finds swamp the economy. Needs a curve or a separate rare currency.

## Open problems
1. Shared vs personal Stacks (recommend personal Stack per player inside a shared world).
2. One dig verb carries ~15 hooks; tools must change how you dig, not just speed.
3. Luck and mutations add rules before the plain dig is proven. Playtest with them off first.
4. Prototype is client-only HTML; Roblox needs server-owned finds, replication, mobile controls.

## Next steps
Five playtests; decide Stack ownership; fix the economy curve; build the Roblox slice (farm, one Stack, dig, sell, save); re-grade with real numbers (time to first needle, second-Stack rate, next-day return).
