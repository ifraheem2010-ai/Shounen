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
