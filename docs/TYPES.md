# The type bible

**Read this before any change to `src/shared/Data/TypeChart.luau`.**

The chart is locked. Not "settled for now" — locked. Everything downstream of it
(roles, movepools, encounter tables, gym design) is balanced against these exact
numbers, and a one-line edit here silently invalidates work that has nothing to do
with types.

---

## Why type identity is the source of power

Every collectible in this game is a **human**. That single decision kills the axis
every other game in the genre uses — "what is it?" — because the answer is always the
same. A first draft used Beast/Machine/Blade and immediately collapsed: a swordsman
with a mechanical arm who transforms in a rage is all three, and nothing about that
tells you how the matchup should go.

The axis that works is **where the power comes from**. It is knowable from a single
illustration, it never returns "all of the above", and it maps onto how these stories
actually differentiate their characters.

Two families:

- **Discipline (7)** — the source of the power itself.
- **Element (5)** — the natural force the character commands.

### The Ki / Arcane test

The two hardest types to keep apart, and the pair a new character will most often be
misfiled between.

> If the power stops working when the character is alone in an empty room, it is
> **Arcane**. If it does not, it is **Ki**.

Ki is cultivated and internal — it is *in* them. Arcane is transactional and
external — a contract, a sigil, a bound familiar, a sealed artifact. The visual
signature follows: an Arcane character always has something floating *near* them that
is not part of them.

This is enforced mechanically as well as visually. **Arcane has no setup moves.** Ki
boosts itself; Arcane manipulates the opponent. Delete that wall and the two types
become one type with two names inside twenty characters.

### The element rule, one line

**The character commands the element; they are not made of it.**

A fire-shaped blob is a different game's starter. A swordsman whose blade breathes
cinder is this one. Applied consistently this keeps the roster human-looking, which is
the entire visual premise.

---

## The chart

`CHART[attacker][defender]`. Omitted pairs are neutral. Dual types multiply.

| Attacker | 2× | 0.5× | 0× |
|---|---|---|---|
| Martial | Arcane, Feral, Frost | Martial, Forge, Spirit, Terra | — |
| Ki | Martial, Forge, Terra | Ki, Arcane, Psyche, Frost | Spirit |
| Arcane | Ki, Feral, Aqua | Arcane, Psyche, Flame, Storm | — |
| Psyche | Ki, Feral, Spirit | Psyche, Arcane | Forge |
| Spirit | Arcane, Psyche, Spirit | Martial, Feral, Forge, Frost | — |
| Feral | Arcane, Psyche, Storm | Martial, Feral, Forge, Flame | — |
| Forge | Martial, Frost, Terra | Forge, Flame, Storm, Aqua | — |
| Flame | Feral, Forge, Frost | Flame, Storm, Terra, Aqua | — |
| Frost | Storm, Terra, Aqua | Ki, Feral, Frost | — |
| Storm | Spirit, Forge, Aqua | Ki, Frost, Storm | Terra |
| Terra | Flame, Forge, Storm | Martial, Arcane, Spirit, Terra | — |
| Aqua | Martial, Flame, Terra | Feral, Frost, Aqua | — |

### Defensive profiles

The same data read the other way — this is the view that actually matters when you are
placing a new character, and the one people forget to check.

| Defender | Weak to | Resists | Immune to | W/R |
|---|---|---|---|---|
| Martial | Ki, Forge, Aqua | Martial, Spirit, Feral, Terra | — | 3/4 |
| Ki | Arcane, Psyche | Ki, Frost, Storm | — | 2/3 |
| Arcane | Martial, Spirit, Feral | Ki, Arcane, Psyche, Terra | — | 3/4 |
| Psyche | Spirit, Feral | Ki, Arcane, Psyche | — | 2/3 |
| Spirit | Psyche, Spirit, Storm | Martial, Terra | Ki | 3/2+1 |
| Feral | Martial, Arcane, Psyche, Flame | Spirit, Feral, Frost, Aqua | — | 4/4 |
| Forge | Ki, Flame, Storm, Terra | Martial, Spirit, Feral, Forge | Psyche | 4/4+1 |
| Flame | Terra, Aqua | Arcane, Feral, Forge, Flame | — | 2/4 |
| Frost | Martial, Forge, Flame | Ki, Spirit, Frost, Storm, Aqua | — | 3/**5** |
| Storm | Feral, Frost, Terra | Arcane, Forge, Flame, Storm | — | 3/4 |
| Terra | Ki, Forge, Frost, Aqua | Martial, Flame, Terra | Storm | 4/3+1 |
| Aqua | Arcane, Frost, Storm | Forge, Flame, Aqua | — | 3/3 |

Weaknesses stay in 2–4, resistances in 2–5. Both bounds are asserted by the test
suite, per type, so a regression names the type it broke.

---

## Load-bearing decisions

### Frost keeps five resistances

Pokémon's Ice type is the canonical design failure of this genre: superb offensively,
**one** resistance, and permanently unplayable no matter what base stats it is given.
Twenty-five years of buffs never fixed it, because the problem was never the numbers.

Frost here is a defensive type that happens to hit hard. Its 2× list (Storm, Terra,
Aqua) is deliberately narrow.

**Do not "fix" Frost by making it more offensive.** That is the same mistake with
extra steps, and it will look like an improvement right up until Frost is unplayable
again.

### Arcane gets no setup moves

Covered above. This is a *mechanical* rule, not flavour text, and
`MoveEffect.isSetup()` exists specifically so a validator can enforce it rather than
relying on everyone remembering.

### Three immunities, all asymmetric

| Immunity | Reverse direction |
|---|---|
| Ki → Spirit is 0× | Spirit → Ki is 1× |
| Psyche → Forge is 0× | Forge → Psyche is 1× |
| Storm → Terra is 0× | Terra → Storm is 2× |

An immunity is the strongest single relationship in the game: it grants a free
switch-in, which is the most valuable resource in turn-based PvP.

Symmetric immunities create **dead matchups** where neither side can meaningfully act
— the least interesting board state a turn-based game can produce. Asymmetric ones
create hard reads: the Spirit player knows the Ki player cannot touch them, and the Ki
player knows that, and both have to act on it.

Three rewards prediction. Six would make the entire metagame about juggling
immunities.

### Discipline stays at seven

Every future type proposal will be a Discipline type, because that is where anime
power fantasies live — sound, poison, time, gravity, luck, blood, probability. All of
them.

**Route them into an existing Discipline type or reject them.** Sound is Ki or Psyche
depending on whether it comes from the body or the mind. Time and gravity are Arcane
if borrowed and Psyche if willed. Luck is not a power source, it is a gimmick, and it
belongs to an ability rather than a type.

### All 12 ship at launch

The chart does not decompose into balanced subsets. Only three balanced 8-type subsets
exist, and **none of them contains the starter triangle**. Shipping "types 1–8 now,
9–12 later" means shipping a broken chart and then breaking it again on the patch that
completes it.

(Holding some types back from the *vertical slice's roster* is a different question
and is a live option — see BUILD_PLAN.md. That is about which characters exist, not
about which entries exist in the chart.)

---

## Legality: 72 of 78

Twelve mono typings and 66 duals. A typing is legal when it has:

- **≥ 2 weaknesses** — fewer and it is too safe to counterplay
- **≤ 6 resistances + immunities** — more and it centralises the metagame
- **≤ 1 quadruple weakness** — more and it is a liability, not a character

All 12 monos pass. Six duals fail:

| Rejected | Why |
|---|---|
| Martial/Terra | 3 quadruple weaknesses (Ki, Forge, Aqua) |
| Ki/Feral | 2 quadruple weaknesses (Arcane, Psyche) |
| Arcane/Psyche | 2 quadruple weaknesses (Spirit, Feral) |
| Feral/Frost | 2 quadruple weaknesses |
| Arcane/Frost | 7 resistances + immunities |
| Frost/Terra | only 1 weakness (Forge, at 4×) |

Note that four of the six are *fragility* failures, not power failures. The instinct
when reviewing a dual type is to check whether it is too strong; the more common
failure is a pair that stacks the same weakness twice.

`TypeChart.validateTyping()` returns the verdict and the reasons. Run it before
approving any dual, and hold the vertical slice to mono-types plus 3–4 duals — dual
typing multiplies both power and bugs.

---

## Coverage: zero unresisted pairs

For every one of the 66 two-type attacking combinations, at least one legal typing
resists both. Defensive play is therefore always *possible*; whether it is *good* is a
stats-and-movepool question, which is the right place for it to be decided.

**Measure against the legal typing pool, not the 12 mono-types.** Measured against
monos alone the same chart reports **20** unresisted pairs — all false alarms, because
no real team is made of mono-types. This distinction has already caused one round of
unnecessary alarm; `findUnresistedPairs()` uses the legal pool.

More than about 4 real results means offensive coverage is too cheap and defensive
play stops being a strategy.

---

## Changing the chart

1. Edit `MATCHUPS` in `src/shared/Data/TypeChart.luau`.
2. Run `lune run run-tests -- --filter TypeChart`.
3. Expect the count assertions to fail. Do **not** update the expected numbers to
   match your change until you have read what moved and can justify it. The numbers
   are the point of the test.
4. Re-check the starter triangle, the three immunities, and Frost's resistance count
   specifically — those are the three things a plausible-looking edit breaks.

A contradiction — the same defender listed as both super-effective and resisted by one
attacker — has been introduced **twice** during design. It is invisible in a
multiplier grid because the second write silently wins, which is why the chart is
authored as three lists per attacker and why `findContradictions()` reads those lists
rather than the derived grid.
