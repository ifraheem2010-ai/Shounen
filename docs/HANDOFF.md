# Handoff

Start here after a context reset. This is a pointer file — it does not repeat what is
already written down elsewhere.

**Last updated:** 2026-08-15, at commit `fd5cdf7`.

---

## Where things stand

**553 tests green, 0 failed. 0 type diagnostics in `src`. Format clean. CI green.**

```bash
cd C:\Websites\shounen
export PATH="$HOME/.rokit/bin:$PATH"   # rokit's bin is on the user PATH but not in this shell
lune run run-tests
```

**Phase 0 and Phase 1 are complete.** The battle engine works end to end: all 19 effect
primitives execute, `Engine` drives the turn loop, and `lune run gate-6v6` resolves a
full 6v6 from a fixed seed and then replays it to prove the log is byte-identical.

**Phase 2 is part-way.** The content tables came before the save system on purpose —
everything downstream points at Species, so it lands first or it forces rework.

| Done this phase | |
|---|---|
| `src/shared/Data/Species.luau` | 9 species, the three starter lines, three stages each |
| `src/shared/Battle/StatCalc.luau` | Gen-5 stat formula; base stats to battle stats |
| Gate battle | now runs on real Moves + Species + StatCalc |

---

## What just happened, in three commits

| Commit | |
|---|---|
| `3ec2aa9` | Engine, and the Phase 1 gate passing |
| `375968c` | Capture, verified against an external reference |
| `fd5cdf7` | The three starter lines; the gate swapped onto real species |

Everything is committed and pushed. The tree was clean at handoff.

---

## The immediate next task

**`src/shared/Data/Moves.luau` needs three low-tier starter moves** — roughly 40 or 60
power, one each of Flame, Frost and Terra.

This is the smallest change with the largest effect on what is currently broken. The
move table holds exactly one move per starter type and two of them are endgame tiers
(a 130-power Flame nuke, a 110-power Terra move), so:

- Six of the nine species have no same-type move before level 10.
- **The starter triangle does not hold at level 15 on any edge** — 0% / 33% / 0% over
  200 seeds. Flame and Terra never apply the 2x the chart promises, and their filler
  coverage points somewhere else entirely.

`Species.NO_EARLY_STAB` records the exact affected set and `tests/data/Species.spec.luau`
asserts it in both directions, so adding the moves and emptying that table is a
self-checking change. Reproduce the measurement with `lune run triangle`.

Full reasoning: `DECISIONS_P2.md` entries **P1** and **P9**.

After that, in rough order: the ProfileStore save system (the thing P2 is actually
named for), then `Data/Encounters.luau`, then the remaining species.

---

## Open questions waiting on the owner

These are balance and scope calls. None were made without you.

1. **The Frost line loses its own triangle edge at level 50** (24% over 200 seeds).
   Glacivast is a pure wall — 70 special attack, and its only same-type move is 25
   power — so it cannot cash in a 2x advantage before Cragmarrow's 110-power attack
   gets through. Three ways out, all of them balance decisions: give the Frost line real
   offense (which contradicts its SpecialWall role), give Frost a stronger same-type
   move, or accept the triangle as a starting-hour promise rather than a lifetime one.
   → `DECISIONS_P2.md` P9

2. **Ten of the thirteen volatiles are inert.** Only Recharge, Flinch and Taunt do
   anything. Implementing Confusion, Protect, Substitute and the rest is a real chunk of
   work with no deadline attached — worth scheduling deliberately rather than absorbing
   into another session. → `DECISIONS_P1.md` D13, and `tests/battle/VolatileGap.spec.luau`

3. **Roster size for the vertical slice.** CLAUDE.md §7 records two options and an
   assessment that shipping the slice with 8 types is the better one. Nine species exist,
   all in three types. That decision now has consequences and has not been confirmed.

4. **Natures and abilities are both absent** and both are schema-affecting. Adding
   either later means a `schemaVersion` bump and a migration; deciding now is cheaper
   than deciding after the save system exists.

---

## Before you change anything

**Read the decision logs.** They exist so that choices made without you can be argued
with rather than rediscovered.

- **`DECISIONS_P1.md`** — 32 entries covering the engine. Read this before touching
  anything under `src/shared/Battle/`. It explains why paralysis is 0.5x and not Gen 5's
  0.25x, why screens ride DamageCalc's trailing modifier slot, why phazing stays random
  while pivoting does not, and a dozen other things that look arbitrary and are not.
- **`DECISIONS_P2.md`** — 9 entries covering the content tables.
- **`CLAUDE.md` §10** — the gotcha list. Several are Luau type-system traps that cost
  real time and will cost it again.
- **`docs/TYPES.md`** — read before any type chart edit. The chart is locked.

**Two rules that have caught real bugs and should keep being followed:**

- Never edit a passing test to make new code pass. Twice now a mutation survived because
  a test was weaker than it looked, and both times the fix was a stronger test.
- Mutation-test new guards. Every session that did it found at least one test that was
  passing for the wrong reason.

---

## Things that are true and easy to get wrong

- The toolchain is at `~/.rokit/bin`, on the Windows user PATH but **not** in a fresh
  Git Bash shell. Export it or commands will look like the tools were never installed.
- `tests/fixtures/` is synthetic on purpose. Engine unit tests use synthetic species so
  a balance change cannot redden the engine suite. Only the gate battle uses real data.
- `src/server/` and `src/client/` are **empty**. The presence of a type for something
  does not mean the thing exists.
