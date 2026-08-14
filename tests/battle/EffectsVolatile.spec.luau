--!strict
--[[
	Group B: the primitives that clear and set conditions — CureStatus,
	ResetStatStages, ApplyVolatile, RemoveVolatile.

	Volatiles are the vocabulary's pressure valve, and the danger with a pressure valve
	is that it becomes a place to store things that never do anything. Three of them
	gate actions and are tested here as behaviour: Recharge, Flinch and Taunt. The rest
	are stored faithfully and have no engine behaviour yet — see VOLATILE_BEHAVIOUR in
	TurnResolver, which names exactly which is which so nobody has to guess.
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

local PHYSICAL = { category = "Physical", accuracy = 1 }

local ALL_MOVES: { [string]: any } = {
	idle = Moves.build("idle", "Martial", "Physical", 10),
	strike = Moves.build("strike", "Martial", "Physical", 90),

	cureSelf = Moves.utility("cureSelf", "Aqua", {
		{ kind = "CureStatus", target = "Self" },
	}, { targeting = "Self" }),
	cureParty = Moves.utility("cureParty", "Aqua", {
		{ kind = "CureStatus", target = "UserParty" },
	}, { targeting = "UserParty" }),
	cureBurnOnly = Moves.utility("cureBurnOnly", "Aqua", {
		{ kind = "CureStatus", target = "Self", statuses = { "Burn" } },
	}, { targeting = "Self" }),

	hazeAll = Moves.utility("hazeAll", "Psyche", {
		{ kind = "ResetStatStages", target = "AllActive" },
	}, { targeting = "AllOthers" }),
	hazePositive = Moves.utility("hazePositive", "Psyche", {
		{ kind = "ResetStatStages", target = "Target", onlyPositive = true },
	}),

	rechargeSelf = Moves.utility("rechargeSelf", "Flame", {
		{ kind = "Damage", power = 90, damageClass = "Physical" },
		{ kind = "ApplyVolatile", volatile = "Recharge", target = "Self" },
	}, PHYSICAL),
	flinchThem = Moves.utility("flinchThem", "Martial", {
		{ kind = "ApplyVolatile", volatile = "Flinch", target = "Target" },
	}, { accuracy = 1 }),
	tauntThem = Moves.utility("tauntThem", "Arcane", {
		{ kind = "ApplyVolatile", volatile = "Taunt", target = "Target", duration = 3 },
	}, { accuracy = 1 }),
	seedThem = Moves.utility("seedThem", "Feral", {
		{ kind = "ApplyVolatile", volatile = "LeechSeed", target = "Target" },
	}, { accuracy = 1 }),
	unseedThem = Moves.utility("unseedThem", "Feral", {
		{ kind = "RemoveVolatile", volatile = "LeechSeed", target = "Target" },
	}, { accuracy = 1 }),
	focusSelf = Moves.utility("focusSelf", "Ki", {
		{ kind = "ApplyVolatile", volatile = "FocusEnergy", target = "Self" },
	}, { targeting = "Self" }),
	boostSelf = Moves.utility("boostSelf", "Ki", {
		{ kind = "StatStage", stat = "atk", delta = 2, target = "Self" },
	}, { targeting = "Self" }),
}

local SPECIES: { [string]: any } = {
	fast = { stats = Battle.statsWith({ spe = 120 }), typing = { "Aqua" } },
	slow = { stats = Battle.statsWith({ spe = 50 }), typing = { "Aqua" } },
}

local function context(seed: number?): any
	return {
		dex = Battle.dex({ species = SPECIES, moves = ALL_MOVES }),
		rng = RNG.new(seed or 1),
	}
end

local function scene(options: { [string]: any }?): any
	local o: any = options or {}
	return Battle.state({
		sides = {
			Battle.side({
				id = 1,
				party = {
					Battle.creature({
						uid = "actor",
						speciesId = "fast",
						moveIds = o.actorMoves or { "idle" },
						status = o.actorStatus,
						statusTurns = o.actorStatusTurns,
					}),
					Battle.creature({
						uid = "bench",
						speciesId = "slow",
						moveIds = { "idle" },
						status = o.benchStatus,
						statusTurns = o.benchStatusTurns,
					}),
				},
				stages = o.actorStages,
			}),
			Battle.side({
				id = 2,
				party = {
					Battle.creature({
						uid = "target",
						speciesId = "slow",
						moveIds = o.targetMoves or { "idle" },
						status = o.targetStatus,
					}),
				},
				stages = o.targetStages,
			}),
		},
	})
end

local ACTOR_ONLY = { [1] = { kind = "Move", slot = 1 } }
local BOTH = { [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } }

local function stagesWith(overrides: { [string]: number }): any
	local result: { [string]: number } =
		{ atk = 0, def = 0, spa = 0, spd = 0, spe = 0, accuracy = 0, evasion = 0 }
	for key, value in overrides do
		result[key] = value
	end
	return result
end

--[[ CureStatus ------------------------------------------------------------- ]]

describe("Effects / CureStatus", function()
	it("clears the user's own status", function()
		local outcome = TurnResolver.resolveTurn(
			scene({ actorMoves = { "cureSelf" }, actorStatus = "Burn" }),
			ACTOR_ONLY,
			context()
		)
		expect(outcome.state.sides[1].party[1].status).toBeNil()
		expect(#Battle.eventsOfKind(outcome.events, "StatusCured")).toBe(1)
	end)

	--[[
		Cured from the bench, not by the sleeper itself: a creature that is asleep cannot
		use a move at all, so self-curing sleep is impossible by construction. Leaving the
		counter behind would leave a woken creature with a phantom timer that the next
		sleep would inherit.
	]]
	it("clears the sleep counter along with the sleep", function()
		local outcome = TurnResolver.resolveTurn(
			scene({ actorMoves = { "cureParty" }, benchStatus = "Sleep", benchStatusTurns = 3 }),
			ACTOR_ONLY,
			context()
		)
		expect(outcome.state.sides[1].party[2].status).toBeNil()
		expect(outcome.state.sides[1].party[2].statusTurns).toBeNil()
	end)

	--[[
		The cleric move. Reaching the bench is the entire reason CureStatus takes a
		target rather than always meaning "the active creature" — a heal bell that only
		cured the thing already in front of you would not be worth a turn.
	]]
	it("reaches the whole party, not just the active creature", function()
		local outcome = TurnResolver.resolveTurn(
			scene({ actorMoves = { "cureParty" }, actorStatus = "Burn", benchStatus = "Poison" }),
			ACTOR_ONLY,
			context()
		)
		expect(outcome.state.sides[1].party[1].status).toBeNil()
		expect(outcome.state.sides[1].party[2].status).toBeNil()
		expect(#Battle.eventsOfKind(outcome.events, "StatusCured")).toBe(2)
	end)

	it("cures only the listed statuses when a list is given", function()
		local outcome = TurnResolver.resolveTurn(
			scene({ actorMoves = { "cureBurnOnly" }, actorStatus = "Poison" }),
			ACTOR_ONLY,
			context()
		)
		expect(outcome.state.sides[1].party[1].status).toBe("Poison")
		expect(#Battle.eventsOfKind(outcome.events, "StatusCured")).toBe(0)
	end)

	it("logs nothing when there was nothing to cure", function()
		local outcome =
			TurnResolver.resolveTurn(scene({ actorMoves = { "cureSelf" } }), ACTOR_ONLY, context())
		expect(#Battle.eventsOfKind(outcome.events, "StatusCured")).toBe(0)
	end)
end)

--[[ ResetStatStages -------------------------------------------------------- ]]

describe("Effects / ResetStatStages", function()
	it("clears every stage on both actives", function()
		local outcome = TurnResolver.resolveTurn(
			scene({
				actorMoves = { "hazeAll" },
				actorStages = stagesWith({ atk = 3 }),
				targetStages = stagesWith({ def = -2, spe = 4 }),
			}),
			ACTOR_ONLY,
			context()
		)
		expect(outcome.state.sides[1].active.stages.atk).toBe(0)
		expect(outcome.state.sides[2].active.stages.def).toBe(0)
		expect(outcome.state.sides[2].active.stages.spe).toBe(0)
	end)

	it("logs one change per stage that actually moved", function()
		local outcome = TurnResolver.resolveTurn(
			scene({ actorMoves = { "hazeAll" }, targetStages = stagesWith({ def = -2, spe = 4 }) }),
			ACTOR_ONLY,
			context()
		)
		expect(#Battle.eventsOfKind(outcome.events, "StatStageChanged")).toBe(2)
	end)

	--[[
		Clearing only the opponent's boosts is a different move from clearing
		everything: it removes their setup without also removing the drops you spent
		turns landing on them.
	]]
	it("clears only the positive stages when asked", function()
		local outcome = TurnResolver.resolveTurn(
			scene({
				actorMoves = { "hazePositive" },
				targetStages = stagesWith({ atk = 3, def = -2 }),
			}),
			ACTOR_ONLY,
			context()
		)
		expect(outcome.state.sides[2].active.stages.atk).toBe(0)
		expect(outcome.state.sides[2].active.stages.def).toBe(-2)
	end)

	it("logs nothing when every stage was already zero", function()
		local outcome =
			TurnResolver.resolveTurn(scene({ actorMoves = { "hazeAll" } }), ACTOR_ONLY, context())
		expect(#Battle.eventsOfKind(outcome.events, "StatStageChanged")).toBe(0)
	end)
end)

--[[ ApplyVolatile / RemoveVolatile ----------------------------------------- ]]

describe("Effects / ApplyVolatile", function()
	it("stores the volatile on the target's active state", function()
		local outcome =
			TurnResolver.resolveTurn(scene({ actorMoves = { "seedThem" } }), ACTOR_ONLY, context())
		expect(outcome.state.sides[2].active.volatiles.LeechSeed).never.toBeNil()
		expect(#Battle.eventsOfKind(outcome.events, "VolatileApplied")).toBe(1)
	end)

	it("stores a duration when the effect states one", function()
		local outcome =
			TurnResolver.resolveTurn(scene({ actorMoves = { "tauntThem" } }), ACTOR_ONLY, context())
		-- Stated as 3; the end-of-turn tick has already taken one, so a duration counts
		-- the turn it landed on.
		expect(outcome.state.sides[2].active.volatiles.Taunt.turnsRemaining).toBe(2)
	end)

	it("does not stack a volatile that is already there", function()
		local state = scene({ actorMoves = { "seedThem" } })
		state.sides[2].active.volatiles.LeechSeed = { turnsRemaining = nil }
		local outcome = TurnResolver.resolveTurn(state, ACTOR_ONLY, context())
		expect(#Battle.eventsOfKind(outcome.events, "VolatileApplied")).toBe(0)
	end)

	it("clears volatiles on switch out", function()
		local state = scene({ actorMoves = { "idle" } })
		state.sides[1].active.volatiles.FocusEnergy = { turnsRemaining = nil }
		local outcome = TurnResolver.resolveTurn(
			state,
			{ [1] = { kind = "Switch", partyIndex = 2 } },
			context()
		)
		expect(next(outcome.state.sides[1].active.volatiles)).toBeNil()
	end)
end)

describe("Effects / RemoveVolatile", function()
	it("removes a volatile that is present and logs it", function()
		local state = scene({ actorMoves = { "unseedThem" } })
		state.sides[2].active.volatiles.LeechSeed = { turnsRemaining = nil }
		local outcome = TurnResolver.resolveTurn(state, ACTOR_ONLY, context())
		expect(outcome.state.sides[2].active.volatiles.LeechSeed).toBeNil()
		expect(#Battle.eventsOfKind(outcome.events, "VolatileRemoved")).toBe(1)
	end)

	it("logs nothing when the volatile was not there", function()
		local outcome = TurnResolver.resolveTurn(
			scene({ actorMoves = { "unseedThem" } }),
			ACTOR_ONLY,
			context()
		)
		expect(#Battle.eventsOfKind(outcome.events, "VolatileRemoved")).toBe(0)
	end)
end)

--[[ The three volatiles that gate actions --------------------------------- ]]

describe("Effects / Recharge", function()
	--[[
		The nuke's price. Without this, cinderlash is 130 power for free and the tier
		table in CLAUDE.md is a lie.
	]]
	it("blocks the user's next action", function()
		local state = scene({ actorMoves = { "rechargeSelf" }, targetMoves = { "idle" } })
		local first = TurnResolver.resolveTurn(state, ACTOR_ONLY, context())
		expect(first.state.sides[1].active.volatiles.Recharge).never.toBeNil()

		local second = TurnResolver.resolveTurn(first.state, ACTOR_ONLY, context(2))
		local failures = Battle.eventsOfKind(second.events, "MoveFailed")
		expect(#failures).toBe(1)
		expect(#Battle.eventsOfKind(second.events, "MoveUsed")).toBe(0)
	end)

	it("clears itself after costing the turn, so it only bites once", function()
		local state = scene({ actorMoves = { "rechargeSelf" } })
		local first = TurnResolver.resolveTurn(state, ACTOR_ONLY, context())
		local second = TurnResolver.resolveTurn(first.state, ACTOR_ONLY, context(2))
		expect(second.state.sides[1].active.volatiles.Recharge).toBeNil()

		local third = TurnResolver.resolveTurn(second.state, ACTOR_ONLY, context(3))
		expect(#Battle.eventsOfKind(third.events, "MoveUsed")).toBe(1)
	end)

	it("does not spend PP on the recharge turn", function()
		local state = scene({ actorMoves = { "rechargeSelf" } })
		local first = TurnResolver.resolveTurn(state, ACTOR_ONLY, context())
		local ppAfterUse = first.state.sides[1].party[1].moves[1].pp
		local second = TurnResolver.resolveTurn(first.state, ACTOR_ONLY, context(2))
		expect(second.state.sides[1].party[1].moves[1].pp).toBe(ppAfterUse)
	end)
end)

describe("Effects / Flinch", function()
	--[[
		The flincher is slower here, so the flinch lands after the target has already
		moved and must NOT retroactively cancel it — a flinch only takes a turn the
		target has not spent yet.
	]]
	it("blocks an action that has not happened yet", function()
		local state = Battle.state({
			sides = {
				Battle.side({
					id = 1,
					party = {
						Battle.creature({
							uid = "quick",
							speciesId = "fast",
							moveIds = { "flinchThem" },
						}),
					},
				}),
				Battle.side({
					id = 2,
					party = {
						Battle.creature({
							uid = "slowpoke",
							speciesId = "slow",
							moveIds = { "strike" },
						}),
					},
				}),
			},
		})
		local outcome = TurnResolver.resolveTurn(state, BOTH, context())
		local failures = Battle.eventsOfKind(outcome.events, "MoveFailed")
		local sawFlinch = false
		for _, failure in failures do
			if failure.sideId == 2 then
				sawFlinch = true
			end
		end
		expect(sawFlinch).toBe(true)
	end)

	it("clears at the end of the turn rather than lingering", function()
		local state = Battle.state({
			sides = {
				Battle.side({
					id = 1,
					party = {
						Battle.creature({
							uid = "quick",
							speciesId = "fast",
							moveIds = { "flinchThem" },
						}),
					},
				}),
				Battle.side({
					id = 2,
					party = {
						Battle.creature({
							uid = "slowpoke",
							speciesId = "slow",
							moveIds = { "strike" },
						}),
					},
				}),
			},
		})
		local outcome = TurnResolver.resolveTurn(state, BOTH, context())
		expect(outcome.state.sides[2].active.volatiles.Flinch).toBeNil()
	end)
end)

describe("Effects / Taunt", function()
	it("blocks a Status move but not a damaging one", function()
		local state = scene({ actorMoves = { "tauntThem" }, targetMoves = { "boostSelf" } })
		local first = TurnResolver.resolveTurn(state, ACTOR_ONLY, context())
		expect(first.state.sides[2].active.volatiles.Taunt).never.toBeNil()

		local second =
			TurnResolver.resolveTurn(first.state, { [2] = { kind = "Move", slot = 1 } }, context(2))
		local failures = Battle.eventsOfKind(second.events, "MoveFailed")
		expect(#failures).toBe(1)
		expect(failures[1].reason).toBe("Taunted")
	end)

	it("counts down and expires", function()
		local state = scene({ actorMoves = { "tauntThem" }, targetMoves = { "boostSelf" } })
		local current = TurnResolver.resolveTurn(state, ACTOR_ONLY, context()).state
		-- One tick already happened at the end of the turn it landed on, so a stated
		-- duration of 3 means three turns INCLUDING that one.
		expect(current.sides[2].active.volatiles.Taunt.turnsRemaining).toBe(2)

		for turn = 1, 2 do
			current = TurnResolver.resolveTurn(current, {}, context(turn + 10)).state
		end
		expect(current.sides[2].active.volatiles.Taunt).toBeNil()
	end)
end)
