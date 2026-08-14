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
