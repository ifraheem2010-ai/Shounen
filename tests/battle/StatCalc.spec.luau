--!strict
--[[
	Stat computation tests.

	Every expected number here was worked out by hand from the Gen-5 formula and the
	arithmetic is written above each one, so a reader can check it without running
	anything. The formula is short enough that a test which merely asserts
	self-consistency would prove nothing at all.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local Species = require(Shared.Data.Species)
local StatCalc = require(Shared.Battle.StatCalc)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect

local function flat(value: number): any
	return { hp = value, atk = value, def = value, spa = value, spd = value, spe = value }
end

describe("StatCalc / the formula", function()
	--[[ floor((2*100 + 31 + 0) * 50 / 100) = floor(115.5) = 115, +5 = 120 ]]
	it("computes a non-HP stat at level 50 with perfect IVs", function()
		expect(StatCalc.computeOther(100, 31, 0, 50)).toBe(120)
	end)

	--[[ 115 + 50 + 10 = 175. HP gets the level again plus a flat ten. ]]
	it("computes HP at level 50 with perfect IVs", function()
		expect(StatCalc.computeHp(100, 31, 0, 50)).toBe(175)
	end)

	--[[
		floor(252 / 4) = 63 -> floor((200 + 31 + 63) * 100 / 100) = 294, +5 = 299
		HP: 294 + 100 + 10 = 404
	]]
	it("quarters EVs before they count", function()
		expect(StatCalc.computeOther(100, 31, 252, 100)).toBe(299)
		expect(StatCalc.computeHp(100, 31, 252, 100)).toBe(404)
	end)

	it("gives 4 EVs the same value as 7 and 0 the same as 3", function()
		-- The quartering means only multiples of four move the number.
		expect(StatCalc.computeOther(100, 31, 4, 100)).toBe(StatCalc.computeOther(100, 31, 7, 100))
		expect(StatCalc.computeOther(100, 31, 0, 100)).toBe(StatCalc.computeOther(100, 31, 3, 100))
	end)

	--[[ level 5, base 45, no IVs: floor(90 * 5 / 100) = 4, +5 = 9; HP 4 + 5 + 10 = 19 ]]
	it("handles an early-game creature", function()
		expect(StatCalc.computeOther(45, 0, 0, 5)).toBe(9)
		expect(StatCalc.computeHp(45, 0, 0, 5)).toBe(19)
	end)

	--[[ level 1, base 45, perfect IVs: floor(121 / 100) = 1, +5 = 6; HP 1 + 1 + 10 = 12 ]]
	it("handles level 1 without collapsing to zero", function()
		expect(StatCalc.computeOther(45, 31, 0, 1)).toBe(6)
		expect(StatCalc.computeHp(45, 31, 0, 1)).toBe(12)
	end)

	--[[
		HP always exceeds an equal-based other stat, which is why early battles take
		several turns rather than one.
	]]
	it("makes HP larger than an equally-based attacking stat", function()
		for _, level in { 5, 20, 50, 100 } do
			expect(StatCalc.computeHp(80, 31, 0, level)).toBeGreaterThan(
				StatCalc.computeOther(80, 31, 0, level)
			)
		end
	end)

	it("rises monotonically with level", function()
		local previous = 0
		for level = 1, 100 do
			local value = StatCalc.computeOther(100, 31, 0, level)
			expect(value).toBeGreaterThanOrEqual(previous)
			previous = value
		end
	end)

	it("rejects a level below 1", function()
		expect(function()
			StatCalc.compute(flat(100), flat(31), flat(0), 0)
		end).toThrow("level")
	end)
end)

describe("StatCalc / whole stat blocks", function()
	it("computes every stat of a block", function()
		local stats = StatCalc.compute(flat(100), flat(31), flat(0), 50)
		expect(stats.hp).toBe(175)
		expect(stats.atk).toBe(120)
		expect(stats.def).toBe(120)
		expect(stats.spa).toBe(120)
		expect(stats.spd).toBe(120)
		expect(stats.spe).toBe(120)
	end)

	--[[
		Pyrecant at level 50 with perfect IVs and no EVs:
		  spa  floor((2*128 + 31) * 50 / 100) + 5 = floor(143.5) + 5 = 148
		  hp   floor((2*72 + 31) * 50 / 100) + 50 + 10 = 87 + 60 = 147
		  spe  floor((2*120 + 31) * 50 / 100) + 5 = floor(135.5) + 5 = 140
	]]
	it("computes a real species", function()
		local pyrecant = Species.getSpecies("flame.pyrecant")
		local stats = StatCalc.compute(pyrecant.baseStats, flat(31), flat(0), 50)
		expect(stats.spa).toBe(148)
		expect(stats.hp).toBe(147)
		expect(stats.spe).toBe(140)
	end)

	--[[
		The wall really is a wall. Glacivast's special defence must clearly exceed
		Pyrecant's, or the role names on the two lines are decoration.
	]]
	it("keeps the roles distinguishable at the same level", function()
		local sweeper =
			StatCalc.compute(Species.getSpecies("flame.pyrecant").baseStats, flat(31), flat(0), 50)
		local wall =
			StatCalc.compute(Species.getSpecies("frost.glacivast").baseStats, flat(31), flat(0), 50)
		local tank = StatCalc.compute(
			Species.getSpecies("terra.cragmarrow").baseStats,
			flat(31),
			flat(0),
			50
		)

		expect(wall.spd).toBeGreaterThan(sweeper.spd)
		expect(wall.hp).toBeGreaterThan(sweeper.hp)
		expect(sweeper.spe).toBeGreaterThan(wall.spe)
		expect(tank.atk).toBeGreaterThan(sweeper.atk)
		expect(tank.def).toBeGreaterThan(sweeper.def)
	end)
end)
