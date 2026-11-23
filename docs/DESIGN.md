# WoW Pet Training+ design doc

**Current version: 1.7.6** · last updated 2026-11-23.

This document records how the addon works and why it was built that way. It is updated with every push (see
[Maintenance](#maintenance)). When code and this doc disagree, trust the code, then fix the doc.

---

## 1. Purpose

Pet Training+ replaces the hunter **Beast Training** window in **WoW: Forever** (Interface 16001,
`WOW_PROJECT_CAMELOT`). Blizzard's window is buggy and doesn't show what you know. Pet Training+:

- shows every pet skill on one line with all its ranks grouped together;
- marks, for each rank, whether you (the hunter) know it, whether the summoned pet has it or can use it, and whether
  you could get it now;
- logs which creature taught you each skill and rank, at the moment you learn it, along with every tame;
- opens any skill in Forever Bestiary (Pet Hunter) with a right-click;
- shows pet loyalty, and records data so it can estimate the time to the next loyalty level.

Owner: Shannon (GitHub `SJLDeveloper`). Repo: public, https://github.com/SJLDeveloper/PetTrainingPlus. MIT licence.

---

## 2. Repo layout and workflow

| Path | What |
|---|---|
| `PetTrainingPlus.toc` | Interface 16001, version, SavedVariables, load order |
| `Data.lua` | Generated skill/rank table, with hand corrections |
| `Core.lua` | Helpers, saved data, hunter knowledge, pet reading, rank states, learn log, tames, slash commands |
| `Trainer.lua` | Beast Training: reading it, the framed layout, the secure Select/Train buttons |
| `Bestiary.lua` | Forever Bestiary link |
| `Loyalty.lua` | Loyalty display and the loyalty recorder |
| `UI.lua` | The window: skill list, detail panel, log tab, pet bar, framing, ESC handling |
| `tests/mock.lua`, `tests/run.lua` | Mock WoW API and the test run (`lua5.1 tests/run.lua`) |
| `docs/DESIGN.md` | This document (not shipped in the release zip) |
| `CLAUDE.md` | Standing instructions for Claude sessions working on this repo (not shipped) |
| `README.md`, `LICENSE` | User-facing description and credits; MIT plus data credits |

Load order (toc): Data, Core, Trainer, Bestiary, Loyalty, UI. Every file shares the addon namespace `ns`. The modules
are `ns.T` (Trainer), `ns.B` (Bestiary), `ns.Loyalty`, and `ns.UI`.

**Places the code lives:**
- Cloud session working copy: `/home/claude/pettrainingplus`. Commits and pushes are made from here.
- Device clone: `Projects/WoW Extension Projects/PetTrainingPlus`, its own repo, used only for this project. It pulls after
  every push.
- Installed addon: `…/World of Warcraft/_forever_/Interface/AddOns/PetTrainingPlus`. Copied from the device clone after
  every push.
- Saved data: `…/_forever_/WTF/Account/XANTHIPPE39/SavedVariables/PetTrainingPlus.lua` (account-wide), plus
  `…/WTF/Account/XANTHIPPE39/91/<Char-Realm>/SavedVariables/PetTrainingPlus.lua` (per character; the hunter is
  Censuh-Brightmane). WoW writes these on logout or `/reload` only.

**Release steps, in order:**
1. Run the tests. They must all pass.
2. Bump `## Version` in the toc.
3. Update this doc.
4. Commit and push.
5. Pull on the device.
6. Copy the addon files to AddOns.
7. Build `PetTrainingPlus-<version>.zip` in the device clone. The zip is git-ignored. It holds the toc, the six `.lua`
   files, README and LICENSE inside a `PetTrainingPlus/` folder; no tests, no docs. Delete the previous zip.

Device-side git needs delete permission on the Projects folder, asked for once per session. Without it, pulls leave lock
files and half-replaced files behind; after granting it, `git reset --hard origin/main` fixes that.

**Commit conventions:**
- Message title is user-facing and ends with the version, e.g. "Blue ranks: … (v1.6.0)".
- Author is Shannon.
- Trailers: `Co-Authored-By` and `Claude-Session`.

---

## 3. What an addon can and can't do with Beast Training

These are the hard constraints the whole design rests on. Reread them before proposing a change to the training flow.

### Forever's own UI source
Blizzard's Forever UI code is mirrored at https://github.com/Gethe/wow-ui-source, branch **`forever`**. Read it before
guessing at frame names or behaviour:
- Beast Training: `Interface/AddOns/Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua`, plus
  `Blizzard_TrainerUI_Camelot.lua` and `Blizzard_TrainerUI.xml`.
- Pet API: `Blizzard_APIDocumentationGenerated/PetInfoDocumentation.lua`.

### Facts about Blizzard's window
- `ClassTrainerFrame` is a ButtonFrameTemplate. It is toplevel, **movable**, MEDIUM strata, and a UI panel (area
  "left").
- Pet trainers have no categories, so the list is flat and sorted by service index.
- The `ScrollBox` (302×330, HIGH strata) has 47-pixel rows, so only about **7 rows exist at a time**. The sizes come from
  globals that `ClassTrainerFrame_Update` re-applies on every update.
- Each row button has `GetID()` = service index and `.displayIndex`. `OnClick` runs
  `ClassTrainer_SetSelection(self.displayIndex)`. The row's texts are `name` and `nameSubText` "(Rank n)".
- The scroll bar arrows react to **OnMouseDown only**, so a secure "click" can't scroll the list.
- Train runs `BuyTrainerService(displayIndexToSkillIndex[selectedService])`. The selected row doesn't have to be on
  screen.
- `selectedService` is set only by:
  - a row click;
  - `ClassTrainer_SelectNearestLearnableSkill` on show;
  - gamepad navigation;
  - the `TRAINER_DESCRIPTION_UPDATE` handler. **That event never fires after `SelectTrainerService` on Forever** (tested
    in game, Nov 21), so this route is closed.
- "available" only means the pet's level is met. Ranks the pet can't afford are listed as available too.

### Taint rules (found in game by the Forever Hunter Pets and Hunter Pet Trainer authors, MIT)
- These taint the trainer, after which Train is blocked for the session: `BuyTrainerService`,
  `ClassTrainer_SetSelection`, ScrollBox APIs, and writing anything Blizzard's trainer code reads (row height, list
  height, scroll position, selection).
- `SetTrainerServiceTypeFilter` is safe. Pass **booleans**, not 1/0.
- `SelectTrainerService` changes only the game's selection, not the window's.
- **What works:** a `SecureActionButtonTemplate` button with `type="click"`. Press 1 has `clickbutton` = the row and
  selects it untainted; press 2 has `clickbutton` = `ClassTrainerTrainButton` and trains it.
- `issecurevariable(ClassTrainerFrame, "selectedService")` tells whether the window's selection is still clean.

### Proven impossible on Forever (don't retry)
Drawing Blizzard's list without its window. v1.4.0–1.4.3 tried four ways:
- alpha 0 on the window with `SetIgnoreParentAlpha` on the list;
- HIGH strata on the list and its rows;
- re-applying row alpha;
- alpha 0 on every other part of the window.

Each time, `/ptp debug` showed the list and its rows in place, shown, opaque, HIGH, and nothing was drawn. **The design
therefore keeps Blizzard's window, untouched, as part of the layout** (see §7).

### Other engine facts
- Forever runs on the modern engine: `C_SpellBook`, `C_Spell`, `C_TooltipInfo`, `C_PetInfo`, `C_StableInfo`. The old
  Craft API is gone.
- In combat many values are secret (`issecretvalue`). `ns.clean` turns them into nil, and pet reads are deferred until
  `PLAYER_REGEN_ENABLED`.
- Beast Training (spell 5149) opens `ClassTrainerFrame` with no NPC and with `ClassTrainerFrameTrainingPointsLabel`
  visible. That is how `T.IsBeastTraining` tells it from an NPC trainer.
- Rows are read with `GetTrainerServiceInfo` and `GetTrainerServiceCost`. `C_TooltipInfo.GetTrainerService(i).id` is the
  pet rank's spell ID.
- The list holds only ranks the hunter knows **and** the current pet's family can learn.

---

## 4. Data model

### Data.lua (shipped)
Data.lua is generated, then hand-corrected. Sources:
- rank spell IDs from HunterTools-Forever (MIT);
- icons, kinds, families, levels and TP costs from Forever Hunter Pets (MIT).

Each entry looks like this:

```lua
{ key = "Bite", icon = 132278, kind = "tame" | "general", fam = { familyIDs }, ranks = {
    { r = 1, pet = <pet spell ID>, hunter = <hunter spell ID>, lvl = <pet level>?, tp = <TP>? }, ... } }
```

- `key` is the English name. It is the identity everywhere: saved data, the Bestiary link, `famCan`.
- `kind = "general"` means a pet trainer teaches it and every family can learn it (Growl, the resistances).
- `fam` is complete for the families it lists. An empty `fam` on a `tame` skill means unknown.
- `pet` is the spell in the pet's spellbook; `hunter` is the spell the hunter learns, which carries the learn message's
  link.
- Missing `lvl`/`tp` values are filled from Beast Training at runtime (`db.meta`).

**Hand corrections (v1.1.1, from Shannon's live play):**
- Dash: Wolf, Cat, Boar, Tallstrider, Hyena.
- Dive: Carrion Bird, Bat, Owl, Wind Serpent.
- Prowl: Cat only.
- Thunderstomp: Gorilla only.
- Shell Shield: Turtle only.
- Harass: removed and left as a commented stub. It is a relic in the game files, has no family, and can't be learned or
  taught.
- Cobra Reflexes (v1.7.5): removed and left as a commented stub, because it isn't available in Forever (Shannon, in
  game). v1.1.1 had added it as a pet-trainer skill for every family at pet level 30.
- Removing a skill is safe for saved data: every lookup by skill name (`ns.byKey`) checks for a missing skill, so old
  log entries or known ranks for it are ignored, and its learn messages no longer match.

Core builds index tables at load: `ns.byKey`, `ns.byPet`, `ns.byHunter`. Each ability gets `a.rankBy[r]`, `a.famSet`
and `a.maxRank`, and each rank gets `r.a` pointing back to its ability.

### SavedVariables

**`PetTrainingPlusDB`** (account-wide):

| Key | Shape | Meaning |
|---|---|---|
| `meta` | `[petSpellID] = { lvl, tp }` | level and full TP cost as Beast Training showed them; wins over Data.lua |
| `famCan` | `[familyID] = { [key] = true }` | seen as learnable by that family (Beast Training list or pet spellbook) |
| `famNames` | `[familyID] = name` | family names in the client's language |
| `locNames` | `[lowercase local name] = key` | localized skill names → English key |
| `creatures` | `[npcID] = { name, teaches = {key=rank}, t }` | what each tamed creature knew |
| `opts` | `replace=true, autoOpen=true, showTames=true, filter="all", petOnly=true, scale=1.3` | settings |
| `pos` | `{ point, rel, x, y }` | window position on its own. (`trainerPos` is a leftover from before v1.5: while attached, dragging moves Blizzard's window, so it is no longer written) |
| `loyalty` | see §10 | loyalty recorder |
| `directWorked`, `directNoEvent` | counters | direct-select attempts (v1.3.2; it skips itself after two "no event" results) |

**`PetTrainingPlusCharDB`** (per character):

| Key | Shape | Meaning |
|---|---|---|
| `known` | `[key] = { [rank] = { t, src } }` | ranks the hunter knows. `src` is `learned`, `trainer` or `training` (read from Beast Training, learned before logging) |
| `scanned` | `[familyID] = time` | last *complete* Beast Training read with a pet of that family |
| `pets` | `[id] = { id, name, fam, guid, origin, level, firstSeen, lastSeen }` | pet records |
| `petSeq` | number | next pet record ID |
| `log` | list, newest last, capped at 1000 | `learn` and `tame` entries |

Migration: v1.2 turned the old `filter = "pet"` into `petOnly = true`.

---

## 5. Core logic (Core.lua)

### Helpers
- `ns.clean(v)`: turns secret values into nil.
- `ns.try(fn, …)`: pcall that returns the cleaned results.
- `ns.api(tbl, name)`: safe lookup of a namespaced function.
- `ns.After`, `ns.Debounce(key, sec, fn)`: timers.
- `ns.On(event, fn)`: one event frame dispatching to many handlers.
- `ns.Changed()`: the one debounced (0.15 s) refresh. It rebuilds the learn index, then `UI.Refresh` and `T.Refresh`.
  **Anything that changes state calls `ns.Changed()`**; nothing refreshes the UI directly.

### Can this family learn this skill? `ns.FamilyCanLearn(fam, a)` → true / false / nil
1. A `general` skill: yes.
2. No family given: nil.
3. The family is in the shipped `fam`: yes.
4. The family is in `famCan`, seen in game: yes.
5. The shipped `fam` is not empty: no (the shipped lists are complete).
6. Otherwise nil, meaning nobody knows yet.

### What the hunter knows: `ns.HunterRankState(r)`
- `known`: the rank is in `char.known`.
- `missing`: not known, and a complete Beast Training read was done with a family that can learn it. Beast Training
  lists every rank you know for that family, so a rank absent from the list is one you don't have.
- `unverified`: not known, and not yet checked.

`ns.CanObtain(r)` (v1.6.0, "blue"): true when you don't know the rank and your level ≥ the rank's pet level
(`ns.RankLevel`). The logic: hunters can tame beasts up to their own level, so a beast of that level that knows the rank
is tameable; for trainer skills, a pet trainer teaches it. It returns nil while the rank's level is unknown, and is
refreshed on `PLAYER_LEVEL_UP`.

### The summoned pet: `ns.ReadPet()`
Reads name, family (`UnitCreatureFamily`), level, spellbook ranks (`ns.ReadPetSpells`, falling back to `IsSpellKnown`
rank by rank), and TP (`C_PetInfo.GetPetTrainingPoints`). Then:
- every rank in the spellbook goes into `famCan`;
- the pet is matched to its record by name and family, with the GUID tail breaking ties and following renames.

Pet GUIDs on Forever use the generic creature ID 165189, so **the GUID can't tell you what creature the pet was**.
Re-read triggers: `UNIT_PET`, `PET_BAR_UPDATE`, `SPELLS_CHANGED`, `UNIT_PET_TRAINING_POINTS`, pet `UNIT_LEVEL` and
`UNIT_NAME_UPDATE`. The read waits for combat to end.

**Training points:** on Forever, total TP = pet level × loyalty level. Shannon's data: a level-22 Unruly pet (loyalty 2)
has 44 TP. An earlier guess of level × (loyalty − 1) was wrong.

### Rank state for the summoned pet: `ns.RankPetState(r)`
Checked in this order:

| State | When |
|---|---|
| `nopet` | no pet summoned |
| `has` | the pet's rank of this skill = r |
| `below` | the pet has a higher rank |
| `family` | `FamilyCanLearn` is false |
| Beast Training open with this rank listed (`T.LiveRow`): | |
| `tp` | listed as "available", but its TP cost > free TP. v1.3.3: Blizzard's "available" ignores TP |
| `trainable` | listed as "available" and affordable |
| `level` / `tp` | listed as not available: pet level too low, else TP |
| Otherwise, from saved data: | |
| `unlearned` | the hunter doesn't know the rank |
| `famunknown` | `FamilyCanLearn` is nil |
| `level` | the pet's level is below the rank's level |
| `tp` | `UpgradeCost` > free TP |
| `trainable` | anything else |

`ns.UpgradeCost(r)`: the live Beast Training cost if there is one, else the rank's TP minus the TP of the rank the pet
already has. Training a higher rank refunds the lower one.

---

## 6. Colours: one rank box, one or two states (UI.lua `rankStyle`)

What the pet has wins over what you know. `rankStyle(r)` returns a key, the pet state, a detail, and an optional
**second key** for stripes.

| Box | Colour | Rule |
|---|---|---|
| `has` | bright green, white number | the pet has this rank |
| `has` + stripes | green box, stripes in your own colour | the pet has it and you **haven't learned it**, e.g. right after a tame. Stripes are blue (could get it), red (missing) or grey (unverified) (v1.6.1) |
| `below` | dim green | the pet has a higher rank |
| `trainable` | yellow-green, thick border | you know it and the pet can train it now |
| `known` | gold | you know it |
| `obtainable` | blue | you don't know it, and `CanObtain` is true (v1.6.0) |
| `missing` | dark red | you don't know it; confirmed by a complete Beast Training read |
| `unknown` | grey | you don't know it; not yet verified |

Stripes are 4 rotated bands (`SetRotation(π/4)`), clipped to the 17×17 box with `SetClipsChildren`. The number sits on
a separate frame above them. Legend labels: Known, Pet has, Trainable, Can get, Not learned, Not seen.

Rank tooltip (`UI.RankTooltip`):
- the spell tooltip;
- how and when you learned the rank (source creature, the pet you had then, where);
- the striped message: "fight alongside it and you'll learn it";
- the blue message: "tame a beast of level N or higher that knows it", or "a pet trainer teaches it";
- level and TP;
- the pet's state.

---

## 7. Beast Training integration (Trainer.lua + UI.lua)

### The framed layout (v1.5.0, Shannon's design)
Blizzard's window is left **exactly as Blizzard draws it**: no alpha, strata, size or scroll changes. Pet Training+
attaches to its right edge, and one border is drawn behind both windows:
- `UI.AttachToTrainer(tf, framed)` puts our window's TOPLEFT on Blizzard's TOPRIGHT, +12 px when framed and +6 px
  otherwise, in MEDIUM strata.
- `UI.SetFramed(on)` draws the backing frame `PetTrainingPlusFrameBack`, in LOW strata. It runs from Blizzard's top-left
  to our bottom-right, or down to Blizzard's bottom if that window is taller. It takes mouse clicks, so clicks between the
  two windows don't fall through to the world.
- Window scale is 1.3 by default (about +4 points of text, from v1.2.0). It is capped by the screen height and, while
  attached, by the room to the right of Blizzard's window.
- Dragging our window while attached calls `ClassTrainerFrame:StartMoving()`, which works because Blizzard marks it
  movable; ours follows. On its own, our window drags itself and remembers `db.pos`. No dragging in combat, because the
  secure buttons hang on the window.
- The "Unframe" / "Frame together" button next to the tabs, and `/ptp dock` / `/ptp replace`, switch between one border
  around both (`opts.replace = true`, the default) and two windows side by side.

### Session lifecycle
1. `TRAINER_SHOW` → `decide()` after 0.05 s. If it's Beast Training, `T.BeginBeast()`; otherwise it's an NPC trainer
   (`T.npcTrainerOpen`), whose list is scanned for `used` ranks (the hunter knows those).
2. `BeginBeast`:
   - `ReadPet`;
   - turn every filter on (`T.ShowAllRows`);
   - attach and frame;
   - show our window (`UI.ShowForTrainer` picks the first skill with a trainable rank);
   - start the driver;
   - scan at 0.3, 1 and 2 s and on `TRAINER_UPDATE`;
   - at 2.3 s switch Blizzard's list to **available-only** (`T.ShowAvailableOnly`), so it shows what can be trained now
     and the chosen rank is more likely to be among the 7 visible rows.

   If Beast Training is shown again for a pet of a different family, everything is read again.
3. `T.Scan("beast")`, on each row:
   - marks the rank known;
   - saves `meta` level and TP (TP only when the pet has no rank of that skill, because otherwise the listed cost is net of
     the refund);
   - adds it to `famCan`;
   - builds `T.live[petSpellID] = { status, lvl, tp, name, rankText, i }`.

   A read with all filters on and every row's rank resolved sets `char.scanned[fam]`, which enables the "missing" state.
   An available-only read marks ranks that dropped out of the list as unavailable.
4. The driver runs `OnUpdate` every 0.25 s: `T.FollowWindowSelection()` and `T.UpdateTrainButton()`. It ends the session
   if Blizzard's window is gone.
5. `TRAINER_CLOSED` (checked again after 0.1 s, because an NPC window closing can follow our `TRAINER_SHOW`) →
   `T.EndBeast()`:
   - restore the filters the user had;
   - clear the glow and the target;
   - remove the frame;
   - `UI.OnTrainerClosed()`.

### Select and Train
- `T.SetTarget(r)` accepts only a rank that is listed as available **and** whose `RankPetState` is `trainable`.
- One secure button, `PetTrainingPlusActionButton` ("SecureActionButtonTemplate,UIPanelButtonTemplate", DIALOG strata),
  is pressed twice:
  - **Select**: `clickbutton` = Blizzard's row for the rank, found by `T.FindRow` through `GetID()` = service index, with
    a fallback on the name and "(Rank n)" text. The row is outlined with a pulsing green glow (`T.ShowGlow`).
  - **Train**: `clickbutton` = `ClassTrainerTrainButton`. It is offered only when the game's selection
    (`GetTrainerSelectionIndex`) and the window's `selectedService` are both this rank, the window's selection is
    untainted (`T.WindowSelects`, using `issecurevariable`), and the pet can afford it.
  - PostClick checks after 0.3 s. A Select that didn't take shows "Press again". After a Train: re-read the pet, re-scan,
    then `T.AfterTrain`.
- **The rank is off screen:** Blizzard's list is outlined with "Scroll down/up to <rank>", and the player scrolls it with
  the mouse wheel. The row is picked up as soon as it is drawn. This is the accepted cost of not being allowed to scroll.
- **Clicking a row in Blizzard's list** → `T.FollowWindowSelection` selects the same rank in our window, and Train is
  ready in one press. Blizzard's own Train button keeps working.
- **After training** (v1.2.1): `T.AfterTrain` waits a few seconds (four retries, 0.6 s apart) for the pet's spellbook to show the rank. Then
  `UI.AdvanceAfterTrain` moves the highlight to the next rank of that skill that is trainable now, else simply the next
  rank, and aims Train at it.
- Direct select (v1.3.2, `T.TryDirect`, `SelectTrainerService` then waiting for `TRAINER_DESCRIPTION_UPDATE`) is still in
  the code, but skips itself after two "no event" results. It never works on Forever.
- `closeBtn` (`PetTrainingPlusCloseTrainer`) is a plain SecureActionButtonTemplate with the minimize-button textures over
  our X, clicking Blizzard's close button. `UIPanelCloseButton` can't be used: its own OnClick replaces the secure click.

### Closing and ESC (v1.5.1)
Pet Training+ **lives and dies with Beast Training** while attached:
- Blizzard's window is a UI panel, and ESC closes panels before UISpecialFrames. Ours was a UISpecialFrame, so the two
  closed out of step.
- `setEscClose(false)` takes our frame out of `UISpecialFrames` while attached, so ESC closes Blizzard's window and
  `TRAINER_CLOSED` closes ours.
- `UI.Hide()` refuses while attached; `UI.Hide(true)` forces it. `UI.OnTrainerClosed` always hides our window, puts it
  back in `UISpecialFrames`, restores its own position and full-width scale, and resets strata to HIGH.
- On its own (`/ptp`, or the addon compartment), our window is an ordinary ESC-closable frame.

---

## 8. Learn log and tames (Core.lua)

### Learning
- Source: the `CHAT_MSG_SYSTEM` message matching the `ERR_LEARN_SPELL_S` pattern (and related globals). Its link holds
  the **hunter-side** spell ID, mapped to a rank through `ns.byHunter`.
  - Some messages carry the rank only in the name, e.g. "Pinch (Rank 1)".
  - If there is no rank at all, it is the rank the pet has.
  - `LEARNED_SPELL_IN_SKILL_LINE` and `LEARNED_SPELL_IN_TAB` are also handled.
- Duplicates within 30 s are ignored.
- `src` is "trainer" when an NPC trainer is open, otherwise "pet".
- The entry stores key, rank, spell, source, trainer name, place (`ns.Where`: zone, subzone, map, x/y), the raw message,
  the pet at that moment, and, for pet learning, the **origin creature from the pet record**.

### Taming: where a pet came from
The pet GUID never carries the creature ID, so the origin is captured from the **target** when the Tame Beast channel
(spell 1515) starts:
- `UNIT_SPELLCAST_CHANNEL_START` / `SUCCEEDED` → `pendingTame`: NPC ID (from the target's GUID), name, level, family,
  classification, place.
- `CHANNEL_STOP` → a pet must arrive within 10 s, otherwise the tame is dropped. Moving cancels the channel without other
  events.
- `UNIT_PET` → after 1.5 s (the spellbook fills at the second `UNIT_PET`), `finishTame`:
  - checks the family matches;
  - creates the pet record with `origin` (including what it knew);
  - writes `db.creatures[npc]` and a "tame" log entry;
  - calls `ns.Loyalty.OnTamed()`;
  - prints what the pet knows.
- `/ptp origin` sets the origin of a pet tamed before the addon was installed, from a targeted beast of the same kind.

---

## 9. Forever Bestiary link (Bestiary.lua; v1.1.0, front-raise v1.3.0)

- Forever Bestiary (Pet Hunter) keeps its `ns` private. Its public entry points are its toggle/compartment globals and
  `SlashCmdList.FBPETHUNTER`; "abilities" opens its Abilities tab.
- Its Abilities tab has one Button per ability, whose OnClick runs `ns.Navigate("ability", en)` with the English key (the
  same keys as our Data.lua).
- `B.ShowAbility(a)`:
  - runs the slash command;
  - finds the visible button under `FBPetHunterFrame` whose text is the ability name (English or the client's language),
    up to 4 tries 0.1 s apart;
  - calls `:Click()`. That is exactly a user's click, and needs no change to Forever Bestiary.
- Triggers: right-click on a list row, a rank box, a rank-table row or a log entry, and the "View in Bestiary" button.
- `B.BringToFront()` raises `FBPetHunterFrame` to the strata of our topmost frame (the action button if shown) at level
  +20. `B.SendBack()` restores it, on a click on our window or on the Bestiary's OnHide, which is hooked once.
- Risk: if Forever Bestiary changes its card layout, nothing is found. The Abilities tab then stays open and a note is
  printed.
- The toc lists `## OptionalDeps: ForeverBestiaryPetHunter`.

---

## 10. Loyalty (Loyalty.lua, v1.7.0)

### What the game exposes (found in game, Nov 22)
- `C_PetInfo.GetPetLoyalty()` returns only a **name** ("Unruly").
- `C_PetInfo.GetPetHappiness()` returns happiness (1–3), damage % (125 when happy) and **loyaltyRate** (20 seen).
- **Loyalty points within a level are not exposed.** The ladder is Rebellious, Unruly, Submissive, Dependable, Faithful,
  Best Friend (`L.NAMES`, `L.MAX = 6`).
- The level comes from the name (`L.LevelFromName`), with total TP ÷ pet level as a fallback (`L.LevelFromTP`).

### The recorder (the "trap")
Shannon's plan: tame a fresh pet, level its loyalty to the top, and use the recorded loyalty rate × time to approximate
each level's threshold, then ship those numbers.
- A sample is taken every 5 s from `PLAYER_LOGIN`, and on `UNIT_HAPPINESS`.
- **In combat** nothing can be read (secret values), but the time still counts (v1.7.2, `L.SampleCombat`): while the pet
  exists, each step adds `dt` at the last rate seen before the fight, and also adds it to `combatSec`. If the pet
  disappears in combat, counting stops. Before v1.7.2 any fight over 20 s was dropped as a gap: Shannon's first Hyena
  segment lost about 5 minutes that way.
- **Resting doesn't count** (v1.7.6): a step taken while `IsResting()` (city or inn), in or out of combat, adds `dt`
  to `summonedSec` and `restSec` but nothing to `rateSec`. While resting, `L.Status` gives no ETA and the pet bar reads
  "(paused: resting)". Runs and segments carry `method` (`L.METHOD = 2`); segments without it were counted the old way
  (all summoned time) and are not used for estimates.
- **Activity** (v1.7.4, `trackActivity`): every counted step also adds `dt` to `afkSec`
  (`UnitIsAFK`), `mountSec` (`IsMounted`) and `taxiSec` (`UnitOnTaxi`). It also adds your experience gained (`UnitXP`,
  with level-ups handled through `UnitXPMax`) to `xp`, and the pet's (`GetPetExperience`) to `petXp`. Experience
  gained in fights is picked up at the first sample after the fight. Nothing is added across a gap (pet dismissed).
  Segments and the export carry all six.
- Runs are kept per pet in `db.loyalty.current["<player>-<realm>#<recId>"]`.
- Time counts only while sampling is continuous (same pet, gap ≤ 20 s). Two samples in the same second (the loop and
  `UNIT_HAPPINESS`) are not a gap (v1.7.2; this used to inflate `gaps`).
- If the summoned pet's level is lower than the run's last pet level, it's a different pet matched to an old record (a
  new tame with the same default name and family). The run starts over, marked not complete (v1.7.2). This was seen in
  game: a Carrion Bird run went from pet level 10 to 7. Each step adds `dt` to `summonedSec` and
  `lastRate × dt` to `rateSec`, and tracks `happySec[1..3]`, rate min/max, and gaps.
- When the level goes up by one, the run is closed as a **segment**: `{from, to, complete, rateSec, summonedSec, wallSec,
  combatSec, samples, gaps, rateMin, rateMax, happySec, petLevelStart, petLevelEnd, family, petName, ended}`, and a chat line is
  printed. Any other change (a drop, a jump) goes to `events`.
- **`complete` is true only if the level was watched from its start**: a fresh tame (`L.OnTamed`, within 120 s), or a
  run opened by the previous level-up. Pets already partway through a level give partial segments, which aren't used for
  estimates.
- `L.Needed(level)` (v1.7.4 order): the average `rateSec` of your complete segments for that level counted the current way (`method == L.METHOD`, v1.7.6), else `L.SHIPPED[level]`. (v1.7.3 had the shipped value first.) The complete segments are
  for that level. `L.Status()` gives the progress and `etaSec = (need − rateSec) / currentRate`.
- Display:
  - pet bar: "Unruly 2/6 (gaining)", plus "~N to Submissive" once an estimate exists;
  - `/ptp loyalty`: a report;
  - `/ptp loyalty export`: a copyable text frame (`PetTrainingPlusLoyaltyExport`).

### Status: thresholds (v1.7.6, provisional; first test)
Shannon's Hyena (fresh tame Nov 22, Best Friend Nov 23; pet level 29 for levels 2–6; happy and rate 20 from level 2 on):

| Step | Rate-seconds (all time) | 18,000 × level | Summoned | Fighting | Resting | Notes |
|---|---|---|---|---|---|---|
| 1 → 2 | 18,850 | 18,000 (+4.7%) | 1,184 s | not counted | not tracked | v1.7.0; rate −10 to 20; fights over 20 s dropped |
| 2 → 3 | 35,800 | 36,000 (−0.6%) | 1,790 s | 336 s | not tracked | started on v1.7.0, reload partway |
| 3 → 4 | 54,100 | 54,000 (+0.2%) | 2,705 s | 1,038 s | not tracked | v1.7.2 |
| 4 → 5 | 122,360 | 72,000 (+70%) | 6,118 s | 241 s | not tracked | v1.7.3; Shannon: "a *lot* of time resting"; fits if ~42 min |
| 5 → 6 | 107,640 | 90,000 (+20%) | 5,382 s | 847 s | **1,072 s** | v1.7.4; **86,200 without resting (−4%)**; 11 h wall clock (overnight logout); 0 XP for you and the pet |

- **Model (v1.7.6): level n → n+1 takes 18,000 × n rate-seconds, counting only time not spent resting.** Shipped as
  `L.SHIPPED[1..5]`. At rate 20: 15, 30, 45, 60 and 75 minutes, 3 h 45 min from tame to Best Friend, plus any resting.
- How it was reached: 18,000 × level fitted levels 1–3 (v1.7.3), then 4 → 5 missed by 70%. The v1.7.4 activity data
  for 5 → 6 showed 18 minutes resting; without them that level fits within 4%, and Shannon confirmed the outlier level
  had a lot of resting.
- **Ruled out by this data:**
  - Fighting speeding loyalty up: levels 2 and 3 have very different combat shares and both fit only if a combat
    second and a quiet second count the same (solving them gives weights 0.98 and 1.01).
  - Experience driving it: 5 → 6 had no experience gained for you or the pet and still fit.
  - Logged-out time counting: 5 → 6 spanned 11 hours on the clock.
  - A curve that simply steepens: 5 → 6 took fewer rate-seconds than 4 → 5.
- Not yet confirmed: the 4 → 5 resting time (not tracked; from memory), and whether it holds for other families and pet
  levels. **Next: a second fresh tame, compared level by level against this table.**
- The v1.7.4 experience tracking recorded 0 for 5 → 6 with 14 minutes of fighting. Unconfirmed whether that was real
  (grey mobs) or a bug; check `xp` on the next pet.
- Open: whether loyalty is gained while the pet is dismissed. Compare `wallSec` with `summonedSec` (since v1.7.2, fights are inside `summonedSec`, so the remaining difference is dismissed time, loading screens and deaths).
- Open: whether rate × time alone fills a level. If complete segments for the same level differ widely between pets,
  look at pet level, happiness time and gaps.

---

## 11. The window (UI.lua)

- Size: 790×560 at scale 1.3 (`/ptp scale 0.6–2`).
- Tabs: **Skills** and **Log**.
- **Pet bar:** portrait, name, level, family, loyalty, free/total/spent TP, and "Tamed from …" or a hint to use
  `/ptp origin`.
- **Pet toggle** (v1.2.0): a large button fixed above the skill list (it doesn't scroll). `opts.petOnly`, default on,
  hides skills where `FamilyCanLearn(petFamily) == false`. It only acts while a pet with a known family is out; with no pet
  everything is shown. Its text says how many skills it hides.
- **Skill list:** two sections, "Learned from beasts" (tame) and "Taught by pet trainers" (general). Skills the family
  can't learn sort last. Each row has the icon, the name and one rank box per rank. Search box; filter `all` / `known`.
- **Detail panel:** families, whether the pet can use the skill, and a ranks table (rank, level, TP, whether you know it, the
  pet's state, and where you learned it). The rank text is blue when it's obtainable. "View in Bestiary" button.
- **Log tab:** learn and tame entries (tames hidden when `opts.showTames` is off), newest first, with the source creature and place. Right-click opens the Bestiary.
- Position: `db.pos` on its own. `/ptp resetpos` clears it. While attached it hangs on Blizzard's window, and dragging
  moves that window.

---

## 12. Slash commands

`/ptp` (also `/pettraining`), plus the addon compartment button:

| Command | What it does |
|---|---|
| (none) | open/close the window |
| `log` | open the Log tab |
| `origin` | set the summoned pet's origin from your target |
| `replace` / `dock` | framed together / two windows |
| `scale N` | window scale, 0.6–2 |
| `resetpos` | reset the window position |
| `loyalty` | loyalty report |
| `loyalty export` | copyable loyalty data |
| `debug` | toggle debug and print the trainer, frame and pet report (`T.DebugReport`) |
| `reset` | clear this character's known ranks, pets and log |
| `help` | list the commands |

---

## 13. Testing

- `lua5.1 tests/run.lua`. 207 checks at v1.7.6; all must pass before a push.
- `tests/mock.lua` is a small WoW API mock:
  - frames, with geometry, strata, alpha, scripts and `tickOnUpdate`;
  - simulated timers (`M.advance(sec)`) and events (`M.fire`);
  - trainer services with a 7-row visible window and a scroll offset;
  - `SelectTrainerService`, `issecurevariable`;
  - units, the pet spellbook, TP;
  - `C_PetInfo` loyalty and happiness.
- Mock quirks to remember:
  - Missing keys return no-op functions, so the code uses `rawget` and `type(x) == "table"` checks.
  - `x and unpack()` truncates multiple returns.
  - State carries over between test sections (pets, TP, strata, open sessions). Close sessions and reset what you change.
- The mock can't prove what Forever actually draws or taints. Everything about drawing and taint has to be checked in
  game (see §3: the v1.4 list passed in the mock and drew nothing in game).

---

## 14. Decision log

| Version | Decision | Why |
|---|---|---|
| 1.1.0 | One line per skill with rank boxes; learn log from the system message; tame origin from the target at channel start | the core brief. The pet GUID has no creature ID |
| 1.1.0 | Bestiary link by clicking Forever Bestiary's own button | its API is private; a real click needs no change on their side |
| 1.1.0 | Training goes through Blizzard's own buttons with a two-press secure click | anything else taints Train |
| 1.1.1 | Family corrections, Cobra Reflexes as general, Harass stubbed out | Shannon's live play |
| 1.2.0 | Large fixed pet toggle (replacing the "For my pet" filter); window ×1.3 | asked for an obvious toggle and +4 pt text |
| 1.2.1 | After Train, advance to the next rank | asked for: train rank 1, be ready for rank 2 |
| 1.3.0 | Movable window; Forever Bestiary raised above us after a right-click | asked for |
| 1.3.1 | Find rows by `GetID()`; ask the player to scroll when the rank is off screen | only about 7 rows exist; found in game |
| 1.3.2 | Try direct select via `SelectTrainerService` | `selectedService` can't be set any other clean way. It failed (no event) and now skips itself |
| 1.3.3 | "available" but unaffordable = `tp`, not trainable | Blizzard's "available" ignores TP |
| 1.4.0–1.4.3 | Embed Blizzard's list in our window | **failed in game four ways; don't retry** |
| 1.5.0 | Frame Pet Training+ around Blizzard's untouched window (Shannon's idea) | the one layout that keeps the real list drawn and clean |
| 1.5.1 | ESC closes Blizzard's window; ours closes with it; ours can't close alone while attached | ESC was closing them out of step |
| 1.6.0 | Blue = not known, but your level ≥ the rank's level | "I don't have this yet, but I could" |
| 1.6.1 | Stripes for two states (the pet has it, you don't) | asked for; e.g. green plus blue right after a tame |
| 1.7.0 | Show loyalty level and direction; record rate × time per level; ship thresholds later | points aren't exposed; Shannon's "trap" |
| 1.7.0 | TP = pet level × loyalty level | Shannon's numbers (22 × 2 = 44) |
| 1.7.1 | Added this design doc and `CLAUDE.md`; the doc is updated on every push. Fixed stale README/help text from before v1.5 | keep the logic written down for future changes |
| 1.7.2 | Loyalty recorder counts combat time at the last rate; same-second samples aren't gaps; a lower pet level restarts the run | first in-game segment lost ~5 min of fights; a Carrion Bird record mix-up |
| 1.7.3 | Ship loyalty thresholds as 18,000 × level rate-seconds (provisional) | three Hyena levels fit within 0.6% (levels 2–3) and 4.7% (noisy level 1); the pet bar can now predict, and the next levels test it |
| 1.7.4 | Record activity per level (resting, AFK, mounted, flight, your XP, pet XP); your own measurements beat the shipped table; ship level 4 as measured, level 5 unknown | the 18,000 × level model missed level 4 by 70%, in a stretch with little fighting |
| 1.7.5 | Remove Cobra Reflexes (commented stub, like Harass) | not available in Forever; the v1.1.1 entry was wrong |
| 1.7.6 | Resting time (city/inn) no longer counts toward loyalty; ship 18,000 × level for levels 1–5; only segments counted this way feed estimates | 5 → 6 fits within 4% without its resting time; Shannon confirmed lots of resting on the 70% outlier |
| — | Kept in its own public repo, used only for this project | Shannon's explicit instruction |

---

## 15. Open items

- In-game checks still to report back: the v1.5.0 framed border spacing, v1.5.1 ESC linking, v1.6.x colours and stripes,
  and the v1.7.0 recorder.
- Loyalty: test the v1.7.6 model with Shannon's second fresh tame (Nov 23), level by level; ideally include a long
  city visit mid-level. Then another family and pet level. Check that `xp` is recorded.
- The realm part of loyalty run keys is empty in game ("Censuh-#2"): `GetRealmName` returned nothing. Harmless, since
  the key only needs to be unique per character.
- Data gaps: several ranks have no `lvl`/`tp` in Data.lua. They fill in from Beast Training as the hunter meets them, and
  `CanObtain` stays nil (no blue) until then.

---

## Maintenance

**This doc is amended with every push.** Before each commit that changes behaviour or data:
1. Bump the version at the top of this doc to match the toc.
2. Update the sections the change touches: functions, saved-data keys, states, colours, events, commands.
3. Add a row to the decision log (§14) with the version, what was decided and why. Include ideas that were tried and
   failed, so they aren't retried.
4. Update §15 Open items.
5. Update the test count in §13.

Then mirror the doc to the claude.ai project doc `claude/pet-training-plus-design.md`, so chat sessions get the same
context.
