# Phase 1 decision log

Every judgement call made without the owner in the room, while building the battle
engine. One entry each: what was decided, what else was on the table, and how to
reverse it.

This exists because the alternative is a codebase full of choices nobody remembers
making. A decision recorded here can be argued with later; one that only lives in the
shape of the code cannot.

Entries are append-only and numbered. Do not renumber.

---

## D1 — Stage 4's instructions arrived truncated; CLAUDE.md §7 used as the authority

**Decision.** The Stage 4 brief ends mid-sentence: "Capture math against known-good
reference values. Engine is". Capture is fully specified and was built as written.
For Engine, the scope was taken from CLAUDE.md §7, which defines Phase 1 exactly:
1v1 and 6v6, move/switch/item/run actions, the Gen-5 damage formula, the 12-type
chart, 5 status conditions, stat stages −6..+6, priority, and capture — with the gate
being "200+ tests green AND a full 6v6 battle resolving in the terminal from a fixed
seed".

**Alternatives.** Stop and wait for the rest of the sentence, which would have burned
most of the hour. Or guess at a larger Engine — matchmaking, AI, persistence — none
of which Phase 1 asks for.

**Reversal.** Engine's public surface is small (`start`, `submitTurn`, `isOver`,
`winner`). If the intended scope was different, the module is one file and its spec is
one file; neither is depended on by anything below it.

---

## D2 — Paralysis speed and the stat-stage ladder recorded as §10 entries, not §5

**Decision.** Both housekeeping notes went into CLAUDE.md §10 "Known gotchas already
hit", as instructed, even though one is a design decision rather than a gotcha.

**Alternatives.** §5 (roles and stat design) is where stat-stage numbers would
naturally live, and a design decision is not really a "gotcha".

**Why §10 anyway.** Both entries exist to stop a future agent from "fixing" something
that is deliberate. That is exactly what §10 is read for. The stat-stage entry is also
a genuine trap: the brief's numbers looked authoritative and were not.

**Reversal.** Move the paragraphs to §5; nothing references them by section number.

---
## D3 — 21 moves split 12 damaging + 9 utility, not evenly across roles

**Decision.** Twelve damaging moves, exactly one per type, plus nine utility moves.

**Why that split.** "Every one of the 12 types needs at least one STAB move" is a hard
floor that consumes 12 of the 21 slots before role coverage is considered at all. The
remaining nine had to cover twelve roles, so several roles share: `forge.replate`
(recovery) serves PhysicalWall, SpecialWall and Tank, because recovery is what makes
all three of those roles function.

**Alternatives.** Spread the damaging moves unevenly — two for offensive types, none
for defensive ones — and spend the slack on utility. Rejected: a type with no damaging
move of its own has characters who cannot use their own type offensively, which makes
the type a label rather than an identity.

**Reversal.** `EXPECTED_MOVE_COUNT` in `tests/data/Moves.spec.luau` is one constant.
The per-type and per-role coverage tests are independent of the total, so growing the
table does not fight them.

---

## D4 — Role coverage lives in a ROLE_REFERENCE map, not a field on Move

**Decision.** `Moves.ROLE_REFERENCE` maps each role id to the moves that demonstrate
it. `Types/Move.luau` was not given a `role` field.

**Alternatives.** Add `role: RoleId` to the Move type. That reads better at the call
site and the validator could check it directly.

**Why not.** A move is data and has no opinion about who uses it — the same recovery
move serves three roles, and a single-valued field would force a lie. Changing the
Move type would also have touched every existing fixture and spec for a field the
engine never reads.

**Reversal.** Delete the map and add the field; the two coverage tests would need
rewriting against it, nothing else.

---

## D5 — The real move table reaches the engine through signature compatibility, not an adapter module

**Decision.** `Moves.getMove(id)` is written with exactly the signature
`BattleDex.getMove` expects, so a caller composes a dex inline:
`{ getMove = Moves.getMove, getStats = ..., getTyping = ... }`. No adapter module was
created.

**Alternatives.** A `Battle/Dex.luau` that imports `Data/Moves`, or a
`Data/BattleDex.luau` that imports the Battle type.

**Why not.** Either one creates a compile-time edge between `Battle/` and `Data/`, and
the whole reason TurnResolver takes an injected dex is that no such edge exists. An
adapter would also be a file with no behaviour of its own to test. Structural
compatibility gets the same result with nothing in between.

**Cost.** Nobody is forced to use the real table — a caller can still pass a dex that
returns nonsense. That is the same tradeoff the injected dex already made.

**Reversal.** Write the adapter; `getMove` already has the right shape, so it would be
a three-line file.

---

## D6 — Arcane's reference move carries a secondary status rather than raw power

**Decision.** `arcane.sigilbrand` is 75 power plus a 30% Poison chance, not a clean
90-power attack.

**Why.** Arcane's declared lean is status, hazards, debuffs and field control, and its
one reference move should show what the type is FOR. A pure 75-power special move
would be indistinguishable from a Ki move with a different colour.

**Alternatives.** Make it a pure status move — but then Arcane has no damaging
same-type move and fails the per-type STAB requirement.

**Reversal.** Drop the InflictStatus effect; the tier and accuracy tests do not depend
on it.

---

## D7 — The 130 nuke pays a Recharge volatile, not a -2 SpA drop

**Decision.** `flame.cinderlash` costs the user the `Recharge` volatile.

**Alternatives.** CLAUDE.md section 6 offers both: "Recharge turn or -2 SpA". A -2 SpA
drop would have reused a primitive already implemented; Recharge needed
`ApplyVolatile`, which was not implemented until Stage 3.

**Why Recharge.** A recharge turn is a real decision — it is a commitment the opponent
can read and punish by switching in something that walls the follow-up. A -2 SpA drop
just makes the second use worse, which is the same choice with less drama. The
validator accepts either, so a future nuke can take the other road.

**Reversal.** Swap the effect for `{ kind = "StatStage", stat = "spa", delta = -2,
target = "Self" }`. The nuke-cost test explicitly accepts both forms.

---

## D8 — Phazing is priority -6 rather than accuracy-gated

**Decision.** `spirit.hollowcall` has priority -6 and 100% accuracy.

**Why.** Matches Gen 5, where the phazing moves moved to guaranteed accuracy and paid
for it in priority. It also produces the better interaction: the move always goes last,
so it undoes a setup sweeper only AFTER that sweeper has had its turn. Making it
accuracy-gated instead turns a read into a coin flip.

**Reversal.** One field.

---
## D9 — Capture moved from Stage 3 to Stage 4, where its maths lives

**Decision.** Stage 3 implements 15 of the 16 remaining primitives. `Capture` is
implemented in Stage 4 alongside `Capture.luau`.

**Why.** Capture is the one primitive whose behaviour is a whole module rather than a
few lines. Implementing the effect in Stage 3 would have meant either stubbing it and
implementing it twice, or pulling Stage 4's capture formula forward into Stage 3 and
losing the commit boundary the brief asked for.

**Reversal.** None needed — it lands in the next commit either way.

---

## D10 — TurnResolver imports Data/TypeChart, and the "no edge to Data" claim was narrowed

**Decision.** `FixedDamage` needs to know whether the target is immune, so TurnResolver
now imports `Data/TypeChart`. The module header's claim that the engine "never reads
src/shared/Data directly" was rewritten rather than left standing.

**Why this is not a contradiction.** The chart is RULES, not content — as much part of
the battle system as the damage formula, and it changes about as often. DamageCalc has
imported it since Stage 1 of the previous session, so the original claim was already
inaccurate. The tables the injected dex exists to keep out are the CONTENT tables,
Moves and Species, which change whenever anyone rebalances anything.

**Alternative considered.** Route the immunity probe through DamageCalc, as the Damage
path does. Rejected: it would mean constructing a fake Damage effect to ask a question
about a FixedDamage one, which is more indirection for less clarity.

**Reversal.** Add `getEffectiveness` to BattleDex and inject it; two lines plus every
dex construction site.

---

## D11 — Damage-scaled recoil charges nothing when the move dealt nothing

**Decision.** `Recoil.fractionOfDamageDealt` returns early when the move dealt zero
damage. `Recoil.fractionOfUserMaxHp` still applies unconditionally.

**Why the asymmetry.** The two fractions mean different things. A fraction of the user's
max HP is the move's own price, paid for using it. A fraction of the damage dealt is a
share of an outcome, and there is no share of nothing. Charging the one-point minimum
against an immunity would bill a player for information they could not have had.

**Alternatives.** Charge the minimum regardless, which is simpler and arguably more
punishing-by-design.

**Reversal.** Delete the early return in `applyRecoil`; one test covers it directly.

---

## D12 — Every point of HP the engine removes goes through one function

**Decision.** `dealDamage` and `healCreature` are the only places HP changes during
effect resolution. Damage, FixedDamage and Recoil all call the same funnel.

**Why.** Clamping at zero, emitting the faint event, and writing the log line are three
things that must agree, and before this refactor the multi-hit loop did them inline
while nothing else did them at all. A second caller doing it slightly differently is
how a creature ends up at -3 HP or faints twice.

**Reversal.** Inline it again, but the faint-event tests will hold you to the behaviour.

---
## D13 — Three volatiles gate actions; the other ten are stored and inert, and said so out loud

**Decision.** `ApplyVolatile` stores any of the 13 volatiles faithfully, but only
Recharge, Flinch and Taunt change what the engine does. A `VOLATILE_BEHAVIOUR` table in
TurnResolver names exactly which three.

**Why not all thirteen.** Confusion, Substitute, LeechSeed, Protect, Endure, Encore,
Locked, Bound, Charging and FocusEnergy are each a small feature with its own rules and
its own tests. Implementing ten of them inside a commit labelled "the four
condition primitives" would have been a much larger change hiding behind a smaller
description.

**Why those three.** They are the ones the vocabulary already depends on. Recharge is
the price of the 130 tier and `flame.cinderlash` already applies it — without the gate
the nuke is free and CLAUDE.md's tier table is a lie. Flinch and Taunt are the two that
gate an action rather than modify a number, so they share the machinery Recharge needed
and cost almost nothing extra.

**The risk being managed.** A volatile that is stored and never read is worse than one
that is missing: the state looks right, the log looks right, and the move does nothing.
The table exists so that gap is greppable rather than a surprise.

**Reversal.** Each remaining volatile is an independent addition; none of them require
changing what is here.

---

## D14 — A stated volatile duration counts the turn it landed on

**Decision.** `duration = 3` means three turns including the one the volatile was
applied on, because the end-of-turn tick runs on that turn too.

**Alternatives.** Skip the first tick so the number means "three full turns after
this one". That needs a marker on the volatile recording the turn it arrived, and
`VolatileState` lives in `Types/BattleState.luau` — data-architect's file.

**Why this one.** It avoids editing another agent's type for a cosmetic difference, and
"three turns" counting the current turn is the more common reading in the genre anyway.

**Reversal.** Add a field to VolatileState and skip one tick; two tests assert the
current counts and would need their numbers moved by one.

---

## D15 — A creature cannot cure its own sleep, and that is the correct behaviour

**Decision.** Left as-is after a test caught it: the status gate blocks a sleeping
creature before any effect runs, so a self-targeted CureStatus can never fire while
asleep. The test was rewritten to cure from the bench instead.

**Why this is right rather than a bug.** Sleep's entire cost is losing turns. A move
that cured it from inside would make sleep cost one turn always, which is not a status
condition, it is a minor inconvenience. Curing sleep is what a cleric teammate is for.

**Reversal.** Move the CureStatus dispatch ahead of the status gate — but the ordering
tests for sleep would all need revisiting, and the status would stop mattering.

---
## D16 — Sigilstones measure themselves as Arcane

**Decision.** The type-scaled hazard uses `Arcane` for its effectiveness lookup, at a
1/8 base fraction, so an entrant takes anywhere from 1/32 to 1/2 of its maximum HP.

**Why a type is needed at all.** The whole point of a type-scaled hazard is that it
punishes a specific team composition rather than taxing everyone equally, and that
requires something to measure against.

**Why Arcane.** A laid sigil is the thematic fit, and it puts the pressure on Ki, Feral
and Aqua — none of which is the type most likely to be switching repeatedly, so it
does not simply reinforce whatever is already strong.

**Alternatives.** Forge, since the hazard-setting reference move is Forge. Rejected:
Forge's 2x list (Martial, Frost, Terra) overlaps heavily with the physical attackers
that already want to stay in, so it would have been close to a dead hazard.

**Reversal.** `SIGILSTONE_TYPE` is one constant in TurnResolver.

---

## D17 — Screens and weather ride DamageCalc's trailing modifier slot

**Decision.** Bulwark, Veilward and the two biasing weathers are folded into the
`otherModifier` field DamageCalc already exposes, rather than teaching the formula what
a screen is.

**Cost, stated plainly.** That slot is applied LAST, after burn. Gen 5 applies weather
earlier in the chain. Because every step truncates, the two orderings can differ by a
point in stacked cases.

**Why accept it.** The alternative is DamageCalc reading BattleState, which would turn a
pure function over numbers into something that needs a whole battle to test. A
one-point difference in a stacked-modifier case is not worth that.

**Reversal.** Add explicit `weather` and `screen` fields to DamageInput and apply them
in Gen 5 order inside the formula.

---

## D18 — Weather exempts the types it is made of

**Decision.** Duststorm does not chip Terra or Forge; Whiteout does not chip Frost.

**Why.** A weather that damages the type it is made of reads as a bug to a player
however defensible the arithmetic, and it also makes those types strictly worse under
conditions their own characters are most likely to set.

**Reversal.** `FIELD_CHIP_EXEMPT` is one table.

---

## D19 — Inversion reverses speed and nothing above it

**Decision.** Under the Inversion field the speed comparison flips, but the priority
bracket and the switch-before-moves rule are untouched.

**Why.** Inverting priority as well would make a priority move go last, which no player
would predict, and it would make phazing at -6 the fastest action in the game. Speed is
the only axis Inversion is about.

**Reversal.** `orderActions` takes `invertSpeed`; widening it to invert priority is a
two-line change and a lot of broken expectations.

---
## D20 — SelfSwitch picks its replacement at random, and that is a placeholder

**Decision.** A pivot move brings in a randomly chosen living party member, drawn from
the injected RNG so it still replays from a seed.

**Why it is wrong, said out loud.** In a real battle the player chooses the
replacement, and that choice is most of what makes a pivot move worth a moveslot.
Picking at random is not the behaviour this should ship with.

**Why it is here anyway.** Engine owns prompting for a mid-turn choice and Engine does
not exist yet. The alternatives were to make the move silently do nothing — the exact
failure the VOLATILE_BEHAVIOUR table exists to prevent — or to invent a pending-choice
protocol now and rewrite it when Engine lands.

**Reversal.** When Engine can prompt, `applySelfSwitch` stops calling `bringIn` and
records a pending switch on the turn outcome instead. The tests asserting that the user
withdraws stay true; only the choice of replacement changes.

---

## D21 — Phazing beats trapping

**Decision.** `Trap` blocks a voluntary switch. It does not block `ForceSwitch` — a
phazing move drags a trapped creature out normally.

**Why.** A trap that also blocked being dragged out would leave the trapped side with
no way off the field at all: no switch, no phaze, nothing but attacking until something
faints. That is a lock rather than a matchup, and locks are what make a trapper
un-fun to play against rather than dangerous.

**How it falls out of the code.** `performSwitch` checks the trap; `applyForceSwitch`
calls `bringIn` directly and never sees the check. That is deliberate, not an
oversight, and is commented as such at both sites.

**Reversal.** Move the trap check into `bringIn` and both paths block.

---

## D22 — Leaving the field releases every trap in both directions

**Decision.** `bringIn` clears `trappedBySideId` on the creature entering AND clears any
trap that the departing creature was applying to the other side.

**Why both.** A trap is a relationship between two creatures on the field. If the
trapper leaves and the mark stays, the victim is held by nobody — permanently, with no
counterplay and no visible cause. That is the worst class of bug in a battle system:
one where the state is wrong but nothing looks wrong.

**Reversal.** Neither direction is needed if traps become duration-based instead.

---
