# Handoff

Start here after a context reset. This is a pointer file — it does not repeat what is
already written down elsewhere.

**Last updated:** 2026-11-05, after the save system was wired to ProfileStore.

---

## Where things stand

**669 tests green, 0 failed. 0 type diagnostics in `src`. Format clean.**

```bash
cd C:\Websites\shounen
export PATH="$HOME/.rokit/bin:$PATH"   # rokit's bin is on the user PATH but not in this shell
lune run run-tests
```

**Phase 0 and Phase 1 are complete.** The battle engine works end to end: all 19 effect
primitives execute, `Engine` drives the turn loop, and `lune run gate-6v6` resolves a
full 6v6 from a fixed seed and then replays it to prove the log is byte-identical.

**Phase 2's save system is complete, wired and running.** What is left in the phase is
content: the rest of the roster, and encounters.

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
| `vendor/ProfileStore.luau` | upstream commit `45c9847`, Apache 2.0, audited, never edited |
| `Services/DataService.luau` | the adapter — the only untestable file in the save path |
| `Bootstrap.server.luau` | the server entry point |

---

## What to pick up next

**`Data/Encounters.luau`**, then the remaining species. Nothing is blocked.

The save system is finished. ProfileStore is vendored at `vendor/ProfileStore.luau`,
pinned to commit `45c9847`, because it is not on the Wally index under any official scope
— every package there named `profilestore` is a third-party fork. `DataService` wires it
to `SaveSession` and `Bootstrap.server.luau` starts it.

**Before trusting it in a real place, run `docs/STUDIO_CHECKS.md`.** `DataService` is the
only file in the save path no test covers — by design, since `src/server/` cannot be
required under Lune — so a manual pass in Studio is the only thing that exercises it.
Six checks. Five take about ten minutes and need API services enabled; check 6 needs the
place published and a second device signed in to the same account, and a 45-second wait.

**If you update the vendored module,** follow `vendor/README.md` and do not skip step 5.
The adapter depends on three specific upstream behaviours, all recorded in its header:
`StartSessionAsync` throws rather than returning nil when the key is already live on this
server, `params` is `{Steal: boolean?}` with no cancel callback, and `EndSession` is
asynchronous.

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

ProfileStore's source is no longer among these — see `DECISIONS_P2.md` P13 and P20.

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
- Mutation-test new guards. The save system ran 44 of them across three modules and found
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
- **The type-check needs two flags or it lies to you.** `luau-lsp analyze src` on its own
  reports 46 errors that are not yours: 36 inside the vendored ProfileStore, and 10
  Roblox globals with no definitions loaded. Section 2 of CLAUDE.md has the real command,
  and CI runs exactly it.
- **`vendor/` is the only place a nonstrict file is allowed,** and the only directory
  exempt from format and strict checks. `tests/battle/Purity.spec.luau` asserts the
  exemption, so moving it under `src/` or editing `STRICT_DIRS` goes red.
