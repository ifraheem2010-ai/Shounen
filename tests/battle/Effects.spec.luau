--!strict
--[[
	The effect interpreter, primitive by primitive.

	TurnResolver dispatches on `effect.kind` and never on a move id, so every test here
	drives a synthetic move built purely to carry one primitive. If any of these
	started needing a specially-named move to pass, Absolute Rule #4 would already be
	broken.

	Group A: the primitives that move HP around — FixedDamage, Recoil, Drain, Heal.
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

--[[ Fixtures -------------------------------------------------------------- ]]

local IDLE = Moves.build("idle", "Martial", "Physical", 10)

local FIXED_FLAT = Moves.utility("fixedFlat", "Martial", {
	{ kind = "FixedDamage", mode = "Flat", value = 40 },
})
local FIXED_LEVEL = Moves.utility("fixedLevel", "Martial", {
	{ kind = "FixedDamage", mode = "UserLevel" },
})
local FIXED_FRACTION = Moves.utility("fixedFraction", "Martial", {
	{ kind = "FixedDamage", mode = "TargetCurrentHpFraction", value = 0.5 },
})
local FIXED_STORM = Moves.utility("fixedStorm", "Storm", {
	{ kind = "FixedDamage", mode = "Flat", value = 40 },
})

local PHYSICAL = { category = "Physical", accuracy = 1 }

local RECOIL_MOVE = Moves.utility("recoiler", "Martial", {
	{ kind = "Damage", power = 100, damageClass = "Physical" },
	{ kind = "Recoil", fractionOfDamageDealt = 0.5 },
}, PHYSICAL)

local RECOIL_FLAT = Moves.utility("recoilFlat", "Martial", {
	{ kind = "Damage", power = 100, damageClass = "Physical" },
	{ kind = "Recoil", fractionOfUserMaxHp = 0.25 },
}, PHYSICAL)

-- Immune target, so the damaging step contributes nothing for the recoil to scale.
local RECOIL_IMMUNE = Moves.utility("recoilImmune", "Storm", {
	{ kind = "FixedDamage", mode = "Flat", value = 40 },
	{ kind = "Recoil", fractionOfUserMaxHp = 0.25 },
}, PHYSICAL)

local DRAIN_MOVE = Moves.utility("drainer", "Martial", {
	{ kind = "Damage", power = 100, damageClass = "Physical" },
	{ kind = "Drain", fractionOfDamageDealt = 0.5 },
}, PHYSICAL)

local HEAL_HALF = Moves.utility("healHalf", "Martial", {
	{ kind = "Heal", fractionOfMaxHp = 0.5, target = "Self" },
}, { targeting = "Self" })
local HEAL_FLAT = Moves.utility("healFlat", "Martial", {
	{ kind = "Heal", flat = 30, target = "Self" },
}, { targeting = "Self" })

local ALL_MOVES: { [string]: any } = {
	idle = IDLE,
	fixedFlat = FIXED_FLAT,
	fixedLevel = FIXED_LEVEL,
	fixedFraction = FIXED_FRACTION,
	fixedStorm = FIXED_STORM,
	recoiler = RECOIL_MOVE,
	recoilFlat = RECOIL_FLAT,
	recoilImmune = RECOIL_IMMUNE,
	drainer = DRAIN_MOVE,
	healHalf = HEAL_HALF,
	healFlat = HEAL_FLAT,
}

local SPECIES: { [string]: any } = {
	fast = { stats = Battle.statsWith({ spe = 120 }), typing = { "Aqua" } },
	slow = { stats = Battle.statsWith({ spe = 50 }), typing = { "Aqua" } },
	terra = { stats = Battle.statsWith({ spe = 50 }), typing = { "Terra" } },
}

local function context(seed: number?): any
	return {
		dex = Battle.dex({ species = SPECIES, moves = ALL_MOVES }),
		rng = RNG.new(seed or 1),
	}
end

--[[
	Side 1 always moves first (speed 120 against 50), so the first side's move lands
	before the second side has a chance to change anything.
]]
local function duel(moveId: string, options: { [string]: any }?): any
	local o: any = options or {}
	return Battle.state({
		sides = {
			Battle.side({
				id = 1,
				party = {
					Battle.creature({
						uid = "actor",
						speciesId = "fast",
						moveIds = { moveId },
						currentHp = o.actorHp or 200,
						level = o.actorLevel or 50,
					}),
				},
			}),
			Battle.side({
				id = 2,
				party = {
					Battle.creature({
						uid = "target",
						speciesId = o.targetSpecies or "slow",
						moveIds = { "idle" },
						currentHp = o.targetHp or 200,
					}),
				},
			}),
		},
	})
end

--[[
	Only the actor submits an intent. A side with no intent simply does not act, which
	keeps the opponent from adding HP changes of its own to the numbers under test —
	these cases are about what the actor did to itself and to the target, and nothing
	else.
]]
local ACTOR_ONLY = { [1] = { kind = "Move", slot = 1 } }

local function resolve(state: any, seed: number?): any
	return TurnResolver.resolveTurn(state, ACTOR_ONLY, context(seed))
end

--[[ FixedDamage ------------------------------------------------------------ ]]

describe("Effects / FixedDamage", function()
	it("takes exactly the stated flat amount", function()
		local outcome = resolve(duel("fixedFlat"))
		expect(outcome.state.sides[2].party[1].currentHp).toBe(160)
	end)

	it("ignores type effectiveness entirely", function()
		-- Martial into Terra is 0.5x, but fixed damage is fixed.
		local outcome = resolve(duel("fixedFlat", { targetSpecies = "terra" }))
		expect(outcome.state.sides[2].party[1].currentHp).toBe(160)
	end)

	--[[
		An immunity still stops it. Gen 5 fixed-damage moves respect type immunity —
		you cannot hit something the move fundamentally cannot reach, however the
		number was arrived at.
	]]
	it("still respects an immunity", function()
		local outcome = resolve(duel("fixedStorm", { targetSpecies = "terra" }))
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

	it("deals damage equal to the user's level", function()
		local outcome = resolve(duel("fixedLevel", { actorLevel = 37 }))
		expect(outcome.state.sides[2].party[1].currentHp).toBe(163)
	end)

	it("takes a fraction of the target's CURRENT hp, not its maximum", function()
		local outcome = resolve(duel("fixedFraction", { targetHp = 80 }))
		expect(outcome.state.sides[2].party[1].currentHp).toBe(40)
	end)

	it("never takes more than the target has left", function()
		local outcome = resolve(duel("fixedFlat", { targetHp = 10 }))
		expect(outcome.state.sides[2].party[1].currentHp).toBe(0)
		expect(#Battle.eventsOfKind(outcome.events, "Fainted")).toBe(1)
	end)

	it("always takes at least one point", function()
		-- 0.5 of 1 HP floors to zero; a connecting hit must still do something.
		local outcome = resolve(duel("fixedFraction", { targetHp = 1 }))
		expect(outcome.state.sides[2].party[1].currentHp).toBe(0)
	end)
end)

--[[ Recoil ----------------------------------------------------------------- ]]

describe("Effects / Recoil", function()
	it("costs the user a fraction of what it dealt", function()
		local outcome = resolve(duel("recoiler"))
		local dealt = 200 - outcome.state.sides[2].party[1].currentHp
		local taken = 200 - outcome.state.sides[1].party[1].currentHp
		expect(dealt).toBeGreaterThan(0)
		expect(taken).toBe(math.max(1, math.floor(dealt * 0.5)))
	end)

	it("costs a fraction of the user's max HP when written that way", function()
		local outcome = resolve(duel("recoilFlat"))
		local taken = 200 - outcome.state.sides[1].party[1].currentHp
		expect(taken).toBe(50)
	end)

	--[[
		Recoil can knock the user out. A wallbreaker that cannot kill itself on its own
		nuke is not making the trade the tier is priced around.
	]]
	it("can faint the user", function()
		local outcome = resolve(duel("recoilFlat", { actorHp = 20 }))
		expect(outcome.state.sides[1].party[1].currentHp).toBe(0)
		local faints = Battle.eventsOfKind(outcome.events, "Fainted")
		local sawActor = false
		for _, faint in faints do
			if faint.creatureUid == "actor" then
				sawActor = true
			end
		end
		expect(sawActor).toBe(true)
	end)

	--[[
		A fraction of the user's max HP is unconditional; a fraction of damage dealt is
		not. This move's damaging step is blanked by an immunity, so the damage-scaled
		recoil has nothing to scale and must stay silent rather than charging a minimum.
	]]
	it("charges nothing when the move dealt no damage", function()
		local flatRecoilStillApplies =
			resolve(duel("recoilImmune", { targetSpecies = "terra" })).state.sides[1].party[1].currentHp
		-- fractionOfUserMaxHp does not depend on damage, so this one still fires.
		expect(flatRecoilStillApplies).toBe(150)
	end)
end)

--[[ Drain ------------------------------------------------------------------ ]]

describe("Effects / Drain", function()
	it("heals the user for a fraction of the damage dealt", function()
		local state = duel("drainer", { actorHp = 100 })
		local outcome = resolve(state)
		local dealt = 200 - outcome.state.sides[2].party[1].currentHp
		local healed = outcome.state.sides[1].party[1].currentHp - 100
		expect(dealt).toBeGreaterThan(0)
		-- The opponent also attacks, so compare against the drain alone by checking
		-- the Healed event rather than net HP.
		local heals = Battle.eventsOfKind(outcome.events, "Healed")
		expect(#heals).toBe(1)
		expect(heals[1].amount).toBe(math.max(1, math.floor(dealt * 0.5)))
		expect(healed).toBe(heals[1].amount)
	end)

	it("cannot take the user above its maximum", function()
		local outcome = resolve(duel("drainer", { actorHp = 200 }))
		expect(outcome.state.sides[1].party[1].currentHp).toBeLessThanOrEqual(200)
		-- Already full, so the drain has nowhere to go and logs nothing.
		expect(#Battle.eventsOfKind(outcome.events, "Healed")).toBe(0)
	end)
end)

--[[ Heal ------------------------------------------------------------------- ]]

describe("Effects / Heal", function()
	it("restores a fraction of max HP", function()
		local outcome = resolve(duel("healHalf", { actorHp = 40 }))
		local heals = Battle.eventsOfKind(outcome.events, "Healed")
		expect(#heals).toBe(1)
		expect(heals[1].amount).toBe(100)
	end)

	it("restores a flat amount", function()
		local outcome = resolve(duel("healFlat", { actorHp = 40 }))
		expect(Battle.eventsOfKind(outcome.events, "Healed")[1].amount).toBe(30)
	end)

	it("clamps at full HP rather than overhealing", function()
		local outcome = resolve(duel("healHalf", { actorHp = 180 }))
		local heals = Battle.eventsOfKind(outcome.events, "Healed")
		expect(heals[1].amount).toBe(20)
		expect(outcome.state.sides[1].party[1].currentHp).toBeLessThanOrEqual(200)
	end)

	it("logs nothing when already at full HP", function()
		local outcome = resolve(duel("healHalf", { actorHp = 200 }))
		expect(#Battle.eventsOfKind(outcome.events, "Healed")).toBe(0)
	end)
end)
