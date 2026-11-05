# Handoff

Start here after a context reset. This is a pointer file — it does not repeat what is
already written down elsewhere.

**Last updated:** 2026-11-05, after the save system.

---

## Where things stand

**661 tests green, 0 failed. 0 type diagnostics in `src`. Format clean.**

```bash
cd C:\Websites\shounen
export PATH="$HOME/.rokit/bin:$PATH"   # rokit's bin is on the user PATH but not in this shell
lune run run-tests
```

**Phase 0 and Phase 1 are complete.** The battle engine works end to end: all 19 effect
primitives execute, `Engine` drives the turn loop, and `lune run gate-6v6` resolves a
full 6v6 from a fixed seed and then replays it to prove the log is byte-identical.

**Phase 2 is nearly done, with one thing blocked on you.**

| Done this phase | |
|---|---|
| `Data/Species.luau` | 9 species, the three starter lines, three stages each |
| `Battle/StatCalc.luau` | Gen-5 stat formula; base stats to battle stats |
| Gate battle | now runs on real Moves + Species + StatCalc |
| 60-tier starter moves | 24 moves; `NO_EARLY_STAB` empty; two triangle edges fixed |
| `Save/ProfileSchema.luau` | the persisted shape, the caps, the reserved fields |
| `Save/Migrations.luau` | the runner; `STEPS` empty; Absolute Rule 7 machine-checked |
| `Save/ProfileValidate.luau` | fatal vs repairable; repair never deletes a creature |
| `Save/SaveSession.luau` | lock, load pipeline, release — the store is injected |

---

## The one thing waiting on you

**ProfileStore cannot be a Wally dependency, and the replacement is your call.**

`CLAUDE.md` section 2 and `wally.toml` both assumed it could be. Checked against the
index directly: there is no official scope, and every Wally package named `profilestore`
is a third-party fork of `MadStudioRoblox/ProfileStore`. This is the one module in the
project whose failure is permanent — a bug anywhere else is a bad battle, a bug here is
somebody's save — so taking an unreviewed fork from an unknown account is a supply-chain
decision rather than a dependency choice.

Three options, with the full argument in **`DECISIONS_P2.md` P13**:

1. **Vendor upstream at a pinned commit** — recommended. Git stays the source of truth,
   the code is reviewable in-tree, updates are manual.
2. **Depend on a third-party fork via Wally** — one line, unknown maintainer.
3. **Defer** — the pure layer is done and tested; leave the adapter unwritten.

**Nothing else is blocked by it.** All the save logic lives in `src/shared/Save/` behind
an injected `Store` interface, which is why a fake store can deny a lock, end a session
unprompted or hand back a corrupt save, and every one of those paths has a test. What is
missing is the adapter in `src/server/Services/` that passes in the real ProfileStore and
the real `Players` events — a thin piece of wiring, and the only part that cannot be
tested under Lune at all.

After that, in rough order: `Data/Encounters.luau`, then the remaining species.

---

## Open questions waiting on the owner

1. **Roster size for the vertical slice.** CLAUDE.md §7 records two options and an
   assessment that shipping the slice with 8 types is the better one. Nine species exist,
   all in three types. Still open — you have said you will come back to it.

2. **Ten of the thirteen volatiles are inert.** Only Recharge, Flinch and Taunt do
   anything. Implementing Confusion, Protect, Substitute and the rest is a real chunk of
   work with no deadline attached — worth scheduling deliberately rather than absorbing
   into another session. → `DECISIONS_P1.md` D13, and `tests/battle/VolatileGap.spec.luau`

   **This still blocks a second thing:** the Frost/Terra triangle edge is parked behind it.

3. **Where ProfileStore comes from.** See above.

---

## Decided, so do not reopen

- **The Frost/Terra edge is not a move-table problem and is not to be fixed with data
  yet.** It stays inverted until the inert volatiles land, because a SpecialWall loses a
  two-max-damage-AI race by construction — LeechSeed, Substitute, recovery and status
  pressure *are* the missing volatiles. Re-measure after them, expect a partial
  improvement rather than a fix (Glacivast has a 70-SpA floor problem that a kit does not
  erase), and if it is still inverted the lever is **species-level** — spread or role
  template — not the move table. → `DECISIONS_P2.md` **P11**
- **Natures and abilities are reserved fields, not systems.** `CreatureInstance` carries
  `nature` and `abilityId`, always nil, read by nothing. A source scan in
  `tests/save/ProfileSchema.spec.luau` fails if any code in `src/` starts touching them,
  so implementing either means deleting it from that spec's `RESERVED` list on purpose.
  → **P12** and **P15**
- **`Reconcile` is never called.** It fills in missing template keys, which is the silent
  save-format change Rule 7 forbids. Migrations are the explicit mechanism. → **P19**
- **The storage key is `Player_<userId>`.** Changing the format orphans every existing
  save. → **P19**

---

## Before you change anything

**Read the decision logs.** They exist so that choices made without you can be argued
with rather than rediscovered.

- **`DECISIONS_P1.md`** — 32 entries covering the engine. Read this before touching
  anything under `src/shared/Battle/`. It explains why paralysis is 0.5x and not Gen 5's
  0.25x, why screens ride DamageCalc's trailing modifier slot, why phazing stays random
  while pivoting does not, and a dozen other things that look arbitrary and are not.
- **`DECISIONS_P2.md`** — 19 entries: the content tables (P1–P12) and the save system
  (P13–P19). Read P13 before touching `wally.toml`, and P17 before adding a migration.
- **`CLAUDE.md` §10** — the gotcha list. Several are Luau type-system traps that cost
  real time and will cost it again.
- **`docs/TYPES.md`** — read before any type chart edit. The chart is locked.

**Two rules that have caught real bugs and should keep being followed:**

- Never edit a passing test to make new code pass. Every mutation survivor so far has
  been a test that was weaker than it looked, and every fix was a stronger test.
- Mutation-test new guards. The save system ran 42 of them across three modules and found
  four real weaknesses, including a test that passed because `tonumber` happened to reject
  a string, and a fake that was gentler than the library it stood in for.

---

## Things that are true and easy to get wrong

- The toolchain is at `~/.rokit/bin`, on the Windows user PATH but **not** in a fresh
  Git Bash shell. Export it or commands will look like the tools were never installed.
- `tests/fixtures/` is synthetic on purpose. Engine unit tests use synthetic species so
  a balance change cannot redden the engine suite. Only the gate battle uses real data.
  `Migrations.spec` applies the same idea to migration steps.
- **`src/server/` cannot be required under Lune.** The shim mounts `src/shared` and
  `tests` and nothing else, so anything put in `src/server/` is permanently untestable.
  That is what decided where the save system lives. → **P14**
- `src/client/` is **empty**. The presence of a type for something does not mean the
  thing exists.
- `lune run profile-size` prints how close a full save is to the 4 MB DataStore limit.
  Run it after adding a field to the profile; the answer today is 5.51%.
