# WoW Pet Training+

A replacement for the hunter **Beast Training** window in WoW: Forever (Interface 16001).

## What it does

- **One line per pet skill, all ranks together.** Each rank is a small pill:
  gold = you know it, green = your current pet has it, bright edge = trainable right now,
  blue = you don't have it yet but could at your level (a beast of that level that knows it is one you can tame, or a
  pet trainer teaches it), red = you have not learned it, grey = not seen yet. When your pet has a rank you haven't
  learned yet (right after a tame), its box is green with stripes in your own colour (blue, red or grey).
- **Only what your pet can learn.** A large toggle above the skill list hides every skill your current pet's family
  can't learn, or shows them all again. With no pet summoned, every skill is shown.
- **Your pet at a glance.** Name, level, family, free training points, and for every skill
  whether this pet has it, can learn it, or its family can't.
- **Learn Log.** At the moment the game says "You have learned a new spell", Pet Training+ writes down
  the skill and rank, the creature your pet was tamed from (name, level, NPC ID, where it was tamed and when),
  your pet's name and level, and where you were. Tames are logged too, with what the beast knew.
- **Beast Training, framed together.** When you cast Beast Training, Pet Training+ opens right beside Blizzard's own
  window and one border is drawn around both: Blizzard's list of ranks you can train on the left, your skills and the
  chosen skill's ranks and details to the right. Blizzard's window is left exactly as Blizzard draws it. Click a rank in
  Pet Training+ or in Blizzard's list, then press Train (or Blizzard's own Train button). Dragging the window moves both.
- **Forever Bestiary link.** Right-click any skill (its line, a rank box, a rank row or a log entry), or use
  **View in Bestiary**, to open that ability in Forever Bestiary (Pet Hunter) exactly as if you had clicked it in its
  Abilities tab: every rank and the beasts that teach it. Needs Forever Bestiary (Pet Hunter) loaded.

- **Loyalty.** The pet bar shows your pet's loyalty level (Rebellious 1/6 … Best Friend 6/6) and whether it is gaining
  or losing loyalty. The game hides loyalty points, so Pet Training+ records how much "loyalty rate × time summoned"
  each level takes (from a fresh tame onwards) and, once a level has been measured, estimates the time to the next one.

## Commands

- `/ptp`: open or close the window
- `/ptp log`: open the Learn Log
- `/ptp loyalty`: loyalty level, rate and progress; `/ptp loyalty export`: the recorded loyalty data, to copy
- `/ptp origin`: for a pet tamed before you installed this, target a beast of the same kind and use this to set its origin
- `/ptp replace` or `/ptp dock`: Beast Training and Pet Training+ framed together as one window (the default), or as
  two windows side by side
- `/ptp resetpos`: put the window back in its default places (it can be dragged anywhere, and remembers a
  separate spot for when Beast Training is open)
- `/ptp scale 1.3`: window size (text included); 1.3 is the default, capped to fit your screen
- `/ptp debug`: print what the addon sees (trainer frames, pet, last log line)
- `/ptp reset`: clear this character's known ranks, pets and log

## Good to know

- Forever's Beast Training lists only the ranks your **current pet's family** can learn. Open it once with each
  family you use, and Pet Training+ fills in everything you know. After that, new ranks are picked up from the
  learn message as you play.
- Training has to go through Blizzard's own Train button, because addons are not allowed to train pets directly.
  That is why Train can take two presses: the first selects the rank in Blizzard's list, the second trains it.
  Blizzard's list only shows about 7 rows at a time and an addon can't scroll it, so when the rank you picked is
  further down, scroll Blizzard's list with the mouse wheel until it lights up (or click it there).
- If you close Pet Training+ while Beast Training is open, the Blizzard window comes back.

## Credits

Rank spell IDs come from HunterTools-Forever (MIT, © 2026 Gideon), taken from Forever client data. Pet levels,
TP costs, icons and families come from Forever Hunter Pets (MIT, © 2026 Elmar Höfinghoff), collected in game.
The Beast Training rules (what taints the trainer, and the two-press secure click) were found in game by the
authors of Forever Hunter Pets and Hunter Pet Trainer (MIT, © 2026 Xzeryn). Spell names and icons belong to
Blizzard Entertainment.

## Development

`tests/` holds a small mock of the WoW API that runs the main flows outside the game
(Beast Training read and ghosting, the two-press Train, learn messages, tames, the Forever Bestiary link):

    lua5.1 tests/run.lua

WoW only loads the files listed in the `.toc`, so `tests/` can stay in the addon folder.
