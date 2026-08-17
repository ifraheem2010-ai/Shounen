# Handoff

Start here after a context reset. This is a pointer file — it does not repeat what is
already written down elsewhere.

**Last updated:** 2026-08-15, after the 60-tier starter moves.

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
| 60-tier starter moves | 24 moves; `NO_EARLY_STAB` empty; two triangle edges fixed |

---

## What just happened

| Commit | |
|---|---|
| `3ec2aa9` | Engine, and the Phase 1 gate passing |
| `375968c` | Capture, verified against an external reference |
| `fd5cdf7` | The three starter lines; the gate swapped onto real species |
| `134cd49` | Handoff docs |
| `4e00114` | The three 60-tier starter moves |

Everything is committed and pushed. The tree was clean at handoff.

**The last session added `flame.emberwake`, `frost.glasswind` and `terra.gravelmaul`** —
60 power, 100%, no secondary effect. The Flame and Terra lines learn theirs at level 5;
the Frost line's learnsets were deliberately left alone. `NO_EARLY_STAB` is empty and the
move table is at 24. Reasoning and the full before/after measurement: `DECISIONS_P2.md`
**P10**.

Triangle after, 200 seeds per edge:

| edge | L15 before | L15 after | L50 |
|---|---|---|---|
| Flame beats Frost | 0% | **95%** ✅ | 92% ✅ |
| Frost beats Terra | 33% | 33% ❌ | 24% ❌ |
| Terra beats Flame | 0% | **64%** ✅ | 100% ✅ |

Level 50 is unchanged on every edge, which is the proof that leaving Frost alone kept
that deferred balance question untouched.

---

## The immediate next task

**The ProfileStore save system.** This is what P2 is actually named for and it is the last
thing in the phase. `src/server/Services/` is still empty.

Two constraints on it that are already decided, before any design work starts:

- **Reserve schema fields for natures and abilities.** Both are confirmed to be coming.
  Nothing will read them for months. Adding them post-launch instead means retroactively
  assigning values to live creature instances — a migration that silently changes
  players' stats. Reserve the field, leave it empty, design no content.
  → `DECISIONS_P2.md` **P12**
- Any schema change bumps `schemaVersion` and ships a migration. Absolute rule 7.

After that, in rough order: `Data/Encounters.luau`, then the remaining species.

---

## Open questions waiting on the owner

1. **Roster size for the vertical slice.** CLAUDE.md §7 records two options and an
   assessment that shipping the slice with 8 types is the better one. Nine species exist,
   all in three types. Still open — the owner has said they will come back to it.

2. **Ten of the thirteen volatiles are inert.** Only Recharge, Flinch and Taunt do
   anything. Implementing Confusion, Protect, Substitute and the rest is a real chunk of
   work with no deadline attached — worth scheduling deliberately rather than absorbing
   into another session. → `DECISIONS_P1.md` D13, and `tests/battle/VolatileGap.spec.luau`

   **This now blocks a second thing:** the Frost/Terra triangle edge is parked behind it.

---

## Decided, so do not reopen

- **The Frost/Terra edge is not a move-table problem and is not to be fixed with data
  yet.** It stays inverted until the inert volatiles land, because a SpecialWall loses a
  two-max-damage-AI race by construction — LeechSeed, Substitute, recovery and status
  pressure *are* the missing volatiles. Re-measure after them, expect a partial
  improvement rather than a fix (Glacivast has a 70-SpA floor problem that a kit does not
  erase), and if it is still inverted the lever is **species-level** — spread or role
  template — not the move table. A triangle that stops mattering by level 50 is fine and
  genre-normal; one that reverses is a lie to the player who picked Frost to beat Terra.
  → `DECISIONS_P2.md` **P11**
- **Natures and abilities both exist and are field-reserved.** → **P12**

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
