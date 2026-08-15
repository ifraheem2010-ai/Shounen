--!strict
--[[
	Group D: the primitives that move creatures in and out — ForceSwitch, SelfSwitch,
	Trap.

	All three exist to take the switch decision away from someone. Phazing takes it from
	the opponent, pivoting takes it from the attacker's own next turn, and trapping
	removes it entirely. Getting the interactions between them wrong is how a player
	ends up unable to act at all, so the cases where they collide are tested explicitly.
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

local ALL_MOVES: { [string]: any } = {
	idle = Moves.build("idle", "Martial", "Physical", 10),
	phaze = Moves.utility("phaze", "Spirit", {
		{ kind = "ForceSwitch", target = "Target" },
	}, { accuracy = 1 }),
	pivot = Moves.utility("pivot", "Aqua", {
		{ kind = "Damage", power = 60, damageClass = "Physical" },
		{ kind = "SelfSwitch" },
	}, { category = "Physical", accuracy = 1 }),
	pivotPassing = Moves.utility("pivotPassing", "Aqua", {
		{ kind = "SelfSwitch", passBoosts = true },
	}, { targeting = "Self" }),
	trap = Moves.utility("trap", "Spirit", {
		{ kind = "Trap", target = "Target" },
	}, { accuracy = 1 }),
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

local function stagesWith(overrides: { [string]: number }): any
	local result: { [string]: number } =
		{ atk = 0, def = 0, spa = 0, spd = 0, spe = 0, accuracy = 0, evasion = 0 }
	for key, value in overrides do
		result[key] = value
	end
	return result
end

--[[
	Side 1 is fast and leads a party of three; side 2 is slow with a party of three, so
	either side has somewhere to go.
]]
local function scene(options: { [string]: any }?): any
	local o: any = options or {}
	return Battle.state({
		sides = {
			Battle.side({
				id = 1,
				party = {
					Battle.creature({
						uid = "a1",
						speciesId = "fast",
						moveIds = o.oneMoves or { "idle" },
					}),
					Battle.creature({
						uid = "a2",
						speciesId = "slow",
						moveIds = { "idle" },
						currentHp = o.a2Hp or 200,
					}),
					Battle.creature({
						uid = "a3",
						speciesId = "slow",
						moveIds = { "idle" },
						currentHp = o.a3Hp or 200,
					}),
				},
				stages = o.oneStages,
			}),
			Battle.side({
				id = 2,
				party = {
					Battle.creature({
						uid = "b1",
						speciesId = "slow",
						moveIds = o.twoMoves or { "idle" },
					}),
					Battle.creature({
						uid = "b2",
						speciesId = "slow",
						moveIds = { "idle" },
						currentHp = o.b2Hp or 200,
					}),
					Battle.creature({
						uid = "b3",
						speciesId = "slow",
						moveIds = { "idle" },
						currentHp = o.b3Hp or 200,
					}),
				},
			}),
		},
	})
end

local ONE = { [1] = { kind = "Move", slot = 1 } }

local function resolve(state: any, intents: any, seed: number?): any
	return TurnResolver.resolveTurn(state, intents, context(seed))
end

--[[ ForceSwitch ----------------------------------------------------------- ]]

describe("Effects / ForceSwitch", function()
	it("drags in a different member of the target's party", function()
		local outcome = resolve(scene({ oneMoves = { "phaze" } }), ONE)
		expect(outcome.state.sides[2].active.partyIndex).never.toBe(1)
		expect(#Battle.eventsOfKind(outcome.events, "SwitchIn")).toBe(1)
		expect(#Battle.eventsOfKind(outcome.events, "SwitchOut")).toBe(1)
	end)

	it("never drags in a fainted one", function()
		for seed = 1, 30 do
			local outcome = resolve(scene({ oneMoves = { "phaze" }, b3Hp = 0 }), ONE, seed)
			expect(outcome.state.sides[2].active.partyIndex).toBe(2)
		end
	end)

	it("does nothing when the target has nowhere to go", function()
		local outcome = resolve(scene({ oneMoves = { "phaze" }, b2Hp = 0, b3Hp = 0 }), ONE)
		expect(outcome.state.sides[2].active.partyIndex).toBe(1)
		expect(#Battle.eventsOfKind(outcome.events, "SwitchIn")).toBe(0)
	end)

	it("clears the dragged-out creature's stat stages", function()
		local state = scene({ oneMoves = { "phaze" } })
		state.sides[2].active.stages = stagesWith({ atk = 4 })
		local outcome = resolve(state, ONE)
		expect(outcome.state.sides[2].active.stages.atk).toBe(0)
	end)

	--[[
		The reason phazing and hazards are a pair: a forced entry pays the same toll a
		voluntary one does, which is what makes laying hazards and then phazing a plan
		rather than two unrelated moves.
	]]
	it("makes the dragged-in creature pay the hazard toll", function()
		local state = scene({ oneMoves = { "phaze" } })
		state.sides[2].hazards.Caltrops = 1
		local outcome = resolve(state, ONE)
		expect(#Battle.eventsOfKind(outcome.events, "HazardDamage")).toBe(1)
	end)

	it("picks reproducibly from a seed", function()
		local first =
			resolve(scene({ oneMoves = { "phaze" } }), ONE, 4242).state.sides[2].active.partyIndex
		for _ = 1, 10 do
			expect(
				resolve(scene({ oneMoves = { "phaze" } }), ONE, 4242).state.sides[2].active.partyIndex
			).toBe(first)
		end
	end)

	it("reaches both replacements across seeds", function()
		local seen: { [number]: boolean } = {}
		for seed = 1, 60 do
			seen[resolve(scene({ oneMoves = { "phaze" } }), ONE, seed).state.sides[2].active.partyIndex] =
				true
		end
		expect(seen[2]).toBe(true)
		expect(seen[3]).toBe(true)
	end)
end)

--[[ SelfSwitch ------------------------------------------------------------ ]]

describe("Effects / SelfSwitch", function()
	it("withdraws the user and brings in a replacement", function()
		local outcome = resolve(scene({ oneMoves = { "pivot" } }), ONE)
		expect(outcome.state.sides[1].active.partyIndex).never.toBe(1)
		expect(#Battle.eventsOfKind(outcome.events, "SwitchIn")).toBe(1)
	end)

	it("still lands its damage before leaving", function()
		local outcome = resolve(scene({ oneMoves = { "pivot" } }), ONE)
		expect(outcome.state.sides[2].party[1].currentHp).toBeLessThan(200)
		local damageIndex, switchIndex = 0, 0
		for index, event in outcome.events do
			if event.kind == "DamageDealt" then
				damageIndex = index
			elseif event.kind == "SwitchIn" then
				switchIndex = index
			end
		end
		expect(damageIndex).toBeLessThan(switchIndex)
	end)

	it("drops the user's stat stages by default", function()
		local state = scene({ oneMoves = { "pivot" }, oneStages = stagesWith({ atk = 3 }) })
		local outcome = resolve(state, ONE)
		expect(outcome.state.sides[1].active.stages.atk).toBe(0)
	end)

	it("carries the stat stages across when the effect says to", function()
		local state = scene({ oneMoves = { "pivotPassing" }, oneStages = stagesWith({ atk = 3 }) })
		local outcome = resolve(state, ONE)
		expect(outcome.state.sides[1].active.partyIndex).never.toBe(1)
		expect(outcome.state.sides[1].active.stages.atk).toBe(3)
	end)

	--[[
		A chooser is the outside world, and the outside world sends party index 99. This
		is TurnResolver's own check — Engine validates separately for the faint path, and
		neither should be relying on the other.
	]]
	it("rejects a replacement the chooser had no right to name", function()
		local state = scene({ oneMoves = { "pivot" } })
		expect(function()
			TurnResolver.resolveTurn(state, ONE, {
				dex = Battle.dex({ species = SPECIES, moves = ALL_MOVES }),
				rng = RNG.new(1),
				chooseReplacement = function(): number
					return 99
				end,
			})
		end).toThrow("not one of the legal replacements")
	end)

	it("uses the chooser's answer when it is legal", function()
		local outcome = TurnResolver.resolveTurn(scene({ oneMoves = { "pivot" } }), ONE, {
			dex = Battle.dex({ species = SPECIES, moves = ALL_MOVES }),
			rng = RNG.new(1),
			chooseReplacement = function(): number
				return 3
			end,
		})
		expect(outcome.state.sides[1].active.partyIndex).toBe(3)
	end)

	it("does nothing when there is nobody to switch to", function()
		local outcome = resolve(scene({ oneMoves = { "pivot" }, a2Hp = 0, a3Hp = 0 }), ONE)
		expect(outcome.state.sides[1].active.partyIndex).toBe(1)
	end)

	it("makes the replacement pay the hazard toll", function()
		local state = scene({ oneMoves = { "pivot" } })
		state.sides[1].hazards.Caltrops = 1
		local outcome = resolve(state, ONE)
		expect(#Battle.eventsOfKind(outcome.events, "HazardDamage")).toBe(1)
	end)
end)

--[[ Trap ------------------------------------------------------------------ ]]

describe("Effects / Trap", function()
	it("marks the target as trapped by the user's side", function()
		local outcome = resolve(scene({ oneMoves = { "trap" } }), ONE)
		expect(outcome.state.sides[2].active.trappedBySideId).toBe(1)
	end)

	it("stops the trapped side switching out", function()
		local state = scene({ oneMoves = { "trap" } })
		local trapped = resolve(state, ONE).state
		expect(function()
			resolve(trapped, { [2] = { kind = "Switch", partyIndex = 2 } })
		end).toThrow("trapped")
	end)

	--[[
		Phazing beats trapping. A trap that also blocked being dragged out would leave
		the trapped side with no way off the field at all, which is a lock rather than a
		matchup.
	]]
	it("does not stop the trapped creature being dragged out", function()
		local state = scene({ oneMoves = { "phaze" } })
		state.sides[2].active.trappedBySideId = 1
		local outcome = resolve(state, ONE)
		expect(outcome.state.sides[2].active.partyIndex).never.toBe(1)
	end)

	it("releases when the trapper leaves the field", function()
		local state = scene()
		state.sides[2].active.trappedBySideId = 1
		local outcome = resolve(state, { [1] = { kind = "Switch", partyIndex = 2 } })
		expect(outcome.state.sides[2].active.trappedBySideId).toBeNil()
	end)

	it("clears when the trapped creature itself leaves", function()
		local state = scene({ oneMoves = { "phaze" } })
		state.sides[2].active.trappedBySideId = 1
		local outcome = resolve(state, ONE)
		expect(outcome.state.sides[2].active.trappedBySideId).toBeNil()
	end)
end)
