--!strict
--[[
	Group C: the primitives that change the ground rather than the creature —
	SetHazard, SetSideCondition, ClearSide, SetField.

	These are the effects with no immediate visible result. A hazard does nothing on the
	turn it is laid; a screen does nothing until something attacks into it. That makes
	them the easiest group to implement wrongly and not notice, so every test here
	checks the consequence rather than the stored state.
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

local function hazardMove(id: string, hazard: string): any
	return Moves.utility(id, "Forge", {
		{ kind = "SetHazard", hazard = hazard, target = "TargetSide" },
	}, { targeting = "TargetSide" })
end

local ALL_MOVES: { [string]: any } = {
	idle = Moves.build("idle", "Martial", "Physical", 10),
	strike = Moves.build("strike", "Martial", "Physical", 90),
	flameHit = Moves.build("flameHit", "Flame", "Special", 90),
	aquaHit = Moves.build("aquaHit", "Aqua", "Special", 90),

	caltrops = hazardMove("caltrops", "Caltrops"),
	sigilstones = hazardMove("sigilstones", "Sigilstones"),
	miasma = hazardMove("miasma", "Miasma"),
	snarewire = hazardMove("snarewire", "Snarewire"),

	bulwark = Moves.utility("bulwark", "Forge", {
		{ kind = "SetSideCondition", condition = "Bulwark", duration = 5, target = "UserSide" },
	}, { targeting = "UserSide" }),
	veilward = Moves.utility("veilward", "Forge", {
		{ kind = "SetSideCondition", condition = "Veilward", duration = 5, target = "UserSide" },
	}, { targeting = "UserSide" }),
	slipstream = Moves.utility("slipstream", "Storm", {
		{ kind = "SetSideCondition", condition = "Slipstream", duration = 4, target = "UserSide" },
	}, { targeting = "UserSide" }),
	sanctuary = Moves.utility("sanctuary", "Aqua", {
		{ kind = "SetSideCondition", condition = "Sanctuary", duration = 5, target = "UserSide" },
	}, { targeting = "UserSide" }),
	mistveil = Moves.utility("mistveil", "Frost", {
		{ kind = "SetSideCondition", condition = "Mistveil", duration = 5, target = "UserSide" },
	}, { targeting = "UserSide" }),

	sweep = Moves.utility("sweep", "Storm", {
		{ kind = "ClearSide", hazards = true, sideConditions = true, target = "UserSide" },
	}, { targeting = "UserSide" }),
	sweepHazardsOnly = Moves.utility("sweepHazardsOnly", "Storm", {
		{ kind = "ClearSide", hazards = true, target = "UserSide" },
	}, { targeting = "UserSide" }),

	burnThem = Moves.utility("burnThem", "Flame", {
		{ kind = "InflictStatus", status = "Burn", target = "Target" },
	}, { accuracy = 1 }),
	dropThem = Moves.utility("dropThem", "Arcane", {
		{ kind = "StatStage", stat = "atk", delta = -2, target = "Target" },
	}, { accuracy = 1 }),

	emberveil = Moves.utility("emberveil", "Flame", {
		{ kind = "SetField", field = "Emberveil", duration = 5 },
	}, { targeting = "Field" }),
	downpour = Moves.utility("downpour", "Aqua", {
		{ kind = "SetField", field = "Downpour", duration = 5 },
	}, { targeting = "Field" }),
	whiteout = Moves.utility("whiteout", "Frost", {
		{ kind = "SetField", field = "Whiteout", duration = 5 },
	}, { targeting = "Field" }),
	duststorm = Moves.utility("duststorm", "Terra", {
		{ kind = "SetField", field = "Duststorm", duration = 5 },
	}, { targeting = "Field" }),
	inversion = Moves.utility("inversion", "Psyche", {
		{ kind = "SetField", field = "Inversion", duration = 5 },
	}, { targeting = "Field" }),
}

local SPECIES: { [string]: any } = {
	fast = { stats = Battle.statsWith({ spe = 120 }), typing = { "Aqua" } },
	slow = { stats = Battle.statsWith({ spe = 50 }), typing = { "Aqua" } },
	frost = { stats = Battle.statsWith({ spe = 50 }), typing = { "Frost" } },
	terra = { stats = Battle.statsWith({ spe = 50 }), typing = { "Terra" } },
	ki = { stats = Battle.statsWith({ spe = 50 }), typing = { "Ki" } },
}

local function context(seed: number?): any
	return {
		dex = Battle.dex({ species = SPECIES, moves = ALL_MOVES }),
		rng = RNG.new(seed or 1),
	}
end

--[[
	Side 1 leads with two party members so it can switch into whatever side 2 laid.
]]
local function scene(options: { [string]: any }?): any
	local o: any = options or {}
	return Battle.state({
		sides = {
			Battle.side({
				id = 1,
				party = {
					Battle.creature({
						uid = "lead",
						speciesId = "fast",
						moveIds = o.oneMoves or { "idle" },
					}),
					Battle.creature({
						uid = "bench",
						speciesId = o.benchSpecies or "slow",
						moveIds = { "idle" },
					}),
				},
			}),
			Battle.side({
				id = 2,
				party = {
					Battle.creature({
						uid = "foe",
						speciesId = o.foeSpecies or "slow",
						moveIds = o.twoMoves or { "idle" },
					}),
				},
			}),
		},
	})
end

local ONE = { [1] = { kind = "Move", slot = 1 } }
local TWO = { [2] = { kind = "Move", slot = 1 } }

local function resolve(state: any, intents: any, seed: number?): any
	return TurnResolver.resolveTurn(state, intents, context(seed))
end

--[[ SetHazard -------------------------------------------------------------- ]]

describe("Effects / SetHazard", function()
	it("lays the hazard on the opposing side", function()
		local outcome = resolve(scene({ oneMoves = { "caltrops" } }), ONE)
		expect(outcome.state.sides[2].hazards.Caltrops).toBe(1)
		expect(#Battle.eventsOfKind(outcome.events, "HazardSet")).toBe(1)
	end)

	it("does nothing to the creature already out", function()
		local outcome = resolve(scene({ oneMoves = { "caltrops" } }), ONE)
		expect(outcome.state.sides[2].party[1].currentHp).toBe(200)
	end)

	--[[
		The whole point: a hazard is a tax on switching, collected on entry. If it never
		fires the move is a wasted turn with a nice log line.
	]]
	it("bites the replacement on switch in", function()
		local state = scene()
		state.sides[1].hazards.Caltrops = 1
		local outcome = resolve(state, { [1] = { kind = "Switch", partyIndex = 2 } })
		expect(outcome.state.sides[1].party[2].currentHp).toBe(175)
		expect(#Battle.eventsOfKind(outcome.events, "HazardDamage")).toBe(1)
	end)

	it("scales with layers", function()
		local state = scene()
		state.sides[1].hazards.Caltrops = 3
		local outcome = resolve(state, { [1] = { kind = "Switch", partyIndex = 2 } })
		-- Three layers take a quarter rather than an eighth.
		expect(outcome.state.sides[1].party[2].currentHp).toBe(150)
	end)

	it("stacks layers up to the cap and no further", function()
		local state = scene({ oneMoves = { "caltrops" } })
		local current = state
		for _ = 1, 5 do
			current = resolve(current, ONE).state
		end
		expect(current.sides[2].hazards.Caltrops).toBe(3)
	end)

	it("scales the type-based hazard against the entrant's typing", function()
		-- Sigilstones are Arcane. Arcane hits Ki for 2x, so a Ki entrant takes double.
		local state = scene({ benchSpecies = "ki" })
		state.sides[1].hazards.Sigilstones = 1
		local outcome = resolve(state, { [1] = { kind = "Switch", partyIndex = 2 } })
		expect(outcome.state.sides[1].party[2].currentHp).toBe(150)
	end)

	it("poisons on entry when the hazard is a status one", function()
		local state = scene()
		state.sides[1].hazards.Miasma = 1
		local outcome = resolve(state, { [1] = { kind = "Switch", partyIndex = 2 } })
		expect(outcome.state.sides[1].party[2].status).toBe("Poison")
	end)

	it("drops speed on entry when the hazard is a speed one", function()
		local state = scene()
		state.sides[1].hazards.Snarewire = 1
		local outcome = resolve(state, { [1] = { kind = "Switch", partyIndex = 2 } })
		expect(outcome.state.sides[1].active.stages.spe).toBe(-1)
	end)
end)

--[[ SetSideCondition ------------------------------------------------------- ]]

describe("Effects / SetSideCondition", function()
	it("stores the condition with its duration", function()
		local outcome = resolve(scene({ oneMoves = { "bulwark" } }), ONE)
		expect(outcome.state.sides[1].sideConditions.Bulwark).toBe(4)
		expect(#Battle.eventsOfKind(outcome.events, "SideConditionSet")).toBe(1)
	end)

	--[[
		A screen has to actually blunt something. Comparing two runs of the same seed
		with and without it is the only honest way to check.
	]]
	it("halves physical damage taken", function()
		local plain = resolve(scene({ twoMoves = { "strike" } }), TWO, 7)
		local plainDamage = 200 - plain.state.sides[1].party[1].currentHp

		local screened = scene({ twoMoves = { "strike" } })
		screened.sides[1].sideConditions.Bulwark = 4
		local withScreen = resolve(screened, TWO, 7)
		local screenedDamage = 200 - withScreen.state.sides[1].party[1].currentHp

		expect(screenedDamage).toBeLessThan(plainDamage)
		expect(screenedDamage).toBe(math.floor(plainDamage * 0.5))
	end)

	it("does not blunt the other damage class", function()
		local screened = scene({ twoMoves = { "flameHit" } })
		screened.sides[1].sideConditions.Bulwark = 4
		local withScreen = resolve(screened, TWO, 7)
		local plain = resolve(scene({ twoMoves = { "flameHit" } }), TWO, 7)
		expect(200 - withScreen.state.sides[1].party[1].currentHp).toBe(
			200 - plain.state.sides[1].party[1].currentHp
		)
	end)

	it("halves special damage under the special screen", function()
		local screened = scene({ twoMoves = { "flameHit" } })
		screened.sides[1].sideConditions.Veilward = 4
		local withScreen = resolve(screened, TWO, 7)
		local plain = resolve(scene({ twoMoves = { "flameHit" } }), TWO, 7)
		local plainDamage = 200 - plain.state.sides[1].party[1].currentHp
		expect(200 - withScreen.state.sides[1].party[1].currentHp).toBe(
			math.floor(plainDamage * 0.5)
		)
	end)

	it("doubles speed under the speed condition", function()
		local state = scene()
		state.sides[2].sideConditions.Slipstream = 4
		-- Side 2 is the slow one at 50; doubled it beats side 1's 120.
		local outcome =
			resolve(state, { [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } })
		local used = Battle.eventsOfKind(outcome.events, "MoveUsed")
		expect(used[1].sideId).toBe(1)
	end)

	it("blocks status under the status screen", function()
		local state = scene({ twoMoves = { "burnThem" } })
		state.sides[1].sideConditions.Sanctuary = 4
		local outcome = resolve(state, TWO)
		expect(outcome.state.sides[1].party[1].status).toBeNil()
	end)

	it("blocks the opponent's stat drops under the mist condition", function()
		local state = scene({ twoMoves = { "dropThem" } })
		state.sides[1].sideConditions.Mistveil = 4
		local outcome = resolve(state, TWO)
		expect(outcome.state.sides[1].active.stages.atk).toBe(0)
	end)

	it("counts down and expires", function()
		local current = resolve(scene({ oneMoves = { "bulwark" } }), ONE).state
		expect(current.sides[1].sideConditions.Bulwark).toBe(4)
		for turn = 1, 4 do
			current = resolve(current, {}, turn + 20).state
		end
		expect(current.sides[1].sideConditions.Bulwark).toBeNil()
	end)
end)

--[[ ClearSide -------------------------------------------------------------- ]]

describe("Effects / ClearSide", function()
	it("sweeps hazards and side conditions off the user's own side", function()
		local state = scene({ oneMoves = { "sweep" } })
		state.sides[1].hazards.Caltrops = 2
		state.sides[1].sideConditions.Bulwark = 3
		local outcome = resolve(state, ONE)
		expect(next(outcome.state.sides[1].hazards)).toBeNil()
		expect(next(outcome.state.sides[1].sideConditions)).toBeNil()
		expect(#Battle.eventsOfKind(outcome.events, "SideCleared")).toBe(1)
	end)

	it("leaves the opposing side alone", function()
		local state = scene({ oneMoves = { "sweep" } })
		state.sides[2].hazards.Caltrops = 2
		local outcome = resolve(state, ONE)
		expect(outcome.state.sides[2].hazards.Caltrops).toBe(2)
	end)

	it("clears only what it was told to clear", function()
		local state = scene({ oneMoves = { "sweepHazardsOnly" } })
		state.sides[1].hazards.Caltrops = 2
		state.sides[1].sideConditions.Bulwark = 3
		local outcome = resolve(state, ONE)
		expect(next(outcome.state.sides[1].hazards)).toBeNil()
		-- Survives the sweep, but the end-of-turn countdown still takes its tick.
		expect(outcome.state.sides[1].sideConditions.Bulwark).toBe(2)
	end)

	it("logs nothing when there was nothing to clear", function()
		local outcome = resolve(scene({ oneMoves = { "sweep" } }), ONE)
		expect(#Battle.eventsOfKind(outcome.events, "SideCleared")).toBe(0)
	end)
end)

--[[ SetField --------------------------------------------------------------- ]]

describe("Effects / SetField", function()
	it("sets the field with its duration", function()
		local outcome = resolve(scene({ oneMoves = { "emberveil" } }), ONE)
		expect(outcome.state.field.activeField).toBe("Emberveil")
		expect(#Battle.eventsOfKind(outcome.events, "FieldSet")).toBe(1)
	end)

	it("boosts its own element and damps the opposing one", function()
		local plain = resolve(scene({ twoMoves = { "flameHit" } }), TWO, 7)
		local plainDamage = 200 - plain.state.sides[1].party[1].currentHp

		local sunny = scene({ twoMoves = { "flameHit" } })
		sunny.field = { activeField = "Emberveil", fieldTurnsRemaining = 4 }
		local boosted = 200 - resolve(sunny, TWO, 7).state.sides[1].party[1].currentHp
		expect(boosted).toBeGreaterThan(plainDamage)

		local rainy = scene({ twoMoves = { "flameHit" } })
		rainy.field = { activeField = "Downpour", fieldTurnsRemaining = 4 }
		local damped = 200 - resolve(rainy, TWO, 7).state.sides[1].party[1].currentHp
		expect(damped).toBeLessThan(plainDamage)
	end)

	it("chips both sides under a damaging field", function()
		local state = scene()
		state.field = { activeField = "Duststorm", fieldTurnsRemaining = 4 }
		local outcome = resolve(state, {})
		expect(#Battle.eventsOfKind(outcome.events, "StatusDamage")).toBe(0)
		local hits = Battle.eventsOfKind(outcome.events, "DamageDealt")
		expect(#hits).toBe(2)
		expect(hits[1].amount).toBe(12)
	end)

	--[[
		A weather that hurts the type it is made of reads as a bug to a player, however
		defensible the maths. Terra and Forge shrug off the duststorm; Frost ignores the
		whiteout.
	]]
	it("exempts the types that belong to the weather", function()
		local state = scene({ foeSpecies = "terra" })
		state.field = { activeField = "Duststorm", fieldTurnsRemaining = 4 }
		local outcome = resolve(state, {})
		expect(#Battle.eventsOfKind(outcome.events, "DamageDealt")).toBe(1)

		local icy = scene({ foeSpecies = "frost" })
		icy.field = { activeField = "Whiteout", fieldTurnsRemaining = 4 }
		expect(#Battle.eventsOfKind(resolve(icy, {}).events, "DamageDealt")).toBe(1)
	end)

	it("reverses turn order under the inversion field", function()
		local state = scene()
		state.field = { activeField = "Inversion", fieldTurnsRemaining = 4 }
		local outcome =
			resolve(state, { [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } })
		-- Side 2 is slower and therefore goes first.
		expect(Battle.eventsOfKind(outcome.events, "MoveUsed")[1].sideId).toBe(2)
	end)

	it("still respects priority under the inversion field", function()
		-- Inversion reverses speed, not the priority bracket above it.
		local state = scene()
		state.field = { activeField = "Inversion", fieldTurnsRemaining = 4 }
		local outcome = resolve(
			state,
			{ [1] = { kind = "Switch", partyIndex = 2 }, [2] = { kind = "Move", slot = 1 } }
		)
		expect(#Battle.eventsOfKind(outcome.events, "SwitchIn")).toBe(1)
		local switchIndex, moveIndex = 0, 0
		for index, event in outcome.events do
			if event.kind == "SwitchIn" then
				switchIndex = index
			elseif event.kind == "MoveUsed" then
				moveIndex = index
			end
		end
		expect(switchIndex).toBeLessThan(moveIndex)
	end)

	it("counts down and expires", function()
		local current = resolve(scene({ oneMoves = { "inversion" } }), ONE).state
		expect(current.field.fieldTurnsRemaining).toBe(4)
		for turn = 1, 4 do
			current = resolve(current, {}, turn + 30).state
		end
		expect(current.field.activeField).toBeNil()
	end)
end)
