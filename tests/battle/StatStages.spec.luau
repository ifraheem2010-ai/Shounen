--!strict
--[[
	Stat stage tests.

	Two separate ladders, and conflating them is the classic bug:

	  battle stats (atk/def/spa/spd/spe)  (2 + s) / 2  upward, 2 / (2 - s) downward
	  accuracy and evasion                (3 + s) / 3  upward, 3 / (3 - s) downward

	So +1 attack is 1.5x but +1 accuracy is 1.33x. Both are asserted below at several
	stages so a copy-paste between the two shows up immediately.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local StatStages = require(Shared.Battle.StatStages)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

local function freshStages(): any
	return { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, accuracy = 0, evasion = 0 }
end

describe("StatStages / bounds", function()
	it("clamps to -6..+6", function()
		expect(StatStages.MIN_STAGE).toBe(-6)
		expect(StatStages.MAX_STAGE).toBe(6)
		expect(StatStages.clamp(9)).toBe(6)
		expect(StatStages.clamp(-9)).toBe(-6)
		expect(StatStages.clamp(3)).toBe(3)
		expect(StatStages.clamp(0)).toBe(0)
	end)

	it("names exactly the seven staged stats", function()
		expect(#StatStages.STAGED_STATS).toBe(7)
		for _, stat in { "atk", "def", "spa", "spd", "spe", "accuracy", "evasion" } do
			expect(StatStages.STAGED_STATS).toContain(stat)
		end
	end)

	--[[
		The module reads a StageBlock with a variable stat name, which needs a cast
		because a Luau table indexer keyed by a union is invariant. This test is what
		makes that cast safe: if the two lists ever drift apart, the cast starts lying
		and this fails first.
	]]
	it("covers every field of a StageBlock and no others", function()
		local block = freshStages()
		local fieldCount = 0
		for _ in block do
			fieldCount += 1
		end
		expect(fieldCount).toBe(#StatStages.STAGED_STATS)
		for _, stat in StatStages.STAGED_STATS do
			if block[stat] == nil then
				fail(`STAGED_STATS lists "{stat}", which is not a field of StageBlock`)
			end
		end
	end)
end)

describe("StatStages / battle stat ladder", function()
	--[[
		Gen 5. Note +1 is 1.5x and +2 is 2.0x — NOT +2 = 1.5x. DamageCalc already
		depends on this exact ladder.
	]]
	it("scales upward as (2 + stage) / 2", function()
		expect(StatStages.battleMultiplier(0)).toBeCloseTo(1, 1e-12)
		expect(StatStages.battleMultiplier(1)).toBeCloseTo(1.5, 1e-12)
		expect(StatStages.battleMultiplier(2)).toBeCloseTo(2, 1e-12)
		expect(StatStages.battleMultiplier(3)).toBeCloseTo(2.5, 1e-12)
		expect(StatStages.battleMultiplier(4)).toBeCloseTo(3, 1e-12)
		expect(StatStages.battleMultiplier(5)).toBeCloseTo(3.5, 1e-12)
		expect(StatStages.battleMultiplier(6)).toBeCloseTo(4, 1e-12)
	end)

	it("scales downward as 2 / (2 - stage)", function()
		expect(StatStages.battleMultiplier(-1)).toBeCloseTo(2 / 3, 1e-12)
		expect(StatStages.battleMultiplier(-2)).toBeCloseTo(0.5, 1e-12)
		expect(StatStages.battleMultiplier(-3)).toBeCloseTo(0.4, 1e-12)
		expect(StatStages.battleMultiplier(-4)).toBeCloseTo(1 / 3, 1e-12)
		expect(StatStages.battleMultiplier(-5)).toBeCloseTo(2 / 7, 1e-12)
		expect(StatStages.battleMultiplier(-6)).toBeCloseTo(0.25, 1e-12)
	end)

	it("does not use the accuracy ladder for battle stats", function()
		-- 4/3 is the accuracy value for +1. If this ever equals it, the two ladders
		-- have been crossed.
		expect(StatStages.battleMultiplier(1)).never.toBeCloseTo(4 / 3, 1e-6)
	end)

	it("floors when applied to a stat", function()
		expect(StatStages.applyToStat(100, 0)).toBe(100)
		expect(StatStages.applyToStat(100, 1)).toBe(150)
		expect(StatStages.applyToStat(100, 2)).toBe(200)
		expect(StatStages.applyToStat(100, 6)).toBe(400)
		expect(StatStages.applyToStat(100, -1)).toBe(66)
		expect(StatStages.applyToStat(100, -2)).toBe(50)
		expect(StatStages.applyToStat(100, -6)).toBe(25)
		expect(StatStages.applyToStat(7, -1)).toBe(4)
	end)

	it("clamps out-of-range stages when applying", function()
		expect(StatStages.applyToStat(100, 99)).toBe(StatStages.applyToStat(100, 6))
		expect(StatStages.applyToStat(100, -99)).toBe(StatStages.applyToStat(100, -6))
	end)
end)

describe("StatStages / accuracy ladder", function()
	it("scales upward as (3 + stage) / 3", function()
		expect(StatStages.accuracyMultiplier(0)).toBeCloseTo(1, 1e-12)
		expect(StatStages.accuracyMultiplier(1)).toBeCloseTo(4 / 3, 1e-12)
		expect(StatStages.accuracyMultiplier(2)).toBeCloseTo(5 / 3, 1e-12)
		expect(StatStages.accuracyMultiplier(3)).toBeCloseTo(2, 1e-12)
		expect(StatStages.accuracyMultiplier(6)).toBeCloseTo(3, 1e-12)
	end)

	it("scales downward as 3 / (3 - stage)", function()
		expect(StatStages.accuracyMultiplier(-1)).toBeCloseTo(0.75, 1e-12)
		expect(StatStages.accuracyMultiplier(-2)).toBeCloseTo(0.6, 1e-12)
		expect(StatStages.accuracyMultiplier(-3)).toBeCloseTo(0.5, 1e-12)
		expect(StatStages.accuracyMultiplier(-6)).toBeCloseTo(1 / 3, 1e-12)
	end)

	it("does not use the battle ladder for accuracy", function()
		expect(StatStages.accuracyMultiplier(1)).never.toBeCloseTo(1.5, 1e-6)
	end)

	--[[
		Accuracy and evasion oppose each other: the chance to hit is the attacker's
		accuracy stage against the defender's evasion stage, so a combined stage of
		zero must be exactly 1.0 however it was reached.
	]]
	it("cancels an equal accuracy and evasion stage", function()
		for stage = -6, 6 do
			local combined = StatStages.accuracyMultiplier(stage)
				* StatStages.accuracyMultiplier(-stage)
			expect(combined).toBeCloseTo(1, 1e-12)
		end
	end)
end)

describe("StatStages / changing stages", function()
	it("returns a new block rather than mutating the old one", function()
		local before = freshStages()
		local result = StatStages.change(before, "atk", 2)
		expect(before.atk).toBe(0)
		expect(result.stages.atk).toBe(2)
	end)

	it("reports the delta it actually applied", function()
		local result = StatStages.change(freshStages(), "atk", 2)
		expect(result.applied).toBe(2)
		expect(result.newStage).toBe(2)
	end)

	it("clamps at the ceiling and reports the truncated delta", function()
		local atFive = StatStages.change(freshStages(), "atk", 5).stages
		local result = StatStages.change(atFive, "atk", 3)
		expect(result.newStage).toBe(6)
		-- Only one of the three requested stages could land.
		expect(result.applied).toBe(1)
	end)

	it("reports zero applied when already maxed", function()
		local atSix = StatStages.change(freshStages(), "atk", 6).stages
		local result = StatStages.change(atSix, "atk", 2)
		expect(result.applied).toBe(0)
		expect(result.newStage).toBe(6)
	end)

	it("clamps at the floor too", function()
		local atMinusSix = StatStages.change(freshStages(), "spe", -9).stages
		expect(atMinusSix.spe).toBe(-6)
		expect(StatStages.change(atMinusSix, "spe", -1).applied).toBe(0)
	end)

	it("leaves the other stats alone", function()
		local result = StatStages.change(freshStages(), "atk", 3)
		expect(result.stages.def).toBe(0)
		expect(result.stages.spa).toBe(0)
		expect(result.stages.spd).toBe(0)
		expect(result.stages.spe).toBe(0)
		expect(result.stages.accuracy).toBe(0)
		expect(result.stages.evasion).toBe(0)
	end)

	it("changes every staged stat independently", function()
		local stages = freshStages()
		for _, stat in StatStages.STAGED_STATS do
			stages = StatStages.change(stages, stat, 1).stages
		end
		for _, stat in StatStages.STAGED_STATS do
			expect(stages[stat]).toBe(1)
		end
	end)

	it("rejects an unknown stat", function()
		expect(function()
			StatStages.change(freshStages(), "hp" :: any, 1)
		end).toThrow("hp")
	end)
end)

describe("StatStages / reset", function()
	local function boosted(): any
		local stages = freshStages()
		stages = StatStages.change(stages, "atk", 3).stages
		stages = StatStages.change(stages, "def", -2).stages
		stages = StatStages.change(stages, "spe", 1).stages
		return stages
	end

	it("clears everything by default", function()
		local cleared = StatStages.reset(boosted())
		for _, stat in StatStages.STAGED_STATS do
			expect(cleared[stat]).toBe(0)
		end
	end)

	it("clears only the positive stages when asked", function()
		local cleared = StatStages.reset(boosted(), { onlyPositive = true })
		expect(cleared.atk).toBe(0)
		expect(cleared.spe).toBe(0)
		expect(cleared.def).toBe(-2)
	end)

	it("clears only the negative stages when asked", function()
		local cleared = StatStages.reset(boosted(), { onlyNegative = true })
		expect(cleared.def).toBe(0)
		expect(cleared.atk).toBe(3)
		expect(cleared.spe).toBe(1)
	end)

	it("returns a new block", function()
		local before = boosted()
		StatStages.reset(before)
		expect(before.atk).toBe(3)
	end)
end)
