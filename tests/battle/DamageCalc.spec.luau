--!strict
--[[
	Damage formula tests.

	Every expected number here was worked out by hand from the Gen-5 formula before
	the implementation existed, and the arithmetic is written out in the comment above
	each anchor case so it can be re-checked without running anything.

	The base case, used everywhere below:

	    level 50, 100 power, 100 attack, 100 defence
	    level term = floor(2 * 50 / 5 + 2)             = 22
	    core       = floor(22 * 100 * 100 / 100)       = 2200
	    base       = floor(2200 / 50) + 2              = 46

	Type effectiveness is never hardcoded — it is pulled from TypeChart and asserted
	to match, so a chart edit moves these tests instead of silently disagreeing with
	them.

	Move data is synthetic (tests/fixtures/SyntheticMoves.luau) and is NOT balance
	data. See that file's header.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Fixtures = require(script.Parent.Parent.fixtures.SyntheticMoves)
local Shared = script.Parent.Parent.Parent.Shared
local DamageCalc = require(Shared.Battle.DamageCalc)
local RNG = require(Shared.Battle.RNG)
local TypeChart = require(Shared.Data.TypeChart)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

--[[ Builders --------------------------------------------------------------- ]]

local function statsWith(overrides: { [string]: number }): any
	local result: { [string]: number } =
		{ hp = 200, atk = 100, def = 100, spa = 100, spd = 100, spe = 100 }
	for key, value in overrides do
		result[key] = value
	end
	return result
end

local function stagesWith(overrides: { [string]: number }): any
	local result: { [string]: number } =
		{ atk = 0, def = 0, spa = 0, spd = 0, spe = 0, accuracy = 0, evasion = 0 }
	for key, value in overrides do
		result[key] = value
	end
	return result
end

-- Attacker defaults to Aqua so a Martial move gets no STAB; defender defaults to Ki,
-- which Martial hits for exactly 1x. Both are neutral baselines chosen so a test that
-- means to isolate one multiplier really does.
local function combatant(options: { [string]: any }?): any
	local o: { [string]: any } = options or {}
	return {
		level = o.level or 50,
		stats = o.stats or statsWith({}),
		stages = o.stages or stagesWith({}),
		typing = o.typing or { "Aqua" },
		status = o.status,
	}
end

local function inputWith(options: { [string]: any }?): any
	local o: { [string]: any } = options or {}
	local move = o.move or Fixtures.PHYSICAL_100_MARTIAL
	return {
		attacker = o.attacker or combatant(),
		defender = o.defender or combatant({ typing = { "Ki" } }),
		move = move,
		effect = o.effect or DamageCalc.damageEffectOf(move),
		isCritical = o.isCritical or false,
		targetCount = o.targetCount,
		otherModifier = o.otherModifier,
	}
end

local function damageAt(roll: number, options: { [string]: any }?): number
	return DamageCalc.computeWithRoll(inputWith(options), roll).damage
end

--[[ The three hand-verification cases -------------------------------------- ]]

describe("DamageCalc / hand-verification anchors", function()
	--[[ base 46, roll 100 -> 46. No STAB, no crit, neutral. ]]
	it("case 1: neutral, no STAB, no crit, max roll = 46", function()
		expect(damageAt(100)).toBe(46)
	end)

	--[[ 46 -> STAB floor(46 * 1.5) = 69 -> type floor(69 * 2) = 138 ]]
	it("case 2: 2x super effective with STAB, max roll = 138", function()
		expect(damageAt(100, {
			attacker = combatant({ typing = { "Martial" } }),
			defender = combatant({ typing = { "Arcane" } }),
		})).toBe(138)
	end)

	--[[ 46 -> burn floor(46 * 0.5) = 23 ]]
	it("case 3: burned attacker using a physical move, max roll = 23", function()
		expect(damageAt(100, { attacker = combatant({ status = "Burn" }) })).toBe(23)
	end)
end)

--[[ Formula ---------------------------------------------------------------- ]]

describe("DamageCalc / Gen-5 base formula", function()
	it("truncates at each documented step", function()
		local result = DamageCalc.computeWithRoll(inputWith(), 100)
		expect(result.baseDamage).toBe(46)
	end)

	--[[ roll 85: floor(46 * 85 / 100) = floor(39.1) = 39 ]]
	it("applies the minimum roll as 85 percent", function()
		expect(damageAt(85)).toBe(39)
	end)

	it("is monotonic across the roll range", function()
		local previous = 0
		for roll = 85, 100 do
			local damage = damageAt(roll)
			expect(damage).toBeGreaterThanOrEqual(previous)
			previous = damage
		end
	end)

	--[[
		level 100: floor(2 * 100 / 5 + 2) = 42
		core = floor(42 * 100 * 100 / 100) = 4200
		base = floor(4200 / 50) + 2 = 84 + 2 = 86
	]]
	it("scales with level", function()
		expect(damageAt(100, { attacker = combatant({ level = 100 }) })).toBe(86)
	end)

	--[[
		level 1: floor(2 / 5 + 2) = floor(2.4) = 2
		core = floor(2 * 100 * 100 / 100) = 200
		base = floor(200 / 50) + 2 = 4 + 2 = 6
	]]
	it("handles level 1 without breaking the floor chain", function()
		expect(damageAt(100, { attacker = combatant({ level = 1 }) })).toBe(6)
	end)

	it("reports the attack and defence it actually used", function()
		local result = DamageCalc.computeWithRoll(inputWith(), 100)
		expect(result.attackUsed).toBe(100)
		expect(result.defenseUsed).toBe(100)
	end)

	it("rejects a roll outside 85..100", function()
		expect(function()
			DamageCalc.computeWithRoll(inputWith(), 84)
		end).toThrow("85")
		expect(function()
			DamageCalc.computeWithRoll(inputWith(), 101)
		end).toThrow("85")
	end)

	it("rejects a move with no damaging effect", function()
		expect(function()
			DamageCalc.computeWithRoll(
				inputWith({ move = Fixtures.STATUS_ONLY, effect = { kind = "Damage", power = 1 } }),
				100
			)
		end).toThrow("Status")
	end)

	it("finds the damaging effect on a move, and none on a status move", function()
		expect(DamageCalc.damageEffectOf(Fixtures.PHYSICAL_100_MARTIAL)).never.toBeNil()
		expect(DamageCalc.damageEffectOf(Fixtures.STATUS_ONLY)).toBeNil()
	end)
end)

--[[ Type effectiveness ----------------------------------------------------- ]]

describe("DamageCalc / type effectiveness", function()
	it("takes its multiplier from TypeChart rather than a local copy", function()
		local defenderTyping = { "Arcane", "Feral" }
		local result = DamageCalc.computeWithRoll(
			inputWith({ defender = combatant({ typing = defenderTyping }) }),
			100
		)
		expect(result.effectiveness).toBe(TypeChart.effectiveness("Martial", defenderTyping))
	end)

	--[[ Martial hits Arcane 2x and Feral 2x -> 4x. 46 -> floor(46 * 4) = 184 ]]
	it("stacks a dual weakness to 4x", function()
		expect(damageAt(100, { defender = combatant({ typing = { "Arcane", "Feral" } }) })).toBe(
			184
		)
	end)

	--[[ Martial is resisted by Terra and Forge -> 0.25x. floor(46 * 0.25) = 11 ]]
	it("stacks a dual resistance to 0.25x", function()
		expect(damageAt(100, { defender = combatant({ typing = { "Terra", "Forge" } }) })).toBe(11)
	end)

	--[[ Martial 2x Arcane, 0.5x Terra -> 1x ]]
	it("cancels a weakness against a resistance", function()
		expect(damageAt(100, { defender = combatant({ typing = { "Arcane", "Terra" } }) })).toBe(46)
	end)

	--[[
		Storm cannot touch Terra. Zero is zero — the minimum-one-damage clamp must not
		resurrect an immune hit, which is the single most embarrassing bug this file
		could ship.
	]]
	it("deals exactly zero into an immunity", function()
		local result = DamageCalc.computeWithRoll(
			inputWith({
				move = Fixtures.PHYSICAL_100_STORM,
				defender = combatant({ typing = { "Terra" } }),
			}),
			100
		)
		expect(result.damage).toBe(0)
		expect(result.effectiveness).toBe(0)
	end)

	it("ignores the chart when the effect opts out", function()
		local result = DamageCalc.computeWithRoll(
			inputWith({
				move = Fixtures.TYPELESS_100_MARTIAL,
				defender = combatant({ typing = { "Arcane" } }),
			}),
			100
		)
		expect(result.effectiveness).toBe(1)
		expect(result.damage).toBe(46)
	end)

	--[[
		level 30, 40 power, 50 attack, 100 defence -> base 7.
		STAB first: floor(7 * 1.5) = 10, then floor(10 * 0.5) = 5
		Type first: floor(7 * 0.5) = 3,  then floor(3 * 1.5) = 4
		Gen 5 applies STAB before type effectiveness, so 5 is correct and 4 means the
		order was flipped. This is the only small case where the two differ.
	]]
	it("applies STAB before type effectiveness, as Gen 5 does", function()
		expect(damageAt(100, {
			move = Fixtures.PHYSICAL_40_MARTIAL,
			attacker = combatant({
				level = 30,
				typing = { "Martial" },
				stats = statsWith({ atk = 50 }),
			}),
			defender = combatant({ typing = { "Terra" } }),
		})).toBe(5)
	end)

	--[[
		level 5, 10 power, 20 attack, 100 defence -> base 2.
		roll 85 -> floor(2 * 0.85) = 1, then 0.25x -> floor(0.25) = 0, clamped to 1.
	]]
	it("clamps a non-immune hit up to 1 damage", function()
		expect(damageAt(85, {
			move = Fixtures.PHYSICAL_10_MARTIAL,
			attacker = combatant({ level = 5, stats = statsWith({ atk = 20 }) }),
			defender = combatant({ typing = { "Terra", "Forge" } }),
		})).toBe(1)
	end)
end)

--[[ STAB ------------------------------------------------------------------- ]]

describe("DamageCalc / STAB", function()
	--[[ floor(46 * 1.5) = 69 ]]
	it("multiplies by 1.5 when the move type is in the attacker typing", function()
		expect(damageAt(100, { attacker = combatant({ typing = { "Martial" } }) })).toBe(69)
	end)

	it("applies on the second half of a dual typing too", function()
		expect(damageAt(100, { attacker = combatant({ typing = { "Aqua", "Martial" } }) })).toBe(69)
	end)

	it("does not apply when the types do not match", function()
		local result = DamageCalc.computeWithRoll(inputWith(), 100)
		expect(result.isStab).toBe(false)
		expect(result.damage).toBe(46)
	end)

	it("reports whether STAB applied", function()
		local result = DamageCalc.computeWithRoll(
			inputWith({ attacker = combatant({ typing = { "Martial" } }) }),
			100
		)
		expect(result.isStab).toBe(true)
	end)
end)

--[[ Critical hits ---------------------------------------------------------- ]]

describe("DamageCalc / critical hits", function()
	--[[ Gen 5 crits are 2x, not the 1.5x of Gen 6 onward. 46 -> 92 ]]
	it("doubles damage, per Gen 5", function()
		expect(damageAt(100, { isCritical = true })).toBe(92)
	end)

	it("reports that it crit", function()
		expect(DamageCalc.computeWithRoll(inputWith({ isCritical = true }), 100).isCritical).toBe(
			true
		)
	end)

	--[[
		Gen 5: a crit ignores the attacker's NEGATIVE attack stages and the defender's
		POSITIVE defence stages, so lowering the attacker or raising the defender
		cannot blunt one. It does not touch the other two directions.
	]]
	it("ignores the attacker's negative attack stages", function()
		local lowered = combatant({ stages = stagesWith({ atk = -1 }) })
		-- Without the crit rule this would be 31; with it, the full 100 attack is used.
		expect(damageAt(100, { attacker = lowered })).toBe(31)
		expect(damageAt(100, { attacker = lowered, isCritical = true })).toBe(92)
	end)

	it("keeps the attacker's positive attack stages", function()
		local raised = combatant({ stages = stagesWith({ atk = 1 }) })
		expect(damageAt(100, { attacker = raised })).toBe(68)
		expect(damageAt(100, { attacker = raised, isCritical = true })).toBe(136)
	end)

	it("ignores the defender's positive defence stages", function()
		local walled = combatant({ typing = { "Ki" }, stages = stagesWith({ def = 1 }) })
		expect(damageAt(100, { defender = walled })).toBe(31)
		expect(damageAt(100, { defender = walled, isCritical = true })).toBe(92)
	end)

	it("keeps the defender's negative defence stages", function()
		local broken = combatant({ typing = { "Ki" }, stages = stagesWith({ def = -1 }) })
		expect(damageAt(100, { defender = broken })).toBe(68)
		expect(damageAt(100, { defender = broken, isCritical = true })).toBe(136)
	end)

	--[[ Gen 5 crit stages: 1/16, 1/8, 1/4, 1/3, then 1/2 from stage 4 up. ]]
	it("uses the Gen 5 critical chance ladder", function()
		expect(DamageCalc.criticalChance(0)).toBeCloseTo(1 / 16, 1e-12)
		expect(DamageCalc.criticalChance(1)).toBeCloseTo(1 / 8, 1e-12)
		expect(DamageCalc.criticalChance(2)).toBeCloseTo(1 / 4, 1e-12)
		expect(DamageCalc.criticalChance(3)).toBeCloseTo(1 / 3, 1e-12)
		expect(DamageCalc.criticalChance(4)).toBeCloseTo(1 / 2, 1e-12)
		expect(DamageCalc.criticalChance(9)).toBeCloseTo(1 / 2, 1e-12)
	end)

	it("rolls crits at roughly the stated rate", function()
		local rng = RNG.new(4242)
		local crits = 0
		local samples = 64000
		for _ = 1, samples do
			if DamageCalc.rollCritical(0, rng) then
				crits += 1
			end
		end
		-- Expected 4000 of 64000.
		expect(crits).toBeGreaterThan(3700)
		expect(crits).toBeLessThan(4300)
	end)

	it("rolls crits reproducibly from a seed", function()
		local first, second = {}, {}
		local a, b = RNG.new(31337), RNG.new(31337)
		for _ = 1, 200 do
			table.insert(first, DamageCalc.rollCritical(2, a))
			table.insert(second, DamageCalc.rollCritical(2, b))
		end
		expect(first).toEqual(second)
	end)
end)

--[[ Burn -------------------------------------------------------------------- ]]

describe("DamageCalc / burn", function()
	--[[
		Gen 5 applies burn as a final damage modifier, not by halving the Attack stat
		before the formula. Halving the stat first would give 24 here, not 23 — the
		truncation lands differently. Gen 3 halved the stat; Gen 5's formula lists Burn
		among the trailing modifiers, and that is what is implemented.
	]]
	it("halves physical damage", function()
		expect(damageAt(100, { attacker = combatant({ status = "Burn" }) })).toBe(23)
	end)

	it("does not touch special damage", function()
		expect(damageAt(100, {
			move = Fixtures.SPECIAL_100_MARTIAL,
			attacker = combatant({ status = "Burn" }),
		})).toBe(46)
	end)

	it("stacks with a critical hit", function()
		-- 46 -> crit 92 -> burn floor(92 * 0.5) = 46
		expect(damageAt(100, { attacker = combatant({ status = "Burn" }), isCritical = true })).toBe(
			46
		)
	end)

	it("is not triggered by any other status", function()
		for _, status in { "Poison", "Paralysis", "Sleep", "Freeze" } do
			expect(damageAt(100, { attacker = combatant({ status = status }) })).toBe(46)
		end
	end)
end)

--[[ Stat stages ------------------------------------------------------------ ]]

describe("DamageCalc / stat stages", function()
	it("uses the Gen 3+ stage multipliers", function()
		expect(DamageCalc.applyStage(100, 0)).toBe(100)
		expect(DamageCalc.applyStage(100, 1)).toBe(150)
		expect(DamageCalc.applyStage(100, 2)).toBe(200)
		expect(DamageCalc.applyStage(100, 6)).toBe(400)
		expect(DamageCalc.applyStage(100, -1)).toBe(66)
		expect(DamageCalc.applyStage(100, -2)).toBe(50)
		expect(DamageCalc.applyStage(100, -6)).toBe(25)
	end)

	it("clamps stages to the -6..+6 range", function()
		expect(DamageCalc.applyStage(100, 9)).toBe(DamageCalc.applyStage(100, 6))
		expect(DamageCalc.applyStage(100, -9)).toBe(DamageCalc.applyStage(100, -6))
	end)

	--[[ +1 attack: 150 attack -> core floor(22 * 100 * 150 / 100) = 3300 -> base 68 ]]
	it("feeds boosted attack into the formula", function()
		expect(damageAt(100, { attacker = combatant({ stages = stagesWith({ atk = 1 }) }) })).toBe(
			68
		)
	end)

	--[[ -1 attack: 66 attack -> core 1452 -> floor(1452 / 50) + 2 = 31 ]]
	it("feeds lowered attack into the formula", function()
		expect(damageAt(100, { attacker = combatant({ stages = stagesWith({ atk = -1 }) }) })).toBe(
			31
		)
	end)

	--[[ +6 attack: 400 attack -> core 8800 -> 178 ]]
	it("handles the maximum boost", function()
		expect(damageAt(100, { attacker = combatant({ stages = stagesWith({ atk = 6 }) }) })).toBe(
			178
		)
	end)

	--[[ -6 attack: 25 attack -> core 550 -> 13 ]]
	it("handles the maximum drop", function()
		expect(damageAt(100, { attacker = combatant({ stages = stagesWith({ atk = -6 }) }) })).toBe(
			13
		)
	end)

	it("reads the defender's defence stages", function()
		expect(damageAt(100, {
			defender = combatant({ typing = { "Ki" }, stages = stagesWith({ def = 1 }) }),
		})).toBe(31)
	end)

	it("reads special stages for a special move", function()
		expect(damageAt(100, {
			move = Fixtures.SPECIAL_100_MARTIAL,
			attacker = combatant({ stages = stagesWith({ spa = 1 }) }),
		})).toBe(68)
	end)

	it("ignores the wrong side's stages", function()
		-- A special-attack boost must do nothing for a physical move.
		expect(damageAt(100, { attacker = combatant({ stages = stagesWith({ spa = 6 }) }) })).toBe(
			46
		)
	end)

	it("lets an effect ignore the defender's boosts without ignoring its drops", function()
		local raised = combatant({ typing = { "Ki" }, stages = stagesWith({ def = 1 }) })
		local lowered = combatant({ typing = { "Ki" }, stages = stagesWith({ def = -1 }) })
		expect(damageAt(100, { move = Fixtures.IGNORES_BOOSTS_100_MARTIAL, defender = raised })).toBe(
			46
		)
		expect(damageAt(100, { move = Fixtures.IGNORES_BOOSTS_100_MARTIAL, defender = lowered })).toBe(
			68
		)
	end)
end)

--[[ Physical vs special ---------------------------------------------------- ]]

describe("DamageCalc / damage class", function()
	it("reads atk and def for a physical move", function()
		expect(damageAt(100, {
			attacker = combatant({ stats = statsWith({ atk = 100, spa = 999 }) }),
			defender = combatant({ typing = { "Ki" }, stats = statsWith({ def = 100, spd = 999 }) }),
		})).toBe(46)
	end)

	it("reads spa and spd for a special move", function()
		-- If this read atk/def instead it would produce 178, not 46.
		expect(damageAt(100, {
			move = Fixtures.SPECIAL_100_MARTIAL,
			attacker = combatant({ stats = statsWith({ atk = 200, spa = 100 }) }),
			defender = combatant({ typing = { "Ki" }, stats = statsWith({ def = 50, spd = 100 }) }),
		})).toBe(46)
	end)
end)

--[[ Trailing modifiers ----------------------------------------------------- ]]

describe("DamageCalc / trailing modifiers", function()
	--[[ multi-target is 0.75 in Gen 5: floor(46 * 0.75) = 34 ]]
	it("reduces damage when a move hits more than one target", function()
		expect(damageAt(100, { targetCount = 2 })).toBe(34)
	end)

	it("leaves a single-target move alone", function()
		expect(damageAt(100, { targetCount = 1 })).toBe(46)
	end)

	it("applies the generic other modifier last", function()
		expect(damageAt(100, { otherModifier = 0.5 })).toBe(23)
	end)
end)

--[[ Randomness ------------------------------------------------------------- ]]

describe("DamageCalc / damage roll", function()
	it("bounds the roll to 85..100", function()
		local rng = RNG.new(2024)
		for _ = 1, 4000 do
			local result = DamageCalc.compute(inputWith(), rng)
			expect(result.randomFactor).toBeGreaterThanOrEqual(85)
			expect(result.randomFactor).toBeLessThanOrEqual(100)
		end
	end)

	it("reaches every one of the 16 roll values", function()
		local rng = RNG.new(11)
		local seen: { [number]: boolean } = {}
		for _ = 1, 4000 do
			seen[DamageCalc.compute(inputWith(), rng).randomFactor] = true
		end
		for factor = 85, 100 do
			if not seen[factor] then
				fail(`roll {factor} never came up in 4000 samples`)
			end
		end
	end)

	it("bounds damage to the 39..46 window for the base case", function()
		local rng = RNG.new(77)
		for _ = 1, 2000 do
			local damage = DamageCalc.compute(inputWith(), rng).damage
			expect(damage).toBeGreaterThanOrEqual(39)
			expect(damage).toBeLessThanOrEqual(46)
		end
	end)

	--[[
		The property the whole engine rests on: same seed, same numbers. If this ever
		fails, an ungated source of randomness got in and every other result in the
		suite is suspect.
	]]
	it("is reproducible from a seed", function()
		local first, second = {}, {}
		local a, b = RNG.new(999), RNG.new(999)
		for _ = 1, 300 do
			table.insert(first, DamageCalc.compute(inputWith(), a).damage)
			table.insert(second, DamageCalc.compute(inputWith(), b).damage)
		end
		expect(first).toEqual(second)
	end)

	it("consumes exactly one draw per computation", function()
		local rng = RNG.new(555)
		local probe = RNG.new(555)
		DamageCalc.compute(inputWith(), rng)
		probe:nextUInt32()
		expect(rng:getState()).toBe(probe:getState())
	end)

	it("reports the min and max of the roll window", function()
		local range = DamageCalc.range(inputWith())
		expect(range.min).toBe(39)
		expect(range.max).toBe(46)
	end)

	it("collapses the range to zero against an immunity", function()
		local range = DamageCalc.range(inputWith({
			move = Fixtures.PHYSICAL_100_STORM,
			defender = combatant({ typing = { "Terra" } }),
		}))
		expect(range.min).toBe(0)
		expect(range.max).toBe(0)
	end)
end)
