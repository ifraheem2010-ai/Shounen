# Build plan

Two tracks. The **design track stays exactly one phase ahead of the code track** —
far enough that implementation is never blocked on a decision, close enough that
nobody designs six phases of content against an engine that turns out to work
differently.

| Phase | Code track | Design track runs ahead on |
|---|---|---|
| **P0** | Tooling, repo skeleton, type chart, test harness, CI | Effect vocabulary, roles |
| **P1** | Headless battle engine | Roster: 18–24 characters, movepools |
| **P2** | Save system (ProfileStore) | Routes, encounter tables, gym |
| **P3** | World — routes, towns, encounters | UI flows, screen inventory |
| **P4** | UI (React-lua) | Story, dialogue |
| **P5** | Vertical slice | Region two |

---

## Phase 0 — complete

- [x] Rojo project and folder structure
- [x] `.luaurc` strict mode, StyLua, Wally manifest, Rokit toolchain pins
- [x] Headless test harness (`tests/TestKit.luau`, zero dependencies)
- [x] Roblox-require emulation for Lune (`.lune/roblox_require.luau`)
- [x] Six agent definitions with hard ownership boundaries
- [x] Type chart — 12 types, validators, tests green
- [x] CI on push — format check, full suite, Rojo build
- [x] Effect vocabulary — 19 closed primitives
- [x] Core type definitions — TypeId, StatBlock, Rng, MoveEffect, Move, Species,
      CreatureInstance, BattleState, BattleIntent

Nothing in P0 renders a pixel, which is exactly why it goes first. Every hour spent
here is an hour that does not get spent debugging a battle by clicking through Studio.

---

## Phase 1 — the headless battle engine

**Owner: battle-engineer. Test-first, without exception.**

### Scope

- 1v1 and 6v6
- Actions: move, switch, item, run
- Gen-5 damage formula
- The 12-type chart
- 5 status conditions: Burn, Poison, Paralysis, Sleep, Freeze
- Stat stages −6..+6
- Priority and turn order
- Capture

### The gate — hard stop

> **200+ tests green AND a full 6v6 battle resolving in the terminal from a fixed
> seed.**

No UI work starts before this passes. Not "mostly passes". The reason for a hard stop
is that a UI built against a moving engine gets built twice, and the second build is
never budgeted.

### Order of work

Roughly dependency order; each step should be green before the next starts.

1. **Rng** — the seeded generator behind `Types/Rng.luau`. Everything else depends on
   it, and it is the cheapest thing in the project to test exhaustively.
2. **Stat computation** — base + IV + EV + level → battle stats, then stage modifiers.
3. **Damage formula** — the type chart is already tested, so this is arithmetic plus
   STAB, crits, and the damage roll.
4. **Turn order** — priority, then speed, then a tiebreak from the Rng.
5. **Move execution** — the effect interpreter. One branch per `effect.kind`.
6. **Status and volatiles** — including their interaction with turn order and damage.
7. **Switching** — voluntary, forced (faint), and phazing. Hazards fire here.
8. **Items and capture.**
9. **6v6 orchestration** — win/loss/draw detection, party management.

### Why determinism is the first requirement, not a nice-to-have

A battle is a long chain of probabilistic events. Without a seeded, injected Rng, a
bug that appears one time in forty is effectively unfixable: you cannot reproduce it,
you cannot write a regression test for it, and you cannot prove you fixed it.

With one, a bug report is a seed and a list of intents, and it reproduces in
milliseconds on any machine.

This is why `math.random` is banned outright in `src/shared/Battle/`, why
`tests/battle/Purity.spec.luau` scans for it, and why the Lune shim simply does not
provide the Roblox globals.

---

## Phase 2 — persistence

**Owner: systems-engineer.** ProfileStore, session-locked and migration-aware.

Every persisted shape change bumps `schemaVersion` and ships a migration, with a test
that loads an old profile through it. There is no version of this project where a
silent save-format change is acceptable — a field rename without a migration is data
loss in a real person's save.

Watch for: session locking across servers, a player rejoining before their profile
releases, and a server shutting down mid-battle.

---

## Phase 3 — world

**Owner: world-builder.** Routes, towns, encounter tables, trainers, the first gym.

- Routes: 4–6 species, rarity tiers 55/30/12/3, level bands within ±2.
- Every route introduces at least one type the player has not fought.
- The gym must be beatable by a player who caught only what is on the route, at the
  route's level, with one type disadvantage. **Simulate this; do not assume it.**
- Never gate progression on something the player can miss permanently.

---

## Phase 4 — UI

**Owner: interface-engineer.** React-lua, added to `wally.toml` at this phase and not
before.

The UI renders `BattleState.log`, not `BattleState`. Every event carries what it needs
— including the type effectiveness multiplier — so the presentation layer can never
disagree with the simulation about what happened.

---

## Phase 5 — the vertical slice

One town, two routes, one gym. Then **get five real people to play it.**

If it is fun at 18 characters, scaling content is mechanical work. If it is not, 150
characters will not fix it — and finding that out at 18 costs a fraction of finding it
out at 150.

### The roster math problem

18 characters across 12 types is 1.5 per type. No type feels real at 1.5. Two options
were identified:

1. **Bump the slice to 24 characters** — 8 evolution lines of 3, 2 per type.
2. **Ship the slice with 8 types**, holding Psyche, Frost, Aqua and one other for
   region two. **This was assessed as the better option.**

Option 2 does not mean shipping an 8-type *chart* — the chart does not decompose into
balanced subsets and all 12 entries stay in the data. It means the slice's roster
draws from 8 of them, so each of those 8 gets 2–3 characters and reads as a real type.

---

## Deferred deliberately

- **Story and dialogue.** The cheapest thing in the project to change and the easiest
  to write against a world that already exists. Writing it first means writing it
  twice.
- **Physics.** Not a question. Roblox provides overworld movement; turn-based battles
  are state machines. There is no physics work in this project.
- **Natures.** A second hidden stat modifier on top of IVs, and an undesigned balance
  surface. Adding them later is a migration; adding them now is a guess.
- **Abilities.** Not yet scoped. When they arrive they will need the same treatment
  the effect vocabulary got: a closed set the engine interprets, never per-character
  special cases.

---

## The day-7 test

**A battle running in the terminal by day seven.**

If it is not running by then, the blocker is tooling, not design — and the correct
response is to fix the tooling, not to design more.
