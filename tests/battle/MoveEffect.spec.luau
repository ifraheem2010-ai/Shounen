--!strict
--[[
	Effect vocabulary tests.

	These guard the vocabulary's CLOSEDNESS as much as its correctness. If a primitive
	is added, the count assertions here fail on purpose — that is the prompt to decide
	whether the addition is genuinely a new primitive or a move that should have been
	expressed with the ones that already exist.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local MoveEffect = require(Shared.Types.MoveEffect)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect

type MoveEffect = MoveEffect.MoveEffect

describe("MoveEffect / closed vocabulary", function()
	it("holds exactly 19 primitives", function()
		expect(#MoveEffect.EFFECT_KINDS).toBe(19)
	end)

	it("lists no primitive twice", function()
		local seen: { [string]: boolean } = {}
		for _, kind in MoveEffect.EFFECT_KINDS do
			expect(seen[kind]).toBeFalsy()
			seen[kind] = true
		end
	end)

	it("keeps the five Phase 1 statuses", function()
		expect(MoveEffect.STATUS_IDS).toEqual({ "Burn", "Poison", "Paralysis", "Sleep", "Freeze" })
	end)

	it("keeps the volatile list closed", function()
		expect(#MoveEffect.VOLATILE_IDS).toBe(13)
	end)

	it("keeps four hazards, five side conditions, five fields", function()
		expect(#MoveEffect.HAZARD_IDS).toBe(4)
		expect(#MoveEffect.SIDE_CONDITION_IDS).toBe(5)
		expect(#MoveEffect.FIELD_IDS).toBe(5)
	end)

	it("boosts seven stats — the five battle stats plus accuracy and evasion", function()
		expect(MoveEffect.BOOSTABLE_STATS).toEqual({
			"atk",
			"def",
			"spa",
			"spd",
			"spe",
			"accuracy",
			"evasion",
		})
	end)

	it("clamps stat stages to -6..+6", function()
		expect(MoveEffect.MIN_STAT_STAGE).toBe(-6)
		expect(MoveEffect.MAX_STAT_STAGE).toBe(6)
	end)
end)

describe("MoveEffect / defaults", function()
	it("gives every primitive a default target", function()
		for _, kind in MoveEffect.EFFECT_KINDS do
			expect(MoveEffect.DEFAULT_TARGETS[kind]).never.toBeNil()
		end
	end)

	it("only uses targets from the closed target list", function()
		local valid: { [string]: boolean } = {}
		for _, target in MoveEffect.EFFECT_TARGETS do
			valid[target] = true
		end
		for _, kind in MoveEffect.EFFECT_KINDS do
			expect(valid[MoveEffect.DEFAULT_TARGETS[kind]]).toBe(true)
		end
	end)

	it("falls back to the default target when the move does not say", function()
		local effect: MoveEffect = { kind = "Damage", power = 90, damageClass = "Physical" }
		expect(MoveEffect.targetOf(effect)).toBe("Target")
	end)

	it("honours an explicit target", function()
		local effect: MoveEffect =
			{ kind = "Damage", power = 90, damageClass = "Physical", target = "Self" }
		expect(MoveEffect.targetOf(effect)).toBe("Self")
	end)

	it("treats a missing chance as certain", function()
		local effect: MoveEffect = { kind = "InflictStatus", status = "Burn" }
		expect(MoveEffect.chanceOf(effect)).toBe(1)
	end)

	it("honours an explicit chance", function()
		local effect: MoveEffect = { kind = "InflictStatus", status = "Burn", chance = 0.3 }
		expect(MoveEffect.chanceOf(effect)).toBe(0.3)
	end)
end)

describe("MoveEffect / isSetup", function()
	--[[
		Arcane gets no setup moves. This is the mechanical wall between Arcane and Ki,
		not flavour: Ki boosts itself, Arcane manipulates the opponent. Break the wall
		and the two types collapse into one within twenty characters. isSetup is what
		lets the data validator enforce it instead of trusting memory.
	]]
	it("counts a positive self boost as setup", function()
		local effect: MoveEffect = { kind = "StatStage", stat = "atk", delta = 2, target = "Self" }
		expect(MoveEffect.isSetup(effect)).toBe(true)
	end)

	it("does not count a debuff on the opponent as setup", function()
		local effect: MoveEffect =
			{ kind = "StatStage", stat = "atk", delta = -2, target = "Target" }
		expect(MoveEffect.isSetup(effect)).toBe(false)
	end)

	it("does not count a self-inflicted drop as setup", function()
		local effect: MoveEffect = { kind = "StatStage", stat = "spa", delta = -2, target = "Self" }
		expect(MoveEffect.isSetup(effect)).toBe(false)
	end)

	it("does not count a boost aimed at the opponent as setup", function()
		local effect: MoveEffect =
			{ kind = "StatStage", stat = "atk", delta = 1, target = "Target" }
		expect(MoveEffect.isSetup(effect)).toBe(false)
	end)

	it("does not count healing as setup", function()
		local effect: MoveEffect = { kind = "Heal", fractionOfMaxHp = 0.5 }
		expect(MoveEffect.isSetup(effect)).toBe(false)
	end)
end)

describe("MoveEffect / isDamaging", function()
	it("counts Damage and FixedDamage", function()
		expect(MoveEffect.isDamaging({ kind = "Damage", power = 90, damageClass = "Special" })).toBe(
			true
		)
		expect(MoveEffect.isDamaging({ kind = "FixedDamage", mode = "UserLevel" })).toBe(true)
	end)

	it("does not count recoil, which is self-damage", function()
		expect(MoveEffect.isDamaging({ kind = "Recoil", fractionOfDamageDealt = 0.33 })).toBe(false)
	end)
end)

describe("MoveEffect / validate", function()
	local function problemsFor(effect: MoveEffect): { string }
		return MoveEffect.validate(effect)
	end

	it("accepts a plain 90 BP attack", function()
		expect(problemsFor({ kind = "Damage", power = 90, damageClass = "Physical" })).toEqual({})
	end)

	it("accepts a wallbreaker STAB with recoil", function()
		expect(problemsFor({ kind = "Damage", power = 120, damageClass = "Physical" })).toEqual({})
		expect(problemsFor({ kind = "Recoil", fractionOfDamageDealt = 0.33 })).toEqual({})
	end)

	it("accepts a multi-hit move", function()
		expect(problemsFor({
			kind = "Damage",
			power = 25,
			damageClass = "Physical",
			hitsRange = { min = 2, max = 5 },
		})).toEqual({})
	end)

	it("rejects an unknown kind", function()
		expect(#problemsFor({ kind = "Teleport" } :: any)).toBe(1)
	end)

	it("rejects an unknown target", function()
		local problems =
			problemsFor({ kind = "Heal", fractionOfMaxHp = 0.5, target = "Everyone" } :: any)
		expect(#problems).toBeGreaterThan(0)
	end)

	it("rejects a chance outside (0, 1]", function()
		expect(#problemsFor({ kind = "InflictStatus", status = "Burn", chance = 0 })).toBe(1)
		expect(#problemsFor({ kind = "InflictStatus", status = "Burn", chance = 1.5 })).toBe(1)
		expect(problemsFor({ kind = "InflictStatus", status = "Burn", chance = 1 })).toEqual({})
	end)

	it("rejects non-positive power", function()
		expect(#problemsFor({ kind = "Damage", power = 0, damageClass = "Physical" })).toBe(1)
	end)

	it("rejects a move that sets both hits and hitsRange", function()
		local problems = problemsFor({
			kind = "Damage",
			power = 25,
			damageClass = "Physical",
			hits = 3,
			hitsRange = { min = 2, max = 5 },
		})
		expect(#problems).toBe(1)
	end)

	it("rejects a hitsRange that counts backwards", function()
		local problems = problemsFor({
			kind = "Damage",
			power = 25,
			damageClass = "Physical",
			hitsRange = { min = 5, max = 2 },
		})
		expect(#problems).toBe(1)
	end)

	it("rejects recoil that specifies neither fraction", function()
		expect(#problemsFor({ kind = "Recoil" })).toBe(1)
	end)

	it("rejects recoil that specifies both fractions", function()
		local problems = problemsFor({
			kind = "Recoil",
			fractionOfDamageDealt = 0.33,
			fractionOfUserMaxHp = 0.25,
		})
		expect(#problems).toBe(1)
	end)

	it("rejects a heal with no amount", function()
		expect(#problemsFor({ kind = "Heal" })).toBe(1)
	end)

	it("rejects a stat change of zero", function()
		expect(#problemsFor({ kind = "StatStage", stat = "atk", delta = 0 })).toBe(1)
	end)

	it("rejects a stat change beyond the stage range", function()
		expect(#problemsFor({ kind = "StatStage", stat = "atk", delta = 7 })).toBe(1)
		expect(#problemsFor({ kind = "StatStage", stat = "atk", delta = -7 })).toBe(1)
	end)

	it("accepts a maximal legal stat change", function()
		expect(problemsFor({ kind = "StatStage", stat = "atk", delta = 6 })).toEqual({})
	end)

	it("rejects a flat FixedDamage with no value", function()
		expect(#problemsFor({ kind = "FixedDamage", mode = "Flat" })).toBe(1)
	end)

	it("rejects a level-based FixedDamage that also carries a value", function()
		expect(#problemsFor({ kind = "FixedDamage", mode = "UserLevel", value = 40 })).toBe(1)
	end)

	it("rejects a ClearSide that clears nothing", function()
		expect(#problemsFor({ kind = "ClearSide" })).toBe(1)
	end)

	it("accepts a hazard-clearing ClearSide", function()
		expect(problemsFor({ kind = "ClearSide", hazards = true })).toEqual({})
	end)

	it("rejects zero-duration field and side conditions", function()
		expect(#problemsFor({ kind = "SetField", field = "Inversion", duration = 0 })).toBe(1)
		expect(#problemsFor({ kind = "SetSideCondition", condition = "Bulwark", duration = 0 })).toBe(
			1
		)
	end)

	it("rejects a ball with no multiplier", function()
		expect(#problemsFor({ kind = "Capture", ballMultiplier = 0 })).toBe(1)
	end)

	it("accepts the pivot, phaze and trap primitives as written", function()
		expect(problemsFor({ kind = "SelfSwitch" })).toEqual({})
		expect(problemsFor({ kind = "SelfSwitch", passBoosts = true })).toEqual({})
		expect(problemsFor({ kind = "ForceSwitch" })).toEqual({})
		expect(problemsFor({ kind = "Trap", duration = 4 })).toEqual({})
	end)

	it("accepts a cleric move — cure everything, whole party", function()
		expect(problemsFor({ kind = "CureStatus", target = "UserParty" })).toEqual({})
	end)

	it("accepts every hazard, side condition and field id", function()
		for _, hazard in MoveEffect.HAZARD_IDS do
			expect(problemsFor({ kind = "SetHazard", hazard = hazard })).toEqual({})
		end
		for _, condition in MoveEffect.SIDE_CONDITION_IDS do
			expect(problemsFor({ kind = "SetSideCondition", condition = condition, duration = 5 })).toEqual({})
		end
		for _, field in MoveEffect.FIELD_IDS do
			expect(problemsFor({ kind = "SetField", field = field, duration = 5 })).toEqual({})
		end
	end)

	it("accepts every status and volatile id", function()
		for _, status in MoveEffect.STATUS_IDS do
			expect(problemsFor({ kind = "InflictStatus", status = status })).toEqual({})
		end
		for _, volatileId in MoveEffect.VOLATILE_IDS do
			expect(problemsFor({ kind = "ApplyVolatile", volatile = volatileId })).toEqual({})
		end
	end)
end)
