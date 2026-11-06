# Phase 2 decision log

Judgement calls made while building the content tables, in the same format as
`DECISIONS_P1.md`: what was decided, what else was on the table, how to reverse it.

Entries are append-only and numbered from P1. Do not renumber.

---

## P1 — Two of three starter lines cannot meet the level-10 STAB rule, and that is recorded rather than worked around

**The situation.** `Moves.luau` holds exactly one move of each starter type:

| type | move | tier |
|---|---|---|
| Flame | `flame.cinderlash` | 130 power, 90%, recharge — the nuke tier |
| Frost | `frost.rimeshard` | 25 x2-5, 95% — the multi-hit tier |
| Terra | `terra.stoneheave` | 110 power, 90% — the high-risk tier |

Frost's is a genuine early-game move. The other two are endgame tiers.

**Decision.** The Flame line learns its only same-type move at level 46 and the Terra
line at level 38. Six of the nine species therefore have no same-type move by level 10.
`Species.NO_EARLY_STAB` records exactly which, with the reason, and `Species.spec`
asserts that set is right in BOTH directions — a species cannot join it quietly, and a
species that gains a low-tier move must be taken off it.

**Alternatives, and why each was rejected.**

- *Hand the nuke to a level-8 starter.* Makes the damage tiers in CLAUDE.md section 6
  decorative. A 130-power move at level 8 is not a tier, it is a typo.
- *Invent a 40-power Flame move.* Explicitly out of scope this session, and inventing
  content to satisfy a validator is how a move table stops meaning anything.
- *Drop the level-10 assertion.* Then nothing notices when it is fixed, and nothing
  notices when a new species makes it worse.

**The actual fix, for whoever picks this up.** Three low-tier moves — a 40 or 60 power
Flame, Frost and Terra move each. That is a move-table session, not a species session.
Adding them empties `NO_EARLY_STAB` and the test starts enforcing the rule for real.

**Measured consequence.** At level 15 the starter triangle does not hold on any edge.
See P9.

---

## P2 — StatCalc lives in Battle/, not Data/

**Decision.** The Gen-5 stat formula went to `src/shared/Battle/StatCalc.luau`.

**Why.** It is a formula, not content — the same class of thing as `DamageCalc`, and it
changes about as often, which is never. `Data/` holds the numbers it operates on.
Putting it beside the species table would have the UI, the save system and the engine
all reaching into `Data/` for arithmetic.

**Why it exists at all this session.** Species cannot reach the engine without it. The
brief asked for the gate battle to run on real species, and base stats are not battle
stats. It is the minimum needed to satisfy that and nothing more.

**Reversal.** Move the file; it has no dependencies beyond `Types/StatBlock`.

---

## P3 — defaultMoveset guarantees same-type coverage rather than taking the last four

**Decision.** The default moveset is the four most recently learned moves, EXCEPT that
a same-type damaging move is always kept if the species knows one.

**Why the naive rule is wrong.** Glacivast learns its only Frost move at level 1 and
four other things after it. The plain last-four rule hands back a level-50 Frost wall
with no Frost move at all — not a set any player would build, and not one a wild
encounter should have either.

**Cost.** `Data/Species` now requires `Data/Moves` to ask a move its type. That is a
Data-to-Data edge, both owned by the same agent, and Moves does not require Species so
there is no cycle.

**Reversal.** Delete the guarantee block; one test covers it directly.

---

## P4 — One role per line, carried by all three stages

**Decision.** All three Flame species declare `SpecialSweeper`, all three Frost declare
`SpecialWall`, all three Terra declare `Tank`.

**Alternatives.** Give each stage its own role — a stage-1 with 304 BST is not a
competitive anything, and arguably has no role.

**Why not.** "What is this character for" is supposed to have one answer. A line whose
stages answer it three different ways is three characters wearing the same name, and the
role field exists so a validator can assert coverage across the roster — which needs the
answer to be stable.

**Reversal.** Per-stage roles; the role coverage checks would need to decide which stage
counts.

---

## P5 — The starters are mono-typed

**Decision.** All nine are single-typed.

**Why.** CLAUDE.md holds the vertical slice to mono-types plus three or four duals, and
dual typing multiplies both power and bugs. The starters are the last place to spend
that budget: they are the characters a player uses for the longest, and a dual-typed
starter would set the expectation for every line after it.

**Reversal.** Any of the legal duals containing Flame, Frost or Terra; the legality
check already covers it.

---

## P6 — The gate dex uses perfect IVs and no EVs

**Decision.** Every creature in the gate battle gets 31 IVs across the board and zero
EVs.

**Why.** It keeps the battle about the species rather than about a training spread
nobody has designed yet, and it removes a second source of per-creature variation from
a log whose entire job is to be reproducible.

**What it hides.** Nothing about the engine — IVs and EVs are inputs to a formula that
has its own tests. It does mean the gate battle is not representative of a real player's
team.

**Reversal.** One function in `GateBattle.luau`.

---

## P7 — The gate roster is the same six species on both sides, in different orders

**Decision.** Both sides field the six evolved forms; only the lead order differs.

**Why.** It makes the type chart the thing deciding matchups rather than a stat gap, and
it means a divergence between two runs cannot be explained away as one side being
stronger. Stage-1 species are left out entirely: a level-50 Emberlin is a punching bag
and a log full of one-sided knockouts demonstrates nothing.

**Reversal.** Change the two roster arrays.

---

## P8 — Names and concepts

**Decision.** Emberlin / Ashvane / Pyrecant, Rimeling / Hoarwen / Glacivast, Cairnling /
Slatewarden / Cragmarrow. Each carries one line describing a person.

**The constraint being honoured.** They are people who command an element, not creatures
made of one — a lamplighter's apprentice, a boy who stopped feeling the cold, a quarry
hand's daughter. That is the visual premise of the game and it is easiest to lose in the
first nine, where the temptation to write "a fire lizard" is strongest.

All nine are constructed compounds of two to three syllables. None is a real anime
character, a Pokemon, or a trademarked term. CLAUDE.md section 9 is why this project
exists.

**Reversal.** Names are a string field; the ids would move with them.

---

## P9 — The starter triangle does not hold at low level, and one edge fails at high level

**Not a decision — a measurement, recorded because it changes what the next session
should do.** Two hundred seeds per edge, using a controller that picks the best-scoring
damaging move it has. Reproduce with `lune run triangle`.

| edge | level 15 | level 50 |
|---|---|---|
| Flame beats Frost | **0%** | 92% ✅ |
| Frost beats Terra | **33%** | **24%** |
| Terra beats Flame | **0%** | 100% ✅ |

**Level 15 — caused by P1.** Flame and Terra have no same-type move, so the 2x the chart
promises is never applied by those sides. They fall back on filler coverage whose
multipliers point somewhere else entirely: `ki.innersurge` is RESISTED by Frost, and
`forge.pistonram` hits both Frost and Flame for 2x. The early learnsets are doing more
type work with their filler than with their own type. This resolves itself the moment
low-tier starter moves exist.

**Level 50 — a separate problem, and a design one.** Frost still loses to Terra with a
2x advantage, because Glacivast is a pure wall: 70 special attack, and its only same-type
move is a 25-power multi-hit. It cannot convert the advantage before Cragmarrow's
110-power `terra.stoneheave` gets through 92 defence. The Frost line's role and its
place in the triangle are pulling against each other.

Three ways out, none of them taken this session because all three are balance calls:
give the Frost line real offense (contradicts SpecialWall), give Frost a stronger
same-type move, or accept that the triangle is a starting-hour promise rather than a
lifetime one.

**Superseded in part by P11**, which sets the plan for this edge.

---

## P10 — Three 60-tier starter moves, and the Frost line does not learn its one

**Decision.** `Moves.luau` gains `flame.emberwake`, `frost.glasswind` and
`terra.gravelmaul` — 60 power, 100% accuracy, no secondary effect. The Flame and Terra
lines learn theirs at **level 5**, on all three stages. The Frost line's learnsets are
untouched. `NO_EARLY_STAB` is now empty. This is the fix P1 specified.

**Why the 60 tier and not the 40 tier.** CLAUDE.md section 6 attaches +1 priority to the
40 tier — that tier *is* the revenge killer's tool, and its power value is the price of
going first. Three starters opening with priority moves would make priority ordinary,
which is the one thing a revenge killer's whole role depends on it not being. 60/100% is
the row the tier table literally labels early-game STAB.

**Why they are plain.** No status chance, no priority, no drawback. A 60-power move that
also does something is not the 60 tier; it is an undeclared tier sitting between two
declared ones, and the table's value is that power can be read off it directly.

**Why the Frost line does not learn `frost.glasswind`.** Frost never had the gap — its
line has carried `frost.rimeshard` from level 1 throughout. Adding a second Frost move
would have been actively harmful in two ways:

- Rimeshard's expected power is 25 x 3.5 hits = **~87.5**, well above 60. Glasswind is a
  downgrade for anyone who already has rimeshard.
- `defaultMoveset` keeps the *latest-learned* same-type move when the last-four rule
  drops them all. A glasswind learned after rimeshard would therefore have silently
  replaced rimeshard in Glacivast's level-50 set — a nerf, applied to the exact matchup
  the owner ruled out of scope, arriving as a side effect of an unrelated change.

The move still belongs in the table: the table is the skeleton the roster is built
against, all three starter types now have the same 60-tier floor, and several existing
moves are on it without any species learning them. It is the future Frost roster's
baseline, not this line's.

**`frost.glasswind` on nobody's learnset is not an oversight. Do not "finish the job" by
adding it to the Frost line.** It looks unfinished and it is not — that omission is the
decision. Note the exact failure mode it avoids, because it is the kind that does not
announce itself: the symptom would have been *"the Frost/Terra edge got worse after a
session that was explicitly not supposed to touch Frost"*, and nothing in the diff would
have pointed at the cause. The learnset gains one line; the damage happens three
abstractions away, inside `defaultMoveset`'s latest-STAB fallback, to a creature whose own
file was never edited. A test suite that was fully green the whole time would have
reported nothing, because no test asserts a win rate.

The general lesson, which outlives this move: **in this codebase a learnset edit is not a
local edit.** `defaultMoveset` derives a battle-ready set from learn *order*, so adding a
move changes what every level-50 instance of that species carries — including wild
encounters and anything the triangle harness measures. Before adding a move to an existing
learnset, check what `defaultMoveset(speciesId, 50)` returns before and after.

**Measured result** — `lune run triangle`, 200 seeds per edge, same controller as P9.

| edge | L15 before | L15 after | L50 before | L50 after |
|---|---|---|---|---|
| Flame beats Frost | 0% | **95%** ✅ | 92% | 92% |
| Frost beats Terra | 33% | 33% | 24% | 24% |
| Terra beats Flame | 0% | **64%** ✅ | 100% | 100% |

Two of three edges went from inverted to holding. Level 50 is **unchanged on every
edge**, which is the confirmation that leaving the Frost learnsets alone kept this
session out of the deferred balance question.

**Why Terra's edge lands at 64% and not 95%.** Cairnling's 2x comes from a 60-power move
while Emberlin answers with `psyche.mindsharpen` into `ki.innersurge`, and Emberlin is 23
speed points faster. The edge holds; it is not dominant. That is a reasonable shape for a
starter matchup and no further tuning was done to it.

**Reversal.** Delete the three moves and the two learnset lines; `NO_EARLY_STAB` goes
back to its six entries, which are recorded in P1.

---

## P11 — The Frost/Terra edge waits on the volatiles, and inversion is the thing being fixed

**Not a decision made without the owner — this one is theirs, recorded here so the next
session does not relitigate it.**

**The state.** Frost beats Terra is the one edge still inverted, at both levels: 33% at
15 and 24% at 50, unmoved by P10. Neither low-tier move could have touched it — glasswind
is weaker than the rimeshard the line already has, and Terra's gravelmaul is neutral into
Frost, so the Terra side keeps reaching for `forge.pistonram` and its 2x anyway.

**Why it is not being fixed now.** The 24% is partly measuring engine surface area that
does not exist yet, not species balance. A SpecialWall loses a race between two
maximum-damage AIs by construction — the kit that makes a wall win is LeechSeed,
Substitute, recovery and status pressure, and that kit is **exactly the ten inert
volatiles**. Measuring a wall in an engine that cannot express walling answers a question
nobody asked.

**The plan, in order.**

1. Implement the inert volatiles (open question 2 in `HANDOFF.md`).
2. Re-run `lune run triangle`.
3. **Expect a partial improvement, not a fix.** Glacivast has a floor problem a kit does
   not erase: 70 special attack with a 25-power same-type move. Buying turns only pays if
   you can convert them, and it cannot.
4. If the edge is *still inverted* after that, the lever is **species-level** — the stat
   spread or the role template — and not the move table. Do not reach for the move table
   again; P10 already established it has nothing left to give here.

**What the target actually is, and it is not 51%.** A triangle that stops mattering by
level 50 is fine and genre-normal — starters grow into their own identities and the
rock-paper-scissors of the first hour is not meant to be a lifetime guarantee. A triangle
that **reverses** is a different thing entirely: it is a lie told to the player who chose
Frost specifically to beat Terra. Decay is acceptable. Inversion is the bug.

---

## P12 — Natures and abilities: reserve the fields now, design the content later

**The owner's call**, recorded here because it binds the ProfileStore session that has not
started yet.

**Decision.** Both natures and abilities **will exist**. The ProfileStore schema reserves
fields for both when it is built, even though nothing will read them for months. No
content is designed for either yet — no nature table, no ability vocabulary, no values on
any species.

**Why reserve rather than add later.** Adding a hidden stat layer after launch means
retroactively assigning values to live creature instances. That is a migration which
**silently changes players' stats** — a creature someone raised gets different numbers on
next login, with no in-game event to explain it. Reserving the field costs one nullable
column now and turns that migration into a backfill of something that was always absent.

**Why not design the content now.** Unchanged from CLAUDE.md section 7: an undesigned
balance surface added early gets balanced around before anyone knows what it is for.
Abilities in particular need the closed-vocabulary treatment the move effects got, or the
engine goes straight back to special-casing.

**What this obliges the next session to do.** Reserve the fields, leave them empty, and do
not let "the field exists" drift into "the system exists" — the same trap CLAUDE.md warns
about for `src/server/` and `src/client/`.

**Reversal.** Dropping a reserved unused field is a `schemaVersion` bump with no data
consequences, which is the cheap direction. That asymmetry is the entire argument.

---
## P13 — ProfileStore is not on Wally, and every package claiming to be it is a stranger's fork

**RESOLVED BY P20** — vendored from the official repository at a pinned commit. The
entry below is kept for the reasoning, not as an open question.

**Was blocked on the owner.** The pure save layer was finished and tested without it; only
the thin adapter in `src/server/Services/` needed the library itself.

**The situation.** `CLAUDE.md` section 2 and `wally.toml` both assume ProfileStore arrives
as a Wally dependency in P2. It cannot. Checked directly against the index rather than
from memory:

| probe | result |
|---|---|
| `UpliftGames/wally-index` → `madstudioroblox/` | 404 — the scope does not exist |
| same index → `loleris/`, `mad-studio-roblox/` | 404 |
| `api.wally.run/v1/package-search?query=profilestore` | 9+ hits, **all third-party forks** |

The forks found: `b1ntran`, `sekuriyo-lotus`, `rustyvirtualgit`, `vyon`, `ddashdev`,
`aspecky`, `buweyy`, `goset33` and others. Several describe themselves as patched for the
new Luau type solver. The upstream module is distributed as a Roblox library asset and a
GitHub repo (`MadStudioRoblox/ProfileStore`), not through Wally.

**Why this is not a shrug.** This is the one module in the project whose failure is
permanent. A bug anywhere else is a bad battle; a bug here is a player's save. Taking an
unreviewed fork of it from an account with no reputation, pinned by a version string its
owner can move, is a supply-chain decision and not a dependency choice.

**The options, as they actually stand.**

1. **Vendor upstream at a pinned commit.** Copy the official module into the repo with its
   licence and the exact commit recorded. Git stays the source of truth, which is already
   this project's stated principle, and the code is reviewable in-tree. Updates are manual.
2. **Depend on a third-party fork via Wally.** One line, normal tooling, and a persistence
   layer maintained by somebody unknown.
3. **Defer.** The pure layer is done and tested. Leave the adapter unwritten.

**Decision: option 1,** taken by the owner. Vendoring means downloading a third-party file
into the repository, which was theirs to authorise rather than mine. See **P20** for what
was actually vendored, what the audit found, and the two check-exclusions it required.

**Reversal.** Cheap in every direction — the library sits behind the injected `Store`
interface in `SaveSession.luau`, so swapping sources touches one file and no tests.

---

## P14 — The save system is split in two, and the test shim is what decided where the line falls

**Decision.** All save logic lives in `src/shared/Save/` — schema, migrations, validation,
session bookkeeping. `src/server/Services/` gets only the wiring that hands it the real
ProfileStore and the real `Players` events.

**Why there, specifically.** Absolute Rule 1 bans Roblox API in `src/shared/Battle/` only,
so a save module could legally have gone anywhere. The deciding constraint was mechanical:
`.lune/roblox_require.luau` mounts `src/shared` and `tests`, and nothing else. Code under
`src/server/` cannot be required under Lune at all, so anything put there is permanently
untestable. That is not a convention anyone has to remember — it is enforced by the
harness, and it means the line between "logic" and "wiring" is drawn by what can be tested
rather than by taste.

**What follows from it.** The store is injected, the same way the engine takes its RNG and
its dex. A fake store can deny a lock, end a session unprompted, or hand back a corrupt
save — none of which can be provoked against a real DataStore. Every refusal path in the
load pipeline is tested because of this, and none of them would be otherwise.

**Reversal.** Moving logic into `src/server/` is always possible and always costs its
tests. The direction worth guarding is the lazy one.

---

## P15 — A reserved field is enforced by a source scan, not by a comment

**The situation.** P12 reserved `nature` and `abilityId` and added a clause: do not let
"the field exists" drift into "the system exists". Every other part of P12 is a one-time
act. That clause is a promise about the next six months.

**Decision.** `tests/save/ProfileSchema.spec.luau` scans every file under `src/` for a read
or write of either field and fails on a hit, with the declaring file excluded. It also
asserts no `Data/Natures.luau` or `Data/Abilities.luau` exists, because an unused table of
natures sitting in `Data/` is content however inert it looks.

Implementing either system means deleting the field from that spec's `RESERVED` list — a
deliberate act, in a diff, with a decision-log entry attached. The test is the mechanism by
which that cannot happen quietly.

**It already paid for itself.** `ProfileValidate` wanted to range-check both fields while
validating everything else on a creature. That would have been reading them, and the scan
would have gone red. Not validating them is correct: there is nothing to validate, because
nothing writes them.

**Also corrected here.** Two comments became false the moment the fields landed, and saying
nothing would have left the codebase arguing with itself:
`Types/CreatureInstance.luau` claimed natures were "deliberately absent", and
`Battle/StatCalc.luau` claimed there was no field to read.

**Reversal.** Deleting the scan is a one-line change, and it is the exact line a reviewer
should ask about.

---

## P16 — The storage cap is a product decision; the technical ceiling was measured and is twenty times higher

**The situation.** `MAX_STORAGE_SIZE` had to be some number. A DataStore value is capped at
4 MB, and exceeding it does not truncate the save — the write fails outright, for whichever
player has collected the most.

**Decision.** 300, with the arithmetic done rather than guessed. `.lune/profile-size.luau`
builds a worst-case profile and reports:

```
  one maximal creature ......... 695 bytes
  a completely full profile .... 225.7 KB  (5.51% of the limit)
  headroom ..................... 3870.3 KB
  limit reached at about ....... 6034 creatures
```

So 306 creatures is nowhere near the constraint. 300 is a slice-scoped product choice — how
much boxing the vertical slice wants — and not a technical ceiling.
`tests/save/ProfileSchema.spec.luau` asserts a full profile stays under half the limit, so
the fields Phase 3 adds cannot quietly eat the margin.

**Why a measurement script and not just the test.** The test answers yes or no. The useful
question when adding a field is "how much room is left", and that needs a number.

**Reversal.** Raising the cap is free and needs no migration — the field already holds a
list. Lowering it is the expensive direction, because it orphans creatures, and
`ProfileValidate` deliberately will not "repair" an over-full storage: the only way to do
that is to delete creatures, which it never does.

---

## P17 — The migration runner is injected, owns the version number, and works on a copy

**The situation.** Version 1 is the first format that has ever existed, so `STEPS` is empty.
A migration framework with nothing to migrate is untested scaffolding, which is the precise
trap CLAUDE.md warns about for `src/server/`.

**Decision.** The runner takes its step list as an argument.
`tests/save/Migrations.spec.luau` drives it with synthetic steps, so every branch is
exercised before a real migration exists — the same injection the engine uses for the RNG
and the dex, for the same reason. Synthetic steps are also the `tests/fixtures/` argument
applied again: a real migration landing must not be able to redden the runner's own suite.

**Absolute Rule 7 is now a test.** A five-line test walks `STEPS` and asserts it forms a
complete path from v1 to `CURRENT_SCHEMA_VERSION`. Bumping the version without writing the
migration is the mistake a code review misses and that surfaces only when a player with an
old save logs in. It now goes red immediately.

**Three smaller calls, each a bug avoided.**

- **The runner stamps `schemaVersion`, never the step.** A step whose author forgets would
  leave a profile that migrates again on every login, re-running a transform that is rarely
  idempotent.
- **Steps run against a deep copy.** The input is ProfileStore's live session table. A
  migration that fails on step three of four must not leave it in a shape no version
  describes. Deep rather than shallow, because a shallow copy still shares the player's
  real inventory and party tables.
- **The path is planned before any of it runs.** Finding the gap halfway through would leave
  a half-migrated profile.

**The refusal worth naming.** A profile whose version is *higher* than this build's is
refused, not loaded. That is a staged rollout or a rollback: the save would load perfectly
and then silently drop every unknown field on the next write. A refused load costs that
player one session; the silent downgrade costs them the save.

**Reversal.** The runner is pure and its signature does not change when real steps arrive.

---

## P18 — Validation splits fatal from repairable on a mechanical rule, and repair has two invariants

**Decision.** `ProfileValidate` returns two lists rather than a boolean, because a bad save
is two situations. The rule for sorting them is mechanical, so nobody has to re-derive the
philosophy when adding a field:

- a wrong **type** is fatal — a string cannot be clamped into a level without inventing a
  number
- a wrong **value** of the right type is repairable — there is exactly one correct answer,
  so clamping is not a guess

A fatal verdict refuses the load. That costs the player a session and keeps the save
intact, which is the right way round: ProfileStore will not overwrite a profile it never
released, so a refused load loses nothing, while a guessed repair is written to disk and is
permanent.

**The two invariants that make unattended repair safe,** both asserted directly:

- **Repair never deletes a creature.** An over-sized party spills into storage. Every clamp
  here is reversible annoyance; a vanished creature is the thing a player quits over.
- **Repair is a fixed point.** A repaired profile validates clean on a second pass. Without
  that, every login repairs the same fields and writes the same lines to the log forever,
  which is where a real bug would hide.

**The EV-total rule is arbitrary and therefore written down.** Which stat to cut when a
spread exceeds 510 is genuinely ambiguous, so the rule is deterministic rather than clever:
walk the stats in canonical order and clamp each so the running total never passes the cap.
Earlier stats keep what they have.

**One guard is fatal that could have gone either way.** A creature with an empty move list
cannot take a turn, and there is no correct move to invent — picking one hands the player
something they never taught it. A refused login beats a battle that errors on turn one.

**Deliberately not checked:** whether a `speciesId` or `moveId` exists. That needs the
content tables, and a save must stay loadable while content is being edited. A renamed
species is a content migration, not a corrupt save.

**Reversal.** Severity is per-check and each one is a single line.

---

## P19 — Four calls in the session layer that are about trust, not mechanism

**Decision, in descending order of how much damage the alternative does.**

**Reconcile is never called, and a test asserts it.** ProfileStore's `Reconcile` fills in
missing template keys. That is exactly the silent save-format change Absolute Rule 7
forbids — a field appearing with no migration and no record that it did. Migrations are the
explicit mechanism and they are tested. Reconcile would also paper over the missing fields
the validator exists to catch, and would make the migration system look unnecessary while
quietly doing a worse version of its job.

**An owner mismatch is fatal.** A profile whose `ownerUserId` is not the player being loaded
is refused. This is the worst thing a load can return: a key collision or a mis-keyed write
would otherwise hand a player someone else's creatures and then save the result under their
own key, destroying both profiles.

**The session-end callback recognises its own session, not just its player.** `EndSession`
fires `OnSessionEnd`, so a late callback from a session the player already left would drop
the profile they are currently using after a rejoin — and from then on every write goes to a
table nothing saves. Nothing about it looks wrong until the progress is gone.

**The store template carries owner id 0 as its "never saved" sentinel.** ProfileStore needs
one static template, so it cannot know whose it is. Roblox user ids start at 1, so 0 is
unambiguous. A test asserts it never survives into a live profile: one that did would mint
creature uids colliding with every other new player's.

**And one that is only a convention until it is not.** The storage key is `Player_<userId>`,
asserted by a test. Changing the format orphans every existing save — the old key stays in
the DataStore and nothing ever looks at it again.

**Reversal.** All four are single-line changes in `SaveSession.luau`, which is why each one
has a test holding it in place rather than a comment.

---
## P20 — ProfileStore vendored at a pinned commit, and the two check-exclusions that came with it

**Resolves P13.** The owner's call: vendor from the official repository, not any Wally
fork.

**What was vendored.**

| | |
|---|---|
| source | <https://github.com/MadStudioRoblox/ProfileStore> |
| commit | `45c9847cbcf1fc260369c50eb335aba7c35aecdd` (2025-07-31) |
| `sha256` | `ad43737203688b8e88cab34ebe8c483000c157e53bfb41e35f1b49ee89d0c95f` |
| licence | **Apache 2.0**, not MIT — retained at `vendor/LICENSE` |
| size | 2242 lines |

**There is no release to pin to.** The repository publishes no tags and no releases, so
"the latest release commit" is the default-branch tip at the time of vendoring. That is
worth knowing before anyone goes looking for a version number: there isn't one, and a
future update is a commit-to-commit diff rather than a changelog read.

**The file was audited before it went in,** which is the point of vendoring over
depending:

- No `HttpService` requests, no `loadstring`, no `getfenv`, no `require` of a marketplace
  asset id, no escaped-byte obfuscation.
- `HttpService` appears once, for `GenerateGUID`, to mint session ids.
- The four services it uses are `DataStoreService`, `MessagingService`, `RunService` and
  `HttpService` — exactly what session-locked persistence needs and nothing more.

**One modification: a 33-line provenance header.** Apache 2.0 requires stating changes, so
the header states that it is the only one. `vendor/README.md` carries the command that
proves the rest is byte-identical: `tail -n +34 vendor/ProfileStore.luau | sha256sum`.

**Three upstream behaviours the adapter had to be written around,** all found by reading
the source rather than the docs, and all recorded in `DataService.luau` so the next update
can re-check them:

1. **`StartSessionAsync` throws** rather than returning nil when the key is already live on
   this server (`ProfileStore.luau:1390`). `ActiveSessionCheck` is cleared only after the
   asynchronous release finishes, so a player who leaves and rejoins the same server fast
   enough hits it. The adapter converts that throw into the nil `SaveSession` already reads
   as `lock-unavailable`; without it, the error escapes a `PlayerAdded` handler and the
   player sits in the game with no profile and nothing watching.
2. **`params` is `{Steal: boolean?}` and there is no cancel callback.** That was
   ProfileService's API. `SaveSession`'s own comment claimed otherwise and has been
   corrected. The "player left while the load was yielding" case therefore has to be
   checked by hand in `onPlayerAdded`.
3. **`EndSession` is asynchronous** — it `task.spawn`s the final save
   (`ProfileStore.luau:1090`), so the session is not released when the call returns and
   `OnSessionEnd` fires later. The test fake fires it synchronously, which is stricter than
   reality and therefore safe.

**`Reconcile` is still never called** (P19), and reading the source confirms why it would
be wrong: `Profile:Reconcile()` is `ReconcileTable(self.Data, self.ProfileStore.template)`,
which is precisely the undocumented field injection Absolute Rule 7 forbids.

**Two exclusions, both load-bearing, both now in CI.**

- **`--ignore="vendor/**"`.** The adapter requires ProfileStore, so `luau-lsp` follows the
  require and reports **36 type errors inside the vendored module** — unknown `task`,
  incompatible internal table types, `false` compared with `true`. None of them are ours
  and none are fixable without editing upstream.
- **`--definitions=globalTypes.d.luau`.** `src/server/` is the first code in this project
  to use the Roblox API at all, so `task`, `warn` and `Player` had no definitions and
  produced **10 errors**. The `luau-lsp analyze` warning about missing definitions had
  been printing harmlessly for the whole project until now.

Both together give 0. The file is downloaded in CI rather than committed: it is an 880 KB
generated mirror of Roblox's API dump, and pinning it would mean shipping something stale
within the week. The cost is that CI now depends on one more URL.

`vendor/` is also out of StyLua's reach (`.styluaignore`) and out of Absolute Rule 3's
scan, which it already was by sitting outside `src/`. That accident is now an assertion:
`tests/battle/Purity.spec.luau` fails if `vendor` is added to `STRICT_DIRS`, if the
directory is moved under `src/`, or if `.styluaignore` stops covering it. `vendor/.luaurc`
sets `nonstrict` with lints off, so the exemption holds for editors too.

**This is the only directory in the repo where "do not apply our standards" is correct,
and the only one where a nonstrict file is allowed.**

**Reversal.** Deleting `vendor/` and taking a Wally fork is a one-line change to
`wally.toml` plus one require in `DataService.luau` — the library sits behind
`SaveSession.Store`, so no test moves. Going the other way, to a newer upstream commit, is
the procedure in `vendor/README.md`, and step 5 is re-checking the three behaviours above.

---
