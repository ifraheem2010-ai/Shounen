# Shounen RPG

A turn-based creature-collector for Roblox, in the Pokémon Brick Bronze lineage. The
collectibles are **original human anime-styled characters** — not monsters, and not
anyone else's IP.

Owned by **Attimo Holdings**. The point of the project is to own the resulting IP
outright, which is why every name in it is a constructed word and why section 9 of
`CLAUDE.md` is not negotiable.

---

## Status

**Phase 0 and Phase 1 complete. Phase 2 (the save system) is next.**

| Phase | | |
|---|---|---|
| **P0** | Tooling, repo skeleton, type chart, test harness, CI | ✅ done |
| **P1** | Headless battle engine | ✅ done — gate passed |
| **P2** | Save system (ProfileStore) | ⬜ next |
| **P3** | World — routes, towns, encounters | ⬜ |
| **P4** | UI (React-lua) | ⬜ |
| **P5** | Vertical slice | ⬜ |

**The Phase 1 gate has passed:** 504 tests green, and a full 6v6 resolves from a fixed
seed in the terminal. Run it yourself with `lune run gate-6v6` — it prints the complete
event log and then replays the battle to prove the log is reproducible.

---

## Getting started

Install the toolchain — this reads `rokit.toml` and gets Lune, Rojo, StyLua, Wally and
luau-lsp at the exact versions CI uses:

```bash
rokit install
```

Run the tests:

```bash
lune run run-tests
```

Filter to one area:

```bash
lune run run-tests -- --filter TypeChart
```

Format:

```bash
stylua .
```

Live-sync into Studio (Studio is a **viewer and playtester only** — git and your
editor are the source of truth):

```bash
rojo serve
```

Type-check (CI runs this too; `src/` is expected to be at zero diagnostics):

```bash
rojo sourcemap default.project.json --output sourcemap.json && luau-lsp analyze --sourcemap=sourcemap.json src
```

`src/` only. `tests/` and `.lune/` require Lune builtins and the shim's fake instance
tree, neither of which luau-lsp can resolve, so analysing them reports nothing but
unresolvable requires. They are covered by being run.

---

## Layout

```
src/shared/Types/     shapes: TypeId, StatBlock, Rng, MoveEffect, Move, Species,
                      CreatureInstance, BattleState, BattleIntent
src/shared/Data/      values: TypeChart, and the content tables to come
src/shared/Battle/    the headless engine — NO ROBLOX API (Phase 1)
src/server/Services/  persistence, remotes, session handling (Phase 2)
src/client/           React-lua UI and input controllers (Phase 4)
tests/                TestKit plus the suites
.lune/                the Lune require shim and the test entry point
docs/                 TYPES.md (the type bible) and BUILD_PLAN.md
```

---

## The three things to know before changing anything

**1. The battle engine touches no Roblox API.** No `Instance`, no `task.*`, no `game`,
and above all no `math.random` — every roll goes through the injected `Rng`. This is
what makes a battle reproducible from a seed, which is what makes a full 6v6 battle
testable in milliseconds instead of by hand in Studio. `tests/battle/Purity.spec.luau`
enforces it, and the Lune shim enforces it by simply not providing those globals.

**2. Moves are data.** The engine branches on `effect.kind` from a closed set of 19
primitives in `Types/MoveEffect.luau`. It never branches on a move id. If a move needs
behaviour the vocabulary cannot express, extend the vocabulary.

**3. The type chart is locked.** Read `docs/TYPES.md` first. In particular: Frost
keeps its five resistances, Arcane gets no setup moves, and the three immunities stay
asymmetric. Each of those is load-bearing for reasons that are written down.

---

## Tests

The suite is pure Luau over plain tables. Nothing in it touches the network, the
clock, or unseeded randomness, so a failure is a real failure — there are no flakes to
retry.

Beyond behaviour, the suite asserts two things that no behavioural test can catch:

- **Rule #1** — a source scan of `src/shared/Battle/` for banned Roblox APIs.
- **Rule #3** — every `.luau` file in `src/`, `tests/` and `.lune/` starts with
  `--!strict`.

Do not assume tests pass. Run them. A test asserting "Frost resists Martial" once
shipped, was wrong, and was caught only by execution.
