--!strict
--[[
	Turn resolution tests.

	The three things a turn has to get right, in the order they bite:

	  1. WHO GOES FIRST. Priority beats speed, speed beats nothing, and a genuine tie
	     is broken by the injected RNG so it stays reproducible.
	  2. WHAT IS STILL TRUE WHEN AN ACTION RUNS. A creature that fainted earlier in
	     the turn does not get to act. Reading the queue as though nothing has changed
	     since it was built is how a fainted character lands a hit.
	  3. WHAT HAPPENS AFTER. End-of-turn chip damage, in speed order.

	All state and move data comes from tests/fixtures/. It is synthetic and NOT
	balance data.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Battle = require(script.Parent.Parent.fixtures.SyntheticBattle)
local Moves = require(script.Parent.Parent.fixtures.SyntheticMoves)
local Shared = script.Parent.Parent.Parent.Shared
local RNG = require(Shared.Battle.RNG)
local TurnResolver = require(Shared.Battle.TurnResolver)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

--[[ Move fixtures used only here ------------------------------------------- ]]

local STRIKE = Moves.build("strike", "Martial", "Physical", 100)
local WEAK = Moves.build("weak", "Martial", "Physical", 10)
local QUICK = Moves.build("quick", "Martial", "Physical", 40, nil, { priority = 1 })
local MULTI = Moves.build("multi", "Martial", "Physical", 25, { hitsRange = { min = 2, max = 5 } })
local STORM = Moves.build("storm", "Storm", "Physical", 100)
local MISSES = Moves.build("misses", "Martial", "Physical", 100, nil, { accuracy = 0 })

local ALL_MOVES = {
	strike = STRIKE,
	weak = WEAK,
	quick = QUICK,
	multi = MULTI,
	storm = STORM,
	misses = MISSES,
}

local function dexWith(species: { [string]: any }): any
	return Battle.dex({ species = species, moves = ALL_MOVES })
end

local BASE_SPECIES: { [string]: any } = {
	fast = { stats = Battle.statsWith({ spe = 120 }), typing = { "Aqua" } },
	slow = { stats = Battle.statsWith({ spe = 50 }), typing = { "Aqua" } },
	even = { stats = Battle.statsWith({ spe = 100 }), typing = { "Aqua" } },
	terra = { stats = Battle.statsWith({ spe = 100 }), typing = { "Terra" } },
	frail = { stats = Battle.statsWith({ spe = 50, hp = 40 }), typing = { "Aqua" } },
}

--[[ Effective speed -------------------------------------------------------- ]]

describe("TurnResolver / effective speed", function()
	local flat = Battle.statsWith({ spe = 100 })

	local function stages(spe: number): any
		return { atk = 0, def = 0, spa = 0, spd = 0, spe = spe, accuracy = 0, evasion = 0 }
	end

	it("is the raw speed with no stages and no status", function()
		expect(TurnResolver.effectiveSpeed(flat, stages(0), nil)).toBe(100)
	end)

	it("applies speed stages", function()
		expect(TurnResolver.effectiveSpeed(flat, stages(1), nil)).toBe(150)
		expect(TurnResolver.effectiveSpeed(flat, stages(2), nil)).toBe(200)
		expect(TurnResolver.effectiveSpeed(flat, stages(-1), nil)).toBe(66)
		expect(TurnResolver.effectiveSpeed(flat, stages(-6), nil)).toBe(25)
	end)

	it("applies the paralysis cut", function()
		expect(TurnResolver.effectiveSpeed(flat, stages(0), "Paralysis")).toBe(50)
	end)

	--[[
		Stages first, then paralysis.

		Speed 99 is chosen deliberately. At a round 100 BOTH orderings produce 75, so
		the obvious test proves nothing:
		    stages then paralysis:  floor(99 * 3/2) = 148 -> floor(148 * 0.5) = 74
		    paralysis then stages:  floor(99 * 0.5) = 49  -> floor(49 * 3/2)  = 73
		Only an odd base speed makes the truncation land in different places.
	]]
	it("applies stages before the paralysis cut", function()
		local odd = Battle.statsWith({ spe = 99 })
		expect(TurnResolver.effectiveSpeed(odd, stages(1), "Paralysis")).toBe(74)
	end)

	it("leaves speed alone under every other status", function()
		for _, status in { "Burn", "Poison", "Sleep", "Freeze" } do
			expect(TurnResolver.effectiveSpeed(flat, stages(0), status)).toBe(100)
		end
	end)

	it("never drops below 1", function()
		expect(TurnResolver.effectiveSpeed(Battle.statsWith({ spe = 1 }), stages(-6), "Paralysis")).toBeGreaterThanOrEqual(
			1
		)
	end)
end)

--[[ Turn order ------------------------------------------------------------- ]]

describe("TurnResolver / action order", function()
	local function entry(sideId: number, kind: string, priority: number, speed: number): any
		return { sideId = sideId, kind = kind, priority = priority, speed = speed }
	end

	local function orderOf(entries: { any }, seed: number): { number }
		local ordered = TurnResolver.orderActions(entries, RNG.new(seed))
		local ids = {}
		for _, e in ordered do
			table.insert(ids, e.sideId)
		end
		return ids
	end

	it("puts higher priority first even against far greater speed", function()
		local entries = { entry(1, "Move", 0, 999), entry(2, "Move", 1, 1) }
		expect(orderOf(entries, 1)).toEqual({ 2, 1 })
	end)

	it("orders by speed within equal priority", function()
		local entries = { entry(1, "Move", 0, 50), entry(2, "Move", 0, 120) }
		expect(orderOf(entries, 1)).toEqual({ 2, 1 })
	end)

	it("respects negative priority", function()
		local entries = { entry(1, "Move", -3, 999), entry(2, "Move", 0, 1) }
		expect(orderOf(entries, 1)).toEqual({ 2, 1 })
	end)

	--[[
		Switching happens before every move regardless of speed. A player who switches
		must eat the incoming hit on the new creature — that is the whole cost of the
		decision, and letting a fast switcher dodge it removes the risk.
	]]
	it("resolves a switch before a move even when the switcher is slower", function()
		local entries = { entry(1, "Move", 0, 999), entry(2, "Switch", 0, 1) }
		expect(orderOf(entries, 1)).toEqual({ 2, 1 })
	end)

	it("resolves a switch before a priority move", function()
		local entries = { entry(1, "Move", 5, 999), entry(2, "Switch", 0, 1) }
		expect(orderOf(entries, 1)).toEqual({ 2, 1 })
	end)

	it("orders two switches by speed", function()
		local entries = { entry(1, "Switch", 0, 50), entry(2, "Switch", 0, 120) }
		expect(orderOf(entries, 1)).toEqual({ 2, 1 })
	end)

	it("breaks an exact tie with the RNG, reproducibly", function()
		local entries = { entry(1, "Move", 0, 100), entry(2, "Move", 0, 100) }
		local first = orderOf(entries, 4242)
		for _ = 1, 20 do
			expect(orderOf(entries, 4242)).toEqual(first)
		end
	end)

	it("lets either side win a tie across seeds", function()
		local entries = { entry(1, "Move", 0, 100), entry(2, "Move", 0, 100) }
		local sawOne, sawTwo = false, false
		for seed = 1, 60 do
			local winner = orderOf(entries, seed)[1]
			if winner == 1 then
				sawOne = true
			else
				sawTwo = true
			end
		end
		expect(sawOne).toBe(true)
		expect(sawTwo).toBe(true)
	end)

	it("does not consult the RNG to decide a non-tie", function()
		-- The draws happen, but they must not change a decided ordering.
		local entries = { entry(1, "Move", 0, 50), entry(2, "Move", 0, 120) }
		for seed = 1, 30 do
			expect(orderOf(entries, seed)).toEqual({ 2, 1 })
		end
	end)
end)

--[[ Resolving a turn ------------------------------------------------------- ]]

describe("TurnResolver / resolving a turn", function()
	local function scenario(options: { [string]: any }?): any
		local o: any = options or {}
		local sideOne = Battle.side({
			id = 1,
			party = {
				Battle.creature({
					uid = "one",
					speciesId = o.speciesOne or "even",
					moveIds = o.movesOne or { "strike" },
					currentHp = o.hpOne or 200,
					status = o.statusOne,
					statusTurns = o.statusTurnsOne,
					pp = o.ppOne,
				}),
			},
		})
		local sideTwo = Battle.side({
			id = 2,
			party = {
				Battle.creature({
					uid = "two",
					speciesId = o.speciesTwo or "even",
					moveIds = o.movesTwo or { "strike" },
					currentHp = o.hpTwo or 200,
					status = o.statusTwo,
					statusTurns = o.statusTurnsTwo,
					pp = o.ppTwo,
				}),
			},
		})
		return Battle.state({ sides = { sideOne, sideTwo } })
	end

	local function resolve(state: any, intents: any, seed: number?): any
		return TurnResolver.resolveTurn(state, intents, {
			dex = dexWith(BASE_SPECIES),
			rng = RNG.new(seed or 12345),
		})
	end

	local BOTH_ATTACK = {
		[1] = { kind = "Move", slot = 1 },
		[2] = { kind = "Move", slot = 1 },
	}

	it("opens with a TurnBegin event and advances the turn counter", function()
		local outcome = resolve(scenario(), BOTH_ATTACK)
		expect(outcome.events[1].kind).toBe("TurnBegin")
		expect(outcome.state.turn).toBe(2)
	end)

	it("logs a MoveUsed for each side", function()
		local outcome = resolve(scenario(), BOTH_ATTACK)
		expect(#Battle.eventsOfKind(outcome.events, "MoveUsed")).toBe(2)
	end)

	it("deals damage in both directions", function()
		local outcome = resolve(scenario(), BOTH_ATTACK)
		expect(#Battle.eventsOfKind(outcome.events, "DamageDealt")).toBe(2)
		expect(outcome.state.sides[1].party[1].currentHp).toBeLessThan(200)
		expect(outcome.state.sides[2].party[1].currentHp).toBeLessThan(200)
	end)

	it("does not mutate the state it was given", function()
		local before = scenario()
		resolve(before, BOTH_ATTACK)
		expect(before.turn).toBe(1)
		expect(before.sides[1].party[1].currentHp).toBe(200)
		expect(#before.log).toBe(0)
	end)

	it("appends the turn's events to the state log", function()
		local outcome = resolve(scenario(), BOTH_ATTACK)
		expect(#outcome.state.log).toBe(#outcome.events)
	end)

	it("spends PP", function()
		local outcome = resolve(scenario(), BOTH_ATTACK)
		expect(outcome.state.sides[1].party[1].moves[1].pp).toBe(9)
	end)

	it("fails a move with no PP left", function()
		local outcome = resolve(scenario({ ppOne = 0 }), BOTH_ATTACK)
		local failures = Battle.eventsOfKind(outcome.events, "MoveFailed")
		expect(#failures).toBe(1)
		expect(failures[1].reason).toBe("NoPp")
	end)

	it("logs a miss rather than damage when the move cannot hit", function()
		local outcome = resolve(scenario({ movesOne = { "misses" } }), BOTH_ATTACK)
		expect(#Battle.eventsOfKind(outcome.events, "MoveMissed")).toBe(1)
		expect(#Battle.eventsOfKind(outcome.events, "DamageDealt")).toBe(1)
	end)

	it("is reproducible from a seed", function()
		local a = resolve(scenario(), BOTH_ATTACK, 999)
		local b = resolve(scenario(), BOTH_ATTACK, 999)
		expect(a.events).toEqual(b.events)
	end)
end)

--[[ Fainting mid-turn ------------------------------------------------------ ]]

describe("TurnResolver / fainting mid-turn", function()
	--[[
		The fast side one-shots the slow side. The slow side's queued move was legal
		when the queue was built and must not run now — a fainted creature acting is
		the bug this whole ordering-then-revalidating structure exists to prevent.
	]]
	local function knockoutScenario(): any
		local fastSide = Battle.side({
			id = 1,
			party = {
				Battle.creature({ uid = "fast", speciesId = "fast", moveIds = { "strike" } }),
			},
		})
		local frailSide = Battle.side({
			id = 2,
			party = {
				Battle.creature({
					uid = "frail",
					speciesId = "frail",
					moveIds = { "strike" },
					currentHp = 10,
				}),
			},
		})
		return Battle.state({ sides = { fastSide, frailSide } })
	end

	local function resolveKo(): any
		return TurnResolver.resolveTurn(knockoutScenario(), {
			[1] = { kind = "Move", slot = 1 },
			[2] = { kind = "Move", slot = 1 },
		}, { dex = dexWith(BASE_SPECIES), rng = RNG.new(7) })
	end

	it("faints the target", function()
		local outcome = resolveKo()
		local faints = Battle.eventsOfKind(outcome.events, "Fainted")
		expect(#faints).toBe(1)
		expect(faints[1].creatureUid).toBe("frail")
		expect(outcome.state.sides[2].party[1].currentHp).toBe(0)
	end)

	it("cancels the fainted creature's queued action", function()
		local outcome = resolveKo()
		local used = Battle.eventsOfKind(outcome.events, "MoveUsed")
		expect(#used).toBe(1)
		expect(used[1].sideId).toBe(1)
	end)

	it("never lets the fainted creature deal damage", function()
		local outcome = resolveKo()
		for _, event in Battle.eventsOfKind(outcome.events, "DamageDealt") do
			-- Damage is recorded against the side that TOOK it.
			expect(event.sideId).toBe(2)
		end
	end)

	it("clamps HP at zero rather than going negative", function()
		local outcome = resolveKo()
		expect(outcome.state.sides[2].party[1].currentHp).toBe(0)
	end)
end)

--[[ End of turn ------------------------------------------------------------ ]]

describe("TurnResolver / end of turn status damage", function()
	local function poisonedScenario(): any
		local fastSide = Battle.side({
			id = 1,
			party = {
				Battle.creature({
					uid = "fast",
					speciesId = "fast",
					moveIds = { "weak" },
					status = "Poison",
				}),
			},
		})
		local slowSide = Battle.side({
			id = 2,
			party = {
				Battle.creature({
					uid = "slow",
					speciesId = "slow",
					moveIds = { "weak" },
					status = "Poison",
				}),
			},
		})
		return Battle.state({ sides = { fastSide, slowSide } })
	end

	local function resolvePoison(): any
		return TurnResolver.resolveTurn(poisonedScenario(), {
			[1] = { kind = "Move", slot = 1 },
			[2] = { kind = "Move", slot = 1 },
		}, { dex = dexWith(BASE_SPECIES), rng = RNG.new(3) })
	end

	it("chips both poisoned creatures for an eighth of max HP", function()
		local outcome = resolvePoison()
		local chips = Battle.eventsOfKind(outcome.events, "StatusDamage")
		expect(#chips).toBe(2)
		for _, chip in chips do
			expect(chip.amount).toBe(25)
			expect(chip.status).toBe("Poison")
		end
	end)

	it("applies the chip in speed order", function()
		local outcome = resolvePoison()
		local chips = Battle.eventsOfKind(outcome.events, "StatusDamage")
		expect(chips[1].creatureUid).toBe("fast")
		expect(chips[2].creatureUid).toBe("slow")
	end)

	it("applies the chip after every action", function()
		local outcome = resolvePoison()
		local lastMoveIndex, firstChipIndex = 0, math.huge
		for index, event in outcome.events do
			if event.kind == "MoveUsed" then
				lastMoveIndex = index
			elseif event.kind == "StatusDamage" and index < firstChipIndex then
				firstChipIndex = index
			end
		end
		expect(firstChipIndex).toBeGreaterThan(lastMoveIndex)
	end)

	it("does not chip an unstatused creature", function()
		local outcome = TurnResolver.resolveTurn(
			Battle.state({
				sides = {
					Battle.side({
						id = 1,
						party = { Battle.creature({ uid = "a", moveIds = { "weak" } }) },
					}),
					Battle.side({
						id = 2,
						party = { Battle.creature({ uid = "b", moveIds = { "weak" } }) },
					}),
				},
			}),
			{ [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = dexWith(BASE_SPECIES), rng = RNG.new(3) }
		)
		expect(#Battle.eventsOfKind(outcome.events, "StatusDamage")).toBe(0)
	end)
end)

--[[ Status blocking actions ------------------------------------------------ ]]

describe("TurnResolver / acting under status", function()
	local function sleepingScenario(turns: number): any
		return Battle.state({
			sides = {
				Battle.side({
					id = 1,
					party = {
						Battle.creature({
							uid = "sleeper",
							moveIds = { "weak" },
							status = "Sleep",
							statusTurns = turns,
						}),
					},
				}),
				Battle.side({
					id = 2,
					party = { Battle.creature({ uid = "other", moveIds = { "weak" } }) },
				}),
			},
		})
	end

	it("blocks a sleeping creature and says why", function()
		local outcome = TurnResolver.resolveTurn(
			sleepingScenario(2),
			{ [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = dexWith(BASE_SPECIES), rng = RNG.new(5) }
		)
		local failures = Battle.eventsOfKind(outcome.events, "MoveFailed")
		expect(#failures).toBe(1)
		expect(failures[1].reason).toBe("Asleep")
		expect(outcome.state.sides[1].party[1].statusTurns).toBe(1)
	end)

	it("wakes up when the counter runs out and acts that turn", function()
		local outcome = TurnResolver.resolveTurn(
			sleepingScenario(0),
			{ [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = dexWith(BASE_SPECIES), rng = RNG.new(5) }
		)
		expect(#Battle.eventsOfKind(outcome.events, "StatusCured")).toBe(1)
		expect(#Battle.eventsOfKind(outcome.events, "MoveUsed")).toBe(2)
		expect(outcome.state.sides[1].party[1].status).toBeNil()
	end)

	it("does not spend PP on a turn it could not act", function()
		local outcome = TurnResolver.resolveTurn(
			sleepingScenario(2),
			{ [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = dexWith(BASE_SPECIES), rng = RNG.new(5) }
		)
		expect(outcome.state.sides[1].party[1].moves[1].pp).toBe(10)
	end)
end)

--[[ Switching -------------------------------------------------------------- ]]

describe("TurnResolver / switching", function()
	local function twoPartyState(): any
		return Battle.state({
			sides = {
				Battle.side({
					id = 1,
					party = {
						Battle.creature({ uid = "lead", moveIds = { "weak" } }),
						Battle.creature({ uid = "bench", moveIds = { "weak" } }),
					},
				}),
				Battle.side({
					id = 2,
					party = {
						Battle.creature({ uid = "foe", speciesId = "fast", moveIds = { "weak" } }),
					},
				}),
			},
		})
	end

	it("brings the replacement in and logs both halves", function()
		local outcome = TurnResolver.resolveTurn(
			twoPartyState(),
			{ [1] = { kind = "Switch", partyIndex = 2 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = dexWith(BASE_SPECIES), rng = RNG.new(1) }
		)
		expect(#Battle.eventsOfKind(outcome.events, "SwitchOut")).toBe(1)
		expect(#Battle.eventsOfKind(outcome.events, "SwitchIn")).toBe(1)
		expect(outcome.state.sides[1].active.partyIndex).toBe(2)
	end)

	it("clears the outgoing creature's stat stages", function()
		local state = twoPartyState()
		state.sides[1].active.stages.atk = 4
		local outcome = TurnResolver.resolveTurn(
			state,
			{ [1] = { kind = "Switch", partyIndex = 2 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = dexWith(BASE_SPECIES), rng = RNG.new(1) }
		)
		expect(outcome.state.sides[1].active.stages.atk).toBe(0)
	end)

	it("makes the replacement take the incoming hit", function()
		local outcome = TurnResolver.resolveTurn(
			twoPartyState(),
			{ [1] = { kind = "Switch", partyIndex = 2 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = dexWith(BASE_SPECIES), rng = RNG.new(1) }
		)
		expect(outcome.state.sides[1].party[2].currentHp).toBeLessThan(200)
		expect(outcome.state.sides[1].party[1].currentHp).toBe(200)
	end)

	it("rejects a switch to a fainted creature", function()
		local state = twoPartyState()
		state.sides[1].party[2].currentHp = 0
		expect(function()
			TurnResolver.resolveTurn(
				state,
				{ [1] = { kind = "Switch", partyIndex = 2 }, [2] = { kind = "Move", slot = 1 } },
				{ dex = dexWith(BASE_SPECIES), rng = RNG.new(1) }
			)
		end).toThrow("fainted")
	end)

	it("rejects a switch to the creature already out", function()
		expect(function()
			TurnResolver.resolveTurn(
				twoPartyState(),
				{ [1] = { kind = "Switch", partyIndex = 1 }, [2] = { kind = "Move", slot = 1 } },
				{ dex = dexWith(BASE_SPECIES), rng = RNG.new(1) }
			)
		end).toThrow("already active")
	end)
end)

--[[ Multi-hit -------------------------------------------------------------- ]]

describe("TurnResolver / multi-hit moves", function()
	local function multiScenario(defenderSpecies: string?, defenderHp: number?): any
		return Battle.state({
			sides = {
				Battle.side({
					id = 1,
					party = {
						Battle.creature({
							uid = "hitter",
							speciesId = "fast",
							moveIds = { "multi" },
						}),
					},
				}),
				Battle.side({
					id = 2,
					party = {
						Battle.creature({
							uid = "target",
							speciesId = defenderSpecies or "slow",
							moveIds = { "weak" },
							currentHp = defenderHp or 200,
						}),
					},
				}),
			},
		})
	end

	local function hitEvents(seed: number, defenderSpecies: string?, defenderHp: number?): { any }
		local outcome = TurnResolver.resolveTurn(
			multiScenario(defenderSpecies, defenderHp),
			{ [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = dexWith(BASE_SPECIES), rng = RNG.new(seed) }
		)
		local hits = {}
		for _, event in Battle.eventsOfKind(outcome.events, "DamageDealt") do
			if event.sideId == 2 then
				table.insert(hits, event)
			end
		end
		return hits
	end

	it("lands between 2 and 5 hits", function()
		for seed = 1, 80 do
			local count = #hitEvents(seed)
			if count < 2 or count > 5 then
				fail(`seed {seed} produced {count} hits, expected 2 to 5`)
			end
		end
	end)

	it("reaches every hit count from 2 to 5", function()
		local seen: { [number]: boolean } = {}
		for seed = 1, 200 do
			seen[#hitEvents(seed)] = true
		end
		for count = 2, 5 do
			if not seen[count] then
				fail(`{count} hits never came up across 200 seeds`)
			end
		end
	end)

	it("logs one event per hit", function()
		local hits = hitEvents(4)
		expect(#hits).toBeGreaterThanOrEqual(2)
		for _, hit in hits do
			expect(hit.amount).toBeGreaterThan(0)
		end
	end)

	--[[
		Each hit rolls its own damage, so the amounts across a run of hits must not all
		be identical. Reusing one roll for every hit is a plausible-looking bug that
		only shows up as multi-hit moves feeling oddly consistent.

		CRITS ARE EXCLUDED FROM THE COMPARISON ON PURPOSE. They vary per hit whatever
		the damage roll does, so comparing raw amounts passes even when a single roll
		is reused — this test survived exactly that mutation before the filter was
		added. Only non-critical hits are evidence about the roll.
	]]
	it("rolls damage separately for each hit", function()
		local sawVariation = false
		for seed = 1, 200 do
			local baseline: number? = nil
			for _, hit in hitEvents(seed) do
				if not hit.isCritical then
					if baseline == nil then
						baseline = hit.amount
					elseif hit.amount ~= baseline then
						sawVariation = true
						break
					end
				end
			end
			if sawVariation then
				break
			end
		end
		expect(sawVariation).toBe(true)
	end)

	it("accumulates the hits into one HP total", function()
		local outcome = TurnResolver.resolveTurn(
			multiScenario(),
			{ [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = dexWith(BASE_SPECIES), rng = RNG.new(4) }
		)
		local hits = {}
		for _, event in Battle.eventsOfKind(outcome.events, "DamageDealt") do
			if event.sideId == 2 then
				table.insert(hits, event)
			end
		end
		local total = 0
		for _, hit in hits do
			total += hit.amount
		end
		expect(outcome.state.sides[2].party[1].currentHp).toBe(200 - total)
	end)

	--[[
		25 power at these stats deals 11-13 a hit, so 15 HP dies on the second — or on
		the first, when the 1/16 crit lands and doubles it. Either way the move rolled
		2 to 5 hits and must stop the instant HP reaches zero, so the killing blow is
		always the last event logged.
	]]
	it("stops when the target faints partway through", function()
		for seed = 1, 40 do
			local hits = hitEvents(seed, "slow", 15)
			if #hits < 1 or #hits > 2 then
				fail(`seed {seed} logged {#hits} hits against 15 HP; expected 1 or 2`)
			end
			expect(hits[#hits].remainingHp).toBe(0)
			for index = 1, #hits - 1 do
				if hits[index].remainingHp <= 0 then
					fail(`seed {seed} kept hitting after the target reached 0 HP`)
				end
			end
		end
	end)

	--[[ Storm cannot touch Terra, so not one of the hits may land. ]]
	it("cancels every hit against an immunity", function()
		local state = Battle.state({
			sides = {
				Battle.side({
					id = 1,
					party = {
						Battle.creature({
							uid = "hitter",
							speciesId = "fast",
							moveIds = { "storm" },
						}),
					},
				}),
				Battle.side({
					id = 2,
					party = {
						Battle.creature({ uid = "rock", speciesId = "terra", moveIds = { "weak" } }),
					},
				}),
			},
		})
		local outcome = TurnResolver.resolveTurn(
			state,
			{ [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = dexWith(BASE_SPECIES), rng = RNG.new(9) }
		)
		local hits = {}
		for _, event in Battle.eventsOfKind(outcome.events, "DamageDealt") do
			if event.sideId == 2 then
				table.insert(hits, event)
			end
		end
		expect(#hits).toBe(0)
		expect(outcome.state.sides[2].party[1].currentHp).toBe(200)

		local failures = Battle.eventsOfKind(outcome.events, "MoveFailed")
		local sawNoEffect = false
		for _, failure in failures do
			if failure.reason == "NoEffect" then
				sawNoEffect = true
			end
		end
		expect(sawNoEffect).toBe(true)
	end)
end)
