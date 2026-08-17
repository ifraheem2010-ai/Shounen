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
