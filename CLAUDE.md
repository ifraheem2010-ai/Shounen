# Shounen RPG — Roblox creature-collector

Turn-based collector RPG in the Pokémon Brick Bronze lineage. The collectible
"creatures" are **original human anime-styled characters**, not monsters and not
existing IP. Owned by **Attimo Holdings**; the point of the project is to own the
resulting IP outright.

Repo root for all project files: `C:\Websites\shounen`

---

## 1. Absolute rules

These are non-negotiable. Every agent and every session reads them first.

1. **`src/shared/Battle/` contains ZERO Roblox API calls.** No `Instance`, no
   `task.*`, no `game`, no `workspace`, no `math.random`. Pure Luau over plain
   tables. Randomness comes from the **injected RNG object only** — this is what
   makes battles deterministic from a seed and testable in milliseconds.
2. **Server-authoritative.** Clients send *intent*, never results. A client says
   "I want to use move slot 2"; the server decides what happened. Never trust a
   client-computed damage number, catch result, or encounter roll.
3. **`--!strict` everywhere.** No exceptions.
4. **Moves are data interpreted by the engine.** Never `if moveId == "X"`. If a
   move needs behaviour the effect vocabulary can't express, extend the
   vocabulary — do not special-case the move.
5. **No real-world IP. Original names only.** See section 9.
6. **Battle changes require tests.** Test-first: the failing test exists before
   the implementation.
7. **Schema changes bump `schemaVersion` and add a migration.** No silent
   save-format changes.

Rules 1 and 3 are enforced automatically by `tests/battle/Purity.spec.luau`.

---

## 2. Tech stack

| Layer | Choice | Notes |
|---|---|---|
| Sync | **Rojo** | Git + VS Code as the source of truth, **not** Studio. Studio is a viewer/playtester only. |
| Toolchain | **Rokit** | `rokit.toml` pins every tool; CI installs the same versions. |
| Language | **Luau**, strict mode | `.luaurc` enforces `languageMode: strict` |
| Packages | **Wally** | ProfileStore added in P2, React added in P4 |
| Persistence | **ProfileStore** | Session-locked, migration-aware |
| UI | **React-lua** (`jsdotlua/react`, `react-roblox`) | P4 only. Do not start before the P1 gate passes. |
| Battle engine | **Headless pure Luau** | Zero Roblox API, runs under Lune |
| Test runner | **Lune** + minimal in-repo harness | Zero external test deps |
| Formatter | **StyLua** | Tabs, width 100, prefer double quotes |
| CI | GitHub Actions on push | Runs the full suite plus a Rojo build |

**Physics is a non-question.** Roblox provides overworld movement. Turn-based
battles are state machines. There is no physics work in this project.

### Commands

```bash
rokit install                      # once, installs the pinned toolchain
lune run run-tests                 # the whole suite
lune run run-tests -- --filter data
stylua .                           # format
rojo serve                         # live-sync into Studio
```

---

## 3. Repo structure

```
C:\Websites\shounen\
├── default.project.json      Rojo tree
├── .luaurc                   strict mode + lint config
├── rokit.toml                pinned toolchain
├── wally.toml                package manifest
├── stylua.toml               formatter config
├── .gitignore
├── CLAUDE.md                 this file — global context for every agent
├── README.md                 human-facing status + phase checklist
├── .claude/
│   └── agents/               six subagent definitions (section 8)
├── .github/workflows/ci.yml
├── .lune/
│   ├── roblox_require.luau   Roblox instance-require emulation for Lune
│   └── run-tests.luau        headless test entry point
├── docs/
│   ├── TYPES.md              the type bible — read before ANY chart edit
│   └── BUILD_PLAN.md         phases, gates, sequencing
├── src/
│   ├── shared/
│   │   ├── Types/            TypeId, StatBlock, Rng, MoveEffect, Move,
│   │   │                     Species, CreatureInstance, BattleState,
│   │   │                     BattleIntent
│   │   ├── Data/             TypeChart.luau, Species, Moves, Learnsets,
│   │   │                     Evolutions, Encounters, Dialogue
│   │   └── Battle/           the headless engine — NO ROBLOX API
│   ├── server/
│   │   └── Services/         BattleService, ProfileService, EncounterService
│   └── client/
│       ├── Controllers/      input → intent
│       └── UI/               React-lua components (P4)
└── tests/
    ├── TestKit.luau          the whole test framework, zero dependencies
    ├── battle/               engine + type chart + source-invariant suites
    └── data/                 content validation suites
```

### The Lune require shim — why it exists

Roblox uses `require(script.Parent.Foo)`; Lune uses relative file paths.
`.lune/roblox_require.luau` builds a fake instance tree over `src/` and injects
it as the environment, so **source files stay Roblox-native**. That means plain
Rojo works with no build step and no darklua conversion, while tests still run
headless in milliseconds. Do not "simplify" this by rewriting sources to use
Lune-style requires — that breaks Studio.

A useful side effect: the injected environment has no `game`, no `Instance`, no
`task`. Anything in `Battle/` that reaches for the Roblox API dies the first time
a test loads it. Rule #1 is enforced by physics, not good intentions.

### Rojo tree (`default.project.json`)

- `ReplicatedStorage.Shared` → `src/shared`
- `ReplicatedStorage.Packages` → `Packages`
- `ServerScriptService.Server` → `src/server`
- `StarterPlayer.StarterPlayerScripts.Client` → `src/client`
- `Workspace`: `StreamingEnabled = true`
- `SoundService`: `RespectFilteringEnabled = true`
- `Players`: `CharacterAutoLoads = false`

(`Workspace.FilteringEnabled` is not set: it is deprecated, forced true by the
engine, and Rojo's reflection database rejects writes to it.)

---

## 4. The type system — LOCKED

**12 types in two families.** Type identity is defined by the **SOURCE OF A
PERSON'S POWER**, never by "what the creature is." Every creature is a human, so
"what it is" fails as an axis — this is why the original Beast/Machine draft was
scrapped.

### Discipline (7) — where the power comes from

| Type | Concept | Mechanical lean |
|---|---|---|
| **Martial** | Trained body, weapons, technique. (Renamed from "Blade" — the old name implied a weapon rather than a fighting style.) | Physical offense |
| **Ki** | Internal energy, aura, cultivated force. Works alone in an empty room. | Self-boosting, setup |
| **Arcane** | Contracts, sigils, curses, summons, sealed artifacts. Stops working if the caster is alone in an empty room. | Status, hazards, debuffs, field control. Special attacker. **NO SETUP MOVES.** |
| **Psyche** | Mental force. Nothing visible happens on the caster's side; the opponent just staggers. | Control, special offense |
| **Spirit** | Ghosts, demons, the ethereal, possession. | Trappers, phazers, status spreaders |
| **Feral** | Transforming your own body. Instinct and drive, not intelligence. (Was "Beast" — reframed as something a person *did to themselves*.) | Bulky physical offense |
| **Forge** | Built gear, augmentation, powered armor, prosthetics, drones. (Was "Machine" — same reframe.) | Defensive backbone: walls, hazard setters, support |

**The Ki/Arcane test:** if the power would stop working when the character is
alone in an empty room, it's Arcane. If it wouldn't, it's Ki.

**Arcane visual signature:** something floats *near* the character that isn't
part of them — glyphs, tomes, chains, a bound familiar.

### Element (5) — what natural force they command

Design rule, one line: **the character commands the element, they are not made of
it.** A fire-shaped blob is a Pokémon starter. A swordsman whose blade breathes
cinder is this game.

| Type | Concept | Mechanical lean |
|---|---|---|
| **Flame** | Combustion, temper | Offensive |
| **Frost** | Ice, stillness, preservation | 5 resistances **by design** |
| **Storm** | Lightning and wind | Speed. Blanked by Terra |
| **Terra** | Stone, weight, gravity | Bulky. Immune to Storm |
| **Aqua** | Flow, pressure, adaptability | Balanced — safest starter type |

### The chart

`CHART[attacker][defender]`. Omitted pairs are neutral (1×). Dual types multiply.

```
Martial  2× Arcane, Feral, Frost      | 0.5× Martial, Forge, Spirit, Terra
Ki       2× Martial, Forge, Terra     | 0.5× Ki, Arcane, Psyche, Frost   | 0× Spirit
Arcane   2× Ki, Feral, Aqua           | 0.5× Arcane, Psyche, Flame, Storm
Psyche   2× Ki, Feral, Spirit         | 0.5× Psyche, Arcane              | 0× Forge
Spirit   2× Arcane, Psyche, Spirit    | 0.5× Martial, Feral, Forge, Frost
Feral    2× Arcane, Psyche, Storm     | 0.5× Martial, Feral, Forge, Flame
Forge    2× Martial, Frost, Terra     | 0.5× Forge, Flame, Storm, Aqua
Flame    2× Feral, Forge, Frost       | 0.5× Flame, Storm, Terra, Aqua
Frost    2× Storm, Terra, Aqua        | 0.5× Ki, Feral, Frost
Storm    2× Spirit, Forge, Aqua       | 0.5× Ki, Frost, Storm            | 0× Terra
Terra    2× Flame, Forge, Storm       | 0.5× Martial, Arcane, Spirit, Terra
Aqua     2× Martial, Flame, Terra     | 0.5× Feral, Frost, Aqua
```

**Starter triangle:** Flame → Frost → Terra → Flame. A clean 2×/2×/2× cycle.

### Load-bearing decisions — do not casually revise

- **Frost keeps five resistances.** Pokémon's Ice is the canonical design
  failure: great offensively, one resistance, permanently unplayable regardless
  of base stats. **Do not "fix" Frost by making it more offensive.**
- **Arcane gets no setup moves.** This is the *mechanical* wall between Arcane
  and Ki, not just flavor. Ki boosts itself; Arcane manipulates the opponent.
  Break it and the two types collapse into one within twenty characters.
  `MoveEffect.isSetup()` exists so a validator can hold this line.
- **Three immunities, all asymmetric.** Ki→Spirit is 0× while Spirit→Ki is
  neutral. Psyche→Forge is 0× (no mind to attack). Storm→Terra is 0×. Symmetric
  immunities create dead matchups where neither side can act; asymmetric ones
  create hard reads. An immunity is the strongest single relationship in the
  game — it grants a free switch-in, the most valuable resource in turn-based
  PvP. Three rewards prediction; six would make the meta about immunity-juggling.
- **Discipline stays at seven.** Every future type proposal will be a Discipline
  type, because that's where anime power fantasies live — sound, poison, time,
  gravity, luck. **Route them into an existing Discipline type or reject them.**
- **All 12 types ship at launch.** The chart does not decompose into balanced
  subsets. Only 3 balanced 8-type subsets exist and none contains the starter
  triangle.

### Chart validation — run after every edit

`TypeChart.luau` ships three validators, wired into CI via
`tests/battle/TypeChart.spec.luau`.

- `findContradictions()` — catches a defender listed as both super-effective and
  resisted. **This bug occurred twice during design.** It reads the authored
  lists rather than the derived grid, because in a grid the second write silently
  wins and the contradiction becomes invisible.
- `validateTyping(typing)` — bounds check on any mono or dual typing. Legal if:
  ≥2 weaknesses (not too safe), ≤6 resistances+immunities (not a centralizing
  wall), ≤1 quadruple weakness (not unplayable).
- `findUnresistedPairs()` — coverage check **against the legal typing pool**, not
  the base types. Measuring against mono-types alone produces 20 false alarms; no
  real team is all mono-types. More than ~4 results means coverage is too easy
  and defensive play dies.

**Current verified status (12 types), asserted by the test suite:**

- Weaknesses per type: 2–4. Resistances per type: 2–5.
- Legal typings: 72 of 78 (12 mono + 60 dual)
- The 6 illegal duals: Martial/Terra, Ki/Feral, Arcane/Psyche, Arcane/Frost,
  Feral/Frost, Frost/Terra
- Contradictions: 0
- Unresisted two-move combos: 0

### Dual typing policy

Allowed, but hold the vertical slice to mono-types plus 3–4 duals. Dual typing
multiplies both power and bugs. Before approving any dual, compute weakness
count, resistance count, and whether the combination has **zero** weaknesses — if
so, reject it or give it deliberately bad stats.

---

## 5. Roles and stat design

PvP is a planned gamemode, so the roster is built PvP-first from day one.
Retrofitting competitive balance onto 60 creatures designed for PvE is brutal.

**Every character has exactly one declared role.** If a player can't tell what a
character is *for* within five seconds of seeing its stats, the design failed.
Templates assume ~510 BST for a fully-evolved competitive character; the machine-
readable copies live in `src/shared/Types/Species.luau`.
Format: HP/Atk/Def/SpA/SpD/Spe.

| Role | Spread | Job | Signature access |
|---|---|---|---|
| Physical sweeper | 70/125/70/50/70/125 | Clean up weakened teams with raw speed | High-power STAB + one coverage move |
| Special sweeper | 70/50/70/125/70/125 | Same, special side | High-power STAB + coverage |
| Setup sweeper | 80/105/85/60/85/105 | Boost once, then break through everything | +2 setup move, bulk to use it |
| Wallbreaker | 90/135/85/60/85/65 | Punch holes in defensive cores | Nuke-tier move, no setup |
| Physical wall | 105/70/135/60/85/45 | Absorb physical attackers indefinitely | Recovery, status, hazards |
| Special wall | 105/60/85/65/135/45 | Same, special side | Recovery, cleric move |
| Pivot | 85/95/95/80/90/95 | Generate momentum, bring teammates in safely | Pivot move (damaging switch) |
| Revenge killer | 65/115/60/60/65/130 | Punish a setup sweeper before it snowballs | Priority move, top speed tier |
| Tank / bulky offense | 100/105/100/70/90/70 | Trade hits, stay in, keep pressure on | Recovery + strong STAB |
| Support / cleric | 95/60/95/85/110/60 | Heal status, set screens, control speed | Screens, heal bell, speed control |
| Hazard setter | 100/85/110/65/90/50 | Chip the opposing team on every switch | Hazard move + recovery |
| Trapper | 80/100/85/95/85/85 | Remove a specific wall from the game | Trapping ability with counterplay |

**Rule:** every role needs ≥3 characters across the roster by endgame and ≥1 in
the slice. A role with one character is a role that gets banned or ignored.

### Base stat bands

- Stage 1: 280–330 · Stage 2: 400–450 · Stage 3: 510–560
- Legendaries 600–680, **at most 3 in the entire game**
- No character exceeds 150 in any single base stat before stage 3

### Speed tiers — fixed

Speed is the single most contested stat in turn-based PvP. Build tiers players
can memorise and predict against; never scatter values randomly.

| Base speed | Tier | Who lives here |
|---|---|---|
| 130+ | Scarf-tier | Revenge killers only. **Max 2 in the whole game** |
| 120–125 | Fast sweeper | Sweepers that must outspeed unboosted everything |
| 105–115 | Standard sweeper | The crowded tier. Most offensive characters |
| 90–100 | Mid | Pivots, bulky offense |
| 65–85 | Slow | Wallbreakers, tanks |
| 40–60 | Trick-Room / walls | Defensive characters |

**Never place a character at 126–129.** Creeping one speed point past an existing
threat is the laziest form of power creep and it invalidates old designs.

---

## 6. Move design

### Damage tiers

| Power | Accuracy | Cost | Use |
|---|---|---|---|
| 40 | 100% | +1 priority | Revenge killing, finishing |
| 60 | 100% | — | Early-game STAB, coverage on walls |
| 75 | 100% | — | Reliable coverage |
| 90 | 100% | — | Standard STAB — the workhorse tier |
| 110 | 90% | — | High-risk STAB |
| 120 | 100% | 33% recoil | Wallbreaker STAB |
| 130 | 90% | Recharge turn or −2 SpA | Nuke. **Max 4 in the game** |
| 25 ×2–5 | 95% | — | Multi-hit |

### Movepool rules

- Every character learns a same-type damaging move by level 12.
- Every type has ≥3 characters and ≥4 moves across the roster.
- Movepools must offer real choices. **If the correct 4 moves are obvious, the
  design has failed.**

### Effect vocabulary — DONE

`src/shared/Types/MoveEffect.luau` holds the **closed set of 19 move primitives**
the engine interprets. Moves are data referencing these primitives; the engine
never branches on a move ID.

```
Damage        FixedDamage   Recoil          Drain            Heal
InflictStatus CureStatus    StatStage       ResetStatStages  ApplyVolatile
RemoveVolatile SetHazard    SetSideCondition ClearSide       SetField
ForceSwitch   SelfSwitch    Trap            Capture
```

Items reuse the same vocabulary — a potion is `Heal`, a ball is `Capture` — so
the item system needs zero new interpreter code. Adding a primitive breaks a
count assertion in `tests/battle/MoveEffect.spec.luau` on purpose; that failure
is the prompt to decide whether the addition is genuinely new.

---

## 7. Roadmap

Two parallel tracks. The **design track stays exactly one phase ahead** of the
code track.

| Phase | Code track |
|---|---|
| **P0** | Tooling, repo skeleton, type chart, test harness, CI |
| **P1** | Headless battle engine |
| **P2** | Save system (ProfileStore) |
| **P3** | World — routes, towns, encounters |
| **P4** | UI (React-lua) |
| **P5** | Vertical slice |

### Phase 0 checklist

- [x] Rojo project, folder structure
- [x] `.luaurc` strict mode, StyLua, Wally manifest, Rokit toolchain pins
- [x] Headless test harness (zero dependencies)
- [x] Roblox-require emulation for Lune
- [x] Six agent definitions
- [x] Type chart — 12 types, tests green
- [x] CI on push
- [x] **Effect vocabulary** (`src/shared/Types/MoveEffect.luau`) — 19 primitives
- [x] Core type definitions (Species, CreatureInstance, Move, BattleState,
      plus TypeId, StatBlock, Rng, BattleIntent)
- [x] Rojo tree finalised

**P0 is complete. P1 is next: the headless battle engine.**

### Phase 1 gate — hard stop

**200+ tests green AND a full 6v6 battle resolving in the terminal from a fixed
seed.** Do not start UI work before this passes.

Phase 1 scope: 1v1 and 6v6, move/switch/item/run actions, Gen-5 damage formula,
the 12-type chart, 5 status conditions (Burn, Poison, Paralysis, Sleep, Freeze),
stat stages −6..+6, priority, and capture.

### Deferred deliberately

- **Story and dialogue** — cheapest to change, easiest to write against a world
  that already exists.
- **Physics** — not a question. See section 2.
- **Natures** — a second hidden stat layer nobody has designed yet. Adding them
  later is a migration; adding them now is an undesigned balance surface.

### The slice

One town, two routes, one gym. Get **five real people** to play it. If it's fun
at 18 characters, scaling content is mechanical. If it isn't, 150 characters
won't fix it.

**Roster math warning:** 18 characters across 12 types is 1.5 each — too thin for
any type to feel real. Two options were identified:

1. Bump the slice to 24 characters (8 lines of 3), 2 per type
2. Ship the slice with 8 types, holding Psyche, Frost, Aqua and one other for
   region two — **this was assessed as the better option**

**Day-7 test:** a battle running in the terminal. If it isn't running by then,
the blocker is tooling, not design.

---

## 8. Subagents

Six definitions live in `.claude/agents/`. Narrow scopes with **hard ownership
boundaries** — a single general agent will lose track of the invariants and start
"fixing" code it doesn't own.

| Agent | Owns | Never touches |
|---|---|---|
| **data-architect** | `src/shared/Data/`, `src/shared/Types/` — species, moves, learnsets, evolutions, type matchups, encounter tables | Engine, services, UI |
| **battle-engineer** | `src/shared/Battle/` — the headless engine | Data values, UI, services |
| **systems-engineer** | `src/server/Services/` — persistence, remotes, session handling | Battle logic, data balance |
| **interface-engineer** | `src/client/` — React-lua UI, controllers | Anything that computes a result |
| **qa-adversary** | `tests/`, simulation harnesses. **Reports only** | Never fixes what it finds |
| **world-builder** | Zone definitions, dialogue data, trainer/gym data | Engine, UI, balance |

**Never let the agent that found an imbalance also fix it** — it will tune toward
its own metric. qa-adversary reports; data-architect rebalances.

### world-builder specifics

- Each route: 4–6 species with rarity tiers (common 55% / uncommon 30% / rare
  12% / very rare 3%).
- Level bands are tight (±2). A route where wild levels swing 8 levels feels
  broken.
- Every route introduces at least one type the player hasn't fought yet.
- Trainer teams: 1–4 characters, 1–2 levels above the local wild band.
- Gym leaders: 3–4 characters, mono-type, each with one coverage move that
  punishes the obvious counter. 3–4 levels above the route ahead of them.
- **A gym must be beatable by a player who caught only what's on the route, at
  the route's level, with one type disadvantage. Test this explicitly.**
- Badges gate progression. State for each gate exactly what it blocks and what
  the player must do to pass. **Never gate on something the player can miss
  permanently.**
- Dialogue is data-driven trees in `Data/Dialogue.luau`. NPC lines under 2
  sentences — players skip long text.

### data-architect validation

After any data change run `lune run run-tests -- --filter data` and fix all
failures. The validator checks: no orphan move IDs, no evolution loops, no
unreachable species, learnsets sorted by level, stat totals in band, and every
species reachable from an encounter table or evolution.

### Standing orchestration prompts

**Phase 1 kickoff:**

> Use the battle-engineer agent. Build the headless battle engine to the Phase 1
> gate: 1v1 and 6v6, move/switch/item/run actions, the Gen-5 damage formula, the
> 12-type chart, 5 status conditions, stat stages −6..+6, priority, and capture.
> Test-first — do not write implementation before the failing test exists. Target
> 200+ tests. Report the failing suite if you can't reach green; do not report
> success on a partial pass. Zero Roblox API. When done, show a full 6v6 battle
> log from seed 12345 running in the terminal.

**Balance sweep (once P1 is green):**

> Use the qa-adversary agent. Write a simulation harness that runs 10,000
> AI-vs-AI battles across all species pairs at level 50 with random legal
> movesets. Output per-species win rate, per-move usage-weighted damage, and
> per-type aggregate win rate. Flag any species above 65% or below 35% win rate
> and any type above 60% aggregate. **Report only — do not change any data.**

---

## 9. IP safety — non-negotiable

Using real anime character names or likenesses gets the game DMCA'd. **Pokémon
Brick Bronze was taken down in 2018** — that is the exact cautionary example for
this genre on this platform.

- Character names are **original constructed words**: 2–4 syllables,
  pronounceable, thematically tied to type and archetype.
- Never a real anime character name. Never a Pokémon name. Never a trademarked
  term.
- Design language is anime-*inspired* — silhouette, transformation-tier
  evolution, aura. **Never a specific character.**
- No copyrighted references and no real anime quotes in dialogue.

---

## 10. Known gotchas already hit

- `TypeChart.ALL_TYPES: { TypeId } = {...}` is **invalid Luau**. You cannot
  annotate a table field assignment; it needs `({...} :: { TypeId })`, or —
  better, and what the file actually does — declare it as a local with a normal
  annotation and assemble the return table at the bottom.
- The type chart has had a same-pair contradiction (super-effective *and*
  resisted) introduced **twice** during design. Always run
  `findContradictions()` after an edit.
- Bash brace expansion (`mkdir -p src/shared/{A,B}`) does not expand in all
  shells and silently creates a literal directory. Use separate `mkdir -p` calls.
- Do not assume tests pass — run them. A test asserting "Frost resists Martial"
  shipped incorrectly and was only caught by execution. Frost is **weak** to
  Martial; that assertion is now written out explicitly in the spec.
- Assigning a computed key (`m[name] = ...`) to a table literal in strict Luau
  turns it into an indexed table and discards the field types above it. Write the
  fields out.
- **A table indexer keyed by a union type is invariant.** Given
  `{ [TypeId]: Family }`, even the literal `map["Martial"] = x` is rejected — the
  key has to be typed as the *whole* union. Generalized iteration widens, so
  `for _, t in ALL_TYPES` yields something the indexer refuses. The fix is to
  annotate the loop variable: `for _, t: TypeId in ALL_TYPES do`. This produced 21
  errors in `TypeChart.luau` and none of them are visible when you just run the
  tests, because it type-checks fine at runtime.
- **A union of union aliases flattens to `string`.** `TypeId = DisciplineType |
  ElementType`, where both are unions of string literals, loses every literal and
  becomes plain `string` — so `{ TypeId }` silently stops rejecting typos. `TypeId`
  is written out flat as all 12 literals for this reason.
- Casting a function to `() -> ()` before `pcall` makes the solver think pcall
  returns one value, so the `err` binding becomes an error. Use `() -> ...any`.
- `Workspace.FilteringEnabled` cannot be set through Rojo — it is deprecated and
  forced true by the engine.
- `wally install` with zero dependencies **deletes** the `Packages` directory, so a
  plain `"$path": "Packages"` breaks `rojo build` on a fresh clone. Use
  `"$path": { "optional": "Packages" }`.
