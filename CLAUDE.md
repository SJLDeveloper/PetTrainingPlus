# Working on WoW Pet Training+

Read `docs/DESIGN.md` before changing anything. It holds how the addon works, the Beast Training constraints (what
taints Train, what can't be drawn), and a log of decisions and failed approaches that must not be retried.

## Every push
1. `lua5.1 tests/run.lua`: every check must pass. Add tests for new behaviour.
2. Bump `## Version` in `PetTrainingPlus.toc`.
3. **Update `docs/DESIGN.md`**: version line, the sections the change touches, a decision-log row (version, decision,
   why), open items, test count. Then mirror it to the claude.ai project doc `claude/pet-training-plus-design.md`.
4. Commit (user-facing title ending in `(vX.Y.Z)`, author Shannon) and push to `SJLDeveloper/PetTrainingPlus`.
5. On the device: pull in `Projects/WoW Extension Projects/PetTrainingPlus`, copy the toc, `*.lua`, README and LICENSE
   to `_forever_/Interface/AddOns/PetTrainingPlus`, and rebuild `PetTrainingPlus-<version>.zip` (addon files only, in a
   `PetTrainingPlus/` folder; no tests or docs). Delete the old zip.

## Rules
- This repo holds this project only. Never add other projects to it.
- Don't touch Blizzard's Beast Training window (alpha, strata, size, scroll, selection). See DESIGN.md §3.
- Mock tests can't prove drawing or taint: those need an in-game check by Shannon.
